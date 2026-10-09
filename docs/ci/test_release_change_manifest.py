#!/usr/bin/env python3
"""Regression tests for PR change traceability. Does not access the network."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("release_change_manifest.py")
SPEC = importlib.util.spec_from_file_location("release_change_manifest", SCRIPT)
assert SPEC and SPEC.loader
manifest = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(manifest)

BASE = "a" * 40
PR_HEAD = "b" * 40
MERGE = "c" * 40
TREE = "d" * 40


class ReleaseChangeManifestTests(unittest.TestCase):
    def test_risk_classifies_sensitive_surfaces(self):
        self.assertEqual(
            manifest.risk("supabase/migrations/001.sql"), "P0_database_migration"
        )
        self.assertEqual(
            manifest.risk("supabase/functions/payment/index.ts"), "P0_backend_function"
        )
        self.assertEqual(
            manifest.risk("android/app/build.gradle"), "P1_native_configuration"
        )
        self.assertEqual(
            manifest.risk("lib/mobile_main.dart"), "P1_runtime_auth"
        )
        self.assertEqual(
            manifest.risk("lib/presentation.dart"), "P2_app_or_web"
        )
        self.assertEqual(
            manifest.risk("docs/SINGLE_APP_WEB_FIRST_2026-10-08.md"),
            "P3_documentation",
        )

    def test_rejects_non_sha_base(self):
        with tempfile.TemporaryDirectory() as temp:
            with patch.object(manifest, "git", side_effect=[MERGE, TREE]):
                with self.assertRaisesRegex(ValueError, "base SHA"):
                    manifest.run("main", Path(temp) / "inventory.json")

    def test_rejects_mismatched_synthetic_merge(self):
        with tempfile.TemporaryDirectory() as temp:
            with patch.dict(os.environ, {"EVENT_NAME": "pull_request", "PR_HEAD_SHA": PR_HEAD}):
                with patch.object(
                    manifest, "git",
                    side_effect=[MERGE, TREE, MERGE + " " + BASE + " " + ("e" * 40)],
                ):
                    with self.assertRaisesRegex(ValueError, "checkout"):
                        manifest.run(BASE, Path(temp) / "inventory.json")

    def test_records_exact_tested_source_for_real_pr(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "manifest.json"
            with patch.dict(os.environ, {"EVENT_NAME": "pull_request", "PR_HEAD_SHA": PR_HEAD}):
                with patch.object(manifest, "git", side_effect=[
                    MERGE, TREE, MERGE + " " + BASE + " " + PR_HEAD, ""
                ]):
                    manifest.run(BASE, output)
            recorded = json.loads(output.read_text())
            self.assertEqual(recorded["base_sha"], BASE)
            self.assertEqual(recorded["pr_head_sha"], PR_HEAD)
            self.assertEqual(recorded["tested_checkout_sha"], MERGE)
            self.assertEqual(recorded["tested_checkout_tree_sha"], TREE)
            self.assertTrue(recorded["base_comparison_complete"])
            self.assertEqual(recorded["changed_file_count"], 0)
            self.assertEqual(
                recorded["status"], "INVENTORY_ONLY_NOT_APPROVED_FOR_PRODUCTION"
            )


if __name__ == "__main__":
    unittest.main()
