-- Filtra los programas de beneficios por público (config.audience).
-- Antes, un conductor recibía los programas de pasajeros (p. ej. MIPRIMERVIAJE).
-- p_role = 'driver' | 'passenger'. Si es null (apps antiguas) se mantiene el
-- comportamiento anterior. Programas sin audience se consideran para todos.

drop function if exists public.my_benefits_overview(text);

create or replace function public.my_benefits_overview(
  p_channel text default 'production'::text,
  p_role text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_runtime jsonb;
  v_zone uuid;
  v_currency text;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  v_runtime := public.resolve_current_runtime_environment();
  if coalesce((v_runtime->>'allowed')::boolean, false) = false
     or (v_runtime->>'environment') is distinct from p_channel
     or p_channel not in ('preview', 'production') then
    raise exception 'Entorno de datos no autorizado';
  end if;
  select z.id, z.currency_code into v_zone, v_currency
  from public.users u
  left join public.driver_profiles dp on dp.id = u.id
  join public.service_zones z on z.id = coalesce(u.last_zone_id, dp.zone_id)
  where u.id = v_uid and z.active;
  if v_zone is null then
    return jsonb_build_object('available', false, 'items', '[]'::jsonb, 'coupons', '[]'::jsonb);
  end if;
  return jsonb_build_object(
    'available', true,
    'currency', v_currency,
    'zone_id', v_zone,
    'items', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id,
        'type', p.program_type,
        'name', p.name,
        'description', p.description,
        'config', p.config,
        'currency', v_currency,
        'starts_at', p.starts_at,
        'ends_at', p.ends_at
      ) order by p.created_at desc), '[]'::jsonb)
      from public.benefit_programs p
      where p.zone_id = v_zone
        and p.channel = p_channel
        and p.state = 'active'
        and (p.starts_at is null or p.starts_at <= now())
        and (p.ends_at is null or p.ends_at > now())
        and (p.program_type in ('coupon', 'activation', 'loyalty', 'referral')
             or (p.program_type = 'driver_challenge'
                 and exists (select 1 from public.driver_profiles dp where dp.id = v_uid)))
        and (
          p_role is null
          or coalesce(p.config->>'audience', 'all') in (
            'all',
            case when p_role = 'driver' then 'drivers' else 'passengers' end
          )
        )
    ),
    'coupons', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id,
        'code', c.code,
        'name', p.name,
        'discount_type', c.discount_type,
        'value', c.value,
        'max_discount', c.max_discount,
        'currency', v_currency,
        'expires_at', c.expires_at,
        'state', c.state
      ) order by c.created_at desc), '[]'::jsonb)
      from public.benefit_user_coupons c
      join public.benefit_programs p on p.id = c.program_id
      where c.user_id = v_uid
        and c.zone_id = v_zone
        and c.channel = p_channel
        and c.state = 'available'
        and c.expires_at > now()
    ),
    'history', (
      select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc), '[]'::jsonb)
      from public.benefit_redemptions r
      where r.user_id = v_uid
        and r.zone_id = v_zone
        and r.channel = p_channel
    )
  );
end;
$function$;

revoke all on function public.my_benefits_overview(text, text) from public, anon;
grant execute on function public.my_benefits_overview(text, text) to authenticated;
