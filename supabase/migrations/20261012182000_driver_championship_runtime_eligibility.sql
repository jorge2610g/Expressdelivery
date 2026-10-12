-- 2026-10-12: enforce test/production driver account isolation on leaderboard.
-- Keeps all existing security definer checks and RPC grants unchanged.
CREATE OR REPLACE FUNCTION public.driver_championships_for_driver(p_channel text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
   from public.driver_profiles dp
   join public.users u on u.id=dp.id
   join public.account_runtime_bindings arb
     on arb.user_id=dp.id and arb.environment=v_champ.channel
   where dp.zone_id=v_champ.zone_id and dp.approval_status='approved'
     and u.account_status='active'
     and (v_champ.channel <> 'preview' or exists (
       select 1 from public.audit_test_group_members mem
       join public.audit_test_groups grp on grp.id=mem.group_id
       where mem.user_id=dp.id and mem.enabled=true and grp.active=true
     ))
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
end $function$

