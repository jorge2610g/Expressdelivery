#!/bin/bash
# Pruebas de vigencia de ofertas y solicitudes (PostgreSQL local aislado, datos sintéticos).
# Usage: run_lifetime.sh <baseline|v3> [race_iterations]
set -u
MODE="$1"; N_RACE="${2:-50}"
DK=/Applications/Docker.app/Contents/Resources/bin/docker; C=express-qa-pg15
H="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$H/../../.." && pwd)"
PATCH="$REPO/docs/pending_migrations/20261016_offer_lifetime_v3_proposal.sql"
DB="qa_lifetime_${MODE}"; OUT="$H/results_lifetime_${MODE}.txt"
P=aaaaaaaa-0000-4000-8000-000000000001; D1=bbbbbbbb-0000-4000-8000-000000000001; D2=bbbbbbbb-0000-4000-8000-000000000002
psqlq() { $DK exec -i $C psql -U postgres -d "$DB" -v ON_ERROR_STOP=1 -q -At "$@" || { echo "SQL ERROR: aborting" | tee -a "$OUT"; exit 1; }; }
pass() { echo "PASS  $1" | tee -a "$OUT"; }
fail() { echo "FAIL  $1" | tee -a "$OUT"; }
val() { psqlq -c "$1"; }

: > "$OUT"
echo "== $(date -u +%FT%TZ) modo=$MODE" | tee -a "$OUT"
$DK exec $C psql -U postgres -d postgres -q -c "drop database if exists $DB" -c "create database $DB template qa_pristine" >/dev/null
[ "$MODE" = "v3" ] && { psqlq < "$PATCH" >/dev/null && echo "propuesta v3 aplicada (solo $DB)" | tee -a "$OUT"; }
psqlq < "$H/test_helper.sql" >/dev/null
psqlq < "$H/seed_base.sql" >/dev/null
psqlq >/dev/null <<SQL
insert into public.account_runtime_bindings(user_id,environment,source) values
 ('$P','preview','synthetic'),('$D1','preview','synthetic'),('$D2','preview','synthetic');
SQL

echo "--- L1 tiempo configurado 20 s" | tee -a "$OUT"
psqlq -c "update public.app_settings set offer_timeout_seconds=20 where id=true" >/dev/null
psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel,service_mode,expires_at) values ('dddddddd-0000-4000-8000-000000000201','$P','searching','preview','taxi', now()+interval '180 seconds');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values ('eeeeeeee-0000-4000-8000-000000000201','dddddddd-0000-4000-8000-000000000201','$D1',1000,'pending', now()+interval '180 seconds','preview');
SQL
l1=$(val "select round(extract(epoch from (expires_at-created_at))::numeric,1) from public.driver_offers where id='eeeeeeee-0000-4000-8000-000000000201'")
echo "   vigencia de oferta (s): $l1" | tee -a "$OUT"
if [ "$MODE" = "v3" ]; then case "$l1" in 19.*|20.*|21.*) pass "L1 oferta respeta offer_timeout=20 s";; *) fail "L1 vigencia $l1 (esperada 20)";; esac
else case "$l1" in 29.*|30.*|31.*) fail "L1 defecto: vigencia $l1 s, ignora offer_timeout=20 s";; *) pass "L1 comportamiento inesperado";; esac; fi

echo "--- L2 tiempo configurado 120 s" | tee -a "$OUT"
psqlq -c "update public.app_settings set offer_timeout_seconds=120 where id=true" >/dev/null
psqlq >/dev/null <<SQL
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values ('eeeeeeee-0000-4000-8000-000000000202','dddddddd-0000-4000-8000-000000000201','$D2',1100,'pending', now()+interval '180 seconds','preview');
SQL
l2=$(val "select round(extract(epoch from (expires_at-created_at))::numeric,1) from public.driver_offers where id='eeeeeeee-0000-4000-8000-000000000202'")
echo "   vigencia de oferta (s): $l2" | tee -a "$OUT"
if [ "$MODE" = "v3" ]; then case "$l2" in 119.*|120.*|121.*) pass "L2 oferta respeta offer_timeout=120 s";; *) fail "L2 vigencia $l2 (esperada 120)";; esac
else case "$l2" in 29.*|30.*|31.*) fail "L2 defecto: vigencia $l2 s, ignora offer_timeout=120 s";; *) pass "L2 comportamiento inesperado";; esac; fi
psqlq -c "update public.app_settings set offer_timeout_seconds=20 where id=true" >/dev/null

echo "--- L3 solicitud ya vencida: no admite ofertas nuevas" | tee -a "$OUT"
psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel,service_mode,expires_at) values ('dddddddd-0000-4000-8000-000000000203','$P','searching','preview','taxi', now()-interval '1 second');
SQL
ins=$(psqlq -c "do \$x\$ begin insert into public.driver_offers(ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values ('dddddddd-0000-4000-8000-000000000203','$D1',1000,'pending', now()+interval '20 seconds','preview'); raise notice 'INSERTED'; exception when others then raise notice 'REJECTED: %', sqlerrm; end \$x\$;" 2>&1 | tr '\n' ' ')
echo "   inserción: ${ins:0:110}" | tee -a "$OUT"
if [ "$MODE" = "v3" ]; then case "$ins" in *REJECTED*) pass "L3 oferta sobre solicitud vencida se rechaza al insertar";; *) fail "L3 aceptada al insertar";; esac
else case "$ins" in *INSERTED*) fail "L3 defecto: oferta sobre solicitud vencida se inserta";; *) pass "L3 comportamiento inesperado";; esac; fi

echo "--- L4 solicitud vence después de crear la oferta: no se puede seleccionar" | tee -a "$OUT"
psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel,service_mode,expires_at) values ('dddddddd-0000-4000-8000-000000000204','$P','searching','preview','taxi', now()+interval '180 seconds');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values ('eeeeeeee-0000-4000-8000-000000000204','dddddddd-0000-4000-8000-000000000204','$D1',1000,'pending', now()+interval '20 seconds','preview');
update public.ride_requests set expires_at = now()-interval '1 second' where id='dddddddd-0000-4000-8000-000000000204';
SQL
r4=$(psqlq -c "select public.test_try_select('eeeeeeee-0000-4000-8000-000000000204','$P')")
echo "   selección tras vencer la solicitud: ${r4:0:60}" | tee -a "$OUT"
if [ "$MODE" = "v3" ]; then case "$r4" in ERR*) pass "L4 solicitud vencida no admite selección";; *) fail "L4 selección aceptada tras vencer la solicitud";; esac
else case "$r4" in OK*) fail "L4 defecto: se acepta una oferta después de vencer la solicitud";; *) pass "L4 comportamiento inesperado";; esac; fi

echo "--- T1 oferta vigente" | tee -a "$OUT"
psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel,service_mode,expires_at) values ('dddddddd-0000-4000-8000-000000000101','$P','searching','preview','taxi', now()+interval '180 seconds');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values ('eeeeeeee-0000-4000-8000-000000000101','dddddddd-0000-4000-8000-000000000101','$D1',1000,'pending', now()+interval '180 seconds','preview');
SQL
r=$(psqlq -c "select public.test_try_select('eeeeeeee-0000-4000-8000-000000000101','$P')")
case "$r" in OK*) pass "T1 oferta vigente se acepta";; *) fail "T1 oferta vigente rechazada: ${r:0:40}";; esac

echo "--- T2 oferta vencida (espera 31 s)" | tee -a "$OUT"
psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel,service_mode,expires_at) values ('dddddddd-0000-4000-8000-000000000102','$P','searching','preview','taxi', now()+interval '180 seconds');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values ('eeeeeeee-0000-4000-8000-000000000102','dddddddd-0000-4000-8000-000000000102','$D1',1000,'pending', now()+interval '180 seconds','preview');
SQL
sleep 31
r=$(psqlq -c "select public.test_try_select('eeeeeeee-0000-4000-8000-000000000102','$P')")
case "$r" in ERR*) pass "T2 oferta vencida se rechaza";; *) fail "T2 oferta vencida aceptada";; esac

echo "--- T3 expires_at nulo en insert (trigger)" | tee -a "$OUT"
psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel,service_mode,expires_at) values ('dddddddd-0000-4000-8000-000000000103','$P','searching','preview','taxi', now()+interval '180 seconds');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values ('eeeeeeee-0000-4000-8000-000000000103','dddddddd-0000-4000-8000-000000000103','$D1',1000,'pending', NULL,'preview');
SQL
nn=$(val "select expires_at is null from public.driver_offers where id='eeeeeeee-0000-4000-8000-000000000103'")
[ "$nn" = "f" ] && pass "T3 el trigger impide expires_at nulo" || fail "T3 expires_at nulo persistido"

echo "--- T4 bypass privilegiado con expires_at nulo" | tee -a "$OUT"
psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel,service_mode,expires_at) values ('dddddddd-0000-4000-8000-000000000104','$P','searching','preview','taxi', now()+interval '180 seconds');
SET session_replication_role = replica;
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values ('eeeeeeee-0000-4000-8000-000000000104','dddddddd-0000-4000-8000-000000000104','$D1',1000,'pending', NULL,'preview');
RESET session_replication_role;
SQL
r4b=$(psqlq -c "select public.test_try_select('eeeeeeee-0000-4000-8000-000000000104','$P')")
if [ "$MODE" = "v3" ]; then case "$r4b" in ERR*) pass "T4 oferta nula por bypass se rechaza";; *) fail "T4 oferta nula por bypass aceptada";; esac
else case "$r4b" in OK*) fail "T4 defecto: oferta nula por bypass aceptada";; *) pass "T4 comportamiento inesperado";; esac; fi

echo "--- T5 segunda aceptación de T1" | tee -a "$OUT"
r5=$(psqlq -c "select public.test_try_select('eeeeeeee-0000-4000-8000-000000000101','$P')")
case "$r5" in ERR*) pass "T5 segunda aceptación rechazada";; *) fail "T5 segunda aceptación permitida";; esac

echo "--- T6 conductor no puede asignarse" | tee -a "$OUT"
psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel,service_mode,expires_at) values ('dddddddd-0000-4000-8000-000000000106','$P','searching','preview','taxi', now()+interval '180 seconds');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values ('eeeeeeee-0000-4000-8000-000000000106','dddddddd-0000-4000-8000-000000000106','$D1',1000,'pending', now()+interval '20 seconds','preview');
SQL
r6=$(psqlq -c "select public.test_try_select('eeeeeeee-0000-4000-8000-000000000106','$D1')")
case "$r6" in ERR*) pass "T6 conductor no puede aceptar su oferta";; *) fail "T6 autoasignación";; esac

echo "--- E1 Envíos: oferta de paquete aceptada, texto de notificación de envío" | tee -a "$OUT"
psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel,service_mode,expires_at,parcel_kind,parcel_sender_name,parcel_recipient_name,parcel_details) values ('dddddddd-0000-4000-8000-000000000301','$P','searching','preview','parcel', now()+interval '180 seconds','moto','Remitente sintético','Destinatario sintético','Sobre sintético');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values ('eeeeeeee-0000-4000-8000-000000000301','dddddddd-0000-4000-8000-000000000301','$D2',1500,'pending', now()+interval '20 seconds','preview');
SQL
e1=$(psqlq -c "select public.test_try_select('eeeeeeee-0000-4000-8000-000000000301','$P')")
case "$e1" in OK*) pass "E1 oferta de Envíos se acepta";; *) fail "E1 Envíos: ${e1:0:60}";; esac
enotif=$(val "select count(*) from public.notifications where user_id='$D2' and title='¡Envío confirmado!'")
[ "$enotif" -ge 1 ] 2>/dev/null && pass "E1 notificación de envío con texto vigente" || fail "E1 texto de envío no encontrado"

echo "--- Carrera determinista (FOR UPDATE)" | tee -a "$OUT"
psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel,service_mode,expires_at) values ('dddddddd-0000-4000-8000-000000000150','$P','searching','preview','taxi', now()+interval '180 seconds');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values
 ('eeeeeeee-0000-4000-8000-000000000150','dddddddd-0000-4000-8000-000000000150','$D1',1000,'pending', now()+interval '20 seconds','preview'),
 ('eeeeeeee-0000-4000-8000-000000000151','dddddddd-0000-4000-8000-000000000150','$D2',1100,'pending', now()+interval '20 seconds','preview');
SQL
printf "begin;\nselect 'A '||public.test_try_select('eeeeeeee-0000-4000-8000-000000000150','$P');\nselect pg_sleep(3);\ncommit;\n" > "$H/.sA.sql"
printf "select 'B '||public.test_try_select('eeeeeeee-0000-4000-8000-000000000151','$P');\n" > "$H/.sB.sql"
$DK exec -i $C psql -U postgres -d "$DB" -q -At < "$H/.sA.sql" > "$H/.oA.txt" 2>&1 & pa=$!; sleep 1
$DK exec -i $C psql -U postgres -d "$DB" -q -At < "$H/.sB.sql" > "$H/.oB.txt" 2>&1; wait $pa
a=$(grep -E "^A " "$H/.oA.txt" | head -1); b=$(grep -E "^B " "$H/.oB.txt" | head -1)
case "$a" in "A OK"*) pass "lock: A asigna";; *) fail "lock A: ${a:0:40}";; esac
case "$b" in "B ERR"*) pass "lock: B rechazada";; *) fail "lock B: ${b:0:40}";; esac
rm -f "$H/.sA.sql" "$H/.sB.sql" "$H/.oA.txt" "$H/.oB.txt"

echo "--- Carrera aleatoria: $N_RACE repeticiones" | tee -a "$OUT"
ok=0; bad=0
for i in $(seq 1 "$N_RACE"); do
  R=$(printf "dddddddd-0000-4000-8000-%012d" $((40000+i)))
  OA=$(printf "eeeeeeee-0000-4000-8000-%012d" $((50000+2*i)))
  OB=$(printf "eeeeeeee-0000-4000-8000-%012d" $((50001+2*i)))
  psqlq >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel,service_mode,expires_at) values ('$R','$P','searching','preview','taxi', now()+interval '180 seconds');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values
 ('$OA','$R','$D1',1000,'pending', now()+interval '20 seconds','preview'),
 ('$OB','$R','$D2',1100,'pending', now()+interval '20 seconds','preview');
SQL
  $DK exec -i $C psql -U postgres -d "$DB" -q -At -c "select 'X '||public.test_try_select('$OA','$P')" > "$H/.ra.txt" 2>&1 & x1=$!
  $DK exec -i $C psql -U postgres -d "$DB" -q -At -c "select 'X '||public.test_try_select('$OB','$P')" > "$H/.rb.txt" 2>&1 & x2=$!
  wait $x1 $x2
  ra=$(grep -E "^X " "$H/.ra.txt" | head -1); rb=$(grep -E "^X " "$H/.rb.txt" | head -1)
  nok=0; case "$ra" in "X OK"*) nok=$((nok+1));; esac; case "$rb" in "X OK"*) nok=$((nok+1));; esac
  inv=$(val "select (select count(*) from public.trips where ride_request_id='$R')||'|'||(select count(*) from public.driver_offers where ride_request_id='$R' and status='selected')||'|'||(select count(*) from public.driver_offers where ride_request_id='$R' and status='declined')||'|'||(select status from public.ride_requests where id='$R')||'|'||(select count(*) from public.trip_status_history h join public.trips t on t.id=h.trip_id where t.ride_request_id='$R')")
  if [ "$nok" -eq 1 ] && [ "$inv" = "1|1|1|driver_selected|1" ]; then ok=$((ok+1)); else bad=$((bad+1)); fi
done
rm -f "$H/.ra.txt" "$H/.rb.txt"
[ "$ok" -eq "$N_RACE" ] && pass "carrera: $ok/$N_RACE con un solo ganador" || fail "carrera: $ok/$N_RACE"
[ "$bad" -eq 0 ] && pass "carrera: 0 inconsistencias" || fail "carrera: $bad inconsistencias"
echo "== fin $MODE" | tee -a "$OUT"
