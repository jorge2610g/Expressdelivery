#!/usr/bin/env python3
"""Contract guard: Web first, one shared Flutter app, no automatic Preview builds."""
from pathlib import Path

root = Path(__file__).resolve().parents[2]

def check(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("Single-app contract violated: " + message)

def read(path: str) -> str:
    return (root / path).read_text(encoding="utf-8")

def workflow_triggers(path: str) -> str:
    source = read(path)
    check("\non:\n" in source and "\npermissions:\n" in source,
          path + " has unexpected workflow trigger structure")
    return source.split("\non:\n", 1)[1].split("\npermissions:\n", 1)[0]

for legacy in (
    ".github/workflows/shorebird-preview-codepush.yml",
    ".github/workflows/shorebird-bootstrap-preview.yml",
    ".github/workflows/express-qa.yml",
):
    trigger = workflow_triggers(legacy)
    check("workflow_dispatch:" in trigger,
          legacy + " must remain manually callable for the legacy release gate")
    check("push:" not in trigger and "schedule:" not in trigger
          and "workflow_run:" not in trigger,
          legacy + " must not generate or audit APK Preview automatically")

check(not (root / ".github/workflows/demand-preview-patch.yml").exists(),
      "obsolete pinned Preview patch workflow must stay removed")

android = read(".github/workflows/build-android.yml")
shorebird = read(".github/workflows/shorebird-preview-codepush.yml")
single = read(".github/workflows/express-single-app-qa.yml")
web = read(".github/workflows/deploy-web.yml")
mobile = read("lib/mobile_main.dart")

check("target=lib/mobile_main.dart" in android,
      "Android release builder must use the unique mobile entrypoint")
check("--target lib/mobile_main.dart" in shorebird,
      "manual legacy build must use the same native entrypoint")
check("lib/preview_main.dart" not in android.replace("lib/preview_main.dart \\", ""),
      "Preview wrapper must never be the official Android release target")
check("bool.fromEnvironment(" in mobile and "'EXPRESS_PREVIEW_MODE'" in mobile,
      "native runtime environment must be explicit")
check("com.express.usuario1" in android,
      "official Android production package must not change")
check("flutter build web --release" in web
      and "--target lib/web_preview.dart" in web,
      "existing Web production deployment must continue")
check("pull_request:" in single and "flutter test" in single
      and "flutter build web --release" in single,
      "Web-first QA must test PRs")
check("native_android:" in single
      and "github.event_name == 'workflow_dispatch' && inputs.native_android" in single
      and "--target lib/mobile_main.dart" in single,
      "Android QA must be manual-only and from the shared entrypoint")
check("retention-days: 1" in single
      and "com.express.usuario.qa" in single,
      "temporary Android QA must not become a long-lived release")

print("PASS: Express single-app, Web-first QA and legacy manual-gate contract.")
