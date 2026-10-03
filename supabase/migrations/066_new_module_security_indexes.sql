-- Harden release-gate internals and add covering indexes for the
-- new Marketplace / release-gate foreign keys.

revoke all on function public.sync_app_release_gate_from_build()
from public, anon, authenticated;

create index if not exists app_release_gate_preview_build_idx
  on public.app_release_gate(preview_build_id);
create index if not exists app_release_gate_approved_preview_build_idx
  on public.app_release_gate(approved_preview_build_id);
create index if not exists app_release_gate_approved_by_idx
  on public.app_release_gate(approved_by);
create index if not exists app_release_gate_production_build_idx
  on public.app_release_gate(production_build_id);

create index if not exists marketplace_merchants_zone_idx
  on public.marketplace_merchants(zone_id);
create index if not exists marketplace_merchants_category_idx
  on public.marketplace_merchants(category_key);
create index if not exists marketplace_products_merchant_idx
  on public.marketplace_products(merchant_id);
