#!/usr/bin/env python3
import json
import math
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

SUPABASE_URL = "https://zgpijrznvaskgcmauwxx.supabase.co"
SUPABASE_KEY = "sb_publishable_MALGs-X8KdmJSq-QQzeazQ_p5xsfrZP"
STATE_PATH = Path("artifacts/backend/driver-request-seed.json")


def request(method, path, *, token=None, body=None, prefer=None):
    data = None if body is None else json.dumps(body).encode()
    headers = {
        "apikey": SUPABASE_KEY,
        "Content-Type": "application/json",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if prefer:
        headers["Prefer"] = prefer
    req = urllib.request.Request(
        SUPABASE_URL + path,
        data=data,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            raw = response.read().decode().strip()
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        raise RuntimeError(f"{method} {path} -> {exc.code}: {detail}") from exc


def sign_in(email, password):
    _, payload = request(
        "POST",
        "/auth/v1/token?grant_type=password",
        body={"email": email, "password": password},
    )
    return payload["access_token"], payload["user"]["id"]


def prepare():
    passenger_email = os.environ["QA_PASSENGER_EMAIL"]
    passenger_password = os.environ["QA_PASSENGER_PASSWORD"]
    driver_email = os.environ["QA_DRIVER_EMAIL"]
    driver_password = os.environ["QA_DRIVER_PASSWORD"]

    passenger_token, passenger_id = sign_in(passenger_email, passenger_password)
    driver_token, driver_id = sign_in(driver_email, driver_password)

    # Make QA account modes deterministic before the emulator starts.
    request(
        "PATCH",
        "/rest/v1/users?id=eq." + urllib.parse.quote(passenger_id),
        token=passenger_token,
        body={"active_mode": "passenger"},
        prefer="return=minimal",
    )
    request(
        "PATCH",
        "/rest/v1/users?id=eq." + urllib.parse.quote(driver_id),
        token=driver_token,
        body={"active_mode": "driver"},
        prefer="return=minimal",
    )

    _, profiles = request(
        "GET",
        "/rest/v1/driver_profiles?select=id,approval_status,online_status&id=eq."
        + urllib.parse.quote(driver_id),
        token=driver_token,
    )
    if not profiles or profiles[0].get("approval_status") != "approved":
        raise RuntimeError("QA driver profile is not approved")

    # Keep the synthetic driver's backend state aligned with the emulator.
    request(
        "PATCH",
        "/rest/v1/driver_profiles?id=eq." + urllib.parse.quote(driver_id),
        token=driver_token,
        body={
            "online_status": "online",
            "latitude": -20.22843,
            "longitude": -70.13847,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        },
        prefer="return=minimal",
    )

    run_id = os.environ.get("GITHUB_RUN_ID", "local")
    origin = f"QA ORIGEN {run_id}"
    destination = f"QA DESTINO {run_id}"
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=4)

    # The exact Preview QA must prove that the server, not only Flutter,
    # calculates the current recommended floor and rejects underpriced rides.
    _, quote = request(
        "POST",
        "/rest/v1/rpc/dynamic_pricing_quote",
        token=passenger_token,
        body={
            "p_service_key": "economy",
            "p_distance_km": 1.6,
            "p_duration_minutes": 6,
            "p_pickup_lat": -20.22843,
            "p_pickup_lng": -70.13847,
            "p_preview": True,
        },
    )
    minimum_fare = float(
        quote.get("minimum_allowed_fare")
        or quote.get("recommended_fare")
        or quote["amount"]
    )
    minimum_fare_clp = math.ceil(minimum_fare)
    if minimum_fare_clp <= 0:
        raise RuntimeError(f"Invalid QA recommended fare: {quote}")

    underpriced_body = {
        "passenger_id": passenger_id,
        "category": "economy",
        "pickup_address": f"QA UNDERFLOOR {run_id}",
        "pickup_latitude": -20.22843,
        "pickup_longitude": -70.13847,
        "destination_address": destination,
        "destination_latitude": -20.22324,
        "destination_longitude": -70.14941,
        "route_distance_km": 1.6,
        "route_duration_minutes": 6,
        "proposed_fare": max(1, minimum_fare_clp - 1),
        "currency": "CLP",
        "payment_method": "cash",
        "pricing_mode": "offer",
        "status": "searching",
        "channel": "preview",
        "expires_at": expires_at.isoformat(),
    }
    try:
        _, unexpected = request(
            "POST",
            "/rest/v1/ride_requests?select=id",
            token=passenger_token,
            body=underpriced_body,
            prefer="return=representation",
        )
    except RuntimeError as exc:
        message = str(exc).lower()
        if "tarifa mínima recomendada" not in message:
            raise
    else:
        if unexpected:
            request(
                "DELETE",
                "/rest/v1/ride_requests?id=eq."
                + urllib.parse.quote(unexpected[0]["id"]),
                token=passenger_token,
                prefer="return=minimal",
            )
        raise RuntimeError(
            "QA fare-floor failure: backend accepted a fare below the recommended minimum"
        )

    _, rows = request(
        "POST",
        "/rest/v1/ride_requests?select=*",
        token=passenger_token,
        body={
            "passenger_id": passenger_id,
            "category": "economy",
            "pickup_address": origin,
            "pickup_latitude": -20.22843,
            "pickup_longitude": -70.13847,
            "destination_address": destination,
            "destination_latitude": -20.22324,
            "destination_longitude": -70.14941,
            "route_distance_km": 1.6,
            "route_duration_minutes": 6,
            "proposed_fare": minimum_fare_clp,
            "currency": "CLP",
            "payment_method": "cash",
            "pricing_mode": "offer",
            "status": "searching",
            "channel": "preview",
            "expires_at": expires_at.isoformat(),
        },
        prefer="return=representation",
    )
    ride = rows[0]

    state = {
        "ride_id": ride["id"],
        "origin": origin,
        "destination": destination,
        "driver_id": driver_id,
        "passenger_id": passenger_id,
        "created_at": ride.get("created_at"),
        "expires_at": ride.get("expires_at"),
        "recommended_fare": minimum_fare_clp,
        "demand_level": quote.get("demand_level"),
        "demand_multiplier": quote.get("demand_multiplier"),
    }
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, indent=2, ensure_ascii=False))
    print(json.dumps(state, ensure_ascii=False))


def cleanup():
    if not STATE_PATH.exists():
        return
    state = json.loads(STATE_PATH.read_text())
    passenger_token, _ = sign_in(
        os.environ["QA_PASSENGER_EMAIL"],
        os.environ["QA_PASSENGER_PASSWORD"],
    )
    try:
        request(
            "POST",
            "/rest/v1/rpc/cancel_ride_request",
            token=passenger_token,
            body={
                "p_ride_request_id": state["ride_id"],
                "p_reason": "Limpieza automática QA",
            },
        )
    except RuntimeError as exc:
        # The driver flow may have already changed the request state.
        print(f"QA cleanup warning: {exc}", file=sys.stderr)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "prepare"
    if mode == "prepare":
        prepare()
    elif mode == "cleanup":
        cleanup()
    else:
        raise SystemExit("usage: qa_driver_request_flow.py [prepare|cleanup]")
