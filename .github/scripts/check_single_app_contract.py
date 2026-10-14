#!/usr/bin/env python3
"""Enforce official Android package and a shared account-scoped runtime."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def check(value: bool, explanation: str) -> None:
    if not value:
        raise SystemExit("SINGLE_APP_CONTRACT: " + explanation)

def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

for deprecated in (
    ".github/workflows/shorebird-preview-codepush.yml",
    ".github/workflows/shorebird-bootstrap-preview.yml",
    ".github/workflows/express-qa.yml",
    ".github/workflows/express-qa-collect-all.yml",
    ".github/recovery/preview-release-recovery.json",
    ".github/preview-build-request.txt",
    "lib/preview_main.dart",
):
    check(not (ROOT / deprecated).exists(), "obsolete separate-app path: " + deprecated)

android = source(".github/workflows/build-android.yml")
qa = source(".github/workflows/express-single-app-qa.yml")
web = source(".github/workflows/deploy-web.yml")
mobile = source("lib/mobile_main.dart")

check("com.express.usuario1" in android, "official Android package missing")
check("com.express.usuario.preview" not in android, "duplicate Android package")
check("preview-apk" not in android, "duplicate Android artifact")
check("com.express.usuario.qa" not in qa, "temporary Android QA package")
check("native-on-demand:" not in qa, "separate APK QA job")
check("flutter test" in qa, "Flutter QA must remain active")
check("--target lib/web_main.dart" in web, "keep the single canonical web build")
check("resolveExpressRuntimeAccess" in source("lib/core/runtime_access.dart"), "account-scoped runtime missing")

print("PASS: one official Android package and shared Web/QA contexts.")
