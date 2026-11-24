-- El administrador puede cambiar la portada de un restaurante (la imagen se sube desde la galería).
create or replace function public.admin_marketplace_set_merchant_media(
  p_merchant_id uuid, p_cover_image_url text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth.uid() is null or not public.is_admin() then raise exception 'No autorizado'; end if;
  if length(coalesce(p_cover_image_url, '')) > 600 then raise exception 'Dirección de imagen demasiado larga'; end if;
  update public.marketplace_merchants
     set cover_image_url = nullif(trim(coalesce(p_cover_image_url, '')), ''), updated_at = now()
   where id = p_merchant_id;
  if not found then raise exception 'Comercio no encontrado'; end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.admin_marketplace_set_merchant_media(uuid, text) from public, anon;
grant execute on function public.admin_marketplace_set_merchant_media(uuid, text) to authenticated;
