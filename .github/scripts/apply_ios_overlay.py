"""Incorpora la configuración iOS de Express en el proyecto generado por Flutter.

Se ejecuta en CI después de regenerar ios/ (flutter create --platforms=ios), igual
que el overlay de Android, de modo que los cambios sobreviven a rm -rf ios.

Qué aplica:
- Info.plist: nombre visible, textos de permisos, esquema de retorno del login,
  notificaciones remotas y cifrado exento.
- Runner.entitlements: Sign in with Apple y push (copiado desde ios_overlay/).
- project.pbxproj: asocia los entitlements al target Runner (solo com.express.usuario1).
- Podfile: definiciones de permission_handler para cámara, micrófono, ubicación y
  notificaciones.

Es idempotente y no contiene secretos ni credenciales.
"""
import plistlib
import re
import shutil
import sys
from pathlib import Path

ROOT = Path("ios")
OVERLAY = Path("ios_overlay")
BUNDLE_ID = "com.express.usuario1"

INFO_VALUES = {
    "CFBundleDisplayName": "Express",
    "ITSAppUsesNonExemptEncryption": False,
    "NSCameraUsageDescription": (
        "Express usa la cámara para escanear códigos QR, hacer llamadas de video "
        "y verificar tu identidad."
    ),
    "NSMicrophoneUsageDescription": (
        "Express usa el micrófono en las llamadas con tu conductor o pasajero."
    ),
    "NSLocationWhenInUseUsageDescription": (
        "Express usa tu ubicación para mostrar tu posición, encontrar viajes "
        "cercanos y seguir tu viaje."
    ),
    "NSLocationAlwaysAndWhenInUseUsageDescription": (
        "Express usa tu ubicación para conectar con viajes cercanos."
    ),
    "NSPhotoLibraryUsageDescription": (
        "Express usa tus fotos para subir documentos e imagen de perfil."
    ),
}
BACKGROUND_MODES = ["remote-notification"]
PERMISSION_DEFINITIONS = [
    "PERMISSION_CAMERA=1",
    "PERMISSION_MICROPHONE=1",
    "PERMISSION_LOCATION=1",
    "PERMISSION_NOTIFICATIONS=1",
]


def patch_info_plist() -> None:
    path = ROOT / "Runner" / "Info.plist"
    data = plistlib.loads(path.read_bytes())
    data.update(INFO_VALUES)

    modes = list(data.get("UIBackgroundModes", []))
    for mode in BACKGROUND_MODES:
        if mode not in modes:
            modes.append(mode)
    data["UIBackgroundModes"] = modes

    url_types = list(data.get("CFBundleURLTypes", []))
    entry = {"CFBundleURLName": BUNDLE_ID, "CFBundleURLSchemes": [BUNDLE_ID]}
    if entry not in url_types:
        url_types.append(entry)
    data["CFBundleURLTypes"] = url_types

    path.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_XML))


def copy_entitlements() -> None:
    source = OVERLAY / "Runner" / "Runner.entitlements"
    if not source.exists():
        sys.exit(f"Falta {source} en el repositorio")
    shutil.copyfile(source, ROOT / "Runner" / "Runner.entitlements")


def patch_pbxproj() -> None:
    path = ROOT / "Runner.xcodeproj" / "project.pbxproj"
    text = path.read_text()
    line = "CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;"
    if line in text:
        return
    # Solo el target principal: el de pruebas usa com.express.usuario1.RunnerTests.
    pattern = re.compile(
        r"^([ \t]*)PRODUCT_BUNDLE_IDENTIFIER = " + re.escape(BUNDLE_ID) + r";\n",
        re.M,
    )
    count = 0

    def add_entitlements(match: re.Match) -> str:
        nonlocal count
        count += 1
        return match.group(0) + f"{match.group(1)}{line}\n"

    updated = pattern.sub(add_entitlements, text)
    if count == 0:
        sys.exit("No se encontró PRODUCT_BUNDLE_IDENTIFIER del target Runner")
    path.write_text(updated)


def ensure_podfile() -> Path:
    """Flutter 3.47 no siempre deja ios/Podfile en el scaffold: se toma la
    plantilla oficial del mismo SDK que compila el build."""
    path = ROOT / "Podfile"
    if path.exists():
        return path
    flutter = shutil.which("flutter")
    if not flutter:
        sys.exit("No se encontró flutter para copiar la plantilla de Podfile")
    sdk_root = Path(flutter).resolve().parents[1]
    template = sdk_root / "packages" / "flutter_tools" / "templates" / "cocoapods" / "Podfile-ios"
    if not template.exists():
        sys.exit(f"Falta la plantilla de Podfile en {template}")
    shutil.copyfile(template, path)
    return path


def patch_podfile() -> None:
    path = ensure_podfile()
    text = path.read_text()
    if "PERMISSION_CAMERA=1" in text:
        return
    marker = "flutter_additional_ios_build_settings(target)"
    if marker not in text:
        sys.exit("Podfile sin el bloque post_install de Flutter")
    indent = re.search(r"^([ \t]*)" + re.escape(marker), text, re.M).group(1)
    definitions = ", ".join(f"'{item}'" for item in PERMISSION_DEFINITIONS)
    block = (
        f"\n{indent}# Permisos de permission_handler (overlay Express iOS)\n"
        f"{indent}target.build_configurations.each do |config|\n"
        f"{indent}  defs = config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)']\n"
        f"{indent}  [{definitions}].each do |d|\n"
        f"{indent}    defs << d unless defs.include?(d)\n"
        f"{indent}  end\n"
        f"{indent}end"
    )
    path.write_text(text.replace(marker, marker + block, 1))


def main() -> None:
    if not ROOT.exists():
        sys.exit("Falta ios/. Ejecuta flutter create --platforms=ios antes.")
    patch_info_plist()
    copy_entitlements()
    patch_pbxproj()
    patch_podfile()
    print("Overlay iOS aplicado")


if __name__ == "__main__":
    main()
