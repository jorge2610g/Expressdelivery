"""Incorpora overlay y permisos Android en el proyecto oficial generado.

Se ejecuta en CI después de regenerar android/ (flutter create), de modo que los
cambios sobreviven a rm -rf android. Las modificaciones son idempotentes.
"""
import re
import sys
from pathlib import Path

PERMISSION = '<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />'
BACKGROUND_LOCATION_PERMISSION = (
    '<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />'
)
SERVICE = '<service android:name=".FloatingOfferService" android:exported="false" />'
BUBBLE_SERVICE = '<service android:name=".DriverBubbleService" android:exported="false" />'
MESSAGING_SERVICE = (
    '<service android:name=".ExpressMessagingService" android:exported="false">'
    '<intent-filter><action android:name="com.google.firebase.MESSAGING_EVENT" />'
    '</intent-filter></service>'
)
REGISTER = 'flutterEngine.plugins.add(FloatingOfferPlugin())'


# Firebase Messaging se declara como implementation en el plugin: sin esta línea,
# el servicio nativo de ofertas no ve sus clases. Versión alineada con firebase_core 4.15.0.
FIREBASE_DEPS = (
    '    implementation(platform("com.google.firebase:firebase-bom:34.19.0"))\n'
    '    implementation("com.google.firebase:firebase-messaging")\n'
)


def patch_app_gradle(gradle: Path) -> None:
    if not gradle.exists():
        return
    text = gradle.read_text()
    if 'firebase-messaging' in text:
        return
    if 'dependencies {' in text:
        text = text.replace('dependencies {', 'dependencies {\n' + FIREBASE_DEPS, 1)
    else:
        text = text.rstrip() + '\n\ndependencies {\n' + FIREBASE_DEPS + '}\n'
    gradle.write_text(text)


def patch_manifest(manifest: Path) -> None:
    text = manifest.read_text()
    for permission in (PERMISSION, BACKGROUND_LOCATION_PERMISSION):
        if permission not in text:
            text = re.sub(
                r'(<manifest[^>]*>)',
                lambda match: match.group(1) + '\n    ' + permission,
                text,
                count=1,
            )
    if SERVICE not in text:
        text = text.replace('</application>', '    ' + SERVICE + '\n    </application>', 1)
    if BUBBLE_SERVICE not in text:
        text = text.replace('</application>', '    ' + BUBBLE_SERVICE + '\n    </application>', 1)
    if 'ExpressMessagingService' not in text:
        text = text.replace('</application>', '    ' + MESSAGING_SERVICE + '\n    </application>', 1)
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
                r'(class MainActivity[^{]*\{)', lambda match: match.group(1) + override, text, count=1
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
    # Idioma por defecto de las mismas claves: un archivo propio, sin tocar values/strings.xml
    # del scaffold. Sin él, el lint de release marca ExtraTranslation.
    base_src = overlay / 'res' / 'values' / 'express_call_labels.xml'
    base_dir = res_dir / 'values'
    base_dir.mkdir(parents=True, exist_ok=True)
    (base_dir / base_src.name).write_text(base_src.read_text())


def main(argv: list[str]) -> int:
    root = Path(argv[1]) if len(argv) > 1 else Path('android/app/src/main')
    manifest = root / 'AndroidManifest.xml'
    if not manifest.exists():
        print('AndroidManifest.xml no encontrado', file=sys.stderr)
        return 1
    patch_manifest(manifest)
    patch_app_gradle(root.parent.parent / 'build.gradle.kts')
    package_dir = Path(argv[2]) if len(argv) > 2 else root / 'kotlin' / 'com' / 'express' / 'usuario1'
    package_dir.mkdir(parents=True, exist_ok=True)
    copy_sources(Path('android_overlay'), package_dir, root / 'res')
    for main_activity in package_dir.glob('MainActivity.kt'):
        register_plugin(main_activity)
    print('Floating offer overlay applied')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
