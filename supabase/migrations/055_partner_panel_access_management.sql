-- Restricted organization-panel access management.

create or replace function public.admin_partner_member_list(p_partner_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,auth
as $function$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if not exists(select 1 from public.partner_organizations where id=p_partner_id) then
    raise exception 'Organización no encontrada';
  end if;

  return (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'partner_id',pm.partner_id,
          'user_id',pm.user_id,
          'full_name',u.full_name,
          'email',au.email,
          'phone',u.phone,
          'role',pm.role,
          'active',pm.active,
          'created_at',pm.created_at
        )
        order by pm.active desc,pm.role,coalesce(u.full_name,au.email::text)
      ),
      '[]'::jsonb
    )
    from public.partner_members pm
    join auth.users au on au.id=pm.user_id
    left join public.users u on u.id=pm.user_id
    where pm.partner_id=p_partner_id
  );
end;
$function$;

create or replace function public.admin_assign_partner_member_by_email(
  p_partner_id uuid,
  p_email text,
  p_role text,
  p_active boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path=public,auth
as $function$
declare
  v_user_id uuid;
  v_email text:=lower(trim(coalesce(p_email,'')));
  v_role text:=lower(trim(coalesce(p_role,'')));
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if not exists(select 1 from public.partner_organizations where id=p_partner_id) then
    raise exception 'Organización no encontrada';
  end if;
  if v_email='' then raise exception 'Correo requerido'; end if;
  if v_role not in ('owner','manager','operator','treasurer') then
    raise exception 'Rol inválido';
  end if;

  select id into v_user_id
  from auth.users
  where lower(email)=v_email
  limit 1;

  if v_user_id is null then
    raise exception 'No existe una cuenta Express con ese correo. Primero debe registrarse en Express.';
  end if;

  insert into public.partner_members(partner_id,user_id,role,active)
  values(p_partner_id,v_user_id,v_role,coalesce(p_active,true))
  on conflict(partner_id,user_id) do update
    set role=excluded.role,
        active=excluded.active;

  perform public.admin_log_action(
    'assign_partner_member',
    'partner_member',
    p_partner_id::text||':'||v_user_id::text,
    jsonb_build_object(
      'partner_id',p_partner_id,
      'user_id',v_user_id,
      'email',v_email,
      'role',v_role,
      'active',coalesce(p_active,true)
    )
  );

  return jsonb_build_object(
    'partner_id',p_partner_id,
    'user_id',v_user_id,
    'email',v_email,
    'role',v_role,
    'active',coalesce(p_active,true)
  );
end;
$function$;

create or replace function public.admin_set_partner_member_active(
  p_partner_id uuid,
  p_user_id uuid,
  p_active boolean
)
returns void
language plpgsql
security definer
set search_path=public
as $function$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  update public.partner_members
  set active=coalesce(p_active,false)
  where partner_id=p_partner_id and user_id=p_user_id;

  if not found then raise exception 'Acceso no encontrado'; end if;

  perform public.admin_log_action(
    'set_partner_member_access',
    'partner_member',
    p_partner_id::text||':'||p_user_id::text,
    jsonb_build_object(
      'partner_id',p_partner_id,
      'user_id',p_user_id,
      'active',coalesce(p_active,false)
    )
  );
end;
$function$;

revoke execute on function public.admin_partner_member_list(uuid) from public,anon;
revoke execute on function public.admin_assign_partner_member_by_email(uuid,text,text,boolean) from public,anon;
revoke execute on function public.admin_set_partner_member_active(uuid,uuid,boolean) from public,anon;

grant execute on function public.admin_partner_member_list(uuid) to authenticated;
grant execute on function public.admin_assign_partner_member_by_email(uuid,text,text,boolean) to authenticated;
grant execute on function public.admin_set_partner_member_active(uuid,uuid,boolean) to authenticated;
