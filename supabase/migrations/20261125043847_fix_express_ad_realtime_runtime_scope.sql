-- Realtime evaluates this policy as the subscriber role. The previous
-- predicate called admin_user_runtime_environment(uuid), which intentionally
-- has no EXECUTE grant for authenticated users. Realtime therefore rejected
-- CDC reads and the app fell back to its periodic ad refresh.
begin;

drop policy if exists express_ad_revisions_own_environment
  on public.express_ad_revisions;

create policy express_ad_revisions_own_environment
on public.express_ad_revisions for select to authenticated
using (
  coalesce(
    (select (public.resolve_current_runtime_environment()->>'allowed')::boolean),
    false
  )
  and channel = (
    select public.resolve_current_runtime_environment()->>'environment'
  )
);

comment on policy express_ad_revisions_own_environment
  on public.express_ad_revisions is
  'Allows Realtime subscribers to read only revision rows for their server-resolved runtime environment.';

commit;
