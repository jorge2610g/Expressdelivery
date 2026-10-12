-- Hourly bounded sweep. Each milestone emits one in-app notification,
-- and the existing notification dispatcher may deliver push.
create index if not exists driver_documents_expiration_active_idx
  on public.driver_documents(expires_at) where expires_at is not null;

create or replace function public.driver_document_expiry_sweep()
returns jsonb language plpgsql security definer set search_path=public
as $$
declare
  v_offline integer:=0;
  v_notices integer:=0;
begin
  v_offline:=public.expire_online_drivers();

  with candidates as (
    select d.id document_id,d.driver_id,r.label,d.expires_at,
      coalesce(b.environment,'production') environment,
      (
        (d.expires_at at time zone
          case upper(coalesce(p.country_code,''))
            when 'CL' then 'America/Santiago'
            when 'BO' then 'America/La_Paz'
            when 'PE' then 'America/Lima'
            else 'UTC' end)::date
        -
        (now() at time zone
          case upper(coalesce(p.country_code,''))
            when 'CL' then 'America/Santiago'
            when 'BO' then 'America/La_Paz'
            when 'PE' then 'America/Lima'
            else 'UTC' end)::date
        - 1
      )::integer days_left
    from public.driver_documents d
    join public.driver_document_requirements r on r.id=d.requirement_id
    join public.driver_profiles p on p.id=d.driver_id
    left join public.account_runtime_bindings b on b.user_id=d.driver_id
    where r.active and r.required
      and d.expires_at is not null
      and d.expires_at<=now()+interval '32 days'
      and (r.country_code is null
           or upper(r.country_code)=upper(coalesce(p.country_code,'')))
      and (r.zone_id is null or r.zone_id=p.zone_id)
  ), milestones as (
    select c.* from candidates c
    where c.days_left in (30,14,7,3,1,0,-1)
      and not exists(
        select 1 from public.notifications n
        where n.user_id=c.driver_id
          and n.type='driver_document_expiry'
          and n.metadata->>'document_id'=c.document_id::text
          and n.metadata->>'milestone_days'=c.days_left::text
      )
  )
  insert into public.notifications(user_id,title,body,type,channel,metadata)
  select m.driver_id,
    case when m.days_left<0 then 'Documento vencido'
         when m.days_left=0 then 'Tu documento vence hoy'
         else 'Tu documento se vencerá pronto' end,
    m.label||': '||case
      when m.days_left<0 then
        'ya está vencido. No podrás aceptar nuevos viajes hasta renovarlo y obtener aprobación.'
      when m.days_left=0 then
        'vence hoy. Actualízalo para continuar trabajando.'
      else
        'faltan '||m.days_left||' días para su vencimiento.'
    end,
    'driver_document_expiry',
    m.environment,
    jsonb_build_object(
      'document_id',m.document_id,
      'milestone_days',m.days_left,
      'expires_at',m.expires_at)
  from milestones m;
  get diagnostics v_notices=row_count;
  return jsonb_build_object('drivers_offline',v_offline,
                            'notices_sent',v_notices);
end;
$$;
revoke all on function public.driver_document_expiry_sweep()
  from public,anon,authenticated;

-- pg_cron is available on the Supabase cluster but was not installed.
-- Installing it here makes expiry independent of an open browser.
create extension if not exists pg_cron with schema pg_catalog;
do $outer$
begin
  if not exists(select 1 from cron.job
                where jobname='driver-document-expiry-hourly') then
    perform cron.schedule(
      'driver-document-expiry-hourly',
      '10 * * * *',
      $job$select public.driver_document_expiry_sweep();$job$
    );
  end if;
end;
$outer$;
