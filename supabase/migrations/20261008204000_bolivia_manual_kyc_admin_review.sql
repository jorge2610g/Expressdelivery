-- Only BO manual identity reviews. No automatic approval of the driver.
-- All admin reads/writes require is_admin and preserve Preview/Production isolation.
create or replace function public.admin_driver_kyc_bolivia_manual_list(
 p_channel text default 'production',
 p_limit integer default 100
)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare
 v_channel text:=lower(trim(coalesce(p_channel,'')));
begin
 if not public.is_admin() then raise exception 'No autorizado'; end if;
 if v_channel not in ('preview','production') then raise exception 'Canal inválido'; end if;
 return (
   select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc),'[]'::jsonb)
   from (
     select d.id,d.driver_id,u.full_name,p.country_code,
       d.document_type,d.document_number,d.front_object_path,
       d.back_object_path,d.selfie_object_path,
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
     order by case when d.status='pending' then 0 else 1 end,d.created_at desc
     limit greatest(1,least(coalesce(p_limit,100),250))
   ) q
 );
end; $$;
revoke all on function public.admin_driver_kyc_bolivia_manual_list(text,integer)
 from public,anon;
grant execute on function public.admin_driver_kyc_bolivia_manual_list(text,integer)
 to authenticated;

create or replace function public.admin_driver_kyc_bolivia_manual_decide(
 p_document_id uuid,
 p_decision text,
 p_reason text default null,
 p_channel text default 'production'
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 v_channel text:=lower(trim(coalesce(p_channel,'')));
 v_decision text:=lower(trim(coalesce(p_decision,'')));
 v_doc public.driver_documents%rowtype;
 v_country text;
 v_code text;
 v_status text;
begin
 if not public.is_admin() then raise exception 'No autorizado'; end if;
 if v_channel not in('preview','production') then raise exception 'Canal inválido'; end if;
 if v_decision not in('approve','reject','retry') then
   raise exception 'Decisión inválida'; end if;
 if v_decision<>'approve' and length(trim(coalesce(p_reason,'')))<5 then
   raise exception 'Indica el motivo del rechazo o repetición'; end if;

 select * into v_doc from public.driver_documents
  where id=p_document_id for update;
 if v_doc.id is null or v_doc.verification_method<>'manual' then
   raise exception 'Documento manual no encontrado'; end if;
 select upper(p.country_code),lower(r.code) into v_country,v_code
 from public.driver_profiles p
 join public.driver_document_requirements r on r.id=v_doc.requirement_id
 where p.id=v_doc.driver_id;
 if v_country is distinct from 'BO' or coalesce(v_code,'') not in
 ('identity_card','national_id','id_card','identity','carnet','cedula','cédula') then
   raise exception 'Solo revisión de identidad de Bolivia'; end if;

 perform public.admin_assert_target_environment(v_doc.driver_id,v_channel);
 if v_doc.status<>'pending' then raise exception 'El documento ya fue revisado'; end if;
 if nullif(trim(coalesce(v_doc.document_number,'')),'') is null
    or v_doc.front_object_path is null or v_doc.back_object_path is null
    or v_doc.selfie_object_path is null then
   raise exception 'No se recibieron todas las capturas'; end if;
 v_status:=case when v_decision='approve' then 'verified' else 'rejected' end;
 update public.driver_documents
 set status=v_status,reviewed_by=auth.uid(),reviewed_at=now(),
     rejection_reason=case when v_decision='approve' then null
       else left(trim(p_reason),1000) end,
     updated_at=now()
 where id=v_doc.id;
 -- Keep the manual identity decision separate from driver/vehicle approval.
 update public.identity_verifications v
 set status=v_status,reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now(),
     completed_at=case when v_decision='approve' then now() else v.completed_at end,
     result=coalesce(v.result,'{}'::jsonb)||jsonb_build_object(
       'manual_review_decision',v_decision,
       'manual_document_id',v_doc.id)
 where v.id=(
   select x.id from public.identity_verifications x
   where x.user_id=v_doc.driver_id
     and x.provider='express_manual' and x.subject_role='driver'
   order by x.created_at desc limit 1
 );
  insert into public.notifications(user_id,title,body,type)
  values(
    v_doc.driver_id,
    case when v_decision='approve' then 'Identidad verificada'
         when v_decision='retry' then 'Nueva captura requerida'
         else 'Verificación de identidad rechazada' end,
    case when v_decision='approve' then
      'Tu identidad fue revisada y aprobada. Tu registro de conductor continúa en revisión.'
      when v_decision='retry' then
      'Necesitamos nuevas fotografías de tu documento. Motivo: '||left(trim(p_reason),500)
      else
      'Tu documento fue rechazado. Motivo: '||left(trim(p_reason),500)
    end,
    'driver_identity_review'
  );
  perform public.admin_log_action(
    'manual_kyc_identity_decision','driver_document',v_doc.id::text,
    jsonb_build_object('decision',v_decision,'driver_id',v_doc.driver_id)
  );
 return jsonb_build_object('ok',true,'document_id',v_doc.id,
    'status',v_status,'approval_requires_separate_driver_review',true);
end; $$;
revoke all on function public.admin_driver_kyc_bolivia_manual_decide(
 uuid,text,text,text) from public,anon;
grant execute on function public.admin_driver_kyc_bolivia_manual_decide(
 uuid,text,text,text) to authenticated;
