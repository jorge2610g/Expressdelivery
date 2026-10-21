#!/usr/bin/env python3
"""Verify or publish the official paired Express build to Play internal only."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path

PACKAGE = "com.express.usuario1"
VERSION = "1.6.3"
BUILD = 142
INTERNAL_TRACKS = ("qa", "internal")
PUBLISH_AUTHORIZATION = "AUTORIZO PRUEBAS INTERNAS"
SERVICE_ACCOUNT = "play-publisher@blue-app-a077b.iam.gserviceaccount.com"
API_ROOT = (
    "https://androidpublisher.googleapis.com/androidpublisher/v3/"
    f"applications/{PACKAGE}"
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_candidate(identity_path: Path, apk_path: Path, aab_path: Path,
                       release_tag: str, tag_commit: str) -> dict:
    if not identity_path.is_file() or identity_path.stat().st_size == 0:
        raise ValueError("Falta el manifiesto identity.json del candidato.")
    for artifact in (apk_path, aab_path):
        if not artifact.is_file() or artifact.stat().st_size < 100_000:
            raise ValueError(f"Falta un artefacto oficial o es demasiado pequeño: {artifact.name}")
    identity = json.loads(identity_path.read_text(encoding="utf-8"))
    if identity.get("artifact_type") != "single-app-candidate-apk+aab":
        raise ValueError("La publicación requiere el candidato oficial conjunto APK + AAB.")
    if identity.get("package_name") != PACKAGE:
        raise ValueError("El paquete no es el Express original.")
    if identity.get("version_name") != VERSION or identity.get("build_number") != BUILD:
        raise ValueError("La versión no corresponde a Express 1.6.3+142.")
    source_sha = identity.get("source_sha", "")
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha) or source_sha != tag_commit:
        raise ValueError("El tag firmado no apunta al SHA fuente del candidato.")
    tag_pattern = (
        rf"single-app-android-qa-v{re.escape(VERSION)}-build{BUILD}-"
        rf"sha{source_sha[:12]}-job[0-9a-f]{{8}}"
    )
    if not re.fullmatch(tag_pattern, release_tag):
        raise ValueError("El tag no coincide con la versión, build, SHA y job.")
    for key, artifact in (("apk_sha256", apk_path), ("aab_sha256", aab_path)):
        expected = identity.get(key, "")
        actual = sha256_file(artifact)
        if not re.fullmatch(r"[0-9a-f]{64}", expected) or actual != expected:
            raise ValueError(f"El SHA-256 de {artifact.suffix[1:].upper()} no coincide con identity.json.")
    return identity


def pick_internal_track(tracks: list[dict]) -> str | None:
    present = {track.get("track") for track in tracks}
    return next((track for track in INTERNAL_TRACKS if track in present), None)


def request_json(session, method: str, url: str, **kwargs) -> dict:
    response = session.request(method, url, timeout=360, **kwargs)
    if not response.ok:
        try:
            error = response.json().get("error", {}).get("message", "Error de Google Play")
        except ValueError:
            error = "Google Play respondió sin JSON"
        raise RuntimeError(f"Google Play HTTP {response.status_code}: {error[:900]}")
    if response.status_code == 204 or not response.content:
        return {}
    return response.json()


def play_tracks_and_codes(session, edit_id: str) -> tuple[list[dict], set[int]]:
    root = f"{API_ROOT}/edits/{edit_id}"
    tracks = request_json(session, "GET", f"{root}/tracks").get("tracks", [])
    codes: set[int] = set()
    for track in tracks:
        for release in track.get("releases", []):
            codes.update(int(code) for code in release.get("versionCodes", []))
    bundles = request_json(session, "GET", f"{root}/bundles").get("bundles", [])
    codes.update(int(bundle["versionCode"]) for bundle in bundles if "versionCode" in bundle)
    return tracks, codes


def run(args) -> None:
    identity = validate_candidate(
        args.identity, args.apk, args.aab, args.release_tag, args.tag_commit
    )
    if args.mode == "publish" and args.confirmation != PUBLISH_AUTHORIZATION:
        raise ValueError(f"Publicar requiere escribir exactamente: {PUBLISH_AUTHORIZATION}")
    secret = os.environ.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", "").strip()
    if not secret:
        raise ValueError("Falta el secreto GOOGLE_PLAY_SERVICE_ACCOUNT_JSON en GitHub Actions.")
    try:
        service_account = json.loads(secret)
    except ValueError as exc:
        raise ValueError("El secreto de Google Play no contiene JSON válido.") from exc
    if service_account.get("type") != "service_account" or service_account.get("client_email") != SERVICE_ACCOUNT:
        raise ValueError("La clave no pertenece a la cuenta de Play Publisher autorizada.")

    from google.auth.transport.requests import AuthorizedSession
    from google.oauth2 import service_account as google_service_account

    credentials = google_service_account.Credentials.from_service_account_info(
        service_account,
        scopes=["https://www.googleapis.com/auth/androidpublisher"],
    )
    session = AuthorizedSession(credentials)
    edit_id = None
    committed = False
    try:
        edit_id = request_json(session, "POST", f"{API_ROOT}/edits", json={})["id"]
        tracks, used_codes = play_tracks_and_codes(session, edit_id)
        track = pick_internal_track(tracks)
        max_code = max(used_codes, default=0)
        code_available = BUILD not in used_codes and BUILD > max_code
        print(f"package={PACKAGE}; internal_track={track}; max_versionCode={max_code}; "
              f"candidate={BUILD}; available={code_available}; mode={args.mode}")
        if args.mode == "check":
            return
        if track is None:
            raise ValueError("No existe una pista interna `qa` o `internal`; publicación detenida.")
        if not code_available:
            raise ValueError(
                f"Google Play ya conoce un versionCode >= {BUILD}; no se subirá este AAB."
            )

        upload_url = (
            f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/"
            f"applications/{PACKAGE}/edits/{edit_id}/bundles?uploadType=media"
        )
        with args.aab.open("rb") as stream:
            uploaded = request_json(
                session, "POST", upload_url,
                headers={"Content-Type": "application/octet-stream"}, data=stream,
            )
        if int(uploaded.get("versionCode", 0)) != BUILD:
            raise RuntimeError("Google Play devolvió un versionCode distinto de 142.")
        track_url = f"{API_ROOT}/edits/{edit_id}/tracks/{track}"
        request_json(session, "PUT", track_url, json={
            "track": track,
            "releases": [{
                "name": f"Express {VERSION} ({BUILD}) - QA",
                "versionCodes": [str(BUILD)],
                "status": "completed",
            }],
        })
        request_json(session, "POST", f"{API_ROOT}/edits/{edit_id}:validate", json={})
        request_json(session, "POST", f"{API_ROOT}/edits/{edit_id}:commit", json={})
        committed = True
        print(f"Publicado solo en pruebas internas: {PACKAGE}, pista={track}, build={BUILD}")
    finally:
        if edit_id and not committed:
            try:
                session.delete(f"{API_ROOT}/edits/{edit_id}", timeout=30)
            except Exception:
                pass


def self_test() -> None:
    from tempfile import TemporaryDirectory

    with TemporaryDirectory() as directory:
        root = Path(directory)
        apk = root / "candidate.apk"
        aab = root / "candidate.aab"
        apk.write_bytes(b"apk" * 50_000)
        aab.write_bytes(b"aab" * 50_000)
        source = "a" * 40
        tag = f"single-app-android-qa-v1.6.3-build142-sha{source[:12]}-job1234abcd"
        identity = {
            "artifact_type": "single-app-candidate-apk+aab",
            "package_name": PACKAGE,
            "version_name": VERSION,
            "build_number": BUILD,
            "source_sha": source,
            "apk_sha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
            "aab_sha256": hashlib.sha256(aab.read_bytes()).hexdigest(),
        }
        identity_path = root / "identity.json"
        identity_path.write_text(json.dumps(identity), encoding="utf-8")
        assert validate_candidate(identity_path, apk, aab, tag, source)["build_number"] == BUILD
        unauthorized = argparse.Namespace(
            identity=identity_path, apk=apk, aab=aab, release_tag=tag,
            tag_commit=source, mode="publish", confirmation="",
        )
        try:
            run(unauthorized)
        except ValueError as error:
            assert "AUTORIZO PRUEBAS INTERNAS" in str(error)
        else:
            raise AssertionError("Publish accepted without the internal-track confirmation")
        for key, value in (("package_name", "com.fake.app"), ("build_number", 141),
                           ("aab_sha256", "0" * 64), ("artifact_type", "aab")):
            broken = dict(identity)
            broken[key] = value
            identity_path.write_text(json.dumps(broken), encoding="utf-8")
            try:
                validate_candidate(identity_path, apk, aab, tag, source)
            except ValueError:
                continue
            raise AssertionError(f"Invalid identity accepted: {key}")
        assert pick_internal_track([{"track": "production"}, {"track": "internal"}]) == "internal"
        assert pick_internal_track([{"track": "production"}, {"track": "qa"}]) == "qa"
        assert pick_internal_track([{"track": "production"}]) is None
        assert pick_internal_track([{"track": "qa"}, {"track": "internal"}]) == "qa"
    print("Play internal publisher self-tests passed.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("check", "publish"), default="check")
    parser.add_argument("--release-tag", default="")
    parser.add_argument("--tag-commit", default="")
    parser.add_argument("--identity", type=Path)
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--aab", type=Path)
    parser.add_argument("--confirmation", default="")
    parser.add_argument("--self-test", action="store_true")
    options = parser.parse_args()
    try:
        if options.self_test:
            self_test()
        elif not all((options.identity, options.apk, options.aab)):
            raise ValueError("Debe señalar identity.json, APK y AAB del mismo candidato.")
        else:
            run(options)
    except (ValueError, RuntimeError, KeyError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
