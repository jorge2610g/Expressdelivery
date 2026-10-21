#!/usr/bin/env python3
"""Upload the official paired Express candidate to Google Play Internal only."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path

PACKAGE = "com.express.usuario1"
AUTHORIZATION = "AUTORIZO APK+AAB PRUEBAS INTERNAS"
SERVICE_ACCOUNT = "play-publisher@blue-app-a077b.iam.gserviceaccount.com"
API_ROOT = (
    "https://androidpublisher.googleapis.com/androidpublisher/v3/"
    f"applications/{PACKAGE}"
)
UPLOAD_ROOT = (
    "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/"
    f"applications/{PACKAGE}"
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def google_session():
    secret = os.environ.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", "").strip()
    if not secret:
        raise ValueError("Falta el secreto GOOGLE_PLAY_SERVICE_ACCOUNT_JSON en GitHub Actions.")
    try:
        service_account = json.loads(secret)
    except ValueError as exc:
        raise ValueError("El secreto de Google Play no contiene JSON válido.") from exc
    if (service_account.get("type") != "service_account" or
            service_account.get("client_email") != SERVICE_ACCOUNT):
        raise ValueError("La clave no corresponde a la cuenta autorizada de Play Publisher.")

    from google.auth.transport.requests import AuthorizedSession
    from google.oauth2 import service_account as google_service_account

    credentials = google_service_account.Credentials.from_service_account_info(
        service_account,
        scopes=["https://www.googleapis.com/auth/androidpublisher"],
    )
    return AuthorizedSession(credentials)


def request_json(session, method: str, url: str, **kwargs) -> dict:
    response = session.request(method, url, timeout=360, **kwargs)
    if not response.ok:
        try:
            message = response.json().get("error", {}).get("message", "Error de Google Play")
        except ValueError:
            message = "Google Play respondió sin JSON"
        raise RuntimeError(f"Google Play HTTP {response.status_code}: {message[:900]}")
    if response.status_code == 204 or not response.content:
        return {}
    return response.json()


def read_candidate(identity_path: Path, apk_path: Path, aab_path: Path,
                   version: str, build: int, source_sha: str,
                   release_tag: str) -> dict:
    for artifact in (identity_path, apk_path, aab_path):
        if not artifact.is_file() or artifact.stat().st_size < 1:
            raise ValueError(f"Falta un archivo del candidato oficial: {artifact.name}")
    identity = json.loads(identity_path.read_text(encoding="utf-8"))
    expected = {
        "artifact_type": "single-app-candidate-apk+aab",
        "package_name": PACKAGE,
        "version_name": version,
        "build_number": build,
        "source_sha": source_sha,
    }
    for key, value in expected.items():
        if identity.get(key) != value:
            raise ValueError(f"identity.json no coincide con el trabajo autorizado ({key}).")
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise ValueError("SHA fuente inválido.")
    if not re.fullmatch(rf"single-app-android-qa-v{re.escape(version)}-build{build}-sha{source_sha[:12]}-job[0-9a-f]{{8}}", release_tag):
        raise ValueError("El tag de Release no corresponde al SHA/build del candidato.")
    for key, artifact in (("apk_sha256", apk_path), ("aab_sha256", aab_path)):
        expected_hash = identity.get(key, "")
        if not re.fullmatch(r"[0-9a-f]{64}", expected_hash) or sha256_file(artifact) != expected_hash:
            raise ValueError(f"El hash {artifact.suffix[1:].upper()} difiere de identity.json.")
    return identity


def read_internal_edit(session, build: int) -> tuple[str, str, dict]:
    edit = request_json(session, "POST", f"{API_ROOT}/edits", json={})
    edit_id = edit.get("id")
    if not edit_id:
        raise RuntimeError("Google Play no devolvió un ID de edición.")
    try:
        tracks = request_json(session, "GET", f"{API_ROOT}/edits/{edit_id}/tracks").get("tracks", [])
        internal = next((track for track in tracks if track.get("track") == "internal"), None)
        if internal is None:
            raise ValueError("La pista internal no existe o la cuenta no tiene acceso al paquete.")
        codes = set()
        for track in tracks:
            for release in track.get("releases", []):
                codes.update(int(code) for code in release.get("versionCodes", []))
        bundles = request_json(session, "GET", f"{API_ROOT}/edits/{edit_id}/bundles").get("bundles", [])
        codes.update(int(bundle["versionCode"]) for bundle in bundles if "versionCode" in bundle)
        max_code = max(codes, default=0)
        if build in codes or build <= max_code:
            raise ValueError(f"versionCode {build} ya está usado o no supera el máximo actual {max_code}.")
        return edit_id, str(max_code), internal
    except Exception:
        try:
            session.delete(f"{API_ROOT}/edits/{edit_id}", timeout=30)
        except Exception:
            pass
        raise


def releases_for_internal_update(internal: dict, new_release: dict) -> list[dict]:
    """Replace the completed internal release while retaining non-completed drafts.

    Google Play permits only one completed release on a track. The previous
    completed Internal release is superseded by the newly authorized build;
    releases in other tracks (including Production) are never read or written.
    """
    releases = [
        release for release in internal.get("releases", [])
        if release.get("status") != "completed"
    ]
    releases.append(new_release)
    return releases


def main(args) -> None:
    if args.mode == "publish" and args.confirmation != AUTHORIZATION:
        raise ValueError(f"La carga requiere la confirmación exacta: {AUTHORIZATION}")
    session = google_session()
    edit_id, max_code, internal = read_internal_edit(session, args.build)
    committed = False
    try:
        print(f"Play preflight OK: package={PACKAGE}, track=internal, candidate={args.build}, max_versionCode={max_code}")
        if args.mode == "check":
            return
        read_candidate(args.identity, args.apk, args.aab, args.version, args.build,
                       args.source_sha, args.release_tag)
        upload_url = f"{UPLOAD_ROOT}/edits/{edit_id}/bundles?uploadType=media"
        with args.aab.open("rb") as stream:
            uploaded = request_json(
                session, "POST", upload_url,
                headers={"Content-Type": "application/octet-stream"}, data=stream,
            )
        if int(uploaded.get("versionCode", 0)) != args.build:
            raise RuntimeError("Google Play recibió un versionCode distinto al autorizado.")
        new_release = {
            "name": f"Express {args.version} ({args.build}) - QA",
            "versionCodes": [str(args.build)],
            "status": "completed",
        }
        request_json(session, "PUT", f"{API_ROOT}/edits/{edit_id}/tracks/internal", json={
            "track": "internal",
            "releases": releases_for_internal_update(internal, new_release),
        })
        request_json(session, "POST", f"{API_ROOT}/edits/{edit_id}:validate", json={})
        request_json(session, "POST", f"{API_ROOT}/edits/{edit_id}:commit", json={})
        committed = True
        print(f"Carga completada en Google Play Internal: {PACKAGE}, {args.version}+{args.build}; sin cambios en Producción.")
    finally:
        if not committed:
            try:
                session.delete(f"{API_ROOT}/edits/{edit_id}", timeout=30)
            except Exception:
                pass


def self_test() -> None:
    from argparse import Namespace
    from tempfile import TemporaryDirectory

    try:
        main(Namespace(mode="publish", confirmation=""))
    except ValueError as error:
        assert AUTHORIZATION in str(error)
    else:
        raise AssertionError("Internal upload accepted without the exact confirmation")

    with TemporaryDirectory() as tmp:
        root = Path(tmp)
        apk, aab, identity = root / "app.apk", root / "app.aab", root / "identity.json"
        apk.write_bytes(b"apk" * 100)
        aab.write_bytes(b"aab" * 100)
        source = "a" * 40
        manifest = {
            "artifact_type": "single-app-candidate-apk+aab",
            "package_name": PACKAGE,
            "version_name": "1.6.3",
            "build_number": 142,
            "source_sha": source,
            "apk_sha256": sha256_file(apk),
            "aab_sha256": sha256_file(aab),
        }
        identity.write_text(json.dumps(manifest), encoding="utf-8")
        tag = f"single-app-android-qa-v1.6.3-build142-sha{source[:12]}-job1234abcd"
        read_candidate(identity, apk, aab, "1.6.3", 142, source, tag)
        existing = {
            "releases": [
                {"name": "141 Internal", "versionCodes": ["141"], "status": "completed"},
                {"name": "draft 140", "versionCodes": ["140"], "status": "draft"},
            ]
        }
        updated = releases_for_internal_update(existing, {
            "name": "142 Internal", "versionCodes": ["142"], "status": "completed"
        })
        assert len([release for release in updated if release.get("status") == "completed"]) == 1
        assert updated[-1]["versionCodes"] == ["142"]
        assert any(release.get("status") == "draft" for release in updated)
        aab.write_bytes(b"tampered")
        try:
            read_candidate(identity, apk, aab, "1.6.3", 142, source, tag)
        except ValueError:
            pass
        else:
            raise AssertionError("Tampered AAB passed identity validation")
    print("Play internal upload self-tests passed.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("check", "publish"), required=True)
    parser.add_argument("--version", default="")
    parser.add_argument("--build", type=int, default=0)
    parser.add_argument("--source-sha", default="")
    parser.add_argument("--release-tag", default="")
    parser.add_argument("--identity", type=Path)
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--aab", type=Path)
    parser.add_argument("--confirmation", default="")
    parser.add_argument("--self-test", action="store_true")
    options = parser.parse_args()
    try:
        if options.self_test:
            self_test()
        else:
            if options.mode == "publish" and not all((options.version, options.build, options.source_sha,
                                                         options.release_tag, options.identity, options.apk, options.aab)):
                raise ValueError("Faltan metadatos o archivos firmados del candidato.")
            main(options)
    except (ValueError, RuntimeError, KeyError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
