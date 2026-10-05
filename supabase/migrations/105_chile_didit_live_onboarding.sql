-- Chile uses Didit Production for identity verification.
-- The national ID is verified by Didit; the driver license remains a separate
-- required onboarding document for Chile.

update public.driver_document_requirements
set active=false,
    updated_at=now()
where upper(coalesce(country_code,''))='CL'
  and zone_id is null
  and code='identity_card';
