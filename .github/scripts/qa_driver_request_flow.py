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


def complete():
    if not STATE_PATH.exists():
        raise RuntimeError("QA ride state is missing")

    state = json.loads(STATE_PATH.read_text())
    passenger_token, passenger_id = sign_in(
        os.environ["QA_PASSENGER_EMAIL"],
        os.environ["QA_PASSENGER_PASSWORD"],
    )
    driver_token, driver_id = sign_in(
        os.environ["QA_DRIVER_EMAIL"],
        os.environ["QA_DRIVER_PASSWORD"],
    )

    if passenger_id != state["passenger_id"] or driver_id != state["driver_id"]:
        raise RuntimeError("QA identities changed after request preparation")

    ride_id = state["ride_id"]
    fare = state["recommended_fare"]
    offer_expires = datetime.now(timezone.utc) + timedelta(minutes=3)

    _, offers = request(
        "POST",
        "/rest/v1/driver_offers?on_conflict=ride_request_id,driver_id&select=*",
        token=driver_token,
        body={
            "ride_request_id": ride_id,
            "driver_id": driver_id,
            "channel": "preview",
            "proposed_fare": fare,
            "eta_minutes": 2,
            "status": "pending",
            "created_at": datetime.now(timezone.utc).isoformat(),
            "expires_at": offer_expires.isoformat(),
        },
        prefer="resolution=merge-duplicates,return=representation",
    )
    if not offers:
        raise RuntimeError("QA driver offer was not created")
    offer_id = offers[0]["id"]

    _, trip_id = request(
        "POST",
        "/rest/v1/rpc/select_ride_offer_v2",
        token=passenger_token,
        body={"p_offer_id": offer_id, "p_channel": "preview"},
    )
    if not trip_id:
        raise RuntimeError("QA passenger could not select the driver offer")

    for status in ("driver_arriving", "driver_waiting"):
        request(
            "POST",
            "/rest/v1/rpc/advance_trip_v2",
            token=driver_token,
            body={
                "p_trip_id": trip_id,
                "p_status": status,
                "p_channel": "preview",
            },
        )

    _, trips = request(
        "GET",
        "/rest/v1/trips?select=id,status,boarding_pin,passenger_id,driver_id&id=eq."
        + urllib.parse.quote(str(trip_id)),
        token=passenger_token,
    )
    if not trips:
        raise RuntimeError("QA trip disappeared after offer selection")
    trip = trips[0]
    pin = str(trip.get("boarding_pin") or "").strip()
    if len(pin) != 4 or not pin.isdigit():
        raise RuntimeError(f"QA boarding PIN is invalid: {pin!r}")

    request(
        "POST",
        "/rest/v1/rpc/start_trip_with_pin_v2",
        token=driver_token,
        body={
            "p_trip_id": trip_id,
            "p_pin": pin,
            "p_channel": "preview",
        },
    )
    request(
        "POST",
        "/rest/v1/rpc/advance_trip_v2",
        token=driver_token,
        body={
            "p_trip_id": trip_id,
            "p_status": "completed",
            "p_channel": "preview",
        },
    )

    _, completed = request(
        "GET",
        "/rest/v1/trips?select=id,status,completed_at&id=eq."
        + urllib.parse.quote(str(trip_id)),
        token=passenger_token,
    )
    if not completed or completed[0].get("status") != "completed":
        raise RuntimeError(f"QA trip did not complete: {completed}")

    _, passenger_pending = request(
        "POST",
        "/rest/v1/rpc/pending_rating_service",
        token=passenger_token,
        body={},
    )
    _, driver_pending = request(
        "POST",
        "/rest/v1/rpc/pending_rating_service",
        token=driver_token,
        body={},
    )

    if not isinstance(passenger_pending, dict):
        raise RuntimeError("Passenger has no pending rating after completed QA trip")
    if not isinstance(driver_pending, dict):
        raise RuntimeError("Driver has no pending rating after completed QA trip")
    if str(passenger_pending.get("id")) != str(trip_id):
        raise RuntimeError(
            f"Passenger pending rating points to another trip: {passenger_pending}"
        )
    if str(driver_pending.get("id")) != str(trip_id):
        raise RuntimeError(
            f"Driver pending rating points to another trip: {driver_pending}"
        )
    if str(passenger_pending.get("to_user_id")) != driver_id:
        raise RuntimeError("Passenger pending rating does not target QA driver")
    if str(driver_pending.get("to_user_id")) != passenger_id:
        raise RuntimeError("Driver pending rating does not target QA passenger")

    state.update(
        {
            "offer_id": offer_id,
            "trip_id": str(trip_id),
            "boarding_pin": pin,
            "completed_at": completed[0].get("completed_at"),
            "passenger_rating_pending": True,
            "driver_rating_pending": True,
        }
    )
    STATE_PATH.write_text(json.dumps(state, indent=2, ensure_ascii=False))
    print(json.dumps(state, ensure_ascii=False))


def finish():
    if not STATE_PATH.exists():
        raise RuntimeError("QA ride state is missing")

    state = json.loads(STATE_PATH.read_text())
    trip_id = state.get("trip_id")
    if not trip_id:
        raise RuntimeError("QA trip was not completed before rating finish")

    passenger_token, passenger_id = sign_in(
        os.environ["QA_PASSENGER_EMAIL"],
        os.environ["QA_PASSENGER_PASSWORD"],
    )
    driver_token, driver_id = sign_in(
        os.environ["QA_DRIVER_EMAIL"],
        os.environ["QA_DRIVER_PASSWORD"],
    )

    def ensure_rating(token, from_user_id, to_user_id, comment):
        _, existing = request(
            "GET",
            "/rest/v1/ratings?select=id&trip_id=eq."
            + urllib.parse.quote(str(trip_id))
            + "&from_user_id=eq."
            + urllib.parse.quote(from_user_id),
            token=token,
        )
        if existing:
            return
        request(
            "POST",
            "/rest/v1/ratings",
            token=token,
            body={
                "trip_id": trip_id,
                "from_user_id": from_user_id,
                "to_user_id": to_user_id,
                "score": 5,
                "comment": comment,
            },
            prefer="return=minimal",
        )

    ensure_rating(
        passenger_token,
        passenger_id,
        driver_id,
        "QA passenger rating",
    )
    ensure_rating(
        driver_token,
        driver_id,
        passenger_id,
        "QA driver rating",
    )

    _, passenger_ratings = request(
        "GET",
        "/rest/v1/ratings?select=id,from_user_id,to_user_id,score&trip_id=eq."
        + urllib.parse.quote(str(trip_id))
        + "&from_user_id=eq."
        + urllib.parse.quote(passenger_id),
        token=passenger_token,
    )
    _, driver_ratings = request(
        "GET",
        "/rest/v1/ratings?select=id,from_user_id,to_user_id,score&trip_id=eq."
        + urllib.parse.quote(str(trip_id))
        + "&from_user_id=eq."
        + urllib.parse.quote(driver_id),
        token=driver_token,
    )
    if not passenger_ratings or not driver_ratings:
        raise RuntimeError(
            "QA bidirectional ratings were not persisted: "
            f"passenger={passenger_ratings}, driver={driver_ratings}"
        )

    _, passenger_pending = request(
        "POST",
        "/rest/v1/rpc/pending_rating_service",
        token=passenger_token,
        body={},
    )
    _, driver_pending = request(
        "POST",
        "/rest/v1/rpc/pending_rating_service",
        token=driver_token,
        body={},
    )
    if isinstance(passenger_pending, dict) and str(passenger_pending.get("id")) == str(trip_id):
        raise RuntimeError("Passenger rating remained pending after submission")
    if isinstance(driver_pending, dict) and str(driver_pending.get("id")) == str(trip_id):
        raise RuntimeError("Driver rating remained pending after submission")

    state["ratings_finished"] = True
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
    elif mode == "complete":
        complete()
    elif mode == "finish":
        finish()
    elif mode == "cleanup":
        cleanup()
    else:
        raise SystemExit(
            "usage: qa_driver_request_flow.py [prepare|complete|finish|cleanup]"
        )
