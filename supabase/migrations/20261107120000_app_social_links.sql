-- Enlaces de redes sociales (TikTok, Facebook, Instagram) del menú de la app.
--
-- Pasajero y conductor muestran tres botones en la cabecera de su menú. Cada
-- enlace se edita desde Adminexpress (Configuración > Redes sociales). Si un
-- enlace está vacío, la app no muestra ese botón.
--
-- Solo archivo: esta migración NO se aplica en producción hasta que el
-- propietario lo autorice.
--
-- Seguridad:
--   * Lectura pública (anon y authenticated): son enlaces públicos de la marca.
--   * Escritura solo por RPC de super admin activo con módulo 'dashboard'.
--   * Los clientes no tienen INSERT/UPDATE/DELETE sobre la tabla.

create table if not exists public.app_social_links (
  id bigint generated always as identity primary key,
  audience text not null check (audience in ('passenger', 'driver')),
  network text not null check (network in ('tiktok', 'facebook', 'instagram')),
  url text not null default '' check (
    url = '' or (url ~ '^https://' and char_length(url) <= 300)
  ),
  updated_at timestamptz not null default now(),
  updated_by uuid,
  constraint app_social_links_audience_network_key unique (audience, network)
);

alter table public.app_social_links enable row level security;

revoke all on table public.app_social_links from public, anon, authenticated;
grant select on table public.app_social_links to anon, authenticated;

drop policy if exists app_social_links_public_select on public.app_social_links;
create policy app_social_links_public_select
  on public.app_social_links
  for select
  to anon, authenticated
  using (true);

insert into public.app_social_links (audience, network, url)
values
  ('passenger', 'tiktok', ''),
  ('passenger', 'facebook', ''),
  ('passenger', 'instagram', ''),
  ('driver', 'tiktok', ''),
  ('driver', 'facebook', ''),
  ('driver', 'instagram', '')
on conflict (audience, network) do nothing;

-- Lectura pública para la app: devuelve solo los enlaces no vacíos.
create or replace function public.app_social_links_public_v1()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'passenger', coalesce((
      select jsonb_object_agg(l.network, l.url)
      from public.app_social_links l
      where l.audience = 'passenger' and l.url <> ''
    ), '{}'::jsonb),
    'driver', coalesce((
      select jsonb_object_agg(l.network, l.url)
      from public.app_social_links l
      where l.audience = 'driver' and l.url <> ''
    ), '{}'::jsonb)
  );
$$;

revoke all on function public.app_social_links_public_v1() from public;
grant execute on function public.app_social_links_public_v1() to anon, authenticated;

-- Lista para Adminexpress: las seis filas, también las vacías.
create or replace function public.admin_app_social_links_list_v1()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'audience', l.audience,
        'network', l.network,
        'url', l.url,
        'updated_at', l.updated_at
      )
      order by l.audience, l.network
    )
    from public.app_social_links l
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_app_social_links_list_v1() from public, anon;
grant execute on function public.admin_app_social_links_list_v1() to authenticated;

-- Guardado desde Adminexpress: upsert de una fila, con registro de auditoría.
create or replace function public.admin_app_social_links_save_v1(
  p_audience text,
  p_network text,
  p_url text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text;
  v_row public.app_social_links%rowtype;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  perform public.admin_operator_assert_module('dashboard');

  if p_audience is null or p_audience not in ('passenger', 'driver') then
    raise exception 'Audiencia no válida';
  end if;

  if p_network is null or p_network not in ('tiktok', 'facebook', 'instagram') then
    raise exception 'Red social no válida';
  end if;

  v_url := btrim(coalesce(p_url, ''));

  if v_url <> '' and v_url !~ '^https://' then
    raise exception 'El enlace debe empezar con https://';
  end if;

  if char_length(v_url) > 300 then
    raise exception 'El enlace no puede superar 300 caracteres';
  end if;

  insert into public.app_social_links (audience, network, url, updated_at, updated_by)
  values (p_audience, p_network, v_url, now(), auth.uid())
  on conflict (audience, network) do update
    set url = excluded.url,
        updated_at = excluded.updated_at,
        updated_by = excluded.updated_by
  returning * into v_row;

  perform public.admin_log_action(
    'save_social_link',
    'app_social_links',
    p_audience || ':' || p_network,
    jsonb_build_object('url', v_url)
  );

  return jsonb_build_object(
    'id', v_row.id,
    'audience', v_row.audience,
    'network', v_row.network,
    'url', v_row.url,
    'updated_at', v_row.updated_at
  );
end;
$$;

revoke all on function public.admin_app_social_links_save_v1(text, text, text) from public, anon;
grant execute on function public.admin_app_social_links_save_v1(text, text, text) to authenticated;
