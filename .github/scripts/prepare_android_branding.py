#!/usr/bin/env python3
from pathlib import Path
import os
import sys

import subprocess

if len(sys.argv) != 3:
    raise SystemExit("usage: prepare_android_branding.py <package_name> <label>")

package_name = sys.argv[1].strip()
label = sys.argv[2].strip()

# Always restore and validate the canonical Express PNG before any Android or
# QA build consumes it. The release workflow already does this explicitly,
# while the x86_64 QA scaffold reaches this helper directly.
restore_script = Path(".github/scripts/restore_branding_asset.py")
if not restore_script.exists():
    raise SystemExit(f"Missing branding restore helper: {restore_script}")
subprocess.run([sys.executable, str(restore_script)], check=True)

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

# Android notification *small icons* must be white monochrome masks.
# The official Express logo has a blue square, speed lines and a white wing.
# Reconstruct its recognizable silhouette rather than using a generic car.
# The transparent wing is cut out using evenOdd; Android will tint the mask.
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
        android:fillType="evenOdd"
        android:pathData="M9.2,7.2 L18.8,7.2 L18.8,16.8 L9.2,16.8 Z
                          M9.2,8.6 L10.7,8.6
                          C12.2,8.6 12.9,9.2 13.7,10.3
                          L15.4,12.6
                          C15.9,13.2 16.3,13.5 17.0,13.6
                          L17.4,13.6
                          C18.1,13.6 18.1,14.6 17.4,14.6
                          L13.7,14.6
                          C13.1,14.6 12.8,14.2 12.8,13.8
                          L11.1,13.8
                          C10.4,13.8 10.4,12.8 11.1,12.8
                          L11.4,12.8
                          C10.2,12.5 9.6,11.2 9.2,10.5 Z"/>
    <path
        android:fillColor="#FFFFFFFF"
        android:strokeColor="#FFFFFFFF"
        android:strokeWidth="0.5"
        android:strokeLineCap="round"
        android:pathData="M4.6,9.8 L10.7,9.8
                          M6.3,11.3 L12.2,11.3"/>
</vector>
"""
)

# Foreground notifications are allowed a full-colour large icon. Use the
# SHA-verified official logo (NOT the monochrome small-icon mask).
import shutil
large_icon_dir = Path("android/app/src/main/res/drawable-nodpi")
large_icon_dir.mkdir(parents=True, exist_ok=True)
shutil.copyfile(
    "assets/branding/express_app_icon.png",
    large_icon_dir / "ic_express_notification_large.png",
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

# Google Mobile Ads requires an Android application ID in the manifest even
# before the first banner is loaded. Preview uses Google's official sample ID;
# Production can inject ADMOB_ANDROID_APP_ID from GitHub Actions without a
# source-code change. Production banners remain disabled until a real ad-unit
# ID and the remote runtime flag are both configured.
admob_app_id = os.environ.get("ADMOB_ANDROID_APP_ID", "").strip()
if not admob_app_id:
    admob_app_id = "ca-app-pub-3940256099942544~3347511713"

if 'com.google.android.gms.ads.APPLICATION_ID' not in text:
    marker = '    </application>'
    metadata = f'''        <meta-data
            android:name="com.google.android.gms.ads.APPLICATION_ID"
            android:value="{admob_app_id}" />
    </application>'''
    if marker not in text:
        raise SystemExit("Android application anchor not found for AdMob")
    text = text.replace(marker, metadata, 1)

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
