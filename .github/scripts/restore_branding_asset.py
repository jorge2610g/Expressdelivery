#!/usr/bin/env python3
from base64 import b64decode
from hashlib import sha256
from pathlib import Path

source = Path("assets/branding/express_app_icon_512.b64")
target = Path("assets/branding/express_app_icon.png")
png_signature = b"\x89PNG\r\n\x1a\n"

# Exact SHA-256 of the official Express logo supplied by the owner,
# resized only to 512x512 for app/launcher use. Do not replace this artwork.
expected_sha256 = "53a364e6cc2cd11d432f9e65b88ccfae5072db5334eb5a2127dc7c213d73f312"

if not source.exists():
    raise SystemExit(f"Missing branding source: {source}")

payload = "".join(source.read_text().split())
try:
    data = b64decode(payload, validate=True)
except Exception as exc:
    raise SystemExit(f"Invalid branding base64: {exc}")

if not data.startswith(png_signature):
    raise SystemExit("Branding source does not decode to a PNG")

digest = sha256(data).hexdigest()
if digest != expected_sha256:
    raise SystemExit(
        f"Official Express logo hash mismatch: {digest} != {expected_sha256}"
    )

# Always overwrite the generated PNG. This prevents an old checked-in image,
# cached workspace, or downloaded external asset from replacing the official logo.
target.parent.mkdir(parents=True, exist_ok=True)
target.write_bytes(data)

print(
    f"Restored official Express logo: {target} "
    f"({len(data)} bytes, sha256={digest})"
)
