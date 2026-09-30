-- Secure, persistent Android signing for Express cloud builds.
-- Production passwords are encrypted with Supabase Vault.
-- The JKS file is private in Supabase Storage and is only handed to the
-- GitHub Actions workflow after validating its GitHub OIDC identity.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'android-signing',
  'android-signing',
  false,
  5242880,
  array['application/octet-stream']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

do $$
begin
  if not exists (
    select 1 from vault.decrypted_secrets
    where name = 'express_android_keystore_password'
  ) then
    perform vault.create_secret(
      encode(gen_random_bytes(32), 'hex'),
      'express_android_keystore_password',
      'Password del keystore Android de producción de Express'
    );
  end if;

  if not exists (
    select 1 from vault.decrypted_secrets
    where name = 'express_android_key_password'
  ) then
    perform vault.create_secret(
      encode(gen_random_bytes(32), 'hex'),
      'express_android_key_password',
      'Password de la clave Android de producción de Express'
    );
  end if;
end
$$;

create or replace function public.android_signing_config_for_worker()
returns jsonb
language sql
security definer
set search_path=public, vault
stable
as $$
  select jsonb_build_object(
    'alias', 'express-release',
    'keystore_path', 'express-release.jks',
    'store_password', (
      select decrypted_secret
      from vault.decrypted_secrets
      where name='express_android_keystore_password'
      limit 1
    ),
    'key_password', (
      select decrypted_secret
      from vault.decrypted_secrets
      where name='express_android_key_password'
      limit 1
    )
  );
$$;

revoke all on function public.android_signing_config_for_worker()
  from public, anon, authenticated;
grant execute on function public.android_signing_config_for_worker()
  to service_role;
