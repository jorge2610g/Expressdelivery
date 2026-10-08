-- Express Bolivia: separate, reversible photo review with optimistic versions.
-- Existing documents remain untouched; no forced recapture of approved photos.
alter table public.driver_documents
 add column if not exists review_parts jsonb not null default '{}'::jsonb;
alter table public.driver_documents
 add constraint driver_documents_review_parts_object
 check (jsonb_typeof(review_parts)='object');

create table if not exists public.driver_manual_identity_review_history (
 id bigint generated always as identity primary key,
 document_id uuid not null references public.driver_documents(id) on delete cascade,
 actor_id uuid not null,
 slot text not null check(slot in('front','back','selfie','profile')),
 from_status text not null,
 to_status text not null,
 from_version integer not null,
 to_version integer not null,
 reason text,
 channel text not null check(channel in('production','preview')),
 created_at timestamptz not null default now()
);
create index if not exists driver_manual_identity_history_doc_idx
 on public.driver_manual_identity_review_history(document_id,created_at desc);
alter table public.driver_manual_identity_review_history enable row level security;
revoke all on public.driver_manual_identity_review_history from anon,authenticated;

-- Existing legacy rows are conservatively initialized with their prior
-- decision. For a historical rejected document, the admin can now undo it.
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
 foreach v_slot in array array['front','back','selfie','profile'] loop
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
    from unnest(array['front','back','selfie','profile']) s
    where v_parts #>> array[s,'status']='rejected')
   else null end;
 return new;
end; $$;
drop trigger if exists trg_driver_kyc_bolivia_part_states on public.driver_documents;
create trigger trg_driver_kyc_bolivia_part_states
 before insert or update on public.driver_documents
 for each row execute function public.driver_kyc_bolivia_part_states();

-- Store profile photo changes on that document, but only for Bolivia manual KYC.
create or replace function public.driver_kyc_bolivia_profile_part_sync()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_doc uuid;
begin
 if upper(coalesce(new.country_code,''))='BO'
   and new.profile_photo_path is distinct from old.profile_photo_path then
   select d.id into v_doc from public.driver_documents d
     join public.driver_document_requirements r on r.id=d.requirement_id
   where d.driver_id=new.id and d.verification_method='manual'
     and lower(r.code) in('identity_card','national_id','id_card','identity',
       'carnet','cedula','cédula')
   order by d.updated_at desc limit 1;
   if v_doc is not null then
     -- Let the document's BEFORE UPDATE trigger see the changed profile path.
     -- It will increment the version and reset only this photograph.
     update public.driver_documents set updated_at=now() where id=v_doc;
   end if;
 end if;
 return new;
end; $$;
-- A photo may also be changed via the driver's existing profile RPC.
-- Keep its moderation status aligned, including for that legacy path.
drop trigger if exists trg_driver_kyc_bolivia_profile_part_sync
  on public.driver_profiles;
create trigger trg_driver_kyc_bolivia_profile_part_sync
 after update of profile_photo_path on public.driver_profiles
 for each row
 when (old.profile_photo_path is distinct from new.profile_photo_path)
 execute function public.driver_kyc_bolivia_profile_part_sync();

create or replace function public.driver_kyc_bolivia_review_state()
returns jsonb language plpgsql stable security definer
set search_path=public as $$
declare v_uid uuid:=auth.uid();
begin
 if v_uid is null then raise exception 'Autenticación requerida'; end if;
 return coalesce((
 select jsonb_build_object('document_id',d.id,'status',d.status,
   'review_parts',d.review_parts,
   'needs_correction', d.status='rejected',
   'driver_approval',p.approval_status)
 from public.driver_documents d
 join public.driver_profiles p on p.id=d.driver_id
 join public.driver_document_requirements r on r.id=d.requirement_id
 where d.driver_id=v_uid and upper(p.country_code)='BO'
   and d.verification_method='manual'
   and lower(r.code) in('identity_card','national_id','id_card',
       'identity','carnet','cedula','cédula')
 order by d.updated_at desc limit 1
 ),jsonb_build_object('status','not_started','needs_correction',false));
end; $$;
revoke all on function public.driver_kyc_bolivia_review_state() from public,anon;
grant execute on function public.driver_kyc_bolivia_review_state() to authenticated;

-- Only the owner can replace one rejected/pending part, never another part.
create or replace function public.driver_kyc_bolivia_replace_part(
 p_document_id uuid,p_slot text,p_path text,p_expected_version integer
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_uid uuid:=auth.uid(); v_doc public.driver_documents%rowtype;
 v_entry jsonb; v_country text; v_slot text:=lower(trim(coalesce(p_slot,'')));
 v_current_version integer;
begin
 if v_uid is null then raise exception 'Autenticación requerida'; end if;
 if v_slot not in ('front','back','selfie','profile') then
   raise exception 'Tipo de fotografía inválido'; end if;
 if nullif(trim(coalesce(p_path,'')),'') is null or
    not public.driver_owns_onboarding_object(p_path) then
   raise exception 'Fotografía inválida o no autorizada'; end if;
 select * into v_doc from public.driver_documents
   where id=p_document_id and driver_id=v_uid and verification_method='manual'
   for update;
 if not found then raise exception 'Documento no encontrado'; end if;
 select upper(p.country_code) into v_country from public.driver_profiles p
 where p.id=v_uid;
 if v_country is distinct from 'BO' then raise exception 'Solo Bolivia'; end if;
 v_entry:=v_doc.review_parts->v_slot;
 v_current_version:=coalesce((v_entry->>'version')::integer,0);
 if v_current_version is distinct from p_expected_version then
   raise exception 'La fotografía cambió; actualiza y vuelve a intentar'; end if;
 if coalesce(v_entry->>'status','pending') not in ('rejected','pending') then
   raise exception 'Esta fotografía ya fue aprobada'; end if;
 if v_slot='profile' then
   update public.driver_profiles set profile_photo_path=p_path,
     approval_status='pending',updated_at=now()
   where id=v_uid;
   update public.driver_documents set
     review_parts=jsonb_set(review_parts,'{profile}',
       jsonb_build_object('status','pending','path',p_path,
         'reason',null,'version',v_current_version+1),true),
     updated_at=now() where id=v_doc.id;
 else
   update public.driver_documents set
     front_object_path=case when v_slot='front' then p_path else front_object_path end,
     back_object_path=case when v_slot='back' then p_path else back_object_path end,
     selfie_object_path=case when v_slot='selfie' then p_path else selfie_object_path end,
     reviewed_at=null,updated_at=now()
   where id=v_doc.id;
 end if;
 update public.identity_verifications set status='pending',
   updated_at=now(),reviewed_at=null,reviewed_by=null
 where id=(select i.id from public.identity_verifications i
   where i.user_id=v_uid and i.provider='express_manual'
     and i.subject_role='driver' order by i.created_at desc limit 1);
 return public.driver_kyc_bolivia_review_state();
end; $$;
revoke all on function public.driver_kyc_bolivia_replace_part(uuid,text,text,integer)
 from public,anon;
grant execute on function public.driver_kyc_bolivia_replace_part(uuid,text,text,integer)
 to authenticated;

create or replace function public.admin_driver_kyc_bolivia_manual_review_part(
 p_document_id uuid,
 p_slot text,
 p_status text,
 p_reason text default null,
 p_expected_version integer default null,
 p_channel text default 'production'
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 v_doc public.driver_documents%rowtype;
 v_slot text:=lower(trim(coalesce(p_slot,'')));
 v_status text:=lower(trim(coalesce(p_status,'')));
 v_channel text:=lower(trim(coalesce(p_channel,'')));
 v_entry jsonb; v_current integer;
 v_new_doc public.driver_documents%rowtype;
 v_path text; v_country text; v_code text;
 v_previous text; v_reason text:=nullif(trim(coalesce(p_reason,'')),'');
begin
 if not public.is_admin() then raise exception 'No autorizado'; end if;
 if v_channel not in('preview','production') then raise exception 'Canal inválido'; end if;
 if v_slot not in('front','back','selfie','profile') then raise exception 'Fotografía inválida'; end if;
 if v_status not in('approved','rejected','pending') then
   raise exception 'Estado inválido'; end if;
 if v_status='rejected' and length(coalesce(v_reason,''))<5 then
   raise exception 'Indica el motivo'; end if;
 select * into v_doc from public.driver_documents where id=p_document_id for update;
 if v_doc.id is null or v_doc.verification_method<>'manual' then
   raise exception 'Documento no encontrado'; end if;
 select upper(p.country_code),lower(r.code) into v_country,v_code
 from public.driver_profiles p
 join public.driver_document_requirements r on r.id=v_doc.requirement_id
 where p.id=v_doc.driver_id;
 if v_country is distinct from 'BO' or v_code not in
  ('identity_card','national_id','id_card','identity','carnet','cedula','cédula') then
  raise exception 'Documento fuera de Bolivia'; end if;
 perform public.admin_assert_target_environment(v_doc.driver_id,v_channel);
 v_entry:=v_doc.review_parts->v_slot;
 v_current:=coalesce((v_entry->>'version')::integer,0);
 if p_expected_version is null or v_current<>p_expected_version then
   raise exception 'La imagen fue actualizada. Refresca antes de decidir'; end if;
 v_previous:=coalesce(v_entry->>'status','pending');
 v_path:=v_entry->>'path';
 if nullif(v_path,'') is null then raise exception 'No hay fotografía para revisar'; end if;
 if v_previous=v_status then
   return jsonb_build_object('ok',true,'unchanged',true,'status',v_doc.status);
 end if;

 update public.driver_documents set
   review_parts=jsonb_set(review_parts,array[v_slot],
     jsonb_build_object('status',v_status,'reason',
       case when v_status='rejected' then left(v_reason,600) else null end,
       'path',v_path,'version',v_current+1,
       'reviewed_at',now(),'reviewed_by',auth.uid()),true),
   reviewed_at=now(),reviewed_by=auth.uid(),updated_at=now()
 where id=v_doc.id returning * into v_new_doc;

 insert into public.driver_manual_identity_review_history(
  document_id,actor_id,slot,from_status,to_status,from_version,to_version,
  reason,channel
 ) values(v_doc.id,auth.uid(),v_slot,v_previous,v_status,v_current,
   v_current+1,case when v_status='rejected' then v_reason else null end,v_channel);
 update public.identity_verifications set
   status=v_new_doc.status,
   reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now(),
   completed_at=case when v_new_doc.status='verified' then now() else completed_at end
 where id=(select i.id from public.identity_verifications i
   where i.user_id=v_doc.driver_id and i.provider='express_manual'
   and i.subject_role='driver' order by i.created_at desc limit 1);

 insert into public.notifications(user_id,title,body,type,channel,metadata)
 values(v_doc.driver_id,
   case when v_status='rejected' then 'Corrige una fotografía'
        when v_status='approved' then 'Fotografía aprobada'
        else 'Fotografía reactivada' end,
   case when v_status='rejected' then
     'Debes actualizar '||case v_slot when 'front' then 'el frente del carné'
        when 'back' then 'el reverso del carné' when 'selfie' then 'tu selfie'
        else 'tu foto de perfil' end||'. '||left(v_reason,250)
     when v_status='approved' then 'Tu fotografía fue aprobada. No necesitas volver a cargarla.'
     else 'Tu fotografía volvió a revisión; no es necesario reemplazarla todavía.' end,
   'driver_identity_review',v_channel,
   jsonb_build_object('route','driver_kyc_correction',
     'document_id',v_doc.id,'slot',v_slot,'status',v_status,
     'review_version',v_current+1,'channel',v_channel,
     'deep_link','express://driver-kyc-correction/'||v_slot));

 perform public.admin_log_action('driver_kyc_photo_review','driver_document',
   v_doc.id::text,jsonb_build_object('slot',v_slot,
   'from_status',v_previous,'to_status',v_status,'version',v_current+1));
 return jsonb_build_object('ok',true,'document_id',v_doc.id,
   'slot',v_slot,'slot_status',v_status,'document_status',v_new_doc.status,
   'version',v_current+1);
end; $$;
revoke all on function public.admin_driver_kyc_bolivia_manual_review_part(
 uuid,text,text,text,integer,text) from public,anon;
grant execute on function public.admin_driver_kyc_bolivia_manual_review_part(
 uuid,text,text,text,integer,text) to authenticated;

-- Aggregate in listing; old admin client cannot reject a whole identity
-- by mistake once this migration is live.
create or replace function public.admin_driver_kyc_bolivia_manual_decide(
 p_document_id uuid,p_decision text,p_reason text default null,
 p_channel text default 'production'
) returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'No autorizado'; end if;
 raise exception 'Revisión por imagen requerida: actualiza el panel administrativo';
end; $$;

create or replace function public.admin_driver_kyc_bolivia_manual_list(
 p_channel text default 'production',p_limit integer default 100
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_channel text:=lower(trim(coalesce(p_channel,'')));
begin
 if not public.is_admin() then raise exception 'No autorizado'; end if;
 if v_channel not in('preview','production') then raise exception 'Canal inválido'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc),'[]'::jsonb)
 from (
 select d.id,d.driver_id,u.full_name,p.country_code,
 d.document_type,d.document_number,d.front_object_path,d.back_object_path,
 d.selfie_object_path,p.profile_photo_path,d.review_parts,
 d.status,d.rejection_reason,d.reviewed_by,d.reviewed_at,
 d.created_at,d.updated_at
 from public.driver_documents d
 join public.driver_profiles p on p.id=d.driver_id
 join public.driver_document_requirements r on r.id=d.requirement_id
 left join public.users u on u.id=d.driver_id
 where upper(coalesce(p.country_code,''))='BO'
   and d.verification_method='manual'
   and lower(coalesce(r.code,'')) in
    ('identity_card','national_id','id_card','identity','carnet','cedula','cédula')
   and public.is_active_audit_user(d.driver_id)=(v_channel='preview')
 order by case when d.status='rejected' then 0
               when d.status='pending' then 1 else 2 end,
   d.created_at desc
 limit greatest(1,least(coalesce(p_limit,100),250))
 ) q);
end; $$;

-- Import previous BO manual documents into independent statuses.
-- Restricted to BO, never overwrites an existing per-photo decision.
update public.driver_documents d
set updated_at=now()
from public.driver_profiles p
join public.driver_document_requirements r on true
where d.driver_id=p.id and d.requirement_id=r.id
  and upper(coalesce(p.country_code,''))='BO'
  and d.verification_method='manual'
  and lower(r.code) in ('identity_card','national_id','id_card',
    'identity','carnet','cedula','cédula')
  and d.review_parts='{}'::jsonb;
