#!/usr/bin/env python3
"""Express Google Play internal-track publisher.

Only the official signed AAB for com.express.usuario1 is accepted.
This command NEVER writes to the production track. Credentials stay in a
GitHub Actions secret and are used only in the ephemeral runner process.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path

PACKAGE = "com.express.usuario1"
INTERNAL_TRACK = "qa"  # Documented default. Legacy apps may return "internal".
LEGACY_INTERNAL_TRACK = "internal"
SAFE_INTERNAL_TRACKS = (INTERNAL_TRACK, LEGACY_INTERNAL_TRACK)
PUBLISH_AUTHORIZATION = "AUTORIZO PRUEBAS INTERNAS"
EXPECTED_SERVICE_ACCOUNT = "play-publisher@blue-app-a077b.iam.gserviceaccount.com"
API_BASE = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}"


def validate_bundle(identity_path: Path, bundle_path: Path, release_tag: str) -> dict:
    if not identity_path.is_file() or not bundle_path.is_file():
        raise ValueError("Faltan el AAB firmado o el manifiesto de identidad.")
    identity = json.loads(identity_path.read_text(encoding="utf-8"))
    if identity.get("package_name") != PACKAGE:
        raise ValueError("El paquete no es el Express original.")
    if identity.get("artifact_type") not in ("single-app-candidate-apk+aab", "aab"):
        raise ValueError("Solo se aceptan AAB oficiales firmados por Express.")
    if identity["artifact_type"] == "aab" and identity.get("apk_sha256"):
        raise ValueError("Un candidato AAB-only no puede declarar un APK.")
    source_sha = identity.get("source_sha", "")
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise ValueError("SHA de origen inválido.")
    version = identity.get("version_name")
    code = identity.get("build_number")
    if not isinstance(version, str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Versión de Express inválida.")
    if type(code) is not int or code < 1:
        raise ValueError("Código de compilación inválido.")
    expected_prefix = f"single-app-android-qa-v{version}-build{code}-sha{source_sha[:12]}-job"
    if not release_tag.startswith(expected_prefix):
        raise ValueError("Tag de release no corresponde al SHA y versión del candidato.")
    if not re.fullmatch(re.escape(expected_prefix) + r"[0-9a-f]{8}", release_tag):
        raise ValueError("Tag de release de candidato inválido.")
    digest = hashlib.file_digest(bundle_path.open("rb"), "sha256").hexdigest()
    if digest != identity.get("aab_sha256"):
        raise ValueError("El SHA-256 del AAB no coincide con la compilación autorizada.")
    if bundle_path.stat().st_size < 100_000:
        raise ValueError("Archivo AAB demasiado pequeño.")
    return identity


def request_json(session, method: str, url: str, **kwargs) -> dict:
    response = session.request(method, url, timeout=360, **kwargs)
    if not response.ok:
        # Do not print request headers, tokens or secret contents.
        try:
            error = response.json().get("error", {})
            message = error.get("message", "Error de Google Play")
        except ValueError:
            message = "Google Play respondió sin JSON"
        raise RuntimeError(f"Google Play HTTP {response.status_code}: {message[:900]}")
    if response.status_code == 204 or not response.content:
        return {}
    return response.json()


def next_play_build_number(known_codes: set[int], requested_code: int) -> int:
    """Choose a fresh versionCode without altering the visible versionName.

    This is advisory. The official Express signing workflow must compile
    and approve the corresponding source SHA before any Play upload.
    """
    return max(max(known_codes, default=0) + 1, requested_code)


def pick_existing_internal_track(tracks: list[dict]) -> str | None:
    """Select only an internal track actually returned by the connected app."""
    present = {t.get("track") for t in tracks}
    return next((name for name in SAFE_INTERNAL_TRACKS if name in present), None)


def inspect_play(session, edit_id: str, version_code: int, *, publish: bool) -> tuple[int, str | None, bool, int]:
    root = f"{API_BASE}/edits/{edit_id}"
    tracks = request_json(session, "GET", f"{root}/tracks").get("tracks", [])
    used_codes = set()
    selected_internal_track = pick_existing_internal_track(tracks)
    # Read-only diagnostics: track identifiers, release statuses and version
    # codes returned by the *connected account* for this exact package.
    # No testers' emails, credentials, app metadata or private data.
    print(f"Google Play tracks.list: total={len(tracks)}")
    for track in tracks:
        identifier = track.get("track", "(sin nombre)")
        releases = track.get("releases", [])
        info = [
            {
                "status": rel.get("status", "unknown"),
                "versionCodes": rel.get("versionCodes", []),
            }
            for rel in releases
        ]
        print(f"  pista={identifier!r} lanzamientos={json.dumps(info, ensure_ascii=False)}")
    for track in tracks:
        for release in track.get("releases", []):
            for code in release.get("versionCodes", []):
                used_codes.add(int(code))
    bundles = request_json(session, "GET", f"{root}/bundles").get("bundles", [])
    print("Google Play bundles registrados: " + str(sorted(
        int(b["versionCode"]) for b in bundles if "versionCode" in b
    )))
    for bundle in bundles:
        if "versionCode" in bundle:
            used_codes.add(int(bundle["versionCode"]))
    max_code = max(used_codes, default=0)
    available = version_code not in used_codes and version_code > max_code
    suggested_code = next_play_build_number(used_codes, version_code)
    print(f"Google Play verificado: paquete={PACKAGE}, pista_interna={selected_internal_track}, "
          f"mayor versionCode conocido={max_code}, candidato={version_code}, "
          f"candidato_disponible={available}, siguiente_code_sugerido={suggested_code}, "
          f"pista interna configurada={'sí' if selected_internal_track else 'no'}")
    if publish and not available:
        raise ValueError(
            f"Build {version_code} ya fue usado o es anterior al código {max_code} en Google Play. "
            f"Siguiente versionCode recomendado: {suggested_code}. "
            "Compilar un NUEVO AAB oficial firmado, conservando versionName y actualizando "
            "el source SHA autorizado; un AAB existente nunca se renumera."
        )
    return max_code, selected_internal_track, available, suggested_code


def write_summary(text: str):
    path = os.environ.get("GITHUB_STEP_SUMMARY", "")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write(text + "\n")


def publish(args):
    identity = validate_bundle(args.identity, args.aab, args.release_tag)
    version_code = identity["build_number"]
    secret = os.environ.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", "").strip()
    if not secret:
        raise ValueError(
            "Falta el secreto GOOGLE_PLAY_SERVICE_ACCOUNT_JSON en GitHub Actions. "
            "Guardar el JSON de la cuenta play-publisher en Settings → Secrets and variables → Actions."
        )
    try:
        credentials_json = json.loads(secret)
    except ValueError as e:
        raise ValueError("El secreto de Google Play no contiene un JSON válido.") from e
    if credentials_json.get("type") != "service_account" or (
        credentials_json.get("client_email") != EXPECTED_SERVICE_ACCOUNT
    ):
        raise ValueError("La clave JSON no pertenece a la cuenta play-publisher autorizada.")

    from google.oauth2 import service_account
    from google.auth.transport.requests import AuthorizedSession

    creds = service_account.Credentials.from_service_account_info(
        credentials_json,
        scopes=["https://www.googleapis.com/auth/androidpublisher"],
    )
    session = AuthorizedSession(creds)
    edit_id = None
    committed = False
    try:
        edit = request_json(session, "POST", f"{API_BASE}/edits", json={})
        edit_id = edit["id"]
        max_code, selected_internal_track, available, suggested_code = inspect_play(
            session, edit_id, version_code, publish=args.mode == "publish"
        )
        if args.mode == "check":
            write_summary(
                f"### Conexión Google Play correcta\n"
                f"- Aplicación: `{PACKAGE}`\n"
                f"- Pista: **Pruebas internas ({selected_internal_track or 'no detectada'})**\n"
                f"- Código más alto conocido: {max_code}\n"
                f"- Próximo versionCode libre recomendado: **{suggested_code}**\n"
                f"- AAB candidato: {version_code} ({identity['version_name']})\n"
                f"- ¿Se puede subir este AAB?: **{'sí' if available else 'no'}**\n"
                f"- Publicación: **no realizada**\n"
                f"- Pista configurada: {'sí' if selected_internal_track else 'no'}"
            )
            return
        if args.mode != "publish" or args.confirmation != PUBLISH_AUTHORIZATION:
            raise ValueError("La publicación necesita AUTORIZO PRUEBAS INTERNAS.")
        if selected_internal_track not in SAFE_INTERNAL_TRACKS:
            raise ValueError(
                "No existe ninguna pista interna permitida (qa/internal) en la app conectada. "
                "Publicación detenida por seguridad."
            )
        print(f"Publicando únicamente en la pista existente {selected_internal_track}")
        upload_url = (
            f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/"
            f"applications/{PACKAGE}/edits/{edit_id}/bundles?uploadType=media"
        )
        with args.aab.open("rb") as stream:
            bundle = request_json(
                session, "POST", upload_url,
                headers={"Content-Type": "application/octet-stream"},
                data=stream,
            )
        uploaded_code = int(bundle["versionCode"])
        if uploaded_code != version_code:
            raise RuntimeError(
                f"Google devolvió versionCode={uploaded_code}, esperado={version_code}."
            )
        # Never touch 'production', 'alpha' or 'beta'. Only internal test track.
        track_url = f"{API_BASE}/edits/{edit_id}/tracks/{selected_internal_track}"
        request_json(
            session, "PUT", track_url, json={
                "track": selected_internal_track,
                "releases": [{
                    "name": f"Express {identity['version_name']} ({version_code}) - QA",
                    "versionCodes": [str(version_code)],
                    "status": "completed",
                }],
            },
        )
        request_json(session, "POST", f"{API_BASE}/edits/{edit_id}:validate", json={})
        request_json(session, "POST", f"{API_BASE}/edits/{edit_id}:commit", json={})
        committed = True
        print(f"PUBLICADO SOLO EN PRUEBAS INTERNAS: {PACKAGE} track={selected_internal_track} versionCode={version_code}")
        write_summary(
            f"### Express enviado a Pruebas internas\n"
            f"- Paquete: `{PACKAGE}`\n- Pista Google Play: **{selected_internal_track}**\n"
            f"- Versión: **{identity['version_name']} ({version_code})**\n"
            f"- Commit del código: `{identity['source_sha']}`\n"
            f"- Producción: **sin cambios**\n"
            f"- Testers: entrar a Play Console → Pruebas internas y aceptar invitación."
        )
    finally:
        if edit_id and not committed:
            # Both dry runs and failed uploads discard the uncommitted edit.
            try:
                session.delete(f"{API_BASE}/edits/{edit_id}", timeout=30)
            except Exception:
                pass


def self_test():
    from tempfile import TemporaryDirectory
    with TemporaryDirectory() as temp:
        p = Path(temp)
        aab = p / "candidate.aab"
        aab.write_bytes(b"ZIP" * 50_000)
        sha = hashlib.sha256(aab.read_bytes()).hexdigest()
        source_sha = "a" * 40
        identity = {
            "package_name": PACKAGE,
            "artifact_type": "single-app-candidate-apk+aab",
            "source_sha": source_sha,
            "version_name": "1.6.3",
            "build_number": 142,
            "aab_sha256": sha,
        }
        ip = p / "identity.json"
        ip.write_text(json.dumps(identity))
        tag = f"single-app-android-qa-v1.6.3-build142-sha{source_sha[:12]}-job1234abcd"
        assert validate_bundle(ip, aab, tag)["build_number"] == 142
        identity["artifact_type"] = "aab"
        identity["apk_sha256"] = ""
        ip.write_text(json.dumps(identity))
        assert validate_bundle(ip, aab, tag)["artifact_type"] == "aab"
        identity["apk_sha256"] = "abc123"
        ip.write_text(json.dumps(identity))
        try:
            validate_bundle(ip, aab, tag)
        except ValueError:
            pass
        else:
            raise AssertionError("AAB-only manifest accepted fake APK checksum")
        identity["apk_sha256"] = ""
        identity["package_name"] = "com.fake.app"
        ip.write_text(json.dumps(identity))
        try:
            validate_bundle(ip, aab, tag)
        except ValueError:
            pass
        else:
            raise AssertionError("Wrong package incorrectly accepted")
    assert pick_existing_internal_track([{"track": "production"}, {"track": "internal"}]) == "internal"
    assert pick_existing_internal_track([{"track": "production"}, {"track": "qa"}]) == "qa"
    assert pick_existing_internal_track([{"track": "production"}]) is None
    assert pick_existing_internal_track([{"track": "qa"}, {"track": "internal"}]) == "qa"
    # Preserve the display version while moving only the build number.
    assert next_play_build_number({140}, 141) == 141
    assert next_play_build_number({140, 141}, 141) == 142
    assert next_play_build_number({140, 141, 145}, 141) == 146
    assert next_play_build_number(set(), 141) == 141
    print("Play internal publisher self-tests passed.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--mode", choices=["check", "publish"], default="check")
    parser.add_argument("--release-tag", default="")
    parser.add_argument("--identity", type=Path)
    parser.add_argument("--aab", type=Path)
    parser.add_argument("--confirmation", default="")
    opts = parser.parse_args()
    try:
        if opts.self_test:
            self_test()
        else:
            if not opts.identity or not opts.aab:
                raise ValueError("Debe señalar identidad y AAB oficial firmado.")
            publish(opts)
    except (ValueError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
