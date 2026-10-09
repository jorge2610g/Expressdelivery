#!/usr/bin/env python3
"""Generate an auditable preview -> production *change inventory*, never deploy.

The JSON records the checked-out git commit/tree, PR head/base and every net
changed path with its status, risk class and SHA-256 where present. Hashes prove
which files were reviewed; they do NOT prove behavioral safety, final build
identity or permission to merge. A new PR commit requires a new inventory.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def git(*args):
    return subprocess.check_output(
        ["git", *args], cwd=ROOT, text=True, encoding="utf-8"
    ).strip()


def risk(path):
    if path.startswith("supabase/migrations/"):
        return "P0_database_migration"
    if path.startswith("supabase/functions/"):
        return "P0_backend_function"
    if path.startswith(".github/workflows/") or path.startswith(".github/scripts/"):
        return "P1_release_automation"
    if path.startswith(("android/", "ios/")):
        return "P1_native_configuration"
    if path.startswith(("lib/core/", "lib/auth_", "lib/mobile_main.dart")):
        return "P1_runtime_auth"
    if path.startswith(("lib/", "assets/", "web/")):
        return "P2_app_or_web"
    if path.startswith(("pubspec.yaml", "pubspec.lock")):
        return "P1_dependencies"
    if path.startswith(("docs/", "AGENTS.md")):
        return "P3_documentation"
    return "P2_other"


def run(base_sha, output_file):
    head = git("rev-parse", "HEAD")
    tree = git("rev-parse", "HEAD^{tree}")
    if base_sha and not re.fullmatch(r"[0-9a-fA-F]{40}", base_sha):
        raise ValueError("base SHA must be 40 hex characters")
    entries = []
    if base_sha:
        # Compare the actual checkout that GitHub tested (normally the
        # PR's synthetic merge commit) to the exact recorded PR base.
        rows = git("diff", "--name-status", "--no-renames",
                   base_sha, "HEAD", "--")
        for line in rows.splitlines():
            fields = line.split("\t", 1)
            if len(fields) != 2:
                raise ValueError(f"Unrecognized git diff entry: {line!r}")
            status, name = fields
            if not name or "\n" in name:
                raise ValueError(f"Unsafe path: {name!r}")
            file_path = ROOT / name
            if status == "D":
                digest = None
            elif status in {"A", "M", "T"} and file_path.is_file():
                digest = hashlib.sha256(file_path.read_bytes()).hexdigest()
            else:
                raise ValueError(f"Unsupported status / missing file: {status} {name}")
            entries.append({
                "path": name,
                "status": status,
                "risk_class": risk(name),
                "sha256": digest,
            })
    else:
        # Manual workflow cannot be represented as a verified comparison.
        print("WARNING: no PR base; change inventory is incomplete", file=sys.stderr)
    report = {
        "schema": "express-release-change-inventory-v1",
        "base_sha": base_sha or None,
        "tested_checkout_sha": head,
        "tested_checkout_tree_sha": tree,
        "pr_head_sha": os.environ.get("PR_HEAD_SHA") or None,
        "base_comparison_complete": bool(base_sha),
        "changed_files": entries,
        "changed_file_count": len(entries),
        "requires_backend_qa": any(x["risk_class"].startswith("P0") for x in entries),
        "status": "INVENTORY_ONLY_NOT_APPROVED_FOR_PRODUCTION",
        "notice": "This inventory lists checked-out file differences, not database changes, runtime health or a signed artifact. Recompute after merge / any base or head change.",
    }
    output_file.parent.mkdir(parents=True, exist_ok=True)
    output_file.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                           encoding="utf-8")
    print(f"Wrote {len(entries)} changed-file entries to {output_file}")
    print(f"tested SHA: {head}; tree SHA: {tree}")
    print("NOT an approval to merge or deploy")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-sha", default="")
    parser.add_argument("--output", default="release-change-manifest.json")
    args = parser.parse_args()
    try:
        run(args.base_sha.strip(), ROOT / args.output)
    except (ValueError, subprocess.CalledProcessError, OSError) as error:
        print(f"FAIL change inventory: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
