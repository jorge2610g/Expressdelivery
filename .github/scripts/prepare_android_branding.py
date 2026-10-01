#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 3:
    raise SystemExit("usage: prepare_android_branding.py <package_name> <label>")

package_name = sys.argv[1].strip()
label = sys.argv[2].strip()

manifest = Path("android/app/src/main/AndroidManifest.xml")
if not manifest.exists():
    raise SystemExit("AndroidManifest.xml not found")

text = manifest.read_text()

# Keep the generated Flutter application but harden the Android container.
if 'android:allowBackup=' not in text:
    text = text.replace(
        '<application\n',
        '<application\n'
        '        android:allowBackup="false"\n'
        '        android:usesCleartextTraffic="false"\n',
        1,
    )

# Use the official Express launcher artwork when available.
official_icon = Path("assets/branding/express_app_icon.png")
icon_ref = "@drawable/express_launcher"
if official_icon.exists():
    import shutil
    drawable_nodpi = Path("android/app/src/main/res/drawable-nodpi")
    drawable_nodpi.mkdir(parents=True, exist_ok=True)
    shutil.copy2(official_icon, drawable_nodpi / "express_app_icon.png")
    icon_ref = "@drawable/express_app_icon"

text = text.replace('android:icon="@mipmap/ic_launcher"', f'android:icon="{icon_ref}"')
text = text.replace('android:roundIcon="@mipmap/ic_launcher_round"', f'android:roundIcon="{icon_ref}"')

# OAuth callback back into the installed app.
if f'android:scheme="{package_name}"' not in text:
    marker = '            </intent-filter>\n        </activity>'
    deep_link = f'''            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data
                    android:scheme="{package_name}"
                    android:host="login-callback" />
            </intent-filter>
        </activity>'''
    if marker not in text:
        raise SystemExit("MainActivity intent-filter anchor not found")
    text = text.replace(marker, deep_link, 1)

manifest.write_text(text)

print(f"Express Android branding ready for {package_name} ({label})")
