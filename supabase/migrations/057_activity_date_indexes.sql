-- Speed up bounded activity/history queries for both customer and courier views.
create index if not exists delivery_requests_customer_created_idx
  on public.delivery_requests (customer_id, created_at desc);

create index if not exists delivery_requests_courier_created_idx
  on public.delivery_requests (courier_id, created_at desc);
