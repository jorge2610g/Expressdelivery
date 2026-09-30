-- Forward every persisted Express notification to Web Push.
-- Applied to production Supabase project zgpijrznvaskgcmauwxx on 2026-09-30.

create or replace function public.dispatch_push_notification()
returns trigger
language plpgsql
security definer
set search_path = public, net
as $$
declare
  v_secret text;
begin
  select webhook_secret
    into v_secret
  from public.push_server_config
  where id = true;

  if v_secret is null then
    return new;
  end if;

  perform net.http_post(
    url := 'https://zgpijrznvaskgcmauwxx.supabase.co/functions/v1/express-push-dispatch',
    body := jsonb_build_object(
      'notification_id', new.id,
      'user_id', new.user_id,
      'title', new.title,
      'body', new.body,
      'type', new.type
    ),
    params := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-express-push-secret', v_secret
    ),
    timeout_milliseconds := 5000
  );

  return new;
end;
$$;

revoke execute on function public.dispatch_push_notification()
  from public, anon, authenticated;

drop trigger if exists trg_dispatch_push_notification
  on public.notifications;

create trigger trg_dispatch_push_notification
after insert on public.notifications
for each row
execute function public.dispatch_push_notification();
