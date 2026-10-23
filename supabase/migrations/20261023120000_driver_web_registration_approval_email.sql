-- Web driver registration approval email delivery.
-- Configure Vault secret driver_approval_service_role_key before applying this migration.
-- Never commit service role credentials or email provider keys.

create table if not exists public.driver_approval_email_outbox (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references auth.users(id) on delete cascade,
  recipient_email text not null,
  recipient_name text not null default 'Conductor',
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  attempts integer not null default 0,
  last_error text,
  constraint driver_approval_email_outbox_attempts_nonnegative check (attempts >= 0)
);

alter table public.driver_approval_email_outbox enable row level security;
revoke all on table public.driver_approval_email_outbox from public, anon, authenticated;
grant all on table public.driver_approval_email_outbox to service_role;

create or replace function public.enqueue_driver_approval_email()
returns trigger
language plpgsql
security definer
set search_path = public, auth, vault, net
set row_security = off
as $$
declare
  v_email text;
  v_name text;
  v_secret text;
  v_event_id uuid;
begin
  if new.approval_status is distinct from 'approved'
     or old.approval_status is not distinct from 'approved' then
    return new;
  end if;

  select au.email, coalesce(nullif(trim(u.full_name), ''),
                            nullif(trim(au.raw_user_meta_data ->> 'full_name'), ''),
                            'Conductor')
    into v_email, v_name
  from auth.users au
  left join public.users u on u.id = au.id
  where au.id = new.id;

  if v_email is null or trim(v_email) = '' then
    raise exception 'No se puede notificar la aprobación: falta el correo de la cuenta';
  end if;

  insert into public.driver_approval_email_outbox (
    driver_id, recipient_email, recipient_name
  ) values (
    new.id, v_email, coalesce(v_name, 'Conductor')
  )
  returning id into v_event_id;

  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'driver_approval_service_role_key'
  limit 1;

  if v_secret is null or trim(v_secret) = '' then
    raise exception 'Configura el secreto driver_approval_service_role_key en Vault antes de aprobar conductores';
  end if;

  perform net.http_post(
    url := 'https://zgpijrznvaskgcmauwxx.supabase.co/functions/v1/driver-approval-email',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_secret
    ),
    body := jsonb_build_object('outbox_id', v_event_id),
    timeout_milliseconds := 8000
  );

  return new;
end;
$$;

revoke all on function public.enqueue_driver_approval_email() from public, anon, authenticated;

drop trigger if exists trg_driver_approval_email on public.driver_profiles;
create trigger trg_driver_approval_email
after update of approval_status on public.driver_profiles
for each row
when (new.approval_status = 'approved' and old.approval_status is distinct from 'approved')
execute function public.enqueue_driver_approval_email();

comment on table public.driver_approval_email_outbox is
  'Private transactional outbox for driver approval emails; service role only.';
