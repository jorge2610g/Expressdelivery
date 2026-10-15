"""Test authenticated envelope encryption without releasing APK plaintext."""
import base64
import hashlib
import importlib.util
import json
import os
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

source = Path(__file__).resolve().parents[1] / '.github/scripts/encrypt_qa_apk.py'
spec = importlib.util.spec_from_file_location('encrypt_qa_apk', source)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class EncryptionQaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.private = rsa.generate_private_key(public_exponent=65537, key_size=3072)
        cls.pem = cls.private.public_key().public_bytes(
            serialization.Encoding.PEM,
            serialization.PublicFormat.SubjectPublicKeyInfo,
        )

    def request(self, sha):
        return {
            'type':'express-qa-debug-encrypted',
            'source_sha':sha,
            'expires_at':(datetime.now(timezone.utc) + timedelta(hours=2))
                        .strftime('%Y-%m-%dT%H:%M:%SZ'),
            'recipient_public_key_pem_b64':base64.b64encode(self.pem).decode(),
            'delivery_key_fingerprint':hashlib.sha256(self.pem).hexdigest(),
        }

    def test_pins_sha_rejects_wrong_branch_or_expired_request(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'r.json'; r=self.request('a'*40)
            path.write_text(json.dumps(r))
            self.assertEqual(mod.check_request(path,'a'*40,'perf/map-continuity-offline-20261015'),r)
            with self.assertRaises(ValueError):
                mod.check_request(path,'b'*40,'perf/map-continuity-offline-20261015')
            with self.assertRaises(ValueError):
                mod.check_request(path,'a'*40,'main')
            r['expires_at']='2020-01-01T00:00:00Z';path.write_text(json.dumps(r))
            with self.assertRaises(ValueError):
                mod.check_request(path,'a'*40,'perf/map-continuity-offline-20261015')

    def test_ciphertext_decrypts_only_with_private_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp=Path(tmp); content=b'FAKE_APK_FOR_TEST_ONLY'*1000
            apk=tmp/'fake.apk';apk.write_bytes(content)
            out=mod.encrypt_apk(apk,self.pem,'a'*40,tmp/'enc')
            meta=json.loads((out.parent/'metadata.json').read_text())
            self.assertNotEqual(out.read_bytes(),content)
            self.assertFalse((out.parent/'fake.apk').exists())
            key=self.private.decrypt(base64.b64decode(meta['wrapped_aes_key_b64']),
                padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA256()),
                             algorithm=hashes.SHA256(),label=None))
            decrypted=AESGCM(key).decrypt(base64.b64decode(meta['nonce_b64']),
                            out.read_bytes(),base64.b64decode(meta['aad_b64']))
            self.assertEqual(decrypted,content)
            self.assertEqual(meta['apk_sha256'],hashlib.sha256(content).hexdigest())

if __name__=='__main__':
    unittest.main()
