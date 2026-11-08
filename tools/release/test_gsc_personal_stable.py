import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import gsc_personal_stable as release


class PersonalStableIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.assets = self.root / "assets"
        self.assets.mkdir()
        self.commit = "a" * 40
        for name in release.BINARIES:
            (self.assets / name).write_bytes(b"MZ" + b"test fixture, never executed" * 5000)
        (self.assets / "SHA256SUMS.txt").write_text("".join(
            release.digest(self.assets / name) + "  " + name + "\n" for name in release.BINARIES), encoding="ascii")
        (self.root / "deploy").mkdir()
        (self.root / "docs/releases").mkdir(parents=True)
        release.write_json(self.root / "deploy" / release.LEDGER, {"schema": 1,
            "scope": "personal_operator_accepted", "full_live_qa_pass_claimed": False,
            "evidence": [{"status": "operator_accepted"}, {"status": "not_run"}]})
        release.write_json(self.root / "FINAL-RELEASE-GATES.json", {"release": {"stable_release_allowed": False}})
        (self.root / "docs/releases/GSC-5.0.0.md").write_text("Personal scope; live QA not claimed.\n", encoding="utf-8")
        release.prepare(self.assets, self.root, release.TAG, self.commit, 123)
        openssl_dir = Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Git/usr/bin"
        if not shutil.which("openssl") and (openssl_dir / "openssl.exe").is_file():
            self.env = patch.dict(os.environ, {"PATH": str(openssl_dir) + os.pathsep + os.environ["PATH"]})
            self.env.start()
            self.addCleanup(self.env.stop)
        self.private = self.root / "disposable-test-key.pem"
        self.openssl("genpkey", "-algorithm", "ED25519", "-out", str(self.private))
        self.openssl("pkey", "-in", str(self.private), "-pubout", "-out", str(self.assets / "deployment-public.pem"))
        self.pin = patch.object(release, "PUBLIC_KEY_SHA256", release.digest(self.assets / "deployment-public.pem"))
        self.pin.start()
        self.addCleanup(self.pin.stop)
        self.sign_and_seal()

    def openssl(self, *args):
        subprocess.run(["openssl", *args], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def sign_and_seal(self):
        self.openssl("pkeyutl", "-sign", "-rawin", "-inkey", str(self.private), "-in",
            str(self.assets / release.MANIFEST), "-out", str(self.assets / (release.MANIFEST + ".sig")))
        release.seal(self.assets)

    def verify(self, metadata=None):
        return release.verify(self.assets, self.root, release.TAG, self.commit, metadata)

    def test_gsc_only_manifest_and_real_ed25519_verification(self):
        self.assertEqual(self.verify(), 123)

    def test_wrong_trusted_public_key_rejected(self):
        with patch.object(release, "PUBLIC_KEY_SHA256", "0" * 64):
            with self.assertRaisesRegex(ValueError, "public key mismatch"):
                self.verify()

    def test_tampered_binary_rejected_even_after_checksums_rewritten(self):
        with (self.assets / release.BINARIES[0]).open("ab") as stream:
            stream.write(b"tamper")
        release.seal(self.assets)
        with self.assertRaisesRegex(ValueError, "signed Windows binary mismatch"):
            self.verify()

    def test_standalone_host_tampering_rejected(self):
        with (self.assets / "GeumyiServerHost.exe").open("ab") as stream:
            stream.write(b"tamper")
        release.seal(self.assets)
        with self.assertRaisesRegex(ValueError, "signed Windows binary mismatch"):
            self.verify()

    def test_invalid_signature_rejected_even_after_checksums_rewritten(self):
        manifest = release.load(self.assets / release.MANIFEST)
        manifest["source_commit"] = "b" * 40
        release.write_json(self.assets / release.MANIFEST, manifest)
        release.seal(self.assets)
        with self.assertRaises(subprocess.CalledProcessError):
            self.verify()

    def test_unrelated_components_rejected_even_when_signed(self):
        manifest = release.load(self.assets / release.MANIFEST)
        manifest["components"]["unrequested_plugin"] = {}
        release.write_json(self.assets / release.MANIFEST, manifest)
        self.sign_and_seal()
        with self.assertRaisesRegex(ValueError, "GSC only"):
            self.verify()

    def test_full_live_qa_claim_rejected(self):
        ledger = release.load(self.root / "deploy" / release.LEDGER)
        ledger["full_live_qa_pass_claimed"] = True
        with self.assertRaisesRegex(ValueError, "must not be claimed"):
            release.validate_ledger(ledger)

    def test_draft_requires_exact_commit_and_complete_remote_digests(self):
        metadata = self.root / "draft.json"
        value = {"draft": True, "prerelease": False, "tag_name": release.TAG,
            "body": (self.assets / release.NOTES).read_text(encoding="utf-8"),
            "target_commitish": self.commit, "assets": [{"name": name,
                "size": (self.assets / name).stat().st_size,
                "digest": "sha256:" + release.digest(self.assets / name)} for name in release.EXPECTED_FILES]}
        release.write_json(metadata, value)
        self.assertEqual(self.verify(metadata), 123)
        value["target_commitish"] = "main"
        release.write_json(metadata, value)
        with self.assertRaisesRegex(ValueError, "exact-commit"):
            self.verify(metadata)

    def test_duplicate_checksum_rows_rejected(self):
        path = self.assets / "SHA256SUMS.txt"
        with path.open("a", encoding="ascii") as stream:
            stream.write(path.read_text(encoding="ascii").splitlines()[0] + "\n")
        with self.assertRaisesRegex(ValueError, "duplicate checksum"):
            self.verify()


if __name__ == "__main__":
    unittest.main()
