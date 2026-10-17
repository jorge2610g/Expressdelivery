#!/bin/bash
# Reconstruye la plantilla local qa_pristine replicando la cadena de migraciones que definen
# las funciones de aceptación, y comprueba las huellas contra producción.
set -u
DK=/Applications/Docker.app/Contents/Resources/bin/docker; C=express-qa-pg15
H="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$H/../../.." && pwd)"; MIG="$REPO/supabase/migrations"
q() { $DK exec -i $C psql -U postgres -d "$1" -v ON_ERROR_STOP="${2:-1}" -q -At; }
$DK exec $C psql -U postgres -d postgres -q -c "drop database if exists qa_prodreplay" -c "create database qa_prodreplay" >/dev/null
q qa_prodreplay 1 < "$H/schema_stub.sql" >/dev/null
while read f; do q qa_prodreplay 0 < "$MIG/$(basename "$f")" >/dev/null 2>&1; done < "$H/replay_list.txt"
q qa_prodreplay 1 < "$H/same_operational_scope_production.sql" >/dev/null
q qa_prodreplay 1 < "$H/align_production.sql" >/dev/null
echo "== hash check (local vs producción)"
$DK exec $C psql -U postgres -d qa_prodreplay -At -F' ' -c "select proname, pronargs, md5(prosrc) from pg_proc where pronamespace='public'::regnamespace and proname in ('enforce_driver_offer_deadline','enforce_driver_offer_minimum_lifetime','express_push_currency_label','guard_request_runtime_channel','is_active_audit_user','normalize_runtime_channel','same_operational_scope','select_ride_offer','select_ride_offer_v2','sync_trip_runtime_channel') order by 1,2" > "$H/.local_hashes.txt"
python3 - "$H" <<'PY'
import sys,pathlib
h=pathlib.Path(sys.argv[1])
prod={}
for l in (h/'production_function_hashes.txt').read_text().splitlines():
    if l and not l.startswith('#'):
        n,a,m=l.split(); prod[(n,a)]=m
local={}
for l in (h/'.local_hashes.txt').read_text().splitlines():
    if l.strip():
        n,a,m=l.split(); local[(n,a)]=m
ok=0
for k in sorted(prod):
    st='MATCH' if local.get(k)==prod[k] else 'DIFF'
    ok+= st=='MATCH'
    print(f"{k[0]:36s} {st}")
print(f"{ok}/{len(prod)} coinciden con producción")
PY
$DK exec $C psql -U postgres -d postgres -q -c "drop database if exists qa_pristine" -c "create database qa_pristine template qa_prodreplay" >/dev/null && echo "plantilla qa_pristine lista"
