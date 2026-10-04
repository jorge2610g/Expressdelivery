-- Unified Express account model: one identity, optional driver capability.
-- Separate passenger/driver reputation and synchronize active_mode through Realtime.

alter table public.ratings
  add column if not exists rated_role text;

update public.ratings r
set rated_role = case
  when r.trip_id is not null then (
    select case
      when t.driver_id = r.to_user_id then 'driver'
      when t.passenger_id = r.to_user_id then 'passenger'
      else null
    end
    from public.trips t
    where t.id = r.trip_id
  )
  when r.delivery_id is not null then (
    select case
      when d.courier_id = r.to_user_id then 'driver'
      when d.customer_id = r.to_user_id then 'passenger'
      else null
    end
    from public.delivery_requests d
    where d.id = r.delivery_id
  )
  else null
end
where r.rated_role is null;

do $$
begin
  if exists(select 1 from public.ratings where rated_role is null) then
    raise exception 'No se pudo clasificar el rol de todas las calificaciones existentes';
  end if;
end
$$;

alter table public.ratings
  alter column rated_role set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='ratings_rated_role_check'
      and conrelid='public.ratings'::regclass
  ) then
    alter table public.ratings
      add constraint ratings_rated_role_check
      check (rated_role in ('passenger','driver'));
  end if;
end
$$;

create index if not exists ratings_to_user_role_created_idx
  on public.ratings(to_user_id,rated_role,created_at desc);

create or replace function public.derive_rating_role()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_role text;
begin
  if new.trip_id is not null then
    select case
      when t.driver_id = new.to_user_id then 'driver'
      when t.passenger_id = new.to_user_id then 'passenger'
      else null
    end
    into v_role
    from public.trips t
    where t.id = new.trip_id;
  elsif new.delivery_id is not null then
    select case
      when d.courier_id = new.to_user_id then 'driver'
      when d.customer_id = new.to_user_id then 'passenger'
      else null
    end
    into v_role
    from public.delivery_requests d
    where d.id = new.delivery_id;
  end if;

  if v_role is null then
    raise exception 'No se pudo determinar el rol de la persona calificada';
  end if;

  new.rated_role := v_role;
  return new;
end;
$$;

drop trigger if exists ratings_derive_role on public.ratings;
create trigger ratings_derive_role
before insert or update of trip_id,delivery_id,to_user_id,rated_role
on public.ratings
for each row execute function public.derive_rating_role();

revoke all on function public.derive_rating_role() from public,anon,authenticated;

create or replace function public.my_rating_summary_for(p_role text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := lower(trim(coalesce(p_role,'')));
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if v_role not in ('passenger','driver') then
    raise exception 'Rol de calificación no válido';
  end if;

  return (
    select jsonb_build_object(
      'role', v_role,
      'count', count(*),
      'average', coalesce(round(avg(score)::numeric, 2), 0),
      'five', count(*) filter (where score = 5),
      'four', count(*) filter (where score = 4),
      'three', count(*) filter (where score = 3),
      'two', count(*) filter (where score = 2),
      'one', count(*) filter (where score = 1)
    )
    from public.ratings
    where to_user_id = v_uid
      and rated_role = v_role
  );
end;
$$;

revoke all on function public.my_rating_summary_for(text) from public,anon;
grant execute on function public.my_rating_summary_for(text) to authenticated;

create or replace function public.my_rating_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := 'passenger';
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select case
    when u.active_mode='driver' then 'driver'
    else 'passenger'
  end
  into v_role
  from public.users u
  where u.id=v_uid;

  return public.my_rating_summary_for(coalesce(v_role,'passenger'));
end;
$$;

revoke all on function public.my_rating_summary() from public,anon;
grant execute on function public.my_rating_summary() to authenticated;

create or replace function public.refresh_driver_rating()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.rated_role <> 'driver' then
    return new;
  end if;

  update public.driver_profiles dp
  set rating = coalesce(
        (
          select round(avg(r.score)::numeric, 2)
          from public.ratings r
          where r.to_user_id = new.to_user_id
            and r.rated_role = 'driver'
        ),
        dp.rating
      ),
      updated_at = now()
  where dp.id = new.to_user_id;

  -- Las calificaciones son privadas. No se crea push ni aviso identificable.
  return new;
end;
$$;

update public.driver_profiles dp
set rating = x.average_rating,
    updated_at = now()
from (
  select r.to_user_id,round(avg(r.score)::numeric,2) as average_rating
  from public.ratings r
  where r.rated_role='driver'
  group by r.to_user_id
) x
where dp.id=x.to_user_id;

create or replace function public.driver_priority_summary_for_v2(
  p_driver_id uuid,
  p_channel text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_s jsonb := public.driver_priority_settings_for(p_channel);
  v_rating numeric := 0;
  v_review_count integer := 0;
  v_completed integer := 0;
  v_recent integer := 0;
  v_rating_score numeric := 0;
  v_reviews_score numeric := 0;
  v_experience_score numeric := 0;
  v_frequency_score numeric := 0;
  v_total numeric := 0;
  v_level text := 'low';
  v_review_target integer := greatest(1,coalesce((v_s->>'review_target')::integer,20));
  v_experience_target integer := greatest(1,coalesce((v_s->>'experience_trip_target')::integer,100));
  v_frequency_target integer := greatest(1,coalesce((v_s->>'frequency_30d_target')::integer,30));
  v_rating_weight numeric := greatest(0,coalesce((v_s->>'rating_weight')::numeric,35));
  v_reviews_weight numeric := greatest(0,coalesce((v_s->>'reviews_weight')::numeric,25));
  v_experience_weight numeric := greatest(0,coalesce((v_s->>'experience_weight')::numeric,20));
  v_frequency_weight numeric := greatest(0,coalesce((v_s->>'frequency_weight')::numeric,20));
  v_high numeric := coalesce((v_s->>'high_min_score')::numeric,80);
  v_medium numeric := coalesce((v_s->>'medium_min_score')::numeric,55);
begin
  select coalesce(round(avg(r.score)::numeric,2),0),count(*)::integer
  into v_rating,v_review_count
  from public.ratings r
  where r.to_user_id=p_driver_id
    and r.rated_role='driver';

  select count(*)::integer
  into v_completed
  from public.trips t
  where t.driver_id=p_driver_id
    and t.status='completed'
    and t.channel=lower(coalesce(nullif(trim(p_channel),''),'production'));

  select count(*)::integer
  into v_recent
  from public.trips t
  where t.driver_id=p_driver_id
    and t.status='completed'
    and t.channel=lower(coalesce(nullif(trim(p_channel),''),'production'))
    and coalesce(t.completed_at,t.created_at)>=now()-interval '30 days';

  v_rating_score := case
    when v_rating<=0 then 50
    else least(100,greatest(0,((v_rating-1)/4)*100))
  end;

  v_reviews_score := least(
    100,
    greatest(
      0,
      v_rating_score*least(1,v_review_count::numeric/v_review_target)
      + 50*(1-least(1,v_review_count::numeric/v_review_target))
    )
  );

  v_experience_score := least(
    100,greatest(0,v_completed::numeric/v_experience_target*100)
  );
  v_frequency_score := least(
    100,greatest(0,v_recent::numeric/v_frequency_target*100)
  );

  v_total := round(
    (
      v_rating_score*v_rating_weight +
      v_reviews_score*v_reviews_weight +
      v_experience_score*v_experience_weight +
      v_frequency_score*v_frequency_weight
    ) / greatest(
      v_rating_weight+v_reviews_weight+v_experience_weight+v_frequency_weight,
      1
    ),
    2
  );

  v_level := case
    when v_total>=v_high then 'high'
    when v_total>=v_medium then 'medium'
    else 'low'
  end;

  return jsonb_build_object(
    'driver_id',p_driver_id,
    'channel',lower(coalesce(nullif(trim(p_channel),''),'production')),
    'level',v_level,
    'score',v_total,
    'average_rating',v_rating,
    'review_count',v_review_count,
    'completed_trips',v_completed,
    'recent_trips_30d',v_recent,
    'metrics',jsonb_build_object(
      'rating',round(v_rating_score,2),
      'reviews',round(v_reviews_score,2),
      'experience',round(v_experience_score,2),
      'frequency',round(v_frequency_score,2)
    )
  );
end;
$$;

create or replace function public.available_ride_requests_for_driver_v2(
  p_channel text default 'production'
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid:=auth.uid();
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_s jsonb;
  v_enforcement boolean:=false;
  v_priority jsonb;
  v_level text:='medium';
  v_base jsonb;
  v_lat numeric;
  v_lng numeric;
  v_result jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  v_s:=public.driver_priority_settings_for(v_channel);
  v_enforcement:=case when v_channel='preview'
    then coalesce((v_s->>'preview_enforcement_enabled')::boolean,false)
    else coalesce((v_s->>'production_enforcement_enabled')::boolean,false)
  end;

  select coalesce(jsonb_agg(e),'[]'::jsonb)
  into v_base
  from jsonb_array_elements(
    coalesce(public.available_ride_requests_for_driver(),'[]'::jsonb)
  ) e
  where public.normalize_runtime_channel(e->>'channel')=v_channel;

  if coalesce(v_enforcement,false) is false then
    return v_base;
  end if;

  v_priority:=public.driver_priority_summary_for_v2(v_uid,v_channel);
  v_level:=coalesce(v_priority->>'level','medium');

  select latitude,longitude into v_lat,v_lng
  from public.driver_profiles where id=v_uid;

  select coalesce(
    jsonb_agg(x.payload order by x.rank_a,x.rank_b,x.rank_c,x.created_at),
    '[]'::jsonb
  )
  into v_result
  from (
    select
      e as payload,
      coalesce((e->>'created_at')::timestamptz,now()) as created_at,
      case
        when v_level in ('high','medium') then coalesce(
          public.geo_distance_km(
            v_lat,v_lng,
            nullif(e->>'pickup_latitude','')::numeric,
            nullif(e->>'pickup_longitude','')::numeric
          ),99999)
        else -coalesce(
          public.geo_distance_km(
            v_lat,v_lng,
            nullif(e->>'pickup_latitude','')::numeric,
            nullif(e->>'pickup_longitude','')::numeric
          ),0)
      end as rank_a,
      case
        when v_level='low' then coalesce(pr.passenger_rating,0)
        else -coalesce(pr.passenger_rating,5)
      end as rank_b,
      case
        when v_level='low' then coalesce(
          nullif(e->>'proposed_fare','')::numeric/
          nullif(nullif(e->>'route_distance_km','')::numeric,0),0
        )
        else -coalesce(
          nullif(e->>'proposed_fare','')::numeric/
          nullif(nullif(e->>'route_distance_km','')::numeric,0),0
        )
      end as rank_c
    from jsonb_array_elements(coalesce(v_base,'[]'::jsonb)) e
    left join lateral (
      select round(avg(r.score)::numeric,2) as passenger_rating
      from public.ratings r
      where r.to_user_id=nullif(e->>'passenger_id','')::uuid
        and r.rated_role='passenger'
    ) pr on true
  ) x;

  return coalesce(v_result,'[]'::jsonb);
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname='supabase_realtime'
      and schemaname='public'
      and tablename='users'
  ) then
    alter publication supabase_realtime add table public.users;
  end if;
end
$$;


create or replace function public.admin_driver_detail(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public','auth'
as $$
declare
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  select jsonb_build_object(
    'user',jsonb_build_object(
      'id',u.id,
      'full_name',u.full_name,
      'email',au.email,
      'phone',u.phone,
      'avatar_url',u.avatar_url,
      'preferred_language',u.preferred_language,
      'active_mode',u.active_mode,
      'account_status',u.account_status,
      'last_zone_id',u.last_zone_id,
      'created_at',u.created_at,
      'updated_at',u.updated_at
    ),
    'driver',to_jsonb(d),
    'zone',case when z.id is null then null else to_jsonb(z) end,
    'vehicles',coalesce((
      select jsonb_agg(to_jsonb(v) order by v.is_active desc,v.updated_at desc)
      from public.driver_vehicles v
      where v.driver_id=d.id
    ),'[]'::jsonb),
    'documents',coalesce((
      select jsonb_agg(to_jsonb(doc) order by doc.created_at desc)
      from public.driver_documents doc
      where doc.driver_id=d.id
    ),'[]'::jsonb),
    'identity_verifications',coalesce((
      select jsonb_agg(to_jsonb(iv) order by iv.created_at desc)
      from public.identity_verifications iv
      where iv.user_id=d.id
    ),'[]'::jsonb),
    'rating_summary',jsonb_build_object(
      'role','driver',
      'count',(select count(*) from public.ratings r where r.to_user_id=d.id and r.rated_role='driver'),
      'average',coalesce((select round(avg(r.score)::numeric,2) from public.ratings r where r.to_user_id=d.id and r.rated_role='driver'),0)
    ),
    'subscription',(
      select case when s.driver_id is null then null else jsonb_build_object(
        'status',s.status,
        'plan_id',s.plan_id,
        'plan_name',p.name,
        'plan_code',p.code,
        'zone_key',p.zone_key,
        'started_at',s.started_at,
        'expires_at',s.expires_at,
        'updated_at',s.updated_at
      ) end
      from public.driver_subscriptions s
      left join public.driver_subscription_plans p on p.id=s.plan_id
      where s.driver_id=d.id
    ),
    'qa',(
      select jsonb_build_object(
        'group_id',m.group_id,
        'group_name',g.name,
        'role',m.role,
        'enabled',m.enabled,
        'group_active',g.active
      )
      from public.audit_test_group_members m
      join public.audit_test_groups g on g.id=m.group_id
      where m.user_id=d.id
      limit 1
    ),
    'partner',(
      select jsonb_build_object(
        'partner_id',pm.partner_id,
        'name',po.name,
        'type',po.organization_type,
        'status',pm.status
      )
      from public.driver_partner_memberships pm
      join public.partner_organizations po on po.id=pm.partner_id
      where pm.driver_id=d.id and pm.status='active'
      order by pm.started_at desc
      limit 1
    ),
    'recent_trips',coalesce((
      select jsonb_agg(q.x order by q.created_at desc)
      from (
        select jsonb_build_object(
          'id',t.id,
          'status',t.status,
          'final_fare',t.final_fare,
          'payment_status',t.payment_status,
          'created_at',t.created_at,
          'completed_at',t.completed_at,
          'pickup_address',rr.pickup_address,
          'destination_address',rr.destination_address
        ) as x,
        t.created_at
        from public.trips t
        left join public.ride_requests rr on rr.id=t.ride_request_id
        where t.driver_id=d.id
        order by t.created_at desc
        limit 20
      ) q
    ),'[]'::jsonb)
  )
  into v_result
  from public.driver_profiles d
  join public.users u on u.id=d.id
  left join auth.users au on au.id=d.id
  left join public.service_zones z on z.id=d.zone_id
  where d.id=p_user_id;

  if v_result is null then
    raise exception 'Conductor no encontrado';
  end if;
  return v_result;
end;
$$;

create or replace function public.admin_user_detail(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public','auth'
as $$
declare
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  select jsonb_build_object(
    'user',jsonb_build_object(
      'id',u.id,
      'full_name',u.full_name,
      'email',au.email,
      'phone',u.phone,
      'avatar_url',u.avatar_url,
      'preferred_language',u.preferred_language,
      'active_mode',u.active_mode,
      'account_status',u.account_status,
      'last_zone_id',u.last_zone_id,
      'created_at',u.created_at,
      'updated_at',u.updated_at
    ),
    'zone',case when z.id is null then null else to_jsonb(z) end,
    'driver',case when d.id is null then null else to_jsonb(d) end,
    'wallet',(
      select case when w.user_id is null then null else to_jsonb(w) end
      from public.wallet_accounts w where w.user_id=u.id
    ),
    'rating_summary',jsonb_build_object(
      'role','passenger',
      'count',(select count(*) from public.ratings r where r.to_user_id=u.id and r.rated_role='passenger'),
      'average',coalesce((select round(avg(r.score)::numeric,2) from public.ratings r where r.to_user_id=u.id and r.rated_role='passenger'),0)
    ),
    'qa',(
      select jsonb_build_object(
        'group_id',m.group_id,
        'group_name',g.name,
        'role',m.role,
        'enabled',m.enabled,
        'group_active',g.active
      )
      from public.audit_test_group_members m
      join public.audit_test_groups g on g.id=m.group_id
      where m.user_id=u.id
      limit 1
    ),
    'recent_trips',coalesce((
      select jsonb_agg(q.trip_json order by q.created_at desc)
      from (
        select
          jsonb_build_object(
            'id',t.id,
            'role',case when t.passenger_id=u.id then 'passenger' else 'driver' end,
            'status',t.status,
            'final_fare',t.final_fare,
            'payment_status',t.payment_status,
            'created_at',t.created_at,
            'completed_at',t.completed_at,
            'pickup_address',rr.pickup_address,
            'destination_address',rr.destination_address
          ) as trip_json,
          t.created_at
        from public.trips t
        left join public.ride_requests rr on rr.id=t.ride_request_id
        where t.passenger_id=u.id or t.driver_id=u.id
        order by t.created_at desc
        limit 20
      ) q
    ),'[]'::jsonb)
  )
  into v_result
  from public.users u
  left join auth.users au on au.id=u.id
  left join public.driver_profiles d on d.id=u.id
  left join public.service_zones z on z.id=coalesce(u.last_zone_id,d.zone_id)
  where u.id=p_user_id;

  if v_result is null then
    raise exception 'Usuario no encontrado';
  end if;

  return v_result;
end;
$$;
