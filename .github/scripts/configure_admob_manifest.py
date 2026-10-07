#!/usr/bin/env python3
from pathlib import Path
import re
import sys

TEST_APP_ID = "ca-app-pub-3940256099942544~3347511713"

requested = sys.argv[1].strip() if len(sys.argv) > 1 else ""
app_id = requested if re.fullmatch(r"ca-app-pub-\d+~\d+", requested) else TEST_APP_ID

manifest = Path("android/app/src/main/AndroidManifest.xml")
source = manifest.read_text()
name = "com.google.android.gms.ads.APPLICATION_ID"

if name in source:
    source = re.sub(
        r'(<meta-data\s+android:name="com\.google\.android\.gms\.ads\.APPLICATION_ID"\s+android:value=")[^"]+("/>)',
        rf'\g<1>{app_id}\2',
        source,
    )
else:
    marker = "</application>"
    metadata = (
        '        <meta-data\n'
        f'            android:name="{name}"\n'
        f'            android:value="{app_id}" />\n'
    )
    if marker not in source:
        raise SystemExit("AndroidManifest.xml has no </application> marker")
    source = source.replace(marker, metadata + "    " + marker, 1)

manifest.write_text(source)
print(f"AdMob Android application ID configured: {app_id}")
