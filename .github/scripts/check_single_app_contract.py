#!/usr/bin/env python3
"""Hard gate: one Express Android application, one admin web, account-scoped QA."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def check(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("ONE_APP_ONE_ADMIN violation: " + message)


for legacy in (
    ".github/workflows/shorebird-preview-codepush.yml",
    ".github/workflows/shorebird-bootstrap-preview.yml",
    ".github/workflows/express-qa.yml",
    ".github/workflows/demand-preview-patch.yml",
):
    check(not (ROOT / legacy).exists(), f"obsolete independent Android Preview path: {legacy}")

android = read(".github/workflows/build-android.yml")
web = read(".github/workflows/deploy-web.yml")
qa = read(".github/workflows/express-single-app-qa.yml")
admin = read("AGENTS.md")

check('target=lib/mobile_main.dart' in android,
      "official build must always use lib/mobile_main.dart")
check('package_name=com.express.usuario1' in android,
      "official Android package must be com.express.usuario1")
check('project_name=preview' not in android
      and 'com.express.usuario.preview' not in android
      and 'com.express.usuario.qa' not in android,
      "no independent Preview/QA Android package may be generated")
check('case "$ARTIFACT_TYPE" in' in android
      and 'apk+aab|candidate-apk+aab|single-app-candidate-apk+aab' in android,
      "builder must reject nonofficial APK artifact types")
check('--dart-define="EXPRESS_PREVIEW_MODE=false"' in android,
      "official APK must start without a separate Preview-build mode")
check("--target lib/preview_main.dart" not in android,
      "Preview wrapper must not be an Android build target")
check(not (ROOT / "lib/preview_main.dart").exists(),
      "obsolete Preview entrypoint must be removed")
check("flutter build web --release" in web
      and "--target lib/web_preview.dart" in web,
      "existing public Express Web deploy must remain intact")
check("pull_request:" in qa and "flutter test" in qa and "flutter build web --release" in qa,
      "PR checks must continue testing the shared code")
check("native-on-demand:" not in qa
      and "com.express.usuario.qa" not in qa,
      "QA must use the signed official APK; no second temporary Android app")
check("UNA WEB, UNA APK" in admin,
      "authority rule must be visible to future coding agents")

print("PASS: one Android package, one admin web and account-isolated QA.")
