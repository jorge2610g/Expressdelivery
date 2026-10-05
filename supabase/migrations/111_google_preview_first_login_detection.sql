-- Make Google Preview first-login classification independent of wall-clock delay.
-- A newly-created OAuth identity is recognized because its first sign-in timestamp
-- is effectively the same as auth.users.created_at. Existing Production identities
-- keep a later last_sign_in_at and are never converted.

create or replace function public.ensure_current_runtime_access(
  p_channel text default 'production'
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_channel text := lower(trim(coalesce(p_channel,'')));
  v_bound text;
  v_source text;
  v_auth_created_at timestamptz;
  v_last_sign_in_at timestamptz;
  v_provider_google boolean := false;
  v_member_group_id uuid;
  v_member_enabled boolean;
  v_group_active boolean;
  v_group_id uuid;
  v_has_production_activity boolean := false;
  v_auto_enrolled boolean := false;
  v_first_google_login boolean := false;
begin
  if v_uid is null then
    raise exception 'No autorizado';
  end if;

  if v_channel not in ('preview','production') then
    raise exception 'Canal inválido';
  end if;

  select
    au.created_at,
    au.last_sign_in_at,
    (
      coalesce(au.raw_app_meta_data->>'provider','') = 'google'
      or coalesce(au.raw_app_meta_data->'providers','[]'::jsonb) ? 'google'
    )
  into v_auth_created_at, v_last_sign_in_at, v_provider_google
  from auth.users au
  where au.id = v_uid;

  if not found then
    raise exception 'Usuario de Auth no encontrado';
  end if;

  v_first_google_login :=
    v_provider_google
    and v_last_sign_in_at is not null
    and v_last_sign_in_at <= v_auth_created_at + interval '5 minutes';

  select b.environment,b.source
  into v_bound,v_source
  from public.account_runtime_bindings b
  where b.user_id=v_uid;

  select m.group_id,m.enabled,g.active
  into v_member_group_id,v_member_enabled,v_group_active
  from public.audit_test_group_members m
  join public.audit_test_groups g on g.id=m.group_id
  where m.user_id=v_uid
  limit 1;

  if v_bound is null and v_member_group_id is not null then
    insert into public.account_runtime_bindings(
      user_id,environment,source,bound_at,updated_at
    )
    values(v_uid,'preview','existing_audit_membership',now(),now())
    on conflict (user_id) do nothing;

    v_bound := 'preview';
    v_source := 'existing_audit_membership';
  end if;

  if v_bound is null and v_channel='preview' then
    if v_first_google_login then
      select
        exists(
          select 1
          from public.ride_requests r
          where r.passenger_id=v_uid
            and coalesce(r.channel,'production')='production'
        )
        or exists(
          select 1
          from public.wallet_country_accounts w
          where w.user_id=v_uid
            and coalesce(w.channel,'production')='production'
        )
        or exists(
          select 1
          from public.wallet_transactions t
          where t.user_id=v_uid
            and coalesce(t.channel,'production')='production'
        )
      into v_has_production_activity;

      if not coalesce(v_has_production_activity,false) then
        select g.id
        into v_group_id
        from public.audit_test_groups g
        where g.slug='qa-core'
          and g.active=true
        order by g.created_at
        limit 1;

        if v_group_id is null then
          return jsonb_build_object(
            'allowed',false,
            'requested_channel',v_channel,
            'bound_environment',null,
            'reason','preview_group_unavailable',
            'auto_enrolled',false
          );
        end if;

        insert into public.audit_test_group_members(
          group_id,user_id,role,enabled,created_at,updated_at
        )
        values(
          v_group_id,v_uid,'passenger',true,now(),now()
        )
        on conflict (user_id)
        do update set
          group_id=excluded.group_id,
          role=excluded.role,
          enabled=true,
          updated_at=now();

        insert into public.account_runtime_bindings(
          user_id,environment,source,bound_at,updated_at
        )
        values(
          v_uid,'preview','google_oauth_preview_first_login',now(),now()
        )
        on conflict (user_id)
        do update set
          environment=excluded.environment,
          source=excluded.source,
          updated_at=now();

        v_bound := 'preview';
        v_source := 'google_oauth_preview_first_login';
        v_member_enabled := true;
        v_group_active := true;
        v_auto_enrolled := true;
      end if;
    end if;

    if v_bound is null then
      insert into public.account_runtime_bindings(
        user_id,environment,source,bound_at,updated_at
      )
      values(v_uid,'production','existing_or_production_identity',now(),now())
      on conflict (user_id) do nothing;

      v_bound := 'production';
      v_source := 'existing_or_production_identity';
    end if;
  end if;

  if v_bound is null and v_channel='production' then
    insert into public.account_runtime_bindings(
      user_id,environment,source,bound_at,updated_at
    )
    values(v_uid,'production','production_first_login',now(),now())
    on conflict (user_id) do nothing;

    v_bound := 'production';
    v_source := 'production_first_login';
  end if;

  if v_bound='preview' then
    select m.enabled,g.active
    into v_member_enabled,v_group_active
    from public.audit_test_group_members m
    join public.audit_test_groups g on g.id=m.group_id
    where m.user_id=v_uid
    limit 1;

    if not coalesce(v_member_enabled,false)
       or not coalesce(v_group_active,false) then
      return jsonb_build_object(
        'allowed',false,
        'requested_channel',v_channel,
        'bound_environment','preview',
        'reason','preview_membership_inactive',
        'auto_enrolled',v_auto_enrolled,
        'source',v_source
      );
    end if;
  end if;

  return jsonb_build_object(
    'allowed',v_bound=v_channel,
    'requested_channel',v_channel,
    'bound_environment',v_bound,
    'reason',
      case
        when v_bound=v_channel then 'ok'
        when v_channel='preview' then 'account_bound_to_production'
        else 'account_bound_to_preview'
      end,
    'auto_enrolled',v_auto_enrolled,
    'source',v_source
  );
end;
$function$;

revoke all on function public.ensure_current_runtime_access(text)
from public,anon;
grant execute on function public.ensure_current_runtime_access(text)
to authenticated;
