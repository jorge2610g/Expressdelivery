-- BO only: the selfie submitted for identity IS the driver's profile photo.
-- Do not add a second independently moderated face check to verification.
-- Migration intentionally preserves old profile review JSON for audit history.
create or replace function public.driver_kyc_bolivia_part_states()
returns trigger language plpgsql security definer set search_path=public as $$
declare
 v_code text; v_country text; v_profile_path text;
 v_parts jsonb:=coalesce(new.review_parts,'{}'::jsonb);
 v_prior text;
 v_slot text; v_path text; v_old_path text; v_entry jsonb;
 v_status text; v_approved integer:=0; v_needed integer:=0;
 v_rejected integer:=0; v_version integer;
begin
 select upper(coalesce(p.country_code,'')),lower(coalesce(r.code,'')),
        nullif(trim(p.profile_photo_path),'')
 into v_country,v_code,v_profile_path
 from public.driver_profiles p
 left join public.driver_document_requirements r on r.id=new.requirement_id
 where p.id=new.driver_id;
 if v_country<>'BO' or new.verification_method<>'manual' or v_code not in
 ('identity_card','national_id','id_card','identity','carnet','cedula','cédula') then
   return new;
 end if;
 v_prior:=case when tg_op='UPDATE' then old.status else new.status end;
 foreach v_slot in array array['front','back','selfie'] loop
   v_path:=case v_slot
      when 'front' then nullif(trim(new.front_object_path),'')
      when 'back' then nullif(trim(new.back_object_path),'')
      when 'selfie' then nullif(trim(new.selfie_object_path),'')
      else v_profile_path end;
   v_old_path:=case when tg_op='UPDATE' then
     case v_slot when 'front' then old.front_object_path
       when 'back' then old.back_object_path
       when 'selfie' then old.selfie_object_path
       else coalesce(old.review_parts #>> '{profile,path}',v_profile_path) end
     else null end;
   v_entry:=v_parts->v_slot;
   if v_entry is null or jsonb_typeof(v_entry)<>'object' then
     v_entry:=jsonb_build_object('status',
       case when tg_op='UPDATE' and old.status='verified' then 'approved'
            when tg_op='UPDATE' and old.status='rejected' then 'rejected'
            else 'pending' end,
       'version',1,'path',v_path,'reason',case when v_prior='rejected' then
           new.rejection_reason else null end);
   elsif v_entry->>'path' is distinct from v_path then
     v_version:=coalesce((v_entry->>'version')::integer,0)+1;
     v_entry:=jsonb_build_object('status','pending','version',v_version,
       'path',v_path,'reason',null);
   end if;
   v_parts:=jsonb_set(v_parts,array[v_slot],v_entry,true);
   if v_path is not null then
     v_needed:=v_needed+1;
     v_status:=coalesce(v_entry->>'status','pending');
     if v_status='approved' then v_approved:=v_approved+1; end if;
     if v_status='rejected' then v_rejected:=v_rejected+1; end if;
   end if;
 end loop;
 new.review_parts:=v_parts;
 -- Front/back/selfie and document number must exist for verified identity.
 if v_approved=v_needed and v_needed>=3 and
    new.front_object_path is not null and new.back_object_path is not null
    and new.selfie_object_path is not null and
    nullif(trim(coalesce(new.document_number,'')),'') is not null then
    new.status:='verified';
 elsif v_rejected>0 then new.status:='rejected';
 else new.status:='pending';
 end if;
 new.rejection_reason:=case when new.status='rejected' then
   (select string_agg(s||': '||left(coalesce(v_parts #>> array[s,'reason'],'Corrección necesaria'),250),'; ')
    from unnest(array['front','back','selfie']) s
    where v_parts #>> array[s,'status']='rejected')
   else null end;
 return new;
end; $$;

-- Recalculate existing BO manual-document status without counting the stale
-- fourth profile slot. The three real photos retain their own decisions.
update public.driver_documents d
set updated_at=now()
from public.driver_profiles p
join public.driver_document_requirements r on true
where d.driver_id=p.id and d.requirement_id=r.id
 and upper(coalesce(p.country_code,''))='BO'
 and d.verification_method='manual'
 and lower(coalesce(r.code,'')) in
 ('identity_card','national_id','id_card','identity','carnet','cedula','cédula');

-- When only the identity selfie is re-uploaded, mirror it to the visible
-- driver profile automatically. Do not require a second camera capture.
create or replace function public.driver_kyc_bolivia_face_profile_mirror()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_country text; v_code text;
begin
 select upper(coalesce(p.country_code,'')),lower(coalesce(r.code,''))
 into v_country,v_code
 from public.driver_profiles p
 join public.driver_document_requirements r on r.id=new.requirement_id
 where p.id=new.driver_id;
 if v_country='BO' and new.verification_method='manual'
  and v_code in ('identity_card','national_id','id_card',
     'identity','carnet','cedula','cédula')
  and nullif(trim(coalesce(new.selfie_object_path,'')),'') is not null then
    update public.driver_profiles
    set profile_photo_path=new.selfie_object_path,updated_at=now()
    where id=new.driver_id
      and profile_photo_path is distinct from new.selfie_object_path;
 end if;
 return new;
end; $$;

drop trigger if exists trg_driver_kyc_bolivia_face_profile_mirror
 on public.driver_documents;
create trigger trg_driver_kyc_bolivia_face_profile_mirror
 after insert or update of selfie_object_path on public.driver_documents
 for each row
 execute function public.driver_kyc_bolivia_face_profile_mirror();
