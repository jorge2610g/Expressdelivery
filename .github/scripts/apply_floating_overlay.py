"""Incorpora la ventana flotante de ofertas en el proyecto Android generado.

Se ejecuta en CI después de regenerar android/ (flutter create), así que los
cambios sobreviven a rm -rf android. Solo añade: un permiso de superposición,
un servicio, el canal nativo y su recurso de diseño. No cambia firma, OIDC,
publicación ni la lista de permisos existente.
"""
import re
import sys
from pathlib import Path

PERMISSION = '<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />'
SERVICE = '<service android:name=".FloatingOfferService" android:exported="false" />'
BUBBLE_SERVICE = '<service android:name=".DriverBubbleService" android:exported="false" />'
REGISTER = 'flutterEngine.plugins.add(FloatingOfferPlugin())'


def patch_manifest(manifest: Path) -> None:
    text = manifest.read_text()
    if PERMISSION not in text:
        text = re.sub(
            r'(<manifest[^>]*>)',
            lambda m: m.group(1) + '\n    ' + PERMISSION,
            text,
            count=1,
        )
    if SERVICE not in text:
        text = text.replace('</application>', '    ' + SERVICE + '\n    </application>', 1)
    if BUBBLE_SERVICE not in text:
        text = text.replace('</application>', '    ' + BUBBLE_SERVICE + '\n    </application>', 1)
    manifest.write_text(text)


def register_plugin(main_activity: Path) -> None:
    """Registra el canal nativo en MainActivity (idempotente)."""
    text = main_activity.read_text()
    if REGISTER in text:
        return
    if 'super.configureFlutterEngine(flutterEngine)' in text:
        text = text.replace(
            'super.configureFlutterEngine(flutterEngine)',
            'super.configureFlutterEngine(flutterEngine)\n        ' + REGISTER,
            1,
        )
    else:
        override = (
            '\n    override fun configureFlutterEngine('
            'flutterEngine: io.flutter.embedding.engine.FlutterEngine) {\n'
            '        super.configureFlutterEngine(flutterEngine)\n'
            '        ' + REGISTER + '\n'
            '    }\n'
        )
        bodyless = re.search(r'class MainActivity[^{\n]*\(\)[ \t]*$', text, re.M)
        if bodyless:
            head = bodyless.group(0)
            text = text.replace(head, head + ' {' + override + '}', 1)
        else:
            text = re.sub(
                r'(class MainActivity[^{]*\{)', lambda m: m.group(1) + override, text, count=1
            )
    main_activity.write_text(text)


def copy_sources(overlay: Path, package_dir: Path, res_dir: Path) -> None:
    for kt in (overlay / 'kotlin').rglob('*.kt'):
        target = package_dir / kt.name
        target.write_text(kt.read_text())
    layout_src = overlay / 'res' / 'layout' / 'express_floating_offer.xml'
    layout_dir = res_dir / 'layout'
    layout_dir.mkdir(parents=True, exist_ok=True)
    (layout_dir / layout_src.name).write_text(layout_src.read_text())
    values_src = overlay / 'res' / 'values-es' / 'strings.xml'
    values_dir = res_dir / 'values-es'
    values_dir.mkdir(parents=True, exist_ok=True)
    (values_dir / 'strings.xml').write_text(values_src.read_text())


def main(argv: list[str]) -> int:
    root = Path(argv[1]) if len(argv) > 1 else Path('android/app/src/main')
    manifest = root / 'AndroidManifest.xml'
    if not manifest.exists():
        print('AndroidManifest.xml no encontrado', file=sys.stderr)
        return 1
    patch_manifest(manifest)
    package_dir = Path(argv[2]) if len(argv) > 2 else root / 'kotlin' / 'com' / 'express' / 'usuario1'
    package_dir.mkdir(parents=True, exist_ok=True)
    copy_sources(Path('android_overlay'), package_dir, root / 'res')
    for main_activity in package_dir.glob('MainActivity.kt'):
        register_plugin(main_activity)
    print('Floating offer overlay applied')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
