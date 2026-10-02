revoke execute on function public.dynamic_pricing_quote(
  text,numeric,numeric,numeric,numeric,boolean
) from public, anon;

grant execute on function public.dynamic_pricing_quote(
  text,numeric,numeric,numeric,numeric,boolean
) to authenticated;
