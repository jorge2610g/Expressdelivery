-- Quick driver counter-offer buttons, scoped by runtime + city(zone) + service.
-- An optional '*' row applies to every service in the zone; an exact service
-- overrides it. No existing rides/offers are rewritten.
begin;
create table if not exists public.driver_quick_offer_rules (
  channel text not null check(channel in ('preview','production')),
  zone_id uuid not null references public.service_zones(id) on delete cascade,
  service_key text not null check(length(service_key)>0),
  step_1 numeric(12,2) not null check(step_1>0),
  step_2 numeric(12,2) not null check(step_2>step_1),
  step_3 numeric(12,2) not null check(step_3>step_2),
  updated_at timestamptz not null default now(),
  primary key(channel,zone_id,service_key)
);
alter table public.driver_quick_offer_rules enable row level security;
revoke all on public.driver_quick_offer_rules from public,anon,authenticated;

-- This function is only invoked by authorized server RPCs; no extra API
-- request is made for each popup or for each second of its countdown.
create or replace function public.driver_quick_offer_steps(
 p_zone_id uuid,p_service_key text,p_channel text,p_currency text
) returns jsonb language plpgsql stable security definer
set search_path=public as $$
declare
 v_1 numeric;
 v_2 numeric;
 v_3 numeric;
begin
 select q.step_1,q.step_2,q.step_3 into v_1,v_2,v_3
 from public.driver_quick_offer_rules q
 where q.channel=p_channel and q.zone_id=p_zone_id
   and q.service_key in (coalesce(p_service_key,''),'*')
 order by case when q.service_key=coalesce(p_service_key,'') then 0 else 1 end
 limit 1;
 if not found then
   if upper(coalesce(p_currency,''))='CLP' then
     v_1:=250;v_2:=500;v_3:=750;
   else
     v_1:=1;v_2:=2;v_3:=3;
   end if;
 end if;
 return jsonb_build_array(v_1,v_2,v_3);
end $$;
revoke all on function public.driver_quick_offer_steps(uuid,text,text,text)
 from public,anon,authenticated;

create or replace function public.admin_driver_quick_offer_get(
 p_zone_id uuid,p_service_key text default '*',
 p_channel text default 'production'
) returns jsonb language plpgsql stable security definer
set search_path=public as $$
declare
 v_currency text;
 v_record public.driver_quick_offer_rules%rowtype;
 v_steps jsonb;
 v_context jsonb;
 v_service text:=nullif(trim(coalesce(p_service_key,'')),'');
begin
 if auth.uid() is null or not public.is_admin()
   or p_channel not in ('preview','production')
   or not public.admin_environment_allowed(p_channel) then
   raise exception 'No autorizado para consultar las ofertas de esta cuenta';
 end if;
 v_context:=public.admin_access_context();
 if v_context->>'zone_id' is not null and
   (v_context->>'zone_id')::uuid is distinct from p_zone_id then
   raise exception 'Zona administrativa no autorizada';
 end if;
 if v_service is null then raise exception 'Servicio inválido'; end if;
 select z.currency_code into v_currency from public.service_zones z
   where z.id=p_zone_id;
 if v_currency is null then raise exception 'Zona no encontrada'; end if;
 if v_service<>'*' and not exists(
   select 1 from public.zone_service_catalog c
   where c.zone_id=p_zone_id and c.service_key=v_service
 ) then raise exception 'Servicio no disponible para esta zona'; end if;
 select * into v_record from public.driver_quick_offer_rules
   where zone_id=p_zone_id and service_key=v_service and channel=p_channel;
 v_steps:=public.driver_quick_offer_steps(p_zone_id,v_service,p_channel,v_currency);
 return jsonb_build_object(
   'zone_id',p_zone_id,'service_key',v_service,
   'channel',p_channel,'currency',v_currency,
   'configured',found,'steps',v_steps
 );
end $$;

create or replace function public.admin_driver_quick_offer_set(
 p_zone_id uuid,p_service_key text,
 p_step_1 numeric,p_step_2 numeric,p_step_3 numeric,
 p_channel text default 'production'
) returns jsonb language plpgsql security definer
set search_path=public as $$
declare
 v_context jsonb;
 v_currency text;
 v_min_step numeric;
 v_service text:=nullif(trim(coalesce(p_service_key,'')),'');
begin
 if auth.uid() is null or not public.is_admin()
   or p_channel not in ('preview','production')
   or not public.admin_environment_allowed(p_channel) then
    raise exception 'Entorno administrativo no autorizado';
 end if;
 v_context:=public.admin_access_context();
 if coalesce(v_context->>'role','') <> 'super_admin' then
    raise exception 'Solo un superadministrador puede modificar ofertas';
 end if;
 if v_context->>'zone_id' is not null and
    (v_context->>'zone_id')::uuid is distinct from p_zone_id then
    raise exception 'Zona administrativa no autorizada';
 end if;
 select currency_code into v_currency from public.service_zones
   where id=p_zone_id;
 if v_currency is null then raise exception 'Zona no encontrada'; end if;
 if v_service is null or
   (v_service<>'*' and not exists(
     select 1 from public.zone_service_catalog c
     where c.zone_id=p_zone_id and c.service_key=v_service
   )) then raise exception 'Servicio no disponible para esta zona'; end if;
 if p_step_1 is null or p_step_2 is null or p_step_3 is null or
    p_step_1<=0 or p_step_2<=p_step_1 or p_step_3<=p_step_2 or
    p_step_3>10000000 then
   raise exception 'Los tres aumentos deben ser positivos, ascendentes y razonables';
 end if;
 v_min_step:=public.fare_rounding_increment(v_currency,p_channel);
 if v_currency='CLP' then v_min_step:=greatest(v_min_step,1); end if;
 if mod(p_step_1,v_min_step)<>0 or mod(p_step_2,v_min_step)<>0
   or mod(p_step_3,v_min_step)<>0 then
   raise exception 'Los aumentos deben ser múltiplos de % %',
      v_min_step,v_currency;
 end if;
 insert into public.driver_quick_offer_rules (
  channel,zone_id,service_key,step_1,step_2,step_3,updated_at
 ) values (p_channel,p_zone_id,v_service,p_step_1,p_step_2,p_step_3,now())
 on conflict (channel,zone_id,service_key) do update
 set step_1=excluded.step_1,step_2=excluded.step_2,
     step_3=excluded.step_3,updated_at=now();
 return public.admin_driver_quick_offer_get(p_zone_id,v_service,p_channel);
end $$;

revoke all on function public.admin_driver_quick_offer_get(uuid,text,text)
 from public,anon;
revoke all on function public.admin_driver_quick_offer_set(
 uuid,text,numeric,numeric,numeric,text) from public,anon;
grant execute on function public.admin_driver_quick_offer_get(uuid,text,text)
 to authenticated;
grant execute on function public.admin_driver_quick_offer_set(
 uuid,text,numeric,numeric,numeric,text) to authenticated;

-- Same dispatch, same eligibility and isolation as v3. Enrich each already
-- authorized request with its current city/service steps in ONE RPC response.
create or replace function public.available_ride_requests_for_driver_v4(
 p_channel text default 'production'
) returns jsonb language plpgsql stable security definer
set search_path=public as $$
declare
 v_raw jsonb;
 v_result jsonb;
begin
 if auth.uid() is null or not public.is_account_active() then
   raise exception 'No autorizado';
 end if;
 v_raw:=public.available_ride_requests_for_driver_v3(p_channel);
 if v_raw is null or jsonb_typeof(v_raw)<>'array' then
   return '[]'::jsonb;
 end if;
 select coalesce(jsonb_agg(
   e||jsonb_build_object('quick_offer_steps',
     public.driver_quick_offer_steps(
       coalesce(
         nullif(e->>'zone_id','')::uuid,
         public.service_zone_id_for_point(
           nullif(e->>'pickup_latitude','')::numeric,
           nullif(e->>'pickup_longitude','')::numeric
         )
       ),
       e->>'category',e->>'channel',e->>'currency'
     )
   ) order by ord),'[]'::jsonb)
 into v_result from jsonb_array_elements(v_raw) with ordinality as data(e,ord);
 return v_result;
end $$;
revoke all on function public.available_ride_requests_for_driver_v4(text)
 from public,anon;
grant execute on function public.available_ride_requests_for_driver_v4(text)
 to authenticated;
commit;
