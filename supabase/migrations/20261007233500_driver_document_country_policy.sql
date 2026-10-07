-- Driver document policy by country + isolated Preview shadow seed.
-- Production policy requested:
--   Chile: Cédula + Licencia active.
--   Bolivia: Carné active, Licencia inactive.

update public.driver_document_requirements
set active = case
      when upper(country_code)='CL' and code in ('identity_card','driver_license') then true
      when upper(country_code)='BO' and code='identity_card' then true
      when upper(country_code)='BO' and code='driver_license' then false
      else active
    end,
    required = case
      when upper(country_code) in ('CL','BO')
       and code in ('identity_card','driver_license') then true
      else required
    end,
    updated_at = now()
where upper(country_code) in ('CL','BO')
  and code in ('identity_card','driver_license');

-- Preview gets an independent copy. Future edits in Prueba do not mutate
-- Production rows above.
insert into public.admin_environment_config(
  environment,module,record_key,payload,updated_at,updated_by
)
values
  (
    'preview','driver_document_requirements','BO:identity_card',
    jsonb_build_object(
      'code','identity_card','label','Carné de identidad',
      'description','Documento de identidad vigente.','country_code','BO',
      'zone_id',null,'required',true,'require_number',true,
      'require_front',true,'require_back',true,'require_selfie',true,
      'active',true,'sort_order',10
    ),
    now(),null
  ),
  (
    'preview','driver_document_requirements','BO:driver_license',
    jsonb_build_object(
      'code','driver_license','label','Licencia de conducir',
      'description','Licencia de conducir vigente.','country_code','BO',
      'zone_id',null,'required',true,'require_number',true,
      'require_front',true,'require_back',true,'require_selfie',false,
      'active',false,'sort_order',20
    ),
    now(),null
  ),
  (
    'preview','driver_document_requirements','CL:identity_card',
    jsonb_build_object(
      'code','identity_card','label','Cédula de identidad',
      'description','Documento de identidad vigente.','country_code','CL',
      'zone_id',null,'required',true,'require_number',true,
      'require_front',true,'require_back',true,'require_selfie',true,
      'active',true,'sort_order',10
    ),
    now(),null
  ),
  (
    'preview','driver_document_requirements','CL:driver_license',
    jsonb_build_object(
      'code','driver_license','label','Licencia de conducir',
      'description','Licencia de conducir vigente.','country_code','CL',
      'zone_id',null,'required',true,'require_number',true,
      'require_front',true,'require_back',true,'require_selfie',false,
      'active',true,'sort_order',20
    ),
    now(),null
  )
on conflict(environment,module,record_key)
do update set
  payload=excluded.payload,
  updated_at=now(),
  updated_by=null;
