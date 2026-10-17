#!/bin/bash
# Fase 1: pruebas con los triggers reales de producción activos.
# Usage: run_phase1.sh <baseline|patched> [race_iterations]
set -u
MODE="$1"; N_RACE="${2:-50}"
DK=/Applications/Docker.app/Contents/Resources/bin/docker
C=express-qa-pg15
S="/private/tmp/claude-501/-Users-mac/d31aa160-1dff-40bf-8a28-25b475d14a30/scratchpad/qa-pg"
REPO=/Users/mac/Documents/Expressdelivery-141
PATCH="$REPO/docs/pending_migrations/20261016_select_ride_offer_expiry_guard_v2.sql"
DB="qa_phase1_${MODE}"
OUT="$S/phase1_${MODE}.txt"
P=aaaaaaaa-0000-4000-8000-000000000001
D1=bbbbbbbb-0000-4000-8000-000000000001
D2=bbbbbbbb-0000-4000-8000-000000000002
psqlq() { $DK exec -i $C psql -U postgres -d "$DB" -v ON_ERROR_STOP=1 -q -At "$@" || { echo "SQL ERROR: aborting" | tee -a "$OUT"; exit 1; }; }
pass() { echo "PASS  $1" | tee -a "$OUT"; }
fail() { echo "FAIL  $1" | tee -a "$OUT"; }

: > "$OUT"
echo "== $(date -u +%FT%TZ) modo=$MODE db=$DB" | tee -a "$OUT"
$DK exec $C psql -U postgres -d postgres -q -c "drop database if exists $DB" -c "create database $DB template qa_pristine" >/dev/null || { echo "no template"; exit 1; }
if [ "$MODE" = "patched" ]; then
  psqlq < "$PATCH" >/dev/null || { fail "aplicar parche"; exit 1; }
  echo "parche v2 aplicado (solo $DB)" | tee -a "$OUT"
fi
psqlq < "$S/test_helper.sql" >/dev/null
psqlq < "$S/seed_base.sql" >/dev/null || { fail "seed"; exit 1; }
psqlq >/dev/null <<SQL
insert into public.account_runtime_bindings(user_id,environment,source) values
 ('$P','preview','synthetic'),('$D1','preview','synthetic'),('$D2','preview','synthetic');
SQL

echo "--- T1 oferta vigente (trigger asigna vigencia real)" | tee -a "$OUT"
psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel,service_mode) values ('dddddddd-0000-4000-8000-000000000101','$P','searching','preview','taxi');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values
 ('eeeeeeee-0000-4000-8000-000000000101','dddddddd-0000-4000-8000-000000000101','$D1',1000,'pending', now()+interval '10 minutes','preview');
SQL
life=$(psqlq -c "select round(extract(epoch from (expires_at-created_at))::numeric,1) from public.driver_offers where id='eeeeeeee-0000-4000-8000-000000000101'")
echo "   vigencia almacenada (s): $life" | tee -a "$OUT"
r=$(psqlq -c "select public.test_try_select('eeeeeeee-0000-4000-8000-000000000101','$P')")
echo "   resultado: ${r:0:50}" | tee -a "$OUT"
case "$r" in OK*) pass "T1 oferta vigente se acepta";; *) fail "T1 oferta vigente se acepta";; esac
case "$life" in 29.*|30.*|31.*|32.*) pass "T8 oferta normal conserva vigencia de ~30 s (trigger de producción)";; *) fail "T8 vigencia inesperada: $life";; esac

echo "--- T3 expires_at nulo al insertar (trigger lo sustituye)" | tee -a "$OUT"
psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel,service_mode) values ('dddddddd-0000-4000-8000-000000000103','$P','searching','preview','taxi');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values
 ('eeeeeeee-0000-4000-8000-000000000103','dddddddd-0000-4000-8000-000000000103','$D1',1000,'pending', NULL,'preview');
SQL
nn=$(psqlq -c "select expires_at is null from public.driver_offers where id='eeeeeeee-0000-4000-8000-000000000103'")
r=$(psqlq -c "select public.test_try_select('eeeeeeee-0000-4000-8000-000000000103','$P')")
echo "   expires_at nulo tras insertar: $nn ; aceptación: ${r:0:40}" | tee -a "$OUT"
case "$nn" in f|false) pass "T3 el trigger impide expires_at nulo en oferta pendiente";; *) fail "T3 el trigger NO impidió expires_at nulo";; esac

echo "--- T4 bypass de triggers (session_replication_role=replica, solo privilegiado)" | tee -a "$OUT"
psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel,service_mode) values ('dddddddd-0000-4000-8000-000000000104','$P','searching','preview','taxi');
SET session_replication_role = replica;
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values
 ('eeeeeeee-0000-4000-8000-000000000104','dddddddd-0000-4000-8000-000000000104','$D1',1000,'pending', NULL,'preview');
RESET session_replication_role;
SQL
nb=$(psqlq -c "select expires_at is null from public.driver_offers where id='eeeeeeee-0000-4000-8000-000000000104'")
r=$(psqlq -c "select public.test_try_select('eeeeeeee-0000-4000-8000-000000000104','$P')")
echo "   expires_at nulo por bypass: $nb ; aceptación: ${r:0:40}" | tee -a "$OUT"
if [ "$MODE" = "patched" ]; then
  case "$r" in ERR*) pass "T4 oferta con expires_at nulo por bypass se RECHAZA (con parche)";; *) fail "T4 oferta nula por bypass no rechazada";; esac
else
  case "$r" in OK*) fail "T4 defecto de base: oferta nula por bypass se ACEPTA (sin parche)";; *) pass "T4 comportamiento inesperado en base sin parche";; esac
fi

echo "--- T2 oferta vencida (espera real de 31 s)" | tee -a "$OUT"
psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel,service_mode) values ('dddddddd-0000-4000-8000-000000000102','$P','searching','preview','taxi');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values
 ('eeeeeeee-0000-4000-8000-000000000102','dddddddd-0000-4000-8000-000000000102','$D1',1000,'pending', now()+interval '10 minutes','preview');
SQL
sleep 31
r=$(psqlq -c "select public.test_try_select('eeeeeeee-0000-4000-8000-000000000102','$P')")
echo "   resultado: ${r:0:50}" | tee -a "$OUT"
case "$r" in ERR*) pass "T2 oferta vencida se rechaza";; *) fail "T2 oferta vencida no rechazada";; esac

echo "--- T5 segunda aceptación de T1" | tee -a "$OUT"
r=$(psqlq -c "select public.test_try_select('eeeeeeee-0000-4000-8000-000000000101','$P')")
case "$r" in ERR*) pass "T5 oferta ya aceptada no se acepta de nuevo";; *) fail "T5 segunda aceptación permitida";; esac

echo "--- T6 conductor no puede asignarse la oferta" | tee -a "$OUT"
psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel,service_mode) values ('dddddddd-0000-4000-8000-000000000106','$P','searching','preview','taxi');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values
 ('eeeeeeee-0000-4000-8000-000000000106','dddddddd-0000-4000-8000-000000000106','$D1',1000,'pending', now()+interval '10 minutes','preview');
SQL
r=$(psqlq -c "select public.test_try_select('eeeeeeee-0000-4000-8000-000000000106','$D1')")
case "$r" in ERR*) pass "T6 el conductor no puede aceptar su propia oferta";; *) fail "T6 conductor pudo asignarse";; esac

echo "--- Carrera determinista (FOR UPDATE)" | tee -a "$OUT"
psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel,service_mode) values ('dddddddd-0000-4000-8000-000000000150','$P','searching','preview','taxi');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values
 ('eeeeeeee-0000-4000-8000-000000000150','dddddddd-0000-4000-8000-000000000150','$D1',1000,'pending', now()+interval '10 minutes','preview'),
 ('eeeeeeee-0000-4000-8000-000000000151','dddddddd-0000-4000-8000-000000000150','$D2',1100,'pending', now()+interval '10 minutes','preview');
SQL
printf "begin;\nselect 'A '||public.test_try_select('eeeeeeee-0000-4000-8000-000000000150','$P');\nselect pg_sleep(3);\ncommit;\n" > "$S/p1_sessA.sql"
printf "select 'B '||public.test_try_select('eeeeeeee-0000-4000-8000-000000000151','$P');\n" > "$S/p1_sessB.sql"
$DK exec -i $C psql -U postgres -d "$DB" -q -At < "$S/p1_sessA.sql" > "$S/p1_outA.txt" 2>&1 &
pa=$!; sleep 1
$DK exec -i $C psql -U postgres -d "$DB" -q -At < "$S/p1_sessB.sql" > "$S/p1_outB.txt" 2>&1
wait $pa
a=$(grep -E "^A " "$S/p1_outA.txt" | head -1); b=$(grep -E "^B " "$S/p1_outB.txt" | head -1)
case "$a" in "A OK"*) pass "lock: A asigna";; *) fail "lock A: ${a:0:40}";; esac
case "$b" in "B ERR"*) pass "lock: B rechazada tras esperar a A";; *) fail "lock B: ${b:0:40}";; esac

echo "--- Carrera aleatoria: $N_RACE repeticiones" | tee -a "$OUT"
ok=0; bad=0
for i in $(seq 1 "$N_RACE"); do
  R=$(printf "dddddddd-0000-4000-8000-%012d" $((20000+i)))
  OA=$(printf "eeeeeeee-0000-4000-8000-%012d" $((30000+2*i)))
  OB=$(printf "eeeeeeee-0000-4000-8000-%012d" $((30001+2*i)))
  psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel,service_mode) values ('$R','$P','searching','preview','taxi');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values
 ('$OA','$R','$D1',1000,'pending', now()+interval '10 minutes','preview'),
 ('$OB','$R','$D2',1100,'pending', now()+interval '10 minutes','preview');
SQL
  psqlq -c "select 'X '||public.test_try_select('$OA','$P')" > "$S/p1_ra_$i.txt" 2>&1 &
  x1=$!
  psqlq -c "select 'X '||public.test_try_select('$OB','$P')" > "$S/p1_rb_$i.txt" 2>&1 &
  x2=$!
  wait $x1 $x2
  ra=$(grep -E "^X " "$S/p1_ra_$i.txt" | head -1); rb=$(grep -E "^X " "$S/p1_rb_$i.txt" | head -1)
  nok=0; case "$ra" in "X OK"*) nok=$((nok+1));; esac; case "$rb" in "X OK"*) nok=$((nok+1));; esac
  inv=$(psqlq -c "select (select count(*) from public.trips where ride_request_id='$R')||'|'||(select count(*) from public.driver_offers where ride_request_id='$R' and status='selected')||'|'||(select count(*) from public.driver_offers where ride_request_id='$R' and status='declined')||'|'||(select status from public.ride_requests where id='$R')||'|'||(select count(*) from public.trip_status_history h join public.trips t on t.id=h.trip_id where t.ride_request_id='$R')")
  if [ "$nok" -eq 1 ] && [ "$inv" = "1|1|1|driver_selected|1" ]; then ok=$((ok+1)); else bad=$((bad+1)); echo "   iter $i inv=$inv" >> "$OUT"; fi
done
[ "$ok" -eq "$N_RACE" ] && pass "carrera: $ok/$N_RACE con un solo ganador" || fail "carrera: $ok/$N_RACE"
[ "$bad" -eq 0 ] && pass "carrera: 0 inconsistencias" || fail "carrera: $bad inconsistencias"

echo "--- Taxi y Envíos: estado final" | tee -a "$OUT"
psqlq -c "select 'trips_total='||count(*) from public.trips" | tee -a "$OUT"
echo "== fin $MODE" | tee -a "$OUT"
