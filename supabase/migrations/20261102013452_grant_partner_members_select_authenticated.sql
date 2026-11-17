-- Permite que usuarios conectados evalúen las reglas de storage de logos de socios
-- sin error de permisos. partner_members tiene RLS activado y sin políticas para
-- usuarios, así que el usuario no ve ninguna fila. No expone datos.
grant select on public.partner_members to authenticated;
