-- Daily gross income summary: one minimal RPC instead of loading hundreds of
-- full trip/delivery records every two minutes on the driver map.
-- Device-local midnight is supplied explicitly as UTC bounds, with DST.
create or replace function public.my_driver_daily_income(
  p_channel text,
  p_start timestamptz,
  p_end timestamptz
) returns jsonb
language plpgsql stable security definer set search_path=public
as $body$
declare
  v_uid uuid:=auth.uid();
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_environment text;
  v_country text;
  v_totals jsonb;
  v_trips integer;
  v_deliveries integer;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'Sesión requerida';
  end if;
  select coalesce(b.environment,'production') into v_environment
  from public.account_runtime_bindings b where b.user_id=v_uid;
  v_environment:=coalesce(v_environment,'production');
  if v_channel<>v_environment then
    raise exception 'Entorno no autorizado';
  end if;
  if p_start is null or p_end is null or p_end<=p_start
     or p_end-p_start>interval '26 hours'
     or p_end-p_start<interval '22 hours'
     or now()<p_start-interval '3 hours'
     or now()>p_end+interval '2 hours' then
    raise exception 'Período diario inválido';
  end if;
  v_country:=nullif(public.current_operating_context()->>'country_code','');
  if v_country is null then
    select country_code into v_country
      from public.driver_profiles where id=v_uid;
  end if;

  with income as materialized (
    select 'trip'::text kind,
       upper(coalesce(nullif(rr.currency,''),'BOB')) currency,
       coalesce(t.final_fare,rr.proposed_fare,0)::numeric amount
    from public.trips t
    join public.ride_requests rr on rr.id=t.ride_request_id
    left join public.service_zones z on z.id=rr.zone_id
    where t.driver_id=v_uid and t.status='completed'
      and t.channel=v_channel and rr.channel=v_channel
      and t.completed_at>=p_start and t.completed_at<p_end
      and (
        z.country_code=v_country or
        (z.id is null and exists(
          select 1 from public.service_zones cz
          where cz.country_code=v_country
            and upper(cz.currency_code)=upper(rr.currency)
        ))
      )
    union all
    select 'delivery'::text kind,
       upper(coalesce(nullif(d.currency,''),'BOB')) currency,
       coalesce(d.proposed_fare,0)::numeric amount
    from public.delivery_requests d
    where d.courier_id=v_uid and d.status='delivered'
      and d.channel=v_channel and d.country_code=v_country
      and d.completed_at>=p_start and d.completed_at<p_end
  ), currencies as (
    select currency,round(sum(amount),2) amount
    from income
    group by currency
  )
  select
    coalesce((select jsonb_object_agg(currency,amount) from currencies),
             '{}'::jsonb),
    (select count(*)::integer from income where kind='trip'),
    (select count(*)::integer from income where kind='delivery')
  into v_totals,v_trips,v_deliveries;

  return jsonb_build_object(
    'totals',coalesce(v_totals,'{}'::jsonb),
    'trips',coalesce(v_trips,0),
    'deliveries',coalesce(v_deliveries,0),
    'day_start',p_start,
    'day_end',p_end,
    'channel',v_channel
  );
end;
$body$;
revoke all on function public.my_driver_daily_income(text,timestamptz,timestamptz)
  from public,anon;
grant execute on function public.my_driver_daily_income(text,timestamptz,timestamptz)
  to authenticated;
