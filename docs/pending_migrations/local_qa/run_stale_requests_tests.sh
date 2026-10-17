#!/bin/bash
# Pruebas locales de close_stale_ride_requests (PostgreSQL aislado, datos sintéticos).
set -u
DK=/Applications/Docker.app/Contents/Resources/bin/docker; C=express-qa-pg15
H="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$H/../../.." && pwd)"
PROP="$REPO/docs/pending_migrations/20261017_close_stale_ride_requests_PROPOSAL.sql"
DB=qa_stale; OUT="$H/results_stale_requests.txt"
P=aaaaaaaa-0000-4000-8000-000000000001; D1=bbbbbbbb-0000-4000-8000-000000000001; D2=bbbbbbbb-0000-4000-8000-000000000002
q() { $DK exec -i $C psql -U postgres -d "$DB" -v ON_ERROR_STOP=1 -q -At "$@" || { echo "SQL ERROR: aborting" | tee -a "$OUT"; exit 1; }; }
pass() { echo "PASS  $1" | tee -a "$OUT"; }
fail() { echo "FAIL  $1" | tee -a "$OUT"; }
: > "$OUT"; echo "== $(date -u +%FT%TZ)" | tee -a "$OUT"
$DK exec $C psql -U postgres -d postgres -q -c "drop database if exists $DB" -c "create database $DB template qa_pristine" >/dev/null
q >/dev/null <<'SQL'
do $$ begin if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin; end if; end $$;
SQL
q < "$H/test_helper.sql" >/dev/null; q < "$H/seed_base.sql" >/dev/null; q < "$PROP" >/dev/null && echo "propuesta aplicada (solo $DB)" | tee -a "$OUT"
q >/dev/null <<SQL
-- A: vencida hace 2 min, sin ofertas -> debe cerrarse
insert into public.ride_requests(id,passenger_id,status,channel,service_mode,expires_at) values ('dddddddd-0000-4000-8000-00000000a001','$P','searching','preview','taxi', now()-interval '2 minutes');
-- B: vencida hace 2 min, con oferta ya rechazada -> cerrar; la oferta no cambia
insert into public.ride_requests(id,passenger_id,status,channel,service_mode,expires_at) values ('dddddddd-0000-4000-8000-00000000b001','$P','searching','preview','taxi', now()-interval '2 minutes');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values ('eeeeeeee-0000-4000-8000-00000000b001','dddddddd-0000-4000-8000-00000000b001','$D1',1000,'declined', now()-interval '1 minute','preview');
-- C: activa -> NO tocar
insert into public.ride_requests(id,passenger_id,status,channel,service_mode,expires_at) values ('dddddddd-0000-4000-8000-00000000c001','$P','searching','preview','taxi', now()+interval '3 minutes');
-- D: vencida con oferta seleccionada y viaje -> NO tocar
insert into public.ride_requests(id,passenger_id,status,channel,service_mode,expires_at) values ('dddddddd-0000-4000-8000-00000000d001','$P','driver_selected','preview','taxi', now()-interval '2 minutes');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values ('eeeeeeee-0000-4000-8000-00000000d001','dddddddd-0000-4000-8000-00000000d001','$D1',1000,'selected', now()-interval '2 minutes','preview');
insert into public.trips(id,ride_request_id,passenger_id,driver_id,status,payment_status,channel) values ('ffffffff-0000-4000-8000-00000000d001','dddddddd-0000-4000-8000-00000000d001','$P','$D1','driver_arriving','pending','preview');
-- E: vencida hace 10 s (dentro del margen de 30 s) -> NO tocar
insert into public.ride_requests(id,passenger_id,status,channel,service_mode,expires_at) values ('dddddddd-0000-4000-8000-00000000e001','$P','searching','preview','taxi', now()-interval '10 seconds');
-- F: expires_at nulo -> NO tocar
insert into public.ride_requests(id,passenger_id,status,channel,service_mode,expires_at) values ('dddddddd-0000-4000-8000-00000000f001','$P','searching','preview','taxi', NULL);
-- G: vencida hace 2 min pero con oferta pendiente VIGENTE -> NO tocar
insert into public.ride_requests(id,passenger_id,status,channel,service_mode,expires_at) values ('dddddddd-0000-4000-8000-00000000a201','$P','searching','preview','taxi', now()-interval '2 minutes');
insert into public.driver_offers(id,ride_request_id,driver_id,proposed_fare,status,expires_at,channel) values ('eeeeeeee-0000-4000-8000-00000000a201','dddddddd-0000-4000-8000-00000000a201','$D2',1000,'pending', now()+interval '20 seconds','preview');
SQL
n1=$(q -c "select public.close_stale_ride_requests(100)")
echo "   primera ejecución cerró: $n1" | tee -a "$OUT"
st() { q -c "select status from public.ride_requests where id='$1'"; }
[ "$(st dddddddd-0000-4000-8000-00000000a001)" = "cancelled" ] && pass "A vencida sin ofertas se cierra" || fail "A no cerrada"
[ "$(st dddddddd-0000-4000-8000-00000000b001)" = "cancelled" ] && [ "$(q -c "select status from public.driver_offers where id='eeeeeeee-0000-4000-8000-00000000b001'")" = "declined" ] && pass "B vencida con oferta rechazada se cierra y la oferta no cambia" || fail "B"
[ "$(st dddddddd-0000-4000-8000-00000000c001)" = "searching" ] && pass "C solicitud activa no se toca" || fail "C tocada"
[ "$(st dddddddd-0000-4000-8000-00000000d001)" = "driver_selected" ] && [ "$(q -c "select status from public.driver_offers where id='eeeeeeee-0000-4000-8000-00000000d001'")" = "selected" ] && pass "D asignada con viaje no se toca" || fail "D tocada"
[ "$(st dddddddd-0000-4000-8000-00000000e001)" = "searching" ] && pass "E dentro del margen de 30 s no se toca" || fail "E tocada"
[ "$(st dddddddd-0000-4000-8000-00000000f001)" = "searching" ] && pass "F expires_at nulo no se toca" || fail "F tocada"
[ "$(st dddddddd-0000-4000-8000-00000000a201)" = "searching" ] && [ "$(q -c "select status from public.driver_offers where id='eeeeeeee-0000-4000-8000-00000000a201'")" = "pending" ] && pass "G con oferta vigente no se toca" || fail "G tocada"
n2=$(q -c "select public.close_stale_ride_requests(100)")
[ "$n2" = "0" ] && pass "idempotente: segunda ejecución no cambia nada" || fail "segunda ejecución cerró $n2"
q >/dev/null <<SQL
insert into public.ride_requests(id,passenger_id,status,channel,service_mode,expires_at) select gen_random_uuid(),'$P','searching','preview','taxi', now()-interval '5 minutes' from generate_series(1,20);
SQL
n3=$(q -c "select public.close_stale_ride_requests(5)")
[ "$n3" = "5" ] && pass "límite de lote respetado (5 de 20)" || fail "límite: $n3"
rem=$(q -c "select count(*) from public.ride_requests where status='searching' and expires_at < now()-interval '30 seconds' and id <> 'dddddddd-0000-4000-8000-00000000a201'")
[ "$rem" = "15" ] && pass "resto del lote pendiente para la siguiente ejecución (15; G excluida por oferta vigente)" || fail "resto: $rem"
echo "== fin" | tee -a "$OUT"
