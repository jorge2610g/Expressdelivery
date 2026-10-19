#!/usr/bin/env python3
"""Static regression checks for the gated Express AAB-only test pipeline.

These are contract checks. They cannot substitute a real signed AAB build
or a Play Console upload and must not deploy the Supabase Edge Function.
"""
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
workflow = yaml.safe_load((ROOT / ".github/workflows/build-android.yml").read_text())
worker = (ROOT / "supabase/functions/android-build-worker/index.ts").read_text()
publisher = (ROOT / "scripts/play_internal.py").read_text()
steps = {step["name"]: step for step in workflow["jobs"]["build"]["steps"]}

def has(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)
    print("OK:", message)

has("aab" in steps["Verify build source identity"]["run"],
    "AAB-only is an explicitly allowed artifact type")
has("steps.claim.outputs.artifact_type != 'aab'" in steps["Build release APK"]["if"],
    "AAB-only never executes flutter build apk")
has("flutter build apk --release" in steps["Build release APK"]["run"],
    "Standard mode continues to build an APK")
has("flutter build appbundle --release" in steps["Build release AAB"]["run"],
    "AAB uses the existing Flutter release builder")
has("steps.mode.outputs.preview != 'true'" in steps["Build release AAB"]["if"],
    "AAB mode remains a non-Preview Express bundle")
for step in ("Verify built Android identity", "Verify Android notification icon"):
    has("steps.claim.outputs.artifact_type != 'aab'" in steps[step]["if"],
        f"APK-only verification skipped for internal AAB: {step}")
aab = steps["Verify official signed AAB-only candidate"]
has("steps.claim.outputs.artifact_type == 'aab'" in aab["if"],
    "AAB verification is type-gated")
has("jarsigner -verify" in aab["run"],
    "AAB package has signature verification")
has("base/resources.pb" in aab["run"],
    "AAB package has resource verification")
has("com.express.usuario1" in aab["run"],
    "Same Express package is checked")
has("unexpected APK" in aab["run"],
    "AAB-only fails if any APK is generated")
stage = steps["Prepare public release names"]["run"]
has('if [ "${{ steps.claim.outputs.artifact_type }}" != "aab" ]; then' in stage,
    "AAB packaging does not copy an APK")
has('APK_SHA256=""' in stage and 'if [ -s "$APK" ]; then' in stage,
    "AAB-only identity has an empty APK checksum")
release = steps["Publish signed Android artifacts as GitHub Release"]["run"]
has('if [ "${{ steps.claim.outputs.artifact_type }}" = "aab" ]; then' in release,
    "Only-AAB release branch exists")
aab_release = release.split('if [ "${{ steps.claim.outputs.artifact_type }}" = "aab" ]; then', 1)[1].split("elif ", 1)[0]
has(".aab" in aab_release and ".apk" not in aab_release,
    "Internal release includes AAB and identity, not APK")
has('APK_URL=""' in release, "Only-AAB release has no fake APK URL")
worker_checks = [
    "['single-app-candidate-apk+aab', 'aab'].includes(job.artifact_type)",
    "'aab'].includes(job.artifact_type)",
    "job.artifact_type !== 'aab' && !/^[0-9a-f]{64}$/i.test(apkSha256)",
    "aabOnly ? (!aabUrl || apkUrl || apkSha256)",
    "artifact_url: aabOnly ? aabUrl : apkUrl",
    "apk_sha256: aabOnly ? null",
    "job.status !== 'building'",
]
for check in worker_checks:
    has(check in worker, f"Edge Function has AAB-only gate: {check}")
has('"aab"' in publisher and 'validate_bundle' in publisher,
    "Play publisher accepts verified AAB-only identity")
has('INTERNAL_TRACK = "qa"' in publisher,
    "Uploader only writes to Google Play internal QA track")
has('PUBLISH_AUTHORIZATION = "AUTORIZO PRUEBAS INTERNAS"' in publisher,
    "Play uploads still need explicit confirmation")
print("AAB-only QA pipeline contracts: all passed.")
