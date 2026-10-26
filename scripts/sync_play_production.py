#!/usr/bin/env python3
"""Read the Express production track from Google Play without committing edits."""
from __future__ import annotations

import json
import os
import sys

PACKAGE = "com.express.usuario1"
SERVICE_ACCOUNT = "play-publisher@blue-app-a077b.iam.gserviceaccount.com"
API_ROOT = (
    "https://androidpublisher.googleapis.com/androidpublisher/v3/"
    f"applications/{PACKAGE}"
)


def main() -> None:
    raw = os.environ.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", "").strip()
    if not raw:
        raise RuntimeError("Falta el secreto de Google Play configurado en GitHub Actions")
    account = json.loads(raw)
    if account.get("type") != "service_account" or account.get("client_email") != SERVICE_ACCOUNT:
        raise RuntimeError("La cuenta de Google Play no es la autorizada")

    from google.auth.transport.requests import AuthorizedSession
    from google.oauth2 import service_account

    credentials = service_account.Credentials.from_service_account_info(
        account,
        scopes=["https://www.googleapis.com/auth/androidpublisher"],
    )
    session = AuthorizedSession(credentials)
    edit_id = ""
    try:
        response = session.post(API_ROOT + "/edits", json={}, timeout=60)
        response.raise_for_status()
        edit_id = str(response.json().get("id", ""))
        if not edit_id:
            raise RuntimeError("Google Play no creó la consulta temporal de lectura")

        response = session.get(f"{API_ROOT}/edits/{edit_id}/tracks", timeout=60)
        response.raise_for_status()
        tracks = response.json().get("tracks", [])
        production = next(
            (track for track in tracks if track.get("track") == "production"),
            None,
        )
        releases = []
        for release in (production or {}).get("releases", []):
            codes = release.get("versionCodes") or []
            if not codes:
                continue
            releases.append({
                "package_name": PACKAGE,
                "version_name": str(release.get("versionName") or ""),
                "version_codes": [str(code) for code in codes],
                "status": str(release.get("status") or ""),
                "user_fraction": release.get("userFraction"),
                "name": str(release.get("name") or ""),
            })
        json.dump(releases, sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
    finally:
        if edit_id:
            # This API edit is read-only and is always deleted without validate/commit.
            try:
                session.delete(f"{API_ROOT}/edits/{edit_id}", timeout=30)
            except Exception:
                pass


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # Do not print the service-account JSON.
        print(f"Google Play production sync failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
