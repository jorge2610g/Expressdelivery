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
        "/rest/v1/driver_profiles?select=id,approval_status,online_status,zone_id,latitude,longitude,city&id=eq."
        + urllib.parse.quote(driver_id),
        token=driver_token,
    )
    if not profiles or profiles[0].get("approval_status") != "approved":
        raise RuntimeError("QA driver profile is not approved")

    profile = profiles[0]
    zone_id = profile.get("zone_id")
    if not zone_id:
        raise RuntimeError("QA driver profile has no operational zone")

    profile_lat = float(profile.get("latitude") or -14.8333)
    profile_lng = float(profile.get("longitude") or -64.9000)

    _, zone_context = request(
        "POST",
        "/rest/v1/rpc/app_zone_context",
        token=driver_token,
        body={
            "p_lat": profile_lat,
            "p_lng": profile_lng,
            "p_for": "driver",
        },
    )
    if not isinstance(zone_context, dict) or zone_context.get("inside_coverage") is not True:
        raise RuntimeError("QA driver is outside an operational zone")

    zone = zone_context.get("zone") or {}
    if str(zone.get("id") or "") != str(zone_id):
        raise RuntimeError("QA driver zone does not match app_zone_context")

    pickup_lat = float(zone.get("center_latitude") or profile_lat)
    pickup_lng = float(zone.get("center_longitude") or profile_lng)
    currency = str(zone.get("currency_code") or "BOB").upper()

    services = [
        item for item in (zone_context.get("services") or [])
        if isinstance(item, dict) and item.get("service_key") != "delivery"
    ]
    if not services:
        raise RuntimeError("QA zone has no enabled ride service visible to driver")
    service_key = str(services[0]["service_key"])

    # Keep QA aligned with the driver's real operational zone. Go offline first,
    # move to the zone center, then reconnect so coverage triggers validate the
    # same zone that the synthetic request will use.
    request(
        "PATCH",
        "/rest/v1/driver_profiles?id=eq." + urllib.parse.quote(driver_id),
        token=driver_token,
        body={
            "online_status": "offline",
            "updated_at": datetime.now(timezone.utc).isoformat(),
        },
        prefer="return=minimal",
    )
    request(
        "PATCH",
        "/rest/v1/driver_profiles?id=eq." + urllib.parse.quote(driver_id),
        token=driver_token,
        body={
            "latitude": pickup_lat,
            "longitude": pickup_lng,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        },
        prefer="return=minimal",
    )
    request(
        "PATCH",
        "/rest/v1/driver_profiles?id=eq." + urllib.parse.quote(driver_id),
        token=driver_token,
        body={
            "online_status": "online",
            "updated_at": datetime.now(timezone.utc).isoformat(),
        },
        prefer="return=minimal",
    )

    destination_lat = pickup_lat + 0.006
    destination_lng = pickup_lng + 0.006
    run_id = os.environ.get("GITHUB_RUN_ID", "local")
    origin = f"QA ORIGEN {run_id}"
    destination = f"QA DESTINO {run_id}"
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=4)

    _, quote = request(
        "POST",
        "/rest/v1/rpc/dynamic_pricing_quote",
        token=passenger_token,
        body={
            "p_service_key": service_key,
            "p_distance_km": 1.6,
            "p_duration_minutes": 6,
            "p_pickup_lat": pickup_lat,
            "p_pickup_lng": pickup_lng,
            "p_preview": True,
        },
    )
    minimum_fare = float(
        quote.get("minimum_allowed_fare")
        or quote.get("recommended_fare")
        or quote["amount"]
    )
    if minimum_fare <= 0:
        raise RuntimeError(f"Invalid QA recommended fare: {quote}")

    if currency == "CLP":
        proposed_fare = math.ceil(minimum_fare)
        underpriced_fare = max(1, proposed_fare - 1)
    else:
        proposed_fare = math.ceil(minimum_fare * 100) / 100
        underpriced_fare = max(0.01, round(proposed_fare - 0.01, 2))

    common = {
        "passenger_id": passenger_id,
        "category": service_key,
        "pickup_latitude": pickup_lat,
        "pickup_longitude": pickup_lng,
        "destination_address": destination,
        "destination_latitude": destination_lat,
        "destination_longitude": destination_lng,
        "route_distance_km": 1.6,
        "route_duration_minutes": 6,
        "currency": currency,
        "payment_method": "cash",
        "pricing_mode": "offer",
        "status": "searching",
        "channel": "preview",
        "expires_at": expires_at.isoformat(),
    }

    underpriced_body = {
        **common,
        "pickup_address": f"QA UNDERFLOOR {run_id}",
        "proposed_fare": underpriced_fare,
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
            **common,
            "pickup_address": origin,
            "proposed_fare": proposed_fare,
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
        "zone_id": zone_id,
        "zone_key": zone.get("zone_key"),
        "zone_city": zone.get("city"),
        "service_key": service_key,
        "currency": currency,
        "pickup_latitude": pickup_lat,
        "pickup_longitude": pickup_lng,
        "destination_latitude": destination_lat,
        "destination_longitude": destination_lng,
        "created_at": ride.get("created_at"),
        "expires_at": ride.get("expires_at"),
        "recommended_fare": proposed_fare,
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
        print(f"QA cleanup warning: {exc}", file=sys.stderr)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "prepare"
    if mode == "prepare":
        prepare()
    elif mode == "cleanup":
        cleanup()
    else:
        raise SystemExit("usage: qa_driver_request_flow.py [prepare|cleanup]")
