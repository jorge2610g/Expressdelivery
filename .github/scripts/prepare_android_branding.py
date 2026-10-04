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

# Launcher icons are generated from assets/branding/express_app_icon.png
# by flutter_launcher_icons in the Android build workflow.

# Android notification icons must be monochrome masks. Using the launcher
# background here makes Android render a black square in the shade and a white
# rectangle in the status bar on dark themes.
drawable_dir = Path("android/app/src/main/res/drawable")
drawable_dir.mkdir(parents=True, exist_ok=True)
(drawable_dir / "ic_stat_express.xml").write_text(
    """<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M3,11l2,-5h14l2,5v7h-2a2,2 0,0 1,-4,0H9a2,2 0,0 1,-4,0H3v-7m4,-3 -1.2,3h12.4L17,8H7m0,5a1.5,1.5 0,1 0,0,3 1.5,1.5 0,0 0,0,-3m10,0a1.5,1.5 0,1 0,0,3 1.5,1.5 0,0 0,0,-3"/>
</vector>
"""
)

values_dir = Path("android/app/src/main/res/values")
values_dir.mkdir(parents=True, exist_ok=True)
(values_dir / "express_notification_colors.xml").write_text(
    """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="express_notification_blue">#0B57D0</color>
</resources>
"""
)

# Firebase uses these resources for background notifications. Local
# notifications reference the same drawable from Dart.
if 'com.google.firebase.messaging.default_notification_icon' not in text:
    marker = '    </application>'
    metadata = '''        <meta-data
            android:name="com.google.firebase.messaging.default_notification_icon"
            android:resource="@drawable/ic_stat_express" />
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_color"
            android:resource="@color/express_notification_blue" />
    </application>'''
    if marker not in text:
        raise SystemExit("Android application anchor not found")
    text = text.replace(marker, metadata, 1)


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
