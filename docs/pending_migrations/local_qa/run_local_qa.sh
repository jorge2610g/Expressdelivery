#!/bin/bash
# Local, isolated acceptance tests for select_ride_offer (Taxi).
# Usage: run_local_qa.sh <database_name> <baseline|patched>
# Only touches the local container express-qa-pg15 (127.0.0.1). Synthetic data only.
set -u
DB="$1"; MODE="$2"
DK=/Applications/Docker.app/Contents/Resources/bin/docker
C=express-qa-pg15

S="$(cd "$(dirname "$0")" && pwd)"
OUT="$S/results_${MODE}.txt"
P=aaaaaaaa-0000-4000-8000-000000000001
D1=bbbbbbbb-0000-4000-8000-000000000001
D2=bbbbbbbb-0000-4000-8000-000000000002
N_RACE=${N_RACE:-30}

psqlq() { $DK exec -i $C psql -U postgres -d "$DB" -v ON_ERROR_STOP=1 -q -At "$@"; }
pass() { echo "PASS  $1" | tee -a "$OUT"; }
fail() { echo "FAIL  $1" | tee -a "$OUT"; }
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then pass "$1 (esperado: $2)"; else fail "$1 (esperado: $2, obtenido: $3)"; fi
}

: > "$OUT"
echo "== $(date -u +%FT%TZ) modo=$MODE db=$DB" | tee -a "$OUT"
$DK exec $C psql -U postgres -d postgres -q -c "drop database if exists $DB" -c "create database $DB" >/dev/null || { echo "cannot create db"; exit 1; }
for f in schema_stub.sql functions_from_repo_latest.sql triggers_from_repo_baseline.sql; do
  psqlq < "$S/$f" >/dev/null || { fail "carga $f"; exit 1; }
done
if [ "$MODE" = "patched" ]; then
  psqlq < "$(git rev-parse --show-toplevel)/docs/pending_migrations/20261016_select_ride_offer_expiry_guard.sql" >/dev/null || { fail "aplicar migración 0eb7cb5"; exit 1; }
  echo "migración 0eb7cb5 aplicada (solo en $DB)" | tee -a "$OUT"
fi
psqlq < "$S/test_helper.sql" >/dev/null
psqlq < "$S/seed_base.sql" >/dev/null || { fail "seed"; exit 1; }

echo "--- Escenarios de aceptación" | tee -a "$OUT"
psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel) values
 ('dddddddd-0000-4000-8000-000000000001','$P','searching','preview'),
 ('dddddddd-0000-4000-8000-000000000002','$P','searching','preview'),
 ('dddddddd-0000-4000-8000-000000000003','$P','searching','preview'),
 ('dddddddd-0000-4000-8000-000000000004','$P','searching','preview');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values
 ('eeeeeeee-0000-4000-8000-000000000001','dddddddd-0000-4000-8000-000000000001','$D1',1000,'pending', now()+interval '10 minutes','preview'),
 ('eeeeeeee-0000-4000-8000-000000000002','dddddddd-0000-4000-8000-000000000002','$D1',1000,'pending', now()-interval '1 minute','preview'),
 ('eeeeeeee-0000-4000-8000-000000000003','dddddddd-0000-4000-8000-000000000003','$D1',1000,'pending', NULL,'preview'),
 ('eeeeeeee-0000-4000-8000-000000000004','dddddddd-0000-4000-8000-000000000004','$D1',1000,'pending', now()+interval '10 minutes','preview');
SQL
r1=$(psqlq -c "select public.test_try_select('eeeeeeee-0000-4000-8000-000000000001','$P')")
r1b=$(psqlq -c "select public.test_try_select('eeeeeeee-0000-4000-8000-000000000001','$P')")
r2=$(psqlq -c "select public.test_try_select('eeeeeeee-0000-4000-8000-000000000002','$P')")
r3=$(psqlq -c "select public.test_try_select('eeeeeeee-0000-4000-8000-000000000003','$P')")
r4=$(psqlq -c "select public.test_try_select('eeeeeeee-0000-4000-8000-000000000004','$D1')")
r4b=$(psqlq -c "select public.test_try_select('eeeeeeee-0000-4000-8000-000000000004','$P')")
echo "   S1  vigente:            ${r1:0:60}" | tee -a "$OUT"
echo "   S1b ya aceptada:        ${r1b:0:60}" | tee -a "$OUT"
echo "   S2  vencida:            ${r2:0:60}" | tee -a "$OUT"
echo "   S3  expires_at nulo:    ${r3:0:60}" | tee -a "$OUT"
echo "   S4  conductor se asigna: ${r4:0:60}" | tee -a "$OUT"
echo "   S4b pasajero (control): ${r4b:0:60}" | tee -a "$OUT"
case "${r1:0:2}" in OK) pass "S1 oferta vigente se acepta";; *) fail "S1 oferta vigente se acepta";; esac
case "${r1b:0:3}" in ERR) pass "S1b segunda aceptación rechazada";; *) fail "S1b segunda aceptación rechazada";; esac
case "${r2:0:3}" in ERR) pass "S2 oferta vencida rechazada";; *) fail "S2 oferta vencida rechazada";; esac
if [ "$MODE" = "patched" ]; then
  case "${r3:0:3}" in ERR) pass "S3 expires_at nulo rechazada (con la migración)";; *) fail "S3 expires_at nulo rechazada (con la migración)";; esac
else
  case "${r3:0:2}" in OK) fail "S3 defecto confirmado en base del repositorio: expires_at nulo SE ACEPTA";; *) pass "S3 expires_at nulo (base sin defecto inesperado)";; esac
fi
case "${r4:0:3}" in ERR) pass "S4 el conductor no puede asignarse la oferta (solo el pasajero)";; *) fail "S4 el conductor no puede asignarse la oferta";; esac
case "${r4b:0:2}" in OK) pass "S4b control: pasajero acepta oferta vigente tras el rechazo";; *) fail "S4b control";; esac

echo "--- Estado tras escenarios" | tee -a "$OUT"
psqlq -c "select 'trips_R1='||count(*) from public.trips where ride_request_id='dddddddd-0000-4000-8000-000000000001'" | tee -a "$OUT"
psqlq -c "select 'R1_status='||status from public.ride_requests where id='dddddddd-0000-4000-8000-000000000001'" | tee -a "$OUT"
psqlq -c "select 'offers_R3_status='||status from public.driver_offers where id='eeeeeeee-0000-4000-8000-000000000003'" | tee -a "$OUT"

echo "--- Bloqueo determinista FOR UPDATE (dos transacciones sobre la misma solicitud)" | tee -a "$OUT"
psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel) values
 ('dddddddd-0000-4000-8000-000000000005','$P','searching','preview');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values
 ('eeeeeeee-0000-4000-8000-000000005001','dddddddd-0000-4000-8000-000000000005','$D1',1000,'pending', now()+interval '10 minutes','preview'),
 ('eeeeeeee-0000-4000-8000-000000005002','dddddddd-0000-4000-8000-000000000005','$D2',1100,'pending', now()+interval '10 minutes','preview');
SQL
printf "begin;\nselect 'A '||public.test_try_select('eeeeeeee-0000-4000-8000-000000005001','$P');\nselect pg_sleep(3);\ncommit;\n" > "$S/sessA.sql"
printf "select 'B '||public.test_try_select('eeeeeeee-0000-4000-8000-000000005002','$P');\n" > "$S/sessB.sql"
t0=$(python3 -c "import time;print(int(time.time()*1000))")
psqlq < "$S/sessA.sql" > "$S/outA.txt" 2>&1 &
pidA=$!
sleep 1
psqlq < "$S/sessB.sql" > "$S/outB.txt" 2>&1
t1=$(python3 -c "import time;print(int(time.time()*1000))")
wait $pidA
a_out=$(grep -E "^A " "$S/outA.txt" | head -1)
b_out=$(grep -E "^B " "$S/outB.txt" | head -1)
echo "   A: ${a_out:0:70}" | tee -a "$OUT"
echo "   B: ${b_out:0:70} (tardó $((t1-t0)) ms desde el inicio de A)" | tee -a "$OUT"
case "$a_out" in "A OK"*) pass "bloqueo: transacción A obtiene la asignación";; *) fail "bloqueo: transacción A";; esac
case "$b_out" in "B ERR"*) pass "bloqueo: transacción B rechazada tras esperar el commit de A";; *) fail "bloqueo: transacción B no rechazada";; esac

echo "--- Carrera aleatoria: $N_RACE repeticiones, dos conductores a la vez" | tee -a "$OUT"
okcount=0; bad=0
for i in $(seq 1 "$N_RACE"); do
  R=$(printf "dddddddd-0000-4000-8000-%012d" $((100+i)))
  OA=$(printf "eeeeeeee-0000-4000-8000-%012d" $((10000+2*i)))
  OB=$(printf "eeeeeeee-0000-4000-8000-%012d" $((10001+2*i)))
  psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel) values ('$R','$P','searching','preview');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values
 ('$OA','$R','$D1',1000,'pending', now()+interval '10 minutes','preview'),
 ('$OB','$R','$D2',1100,'pending', now()+interval '10 minutes','preview');
SQL
  psqlq -c "select 'X '||public.test_try_select('$OA','$P')" > "$S/ra_$i.txt" 2>&1 &
  pa=$!
  psqlq -c "select 'X '||public.test_try_select('$OB','$P')" > "$S/rb_$i.txt" 2>&1 &
  pb=$!
  wait $pa $pb
  ra=$(grep -E "^X " "$S/ra_$i.txt" | head -1); rb=$(grep -E "^X " "$S/rb_$i.txt" | head -1)
  nok=0; case "$ra" in "X OK"*) nok=$((nok+1));; esac; case "$rb" in "X OK"*) nok=$((nok+1));; esac
  inv=$(psqlq -c "select (select count(*) from public.trips where ride_request_id='$R')||'|'||(select count(*) from public.driver_offers where ride_request_id='$R' and status='selected')||'|'||(select count(*) from public.driver_offers where ride_request_id='$R' and status='declined')||'|'||(select status from public.ride_requests where id='$R')||'|'||(select count(*) from public.trip_status_history h join public.trips t on t.id=h.trip_id where t.ride_request_id='$R')||'|'||(select count(*) from public.trips t join public.driver_offers o on o.ride_request_id=t.ride_request_id and o.status='selected' where t.ride_request_id='$R' and o.driver_id=t.driver_id)")
  if [ "$nok" -eq 1 ] && [ "$inv" = "1|1|1|driver_selected|1|1" ]; then okcount=$((okcount+1)); else bad=$((bad+1)); echo "   iter $i: A='${ra:0:25}' B='${rb:0:25}' inv=$inv" >> "$OUT"; fi
done
check "carrera: exactamente un ganador en las $N_RACE repeticiones" "$N_RACE" "$okcount"
check "carrera: sin registros inconsistentes (trips=1, selected=1, declined=1, estado driver_selected, historial=1, conductor coherente)" "0" "$bad"

echo "--- Totales" | tee -a "$OUT"
psqlq -c "select 'trips_total='||count(*) from public.trips" | tee -a "$OUT"
psqlq -c "select 'requests_driver_selected='||count(*) from public.ride_requests where status='driver_selected'" | tee -a "$OUT"
echo "== fin $MODE" | tee -a "$OUT"
