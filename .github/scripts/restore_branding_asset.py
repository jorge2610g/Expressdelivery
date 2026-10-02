#!/usr/bin/env python3
from base64 import b64decode
from pathlib import Path

source = Path("assets/branding/express_app_icon_512.b64")
target = Path("assets/branding/express_app_icon.png")

if not source.exists():
    raise SystemExit(f"Missing branding source: {source}")

payload = "".join(source.read_text().split())
try:
    data = b64decode(payload, validate=True)
except Exception as exc:
    raise SystemExit(f"Invalid branding base64: {exc}")

png_signature = b"\x89PNG\r\n\x1a\n"
if not data.startswith(png_signature):
    raise SystemExit("Branding source does not decode to a PNG")

target.parent.mkdir(parents=True, exist_ok=True)
target.write_bytes(data)

print(f"Restored official Express icon: {target} ({len(data)} bytes)")
