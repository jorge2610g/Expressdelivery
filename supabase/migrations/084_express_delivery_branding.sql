-- Rename the customer marketplace experience to Express Delivery.
-- Visibility flags remain unchanged; Production stays disabled until approval.
update public.marketplace_settings
set module_name='Express Delivery',
    hero_title='Pide lo que quieras con Express Delivery',
    hero_subtitle='Restaurantes, supermercados, farmacia y más.',
    search_placeholder='Busca restaurantes, tiendas o productos',
    updated_at=now()
where id=true;
