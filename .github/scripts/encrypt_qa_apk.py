"""User-requested encrypted Android QA delivery. Never emit plaintext APK artifacts."""
import base64
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

def check_request(path: Path, source_sha: str, branch: str) -> dict:
    request = json.loads(path.read_text(encoding='utf8'))
    if request.get('type') != 'express-qa-debug-encrypted':
        raise ValueError('Only user-requested encrypted QA builds are permitted')
    if request.get('source_sha') != source_sha:
        raise ValueError('Request source SHA must be the HEAD parent')
    if branch != 'perf/map-continuity-offline-20261015':
        raise ValueError('Builds are restricted to Express QA PR branch')
    raw_expiry = request.get('expires_at', '')
    if not raw_expiry.endswith('Z'):
        raise ValueError('Request expiration must be UTC')
    expiry = datetime.fromisoformat(raw_expiry.replace('Z', '+00:00'))
    if datetime.now(timezone.utc) >= expiry:
        raise ValueError('Expired user request')
    name = request.get('delivery_key_fingerprint', '')
    if len(name) != 64 or any(c not in '0123456789abcdef' for c in name):
        raise ValueError('Missing RSA recipient fingerprint')
    pem = base64.b64decode(request['recipient_public_key_pem_b64'], validate=True)
    if hashlib.sha256(pem).hexdigest() != name:
        raise ValueError('Recipient public key fingerprint mismatch')
    return request

def encrypt_apk(path: Path, public_pem: bytes, source_sha: str, dest: Path) -> Path:
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa, padding
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    public = serialization.load_pem_public_key(public_pem)
    if not isinstance(public, rsa.RSAPublicKey) or public.key_size < 3072:
        raise ValueError('RSA recipient key must have at least 3072 bits')
    plaintext = path.read_bytes()
    if not plaintext:
        raise ValueError('APK is empty')
    key = os.urandom(32)
    nonce = os.urandom(12)
    aad = f'express-qa-apk:{source_sha}'.encode()
    ciphertext = AESGCM(key).encrypt(nonce, plaintext, aad)
    sealed = public.encrypt(key, padding.OAEP(
        mgf=padding.MGF1(algorithm=hashes.SHA256()),
        algorithm=hashes.SHA256(), label=None,
    ))
    dest.mkdir(parents=True, exist_ok=True)
    out = dest / 'express-qa.apk.aesgcm'
    out.write_bytes(ciphertext)
    meta = {
        'type': 'express-qa-debug-encrypted',
        'version': '1',
        'source_sha': source_sha,
        'ciphertext_filename': out.name,
        'aad_b64': base64.b64encode(aad).decode(),
        'nonce_b64': base64.b64encode(nonce).decode(),
        'wrapped_aes_key_b64': base64.b64encode(sealed).decode(),
        'apk_sha256': hashlib.sha256(plaintext).hexdigest(),
        'ciphertext_sha256': hashlib.sha256(ciphertext).hexdigest(),
        'apk_bytes': len(plaintext),
        'warning': 'Debug QA only, package suffix .qa; not Google Play or production signed',
    }
    (dest / 'metadata.json').write_text(json.dumps(meta, indent=2) + '\n')
    # Deliberately never copy the plaintext into the upload directory.
    return out

if __name__ == '__main__':
    if len(sys.argv) != 5:
        raise SystemExit('Usage: script.py validate|encrypt request.json source_sha path')
    action, request_path, sha, location = sys.argv[1:]
    request = check_request(Path(request_path), sha,
                            os.environ.get('GITHUB_REF_NAME', ''))
    if action == 'validate':
        print('Authorized, unexpired, source-pinned encrypted QA request')
    elif action == 'encrypt':
        apk = Path(location)
        pem = base64.b64decode(request['recipient_public_key_pem_b64'], validate=True)
        output = encrypt_apk(apk, pem, sha, Path('build/qa-encrypted'))
        print(f'Only encrypted QA artifact prepared: {output.name}')
    else:
        raise ValueError('Unknown action')
