-- Bolivia uses Didit for identity verification.
-- Manual identity card and driver license rows are disabled at country scope.
-- Extra documents such as driver license can be re-enabled with zone-specific
-- requirements from AdminExpress without duplicating the base identity flow.

update public.driver_document_requirements
set active=false,
    updated_at=now()
where upper(coalesce(country_code,''))='BO'
  and zone_id is null
  and code in ('identity_card','driver_license');
