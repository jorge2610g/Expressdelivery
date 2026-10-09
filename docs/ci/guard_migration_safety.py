#!/usr/bin/env python3
"""Fail closed on obviously destructive migrations in Express PRs.

Checks only newly added migrations relative to the PR base. Existing
migrations are append-only and may not be edited or deleted. This guard is
a lightweight supplement to (not a substitute for) database QA and review.
"""
import argparse
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
PREFIX = "supabase/migrations/"
RISKS = (
    ("DROP TABLE", r"\bdrop\s+table\b"),
    ("DROP COLUMN", r"\balter\s+table\b[\s\S]{0,180}\bdrop\s+column\b"),
    ("TRUNCATE", r"\btruncate\b"),
    ("DISABLE RLS", r"\balter\s+table\b[\s\S]{0,180}\bdisable\s+row\s+level\s+security\b"),
    ("ALTER COLUMN TYPE", r"\balter\s+table\b[\s\S]{0,180}\balter\s+column\b[\s\S]{0,180}\btype\b"),
)


def clean_sql(raw: str) -> str:
    without_blocks = re.sub(r"/\*.*?\*/", "", raw, flags=re.DOTALL)
    return re.sub(r"--[^\n]*", "", without_blocks)


def verify_added(path: str) -> list[str]:
    sql = clean_sql((ROOT / path).read_text(encoding="utf-8"))
    return [
        f"{path}: operation {title} requires separately reviewed manual migration"
        for title, pattern in RISKS
        if re.search(pattern, sql, flags=re.IGNORECASE)
    ]


def changes(base: str) -> list[tuple[str, str]]:
    output = subprocess.check_output(
        ["git", "diff", "--name-status", "--diff-filter=ACDMR",
         "--no-renames", base, "HEAD", "--", PREFIX],
        cwd=ROOT,
        text=True,
    )
    found: list[tuple[str, str]] = []
    for line in output.splitlines():
        parts = line.split("\t")
        if len(parts) >= 2 and parts[1].startswith(PREFIX) and parts[1].endswith(".sql"):
            found.append((parts[0], parts[1]))
    return found


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-sha", default="", help="PR base SHA; omitted for manual workflow")
    args = parser.parse_args()
    if not args.base_sha:
        print("SKIP: no PR base SHA (manual workflow).")
        return 0
    if not re.fullmatch(r"[a-fA-F0-9]{40}", args.base_sha):
        print("FAIL: invalid PR base SHA", file=sys.stderr)
        return 2
    problems = []
    for status, path in changes(args.base_sha):
        if status != "A":
            problems.append(f"{path}: migrations are append-only; create a NEW migration, never modify/delete old SQL")
        else:
            problems.extend(verify_added(path))
    for problem in problems:
        print("FAIL: " + problem, file=sys.stderr)
    if problems:
        print("No migration applied. Correct the PR before deployment.", file=sys.stderr)
        return 1
    print("PASS: changed migrations are additive by this static check.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
