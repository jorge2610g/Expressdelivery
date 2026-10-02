-- Optimización de consultas frecuentes y políticas RLS.
-- No cambia reglas de negocio ni elimina datos.

create index if not exists admin_audit_log_admin_user_id_idx
  on public.admin_audit_log(admin_user_id);

create index if not exists app_releases_build_job_id_idx
  on public.app_releases(build_job_id);

create index if not exists app_releases_published_by_idx
  on public.app_releases(published_by);

create index if not exists build_jobs_created_by_idx
  on public.build_jobs(created_by);

create index if not exists driver_request_push_locks_ride_request_id_idx
  on public.driver_request_push_locks(ride_request_id);

create index if not exists wallet_transactions_delivery_id_idx
  on public.wallet_transactions(delivery_id);

create index if not exists wallet_transactions_trip_id_idx
  on public.wallet_transactions(trip_id);

drop policy if exists push_subscriptions_read_own
  on public.push_subscriptions;
create policy push_subscriptions_read_own
  on public.push_subscriptions
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists push_subscriptions_delete_own
  on public.push_subscriptions;
create policy push_subscriptions_delete_own
  on public.push_subscriptions
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists native_push_tokens_select_own
  on public.native_push_tokens;
create policy native_push_tokens_select_own
  on public.native_push_tokens
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists native_push_tokens_delete_own
  on public.native_push_tokens;
create policy native_push_tokens_delete_own
  on public.native_push_tokens
  for delete
  to authenticated
  using (user_id = (select auth.uid()));
