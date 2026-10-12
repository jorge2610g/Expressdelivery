-- Individual driver document/evidence review.
-- Keeps approved evidence immutable when another photo/document must be corrected.
-- Shared by web/Android; environment isolation remains account/channel based.

create or replace function public.driver_kyc_bolivia_part_states()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
 v_code text; v_country text; v_profile_path text;
 v_parts jsonb:=coalesce(new.review_parts,'{}'::jsonb);
 v_prior text;
 v_slot text; v_path text; v_entry jsonb;
 v_status text; v_approved integer:=0; v_needed integer:=0;
 v_rejected integer:=0; v_version integer;
begin
 select upper(coalesce(p.country_code,'')),lower(coalesce(r.code,'')),
        nullif(trim(p.profile_photo_path),'')
 into v_country,v_code,v_profile_path
 from public.driver_profiles p
 left join public.driver_document_requirements r on r.id=new.requirement_id
 where p.id=new.driver_id;

 if new.verification_method<>'manual' or v_code not in
 ('identity_card','national_id','id_card','identity','carnet','cedula','cédula') then
   return new;
 end if;

 v_prior:=case when tg_op='UPDATE' then old.status else new.status end;

 foreach v_slot in array array['front','back','selfie','profile'] loop
   v_path:=case v_slot
      when 'front' then nullif(trim(new.front_object_path),'')
      when 'back' then nullif(trim(new.back_object_path),'')
      when 'selfie' then nullif(trim(new.selfie_object_path),'')
      else v_profile_path
   end;

   v_entry:=v_parts->v_slot;

   if v_entry is null or jsonb_typeof(v_entry)<>'object' then
     v_entry:=jsonb_build_object(
       'status',
       case
         when tg_op='UPDATE' and old.status='verified' and v_path is not null
           then 'approved'
         when tg_op='UPDATE' and old.status='rejected' and v_slot<>'profile'
           then 'rejected'
         else 'pending'
       end,
       'version',1,
       'path',v_path,
       'reason',
       case
         when v_prior='rejected' and v_slot<>'profile' then new.rejection_reason
         else null
       end
     );
   elsif coalesce(v_entry->>'path','') is distinct from coalesce(v_path,'') then
     v_version:=coalesce((v_entry->>'version')::integer,0)+1;
     v_entry:=jsonb_build_object(
       'status','pending',
       'version',v_version,
       'path',v_path,
       'reason',null
     );
   end if;

   v_parts:=jsonb_set(v_parts,array[v_slot],v_entry,true);

   -- Document identity status depends only on identity evidence.
   -- Profile photo is reviewed independently and must never invalidate
   -- already-approved carnet front/back/selfie.
   if v_slot<>'profile' and v_path is not null then
     v_needed:=v_needed+1;
     v_status:=coalesce(v_entry->>'status','pending');
     if v_status='approved' then v_approved:=v_approved+1; end if;
     if v_status='rejected' then v_rejected:=v_rejected+1; end if;
   end if;
 end loop;

 new.review_parts:=v_parts;

 if v_approved=v_needed and v_needed>=3
    and new.front_object_path is not null
    and new.back_object_path is not null
    and new.selfie_object_path is not null
    and nullif(trim(coalesce(new.document_number,'')),'') is not null then
   new.status:='verified';
 elsif v_rejected>0 then
   new.status:='rejected';
 else
   new.status:='pending';
 end if;

 new.rejection_reason:=case when new.status='rejected' then
   (
     select string_agg(
       s||': '||left(coalesce(v_parts #>> array[s,'reason'],'Corrección necesaria'),250),
       '; '
     )
     from unnest(array['front','back','selfie']) s
     where v_parts #>> array[s,'status']='rejected'
   )
   else null
 end;

 return new;
end;
$$;

-- Backfill the independent profile slot for existing manual identity records.
-- Existing verified identities keep their current approval; this migration
-- must not force already-approved drivers back through onboarding.
update public.driver_documents d
set review_parts=jsonb_set(
  coalesce(d.review_parts,'{}'::jsonb),
  '{profile}',
  jsonb_build_object(
    'status',
    case
      when d.status='verified' and nullif(trim(coalesce(p.profile_photo_path,'')),'') is not null
        then 'approved'
      else 'pending'
    end,
    'version',1,
    'path',nullif(trim(coalesce(p.profile_photo_path,'')),''),
    'reason',null
  ),
  true
),
updated_at=d.updated_at
from public.driver_profiles p,
     public.driver_document_requirements r
where d.driver_id=p.id
  and r.id=d.requirement_id
  and d.verification_method='manual'
  and lower(r.code) in
    ('identity_card','national_id','id_card','identity','carnet','cedula','cédula')
  and (d.review_parts is null
       or jsonb_typeof(d.review_parts->'profile') is distinct from 'object');

create or replace function public.driver_kyc_bolivia_review_state()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_uid uuid:=auth.uid();
begin
 if v_uid is null then raise exception 'Autenticación requerida'; end if;

 return coalesce((
   select jsonb_build_object(
     'document_id',d.id,
     'status',d.status,
     'review_parts',coalesce(d.review_parts,'{}'::jsonb),
     'needs_correction',
       exists(
         select 1
         from jsonb_each(coalesce(d.review_parts,'{}'::jsonb)) p(slot,value)
         where nullif(p.value->>'path','') is not null
           and coalesce(p.value->>'status','pending')='rejected'
       ),
     'correction_slots',
       coalesce((
         select jsonb_agg(p.slot order by
           case p.slot
             when 'front' then 1
             when 'back' then 2
             when 'selfie' then 3
             when 'profile' then 4
             else 9
           end
         )
         from jsonb_each(coalesce(d.review_parts,'{}'::jsonb)) p(slot,value)
         where nullif(p.value->>'path','') is not null
           and coalesce(p.value->>'status','pending')='rejected'
       ),'[]'::jsonb),
     'driver_approval',p.approval_status
   )
   from public.driver_documents d
   join public.driver_profiles p on p.id=d.driver_id
   join public.driver_document_requirements r on r.id=d.requirement_id
   where d.driver_id=v_uid
     and d.verification_method='manual'
     and lower(r.code) in
       ('identity_card','national_id','id_card','identity','carnet','cedula','cédula')
   order by d.updated_at desc
   limit 1
 ),jsonb_build_object(
   'status','not_started',
   'review_parts','{}'::jsonb,
   'needs_correction',false,
   'correction_slots','[]'::jsonb
 ));
end;
$$;

create or replace function public.driver_kyc_bolivia_replace_part(
 p_document_id uuid,
 p_slot text,
 p_path text,
 p_expected_version integer
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
 v_uid uuid:=auth.uid();
 v_doc public.driver_documents%rowtype;
 v_entry jsonb;
 v_slot text:=lower(trim(coalesce(p_slot,'')));
 v_current_version integer;
begin
 if v_uid is null then raise exception 'Autenticación requerida'; end if;
 if v_slot not in ('front','back','selfie','profile') then
   raise exception 'Tipo de fotografía inválido';
 end if;
 if nullif(trim(coalesce(p_path,'')),'') is null
    or not public.driver_owns_onboarding_object(p_path) then
   raise exception 'Fotografía inválida o no autorizada';
 end if;

 select * into v_doc
 from public.driver_documents
 where id=p_document_id
   and driver_id=v_uid
   and verification_method='manual'
 for update;

 if not found then raise exception 'Documento no encontrado'; end if;

 v_entry:=coalesce(v_doc.review_parts,'{}'::jsonb)->v_slot;
 v_current_version:=coalesce((v_entry->>'version')::integer,0);

 if v_current_version is distinct from p_expected_version then
   raise exception 'La fotografía cambió; actualiza y vuelve a intentar';
 end if;
 if coalesce(v_entry->>'status','pending') not in ('rejected','pending') then
   raise exception 'Esta fotografía ya fue aprobada';
 end if;

 if v_slot='profile' then
   update public.driver_profiles
   set profile_photo_path=p_path,
       approval_status='pending',
       online_status='offline',
       updated_at=now()
   where id=v_uid;

   update public.driver_documents
   set review_parts=jsonb_set(
         coalesce(review_parts,'{}'::jsonb),
         '{profile}',
         jsonb_build_object(
           'status','pending',
           'path',p_path,
           'reason',null,
           'version',v_current_version+1
         ),
         true
       ),
       updated_at=now()
   where id=v_doc.id;
 else
   update public.driver_documents
   set front_object_path=case when v_slot='front' then p_path else front_object_path end,
       back_object_path=case when v_slot='back' then p_path else back_object_path end,
       selfie_object_path=case when v_slot='selfie' then p_path else selfie_object_path end,
       reviewed_at=null,
       updated_at=now()
   where id=v_doc.id;

   -- Replacing identity evidence reopens identity verification.
   update public.identity_verifications
   set status='pending',
       updated_at=now(),
       reviewed_at=null,
       reviewed_by=null
   where id=(
     select i.id
     from public.identity_verifications i
     where i.user_id=v_uid
       and i.provider='express_manual'
       and i.subject_role='driver'
     order by i.created_at desc
     limit 1
   );
 end if;

 return public.driver_kyc_bolivia_review_state();
end;
$$;

create or replace function public.driver_auto_approve_if_complete(p_driver_id uuid)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.driver_profiles%rowtype;
  v_required int;
  v_missing int;
  v_identity public.driver_documents%rowtype;
begin
  if p_driver_id is null or not public.is_admin() then
    return false;
  end if;

  select * into v_profile
  from public.driver_profiles
  where id=p_driver_id;

  if v_profile.id is null
     or v_profile.approval_status<>'pending'
     or nullif(trim(coalesce(v_profile.country_code,'')),'') is null then
    return false;
  end if;

  select count(*),
         count(*) filter (
           where not exists (
             select 1
             from public.driver_documents d
             where d.driver_id=p_driver_id
               and d.requirement_id=r.id
               and d.status='verified'
           )
         )
  into v_required,v_missing
  from public.driver_document_requirements r
  where r.active
    and r.required
    and (r.country_code is null
         or upper(r.country_code)=upper(v_profile.country_code))
    and (r.zone_id is null or r.zone_id=v_profile.zone_id);

  if v_required=0 or v_missing>0 then
    return false;
  end if;

  select d.* into v_identity
  from public.driver_documents d
  join public.driver_document_requirements r on r.id=d.requirement_id
  where d.driver_id=p_driver_id
    and d.verification_method='manual'
    and lower(r.code) in
      ('identity_card','national_id','id_card','identity','carnet','cedula','cédula')
  order by d.updated_at desc
  limit 1;

  if v_identity.id is null
     or v_identity.status<>'verified'
     or nullif(trim(coalesce(v_profile.profile_photo_path,'')),'') is null
     or exists(
       select 1
       from jsonb_each(coalesce(v_identity.review_parts,'{}'::jsonb)) p(slot,value)
       where nullif(p.value->>'path','') is not null
         and coalesce(p.value->>'status','pending')<>'approved'
     ) then
    return false;
  end if;

  begin
    perform public.admin_set_driver_approval(p_driver_id,'approved');
  exception when others then
    return false;
  end;

  return true;
end;
$$;

create or replace function public.update_my_driver_documents_for_review(
 p_documents jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_profile public.driver_profiles%rowtype;
  v_doc jsonb;
  v_req record;
  v_path text;
  v_submitted boolean:=false;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select * into v_profile
  from public.driver_profiles
  where id=v_uid;

  if v_profile.id is null then
    raise exception 'Perfil de conductor no encontrado';
  end if;

  -- Every required additional document may be satisfied either by an already
  -- verified stored document OR by the specific correction included now.
  for v_req in
    select r.id,r.label,r.require_number,r.require_front,r.require_back,r.require_selfie
    from public.driver_document_requirements r
    where r.active=true
      and r.required=true
      and (r.country_code is null
           or upper(r.country_code)=upper(coalesce(v_profile.country_code,'')))
      and (r.zone_id is null or r.zone_id=v_profile.zone_id)
      and lower(coalesce(r.code,'')) not in
        ('identity_card','national_id','id_card','carnet','cedula','cédula')
      and lower(coalesce(r.code,'')) not like '%identity%'
  loop
    if not exists(
      select 1
      from public.driver_documents existing
      where existing.driver_id=v_uid
        and existing.requirement_id=v_req.id
        and existing.status='verified'
        and (not v_req.require_number
             or nullif(trim(coalesce(existing.document_number,'')),'') is not null)
        and (not v_req.require_front
             or nullif(trim(coalesce(existing.front_object_path,'')),'') is not null)
        and (not v_req.require_back
             or nullif(trim(coalesce(existing.back_object_path,'')),'') is not null)
        and (not v_req.require_selfie
             or nullif(trim(coalesce(existing.selfie_object_path,'')),'') is not null)
    )
    and not exists(
      select 1
      from jsonb_array_elements(coalesce(p_documents,'[]'::jsonb)) d
      where d->>'requirement_id'=v_req.id::text
        and (not v_req.require_number
             or nullif(trim(coalesce(d->>'document_number','')),'') is not null)
        and (not v_req.require_front
             or public.driver_owns_onboarding_object(d->>'front_object_path'))
        and (not v_req.require_back
             or public.driver_owns_onboarding_object(d->>'back_object_path'))
        and (not v_req.require_selfie
             or public.driver_owns_onboarding_object(d->>'selfie_object_path'))
    ) then
      raise exception 'Falta completar el documento requerido: %',v_req.label;
    end if;
  end loop;

  for v_doc in
    select value
    from jsonb_array_elements(coalesce(p_documents,'[]'::jsonb))
  loop
    if not exists(
      select 1
      from public.driver_document_requirements r
      where r.id=nullif(v_doc->>'requirement_id','')::uuid
        and r.active=true
        and (r.country_code is null
             or upper(r.country_code)=upper(coalesce(v_profile.country_code,'')))
        and (r.zone_id is null or r.zone_id=v_profile.zone_id)
    ) then
      raise exception 'Documento no permitido para esta ciudad';
    end if;

    foreach v_path in array array[
      nullif(trim(coalesce(v_doc->>'front_object_path','')),''),
      nullif(trim(coalesce(v_doc->>'back_object_path','')),''),
      nullif(trim(coalesce(v_doc->>'selfie_object_path','')),'')
    ] loop
      if v_path is not null
         and not public.driver_owns_onboarding_object(v_path) then
        raise exception 'Archivo de documento inválido';
      end if;
    end loop;

    v_submitted:=true;

    insert into public.driver_documents(
      driver_id,requirement_id,document_type,document_number,
      front_object_path,back_object_path,selfie_object_path,
      status,verification_method,updated_at
    )
    values(
      v_uid,
      nullif(v_doc->>'requirement_id','')::uuid,
      coalesce(nullif(v_doc->>'document_type',''),'document'),
      nullif(trim(coalesce(v_doc->>'document_number','')),''),
      nullif(trim(coalesce(v_doc->>'front_object_path','')),''),
      nullif(trim(coalesce(v_doc->>'back_object_path','')),''),
      nullif(trim(coalesce(v_doc->>'selfie_object_path','')),''),
      'pending','manual',now()
    )
    on conflict(driver_id,requirement_id)
    where requirement_id is not null
    do update set
      document_type=excluded.document_type,
      document_number=excluded.document_number,
      front_object_path=excluded.front_object_path,
      back_object_path=excluded.back_object_path,
      selfie_object_path=excluded.selfie_object_path,
      status=case
        when public.driver_documents.document_number
               is not distinct from excluded.document_number
         and public.driver_documents.front_object_path
               is not distinct from excluded.front_object_path
         and public.driver_documents.back_object_path
               is not distinct from excluded.back_object_path
         and public.driver_documents.selfie_object_path
               is not distinct from excluded.selfie_object_path
          then public.driver_documents.status
        else 'pending'
      end,
      verification_method='manual',
      verification_score=case
        when public.driver_documents.document_number
               is not distinct from excluded.document_number
         and public.driver_documents.front_object_path
               is not distinct from excluded.front_object_path
         and public.driver_documents.back_object_path
               is not distinct from excluded.back_object_path
         and public.driver_documents.selfie_object_path
               is not distinct from excluded.selfie_object_path
          then public.driver_documents.verification_score
        else null
      end,
      reviewed_by=case
        when public.driver_documents.document_number
               is not distinct from excluded.document_number
         and public.driver_documents.front_object_path
               is not distinct from excluded.front_object_path
         and public.driver_documents.back_object_path
               is not distinct from excluded.back_object_path
         and public.driver_documents.selfie_object_path
               is not distinct from excluded.selfie_object_path
          then public.driver_documents.reviewed_by
        else null
      end,
      reviewed_at=case
        when public.driver_documents.document_number
               is not distinct from excluded.document_number
         and public.driver_documents.front_object_path
               is not distinct from excluded.front_object_path
         and public.driver_documents.back_object_path
               is not distinct from excluded.back_object_path
         and public.driver_documents.selfie_object_path
               is not distinct from excluded.selfie_object_path
          then public.driver_documents.reviewed_at
        else null
      end,
      rejection_reason=case
        when public.driver_documents.document_number
               is not distinct from excluded.document_number
         and public.driver_documents.front_object_path
               is not distinct from excluded.front_object_path
         and public.driver_documents.back_object_path
               is not distinct from excluded.back_object_path
         and public.driver_documents.selfie_object_path
               is not distinct from excluded.selfie_object_path
          then public.driver_documents.rejection_reason
        else null
      end,
      updated_at=case
        when public.driver_documents.document_number
               is not distinct from excluded.document_number
         and public.driver_documents.front_object_path
               is not distinct from excluded.front_object_path
         and public.driver_documents.back_object_path
               is not distinct from excluded.back_object_path
         and public.driver_documents.selfie_object_path
               is not distinct from excluded.selfie_object_path
          then public.driver_documents.updated_at
        else now()
      end;
  end loop;

  if v_submitted then
    update public.driver_profiles
    set approval_status='pending',
        online_status='offline',
        updated_at=now()
    where id=v_uid;
  end if;

  return jsonb_build_object(
    'ok',true,
    'approval_status',(select approval_status from public.driver_profiles where id=v_uid),
    'submitted',v_submitted
  );
end;
$$;
