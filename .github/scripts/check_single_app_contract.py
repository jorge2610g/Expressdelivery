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

# Una sola app: los workflows de la app paralela ya no existen en el repositorio.
for removed in (
    ".github/workflows/shorebird-preview-codepush.yml",
    ".github/workflows/shorebird-bootstrap-preview.yml",
    ".github/workflows/express-qa.yml",
    ".github/workflows/express-qa-collect-all.yml",
):
    check(not (root / removed).exists(),
          removed + " pertenece a la app paralela y debe permanecer eliminado")

check(not (root / ".github/workflows/demand-preview-patch.yml").exists(),
      "obsolete pinned Preview patch workflow must stay removed")

android = read(".github/workflows/build-android.yml")
single = read(".github/workflows/express-single-app-qa.yml")
web = read(".github/workflows/deploy-web.yml")
mobile = read("lib/mobile_main.dart")

check("target=lib/mobile_main.dart" in android,
      "Android release builder must use the unique mobile entrypoint")
check("--target lib/preview_main.dart" not in android and "target=lib/preview_main.dart" not in android,
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
check("native_android" not in single and "com.express.usuario.qa" not in single,
      "no existe APK de QA con paquete paralelo: una sola app, un solo build")
check("retention-days: 1" not in single,
      "no debe haber APK temporal de larga vida en el flujo de QA")

# Una sola app y trazabilidad única en todos los workflows.
import glob
for wf in glob.glob(str(root / ".github/workflows/*.yml")):
    text = Path(wf).read_text()
    name = Path(wf).name
    check("com.express.usuario.preview" not in text and "com.express.usuario.qa" not in text,
          name + " no debe referenciar paquetes paralelos")
    check("git push origin HEAD:main" not in text,
          name + " no debe hacer push directo a main")

print("PASS: Express single-app, Web-first QA and legacy manual-gate contract.")
