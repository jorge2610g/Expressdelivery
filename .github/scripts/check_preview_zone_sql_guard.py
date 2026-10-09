#!/usr/bin/env python3
"""Fail closed if the proposed QA zone guard changes Production SQL behavior.

Static source inspection only: does not parse/execute SQL, access databases or
certify that any runtime is isolated. Integration tests remain mandatory.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "supabase/migrations/20261009172500_exclusive_zone_coverage_mode.sql"
PROPOSAL = ROOT / "docs/backend_patches/preview_zone_coverage_fail_closed.sql"
START = "create or replace function public.admin_zone_coverage_save("
END = "\nrevoke all on function public.admin_zone_coverage_get"
GUARD = """ -- QA must never mutate the live geography, regardless of UI/client version.
 -- Production continues to execute the historical implementation unchanged.
 if p_channel='preview' then
   raise exception 'Esta cobertura es exclusiva de QA: utiliza la configuración aislada de Preview';
 end if;
"""
SIDE_EFFECTS = ("public.admin_upsert_zone_v3(", "update public.service_zone_polygons", "insert into public.service_zone_polygons", "update public.service_zones")


def check():
    source = SOURCE.read_text(encoding="utf-8")
    proposal = PROPOSAL.read_text(encoding="utf-8")
    assert source.count(START) == 1, "Missing/ambiguous original RPC"
    assert proposal.count(START) == 1, "Missing/ambiguous proposed RPC"
    assert source.count(END) == 1, "Migration has changed: re-review required"
    original = source[source.index(START):source.index(END)].strip()
    changed = proposal[proposal.index(START):].strip()
    assert changed.startswith(START), "Unexpected SQL preamble"
    assert changed.endswith("end $$;"), "Malformed SQL dollar quote / terminator"
    assert changed.count(GUARD) == 1, "Preview fail-closed guard absent or modified"
    assert original == changed.replace(GUARD, ""), (
        "Production RPC changed beyond adding the Preview guard; manual review required"
    )
    authorized = changed.index("raise exception 'No autorizado para modificar la cobertura'")
    preview = changed.index("if p_channel='preview' then")
    first_side_effect = min(changed.index(x) for x in SIDE_EFFECTS)
    assert authorized < preview < first_side_effect, "Guard must run after auth, before live mutations"
    assert "if p_channel not in ('preview','production')" not in changed, "Authorization contract drift"
    assert "security definer" in changed.lower(), "Existing security mode changed"
    print("PASS static source parity: Production SQL unchanged; Preview rejected before writes")
    print("NOT a SQL syntax check or a runtime database/role security test")


if __name__ == "__main__":
    try:
        check()
    except (AssertionError, ValueError, OSError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
