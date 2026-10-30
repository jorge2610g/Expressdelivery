-- Read-only dashboard data for the Admin Express driver-plan referral screen.
-- Results are limited to the caller's authorized admin environment and zone.
begin;

create or replace function public.admin_driver_referral_dashboard(
  p_zone_id uuid,
  p_channel text,
  p_status text default 'all'
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_stats jsonb;
  v_referrals jsonb;
begin
  if auth.uid() is null
    or not public.is_admin()
    or p_channel not in ('preview','production')
    or not public.admin_environment_allowed(p_channel) then
    raise exception 'Acceso a referidos no autorizado';
  end if;

  v_context := public.admin_access_context();
  if coalesce(v_context->>'role','') not in ('super_admin','zone_monitor') then
    raise exception 'El historial de referidos requiere acceso administrativo central';
  end if;
  if v_context->>'zone_id' is not null
    and (v_context->>'zone_id')::uuid <> p_zone_id then
    raise exception 'Zona administrativa no autorizada';
  end if;
  if p_status not in ('all','pending','qualified','reward_review','closed') then
    raise exception 'Filtro de estado inválido';
  end if;
  if not exists(select 1 from public.service_zones z where z.id=p_zone_id and z.active) then
    raise exception 'Zona no disponible';
  end if;

  select jsonb_build_object(
    'total', count(*),
    'pending', count(*) filter (where l.state='pending'),
    'activated', count(*) filter (where l.state='qualified'),
    'conversion_percent', case when count(*)=0 then 0
      else round(100.0 * count(*) filter (where l.state='qualified') / count(*), 1) end
  )
  into v_stats
  from public.benefit_referral_links l
  join public.benefit_programs p on p.id=l.program_id
  where l.zone_id=p_zone_id and l.channel=p_channel
    and p.program_type='referral_commission';

  select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc), '[]'::jsonb)
  into v_referrals
  from (
    select
      l.id,
      l.state,
      l.plan_payment_percent,
      l.created_at,
      l.qualified_at,
      code.code as referral_code,
      referrer.full_name as referrer_name,
      referrer.phone as referrer_phone,
      referred.full_name as referred_name,
      referred.phone as referred_phone,
      coalesce(payments.payment_count,0) as plan_payment_count,
      coalesce(payments.commission_total,0) as commission_total,
      payments.last_payment_at
    from public.benefit_referral_links l
    join public.benefit_programs p on p.id=l.program_id
    join public.users referrer on referrer.id=l.referrer_id
    join public.users referred on referred.id=l.referee_id
    left join public.driver_referral_codes code
      on code.driver_id=l.referrer_id and code.channel=l.channel
    left join lateral (
      select count(*)::integer as payment_count,
        coalesce(sum(c.commission_amount),0)::numeric(12,2) as commission_total,
        max(c.created_at) as last_payment_at
      from public.benefit_subscription_commissions c
      where c.referral_id=l.id and c.channel=l.channel
    ) payments on true
    where l.zone_id=p_zone_id and l.channel=p_channel
      and p.program_type='referral_commission'
      and (p_status='all' or l.state=p_status)
  ) r;

  return jsonb_build_object('stats',v_stats,'referrals',v_referrals,'currency','BOB');
end $$;

revoke all on function public.admin_driver_referral_dashboard(uuid,text,text) from public,anon;
grant execute on function public.admin_driver_referral_dashboard(uuid,text,text) to authenticated;

commit;
