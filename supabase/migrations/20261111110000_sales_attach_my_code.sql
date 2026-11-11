-- La app Android recibe el código del asesor desde el referrer de Google Play
-- o desde el enlace https://expressviajes.online/r/CODIGO y lo envía aquí tras
-- el primer inicio de sesión (Google). Solo atribuye cuentas NUEVAS (creadas
-- hace menos de 3 días) que todavía no tienen asesor.
create or replace function public.sales_attach_my_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'auth'
as $$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(trim(coalesce(p_code, '')));
  v_advisor uuid;
  v_created timestamptz;
begin
  if v_uid is null then
    raise exception 'No autorizado';
  end if;
  if exists (select 1 from public.sales_attributions where user_id = v_uid) then
    return jsonb_build_object('status', 'already_attributed');
  end if;
  select au.created_at into v_created from auth.users au where au.id = v_uid;
  if v_created is null or v_created < now() - interval '3 days' then
    return jsonb_build_object('status', 'account_too_old');
  end if;
  select a.id into v_advisor from public.sales_advisors a where a.code = v_code and a.active;
  if v_advisor is null then
    return jsonb_build_object('status', 'invalid_code');
  end if;
  insert into public.sales_attributions (user_id, advisor_id, role)
    values (v_uid, v_advisor,
            case when exists (select 1 from public.driver_profiles dp where dp.id = v_uid)
                 then 'driver' else 'passenger' end)
    on conflict (user_id) do nothing;
  perform public.sales_refresh_registration(v_uid);
  return jsonb_build_object('status', 'attached');
end
$$;

revoke all on function public.sales_attach_my_code(text) from public, anon;
grant execute on function public.sales_attach_my_code(text) to authenticated;
