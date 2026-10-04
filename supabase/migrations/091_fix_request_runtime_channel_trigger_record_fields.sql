-- Fix the shared ride/delivery runtime-channel guard.
-- A trigger RECORD only exposes the columns of its current table, so directly
-- referencing NEW.customer_id while running on ride_requests raises 42703.
-- Read the table-specific identity through to_jsonb(NEW) instead and enforce
-- isolation in both directions.

create or replace function public.guard_request_runtime_channel()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user uuid;
  v_is_preview_user boolean := false;
begin
  new.channel := public.normalize_runtime_channel(new.channel);

  case tg_table_name
    when 'ride_requests' then
      v_user := nullif(to_jsonb(new)->>'passenger_id','')::uuid;
    when 'delivery_requests' then
      v_user := nullif(to_jsonb(new)->>'customer_id','')::uuid;
    else
      raise exception 'Tabla no soportada por guard_request_runtime_channel: %', tg_table_name;
  end case;

  v_is_preview_user := coalesce(public.is_active_audit_user(v_user), false);

  if new.channel = 'preview' and not v_is_preview_user then
    raise exception 'Preview requiere una cuenta QA/sandbox activa';
  end if;

  if new.channel = 'production' and v_is_preview_user then
    raise exception 'Una cuenta QA/Preview no puede crear datos de Producción';
  end if;

  return new;
end;
$function$;

revoke all on function public.guard_request_runtime_channel()
  from public, anon;
