-- Campeonato Express — rankings calculated from completed trips, scoped to runtime/zone/service.
-- Payments are NOT automated; prize text is an administrative commitment.
begin;
create table if not exists public.driver_championships(
 id uuid primary key default gen_random_uuid(),
 channel text not null check(channel in ('preview','production')),
 zone_id uuid not null references public.service_zones(id),
 service_key text not null default '*' check(service_key in ('*','economy','motorcycle','comfort','xl')),
 title text not null check(length(trim(title)) between 4 and 100),
 starts_at timestamptz not null,
 ends_at timestamptz not null,
 state text not null default 'draft' check(state in ('draft','active','closed')),
 first_prize text not null default '' check(length(first_prize)<=180),
 second_prize text not null default '' check(length(second_prize)<=180),
 third_prize text not null default '' check(length(third_prize)<=180),
 rules text not null default 'Solo cuentan viajes completados y válidos.' check(length(rules)<=1000),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(ends_at>starts_at and ends_at<=starts_at+interval '366 days')
);
create index if not exists driver_championships_live_lookup
 on public.driver_championships(channel,zone_id,state,ends_at desc);
create index if not exists driver_championships_zone_service
 on public.driver_championships(channel,zone_id,service_key,starts_at,ends_at);
create index if not exists driver_championships_trip_window on public.trips(driver_id,completed_at)
 where status='completed';
alter table public.driver_championships enable row level security;
revoke all on public.driver_championships from public,anon,authenticated;
-- RPC admin: read only selected city's records and the requesting account's runtime.
create or replace function public.admin_driver_championship_list(
 p_zone_id uuid,p_channel text
) returns jsonb language plpgsql stable security definer
set search_path=public as $$
declare v_context jsonb;
begin
 if auth.uid() is null or not public.is_admin()
   or p_channel not in ('preview','production')
   or not public.admin_environment_allowed(p_channel) then
   raise exception 'Acceso a campeonatos no autorizado';
 end if;
 v_context:=public.admin_access_context();
 if v_context->>'zone_id' is not null
   and (v_context->>'zone_id')::uuid<>p_zone_id then
   raise exception 'Zona administrativa no autorizada';
 end if;
 return (select coalesce(jsonb_agg(to_jsonb(c) order by c.created_at desc),'[]'::jsonb)
 from public.driver_championships c
 where c.zone_id=p_zone_id and c.channel=p_channel);
end $$;

create or replace function public.admin_driver_championship_save(
 p_id uuid,p_zone_id uuid,p_channel text,p_service_key text,
 p_title text,p_starts_at timestamptz,p_ends_at timestamptz,p_state text,
 p_first_prize text,p_second_prize text,p_third_prize text,p_rules text
) returns jsonb language plpgsql security definer
set search_path=public as $$
declare v_context jsonb;v_id uuid;v_record public.driver_championships%rowtype;
begin
 v_context:=public.admin_access_context();
 if auth.uid() is null or not public.is_admin()
   or not public.admin_environment_allowed(p_channel)
   or v_context->>'role'<>'super_admin' then
   raise exception 'Solo el superadministrador autorizado puede configurar campeonatos';
 end if;
 if v_context->>'zone_id' is not null
   and (v_context->>'zone_id')::uuid<>p_zone_id then
   raise exception 'Zona administrativa no autorizada';
 end if;
 if not exists(select 1 from public.service_zones z where z.id=p_zone_id and z.active)
   then raise exception 'Zona inexistente o inactiva'; end if;
 if p_service_key is null or p_service_key not in ('*','economy','motorcycle','comfort','xl')
   or (p_service_key<>'*' and not exists(
     select 1 from public.zone_service_catalog zs
     where zs.zone_id=p_zone_id and zs.service_key=p_service_key
   )) then raise exception 'Servicio no disponible'; end if;
 if p_channel not in ('preview','production') or p_state not in ('draft','active','closed')
   or trim(coalesce(p_title,''))='' or length(trim(p_title))>100
   or p_starts_at is null or p_ends_at is null
   or p_ends_at<=p_starts_at or p_ends_at>p_starts_at+interval '366 days'
   or length(coalesce(p_first_prize,''))>180
   or length(coalesce(p_second_prize,''))>180
   or length(coalesce(p_third_prize,''))>180
   or length(coalesce(p_rules,''))>1000 then
   raise exception 'Configuración del campeonato inválida';
 end if;
 -- Avoid two contests awarding the same rides in the same city and service.
 if p_state='active' and exists(
   select 1 from public.driver_championships c
   where c.channel=p_channel and c.zone_id=p_zone_id and c.state='active'
     and c.id is distinct from p_id
     and (c.service_key='*' or p_service_key='*' or c.service_key=p_service_key)
     and tstzrange(c.starts_at,c.ends_at,'[)') &&
         tstzrange(p_starts_at,p_ends_at,'[)')
 ) then raise exception 'Ya existe un campeonato activo que se superpone en esta zona y servicio'; end if;
 if p_id is not null and not exists(
   select 1 from public.driver_championships
   where id=p_id and channel=p_channel and zone_id=p_zone_id
 ) then raise exception 'No se puede modificar un campeonato ajeno'; end if;
 insert into public.driver_championships(
   id,channel,zone_id,service_key,title,starts_at,ends_at,state,
   first_prize,second_prize,third_prize,rules
 ) values (
   coalesce(p_id,gen_random_uuid()),p_channel,p_zone_id,p_service_key,trim(p_title),
   p_starts_at,p_ends_at,p_state,coalesce(p_first_prize,''),
   coalesce(p_second_prize,''),coalesce(p_third_prize,''),
   coalesce(p_rules,'Solo cuentan viajes completados y válidos.')
 )
 on conflict(id) do update set
   service_key=excluded.service_key,title=excluded.title,
   starts_at=excluded.starts_at,ends_at=excluded.ends_at,state=excluded.state,
   first_prize=excluded.first_prize,second_prize=excluded.second_prize,
   third_prize=excluded.third_prize,rules=excluded.rules,updated_at=now()
 returning * into v_record;
 perform public.admin_log_action(
   'upsert','driver_championship',v_record.id::text,
   jsonb_build_object('channel',p_channel,'zone_id',p_zone_id,
     'service',p_service_key,'state',p_state,'title',p_title)
 );
 return to_jsonb(v_record);
end $$;

-- One authenticated driver may only read the active championship in their
-- currently assigned zone and their bound environment. Never expose raw trips.
create or replace function public.driver_championships_for_driver(
 p_channel text default 'production'
) returns jsonb language plpgsql stable security definer
set search_path=public as $$
declare
 v_uid uuid:=auth.uid();
 v_runtime jsonb;
 v_zone uuid;
 v_champ public.driver_championships%rowtype;
 v_ranking jsonb;
 v_myrank integer;
 v_mytrips integer;
 v_top_ten jsonb;
begin
 if v_uid is null or not public.is_account_active() then
   raise exception 'No autorizado';
 end if;
 v_runtime:=public.resolve_current_runtime_environment();
 if coalesce((v_runtime->>'allowed')::boolean,false)=false
   or (v_runtime->>'environment') is distinct from p_channel
   or p_channel not in ('preview','production') then
   raise exception 'Entorno de datos no autorizado';
 end if;
 select dp.zone_id into v_zone
 from public.driver_profiles dp join public.service_zones z on z.id=dp.zone_id
 where dp.id=v_uid and dp.approval_status='approved' and z.active;
 if v_zone is null then
   return jsonb_build_object('available',false,'message','El conductor debe estar aprobado y tener una zona activa');
 end if;
 select * into v_champ
 from public.driver_championships c
 where c.zone_id=v_zone and c.channel=p_channel
   and c.state='active' and c.starts_at<=now() and c.ends_at>now()
 order by c.created_at desc limit 1;
 if v_champ.id is null then
   return jsonb_build_object('available',false,'message','Aún no hay un campeonato activo en tu zona');
 end if;

 with eligible as (
   select dp.id,u.full_name
   from public.driver_profiles dp join public.users u on u.id=dp.id
   where dp.zone_id=v_champ.zone_id and dp.approval_status='approved'
     and u.account_status='active'
 ), counts as (
   select e.id,e.full_name,count(t.id)::integer as rides
   from eligible e left join public.trips t on t.driver_id=e.id
     and t.status='completed' and t.channel=v_champ.channel
     and t.completed_at>=v_champ.starts_at and t.completed_at<v_champ.ends_at
     and exists(select 1 from public.ride_requests r where r.id=t.ride_request_id
         and r.zone_id=v_champ.zone_id and r.channel=v_champ.channel
         and (v_champ.service_key='*' or r.category=v_champ.service_key))
   group by e.id,e.full_name
 ), ordered as (
   select id,full_name,rides,
   row_number() over(order by rides desc,full_name asc,id)::integer as pos
   from counts
 )
 select
  coalesce(jsonb_agg(jsonb_build_object(
    'position',o.pos,
    'name',case when o.id=v_uid then 'Tú'
      else coalesce(nullif(split_part(trim(o.full_name),' ',1),''),'Conductor') ||
        case when position(' ' in trim(o.full_name))>0
          then ' '||left(split_part(trim(o.full_name),' ',2),1)||'.' else '' end end,
    'rides',o.rides,'is_me',o.id=v_uid
  ) order by o.pos) filter(where o.pos<=10),'[]'::jsonb),
  max(o.pos) filter(where o.id=v_uid),
  max(o.rides) filter(where o.id=v_uid)
 into v_top_ten,v_myrank,v_mytrips from ordered o;
 return jsonb_build_object(
   'available',true,'id',v_champ.id,'title',v_champ.title,
   'service_key',v_champ.service_key,
   'zone_name',(select name from public.service_zones where id=v_zone),
   'currency',(select currency_code from public.service_zones where id=v_zone),
   'starts_at',v_champ.starts_at,'ends_at',v_champ.ends_at,
   'first_prize',v_champ.first_prize,'second_prize',v_champ.second_prize,
   'third_prize',v_champ.third_prize,'rules',v_champ.rules,
   'top_ten',v_top_ten,'my_position',v_myrank,
   'my_rides',coalesce(v_mytrips,0)
 );
end $$;
-- Functions run as owner solely for authorized, scoped read/write.
revoke all on function public.admin_driver_championship_list(uuid,text) from public,anon;
revoke all on function public.admin_driver_championship_save(uuid,uuid,text,text,text,timestamptz,timestamptz,text,text,text,text,text) from public,anon;
revoke all on function public.driver_championships_for_driver(text) from public,anon;
grant execute on function public.admin_driver_championship_list(uuid,text) to authenticated;
grant execute on function public.admin_driver_championship_save(uuid,uuid,text,text,text,timestamptz,timestamptz,text,text,text,text,text) to authenticated;
grant execute on function public.driver_championships_for_driver(text) to authenticated;
commit;