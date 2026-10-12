-- Individual front/back review for driver's licence. Expressdelivery owns
-- backend migrations; Adminexpress must use the same RPC for both account
-- environments. Do not apply to production before Preview QA.
create or replace function public.driver_license_part_states()
returns trigger
language plpgsql security definer set search_path=public
as $$
declare
  v_code text;
  v_parts jsonb := coalesce(new.review_parts, '{}'::jsonb);
  v_part jsonb;
  v_slot text;
  v_path text;
  v_old_path text;
  v_status text;
  v_version integer;
  v_all_approved boolean := true;
  v_rejected boolean := false;
  v_old_status text;
begin
  select lower(coalesce(r.code,'')) into v_code
    from public.driver_document_requirements r
   where r.id=new.requirement_id;
  if lower(coalesce(new.document_type,'')) <> 'driver_license'
     and coalesce(v_code,'') <> 'driver_license' then
    return new;
  end if;

  v_old_status := case when tg_op='UPDATE' then old.status else new.status end;
  foreach v_slot in array array['front','back'] loop
    v_path := case when v_slot='front'
      then nullif(trim(coalesce(new.front_object_path,'')),'')
      else nullif(trim(coalesce(new.back_object_path,'')),'') end;
    if tg_op='UPDATE' then
      v_old_path := case when v_slot='front'
        then nullif(trim(coalesce(old.front_object_path,'')),'')
        else nullif(trim(coalesce(old.back_object_path,'')),'') end;
    else
      v_old_path := v_path;
    end if;
    v_part := v_parts->v_slot;
    if v_part is null or jsonb_typeof(v_part)<>'object' then
      v_part := jsonb_build_object(
        'status',case
          when v_path is null then 'pending'
          -- A changed image on an old, globally verified licence is NOT
          -- approved just because the old document was approved.
          when v_old_path is distinct from v_path then 'pending'
          when v_old_status='verified' then 'approved'
          when v_old_status='rejected' then 'rejected'
          else 'pending' end,
        'version',0,'path',v_path,'reason',null);
    elsif coalesce(v_part->>'path','') is distinct from coalesce(v_path,'') then
      v_version := coalesce((v_part->>'version')::integer,0)+1;
      v_part := jsonb_build_object(
        'status','pending','version',v_version,
        'path',v_path,'reason',null);
    end if;
    v_parts := jsonb_set(v_parts,array[v_slot],v_part,true);
    v_status := coalesce(v_part->>'status','pending');
    if v_path is null or v_status<>'approved' then
      v_all_approved := false;
    end if;
    if v_path is not null and v_status='rejected' then
      v_rejected := true;
    end if;
  end loop;

  new.review_parts := v_parts;
  if v_all_approved
     and nullif(trim(coalesce(new.document_number,'')),'') is not null then
    new.status := 'verified';
  elsif v_rejected then
    new.status := 'rejected';
  else
    new.status := 'pending';
  end if;
  new.rejection_reason := case when v_rejected then
    (select string_agg(
      case s when 'front' then 'Frente' else 'Reverso' end || ': ' ||
      left(coalesce(v_parts #>> array[s,'reason'],'Corrección necesaria'),250),
      '; ')
     from unnest(array['front','back']) s
     where v_parts #>> array[s,'status']='rejected')
    else null end;
  return new;
end;
$$;

drop trigger if exists trg_driver_license_part_states on public.driver_documents;
create trigger trg_driver_license_part_states
before insert or update of front_object_path,back_object_path,review_parts
on public.driver_documents
for each row execute function public.driver_license_part_states();

revoke all on function public.driver_license_part_states() from public,anon,authenticated;

create or replace function public.admin_driver_license_review_part(
  p_document_id uuid,
  p_slot text,
  p_status text,
  p_reason text default null,
  p_expected_version integer default null,
  p_channel text default 'production'
)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_doc public.driver_documents%rowtype;
  v_updated public.driver_documents%rowtype;
  v_slot text := lower(trim(coalesce(p_slot,'')));
  v_status text := lower(trim(coalesce(p_status,'')));
  v_reason text := nullif(trim(coalesce(p_reason,'')),'');
  v_channel text := lower(trim(coalesce(p_channel,'')));
  v_entry jsonb;
  v_path text;
  v_current integer;
  v_previous text;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if v_channel not in ('preview','production') then
    raise exception 'Canal inválido';
  end if;
  if v_slot not in ('front','back') then
    raise exception 'Parte de licencia inválida';
  end if;
  if v_status not in ('approved','rejected','pending') then
    raise exception 'Estado inválido';
  end if;
  if v_status='rejected' and length(coalesce(v_reason,''))<5 then
    raise exception 'Especifica un motivo de al menos cinco caracteres';
  end if;

  select * into v_doc from public.driver_documents
  where id=p_document_id for update;
  if v_doc.id is null or lower(coalesce(v_doc.document_type,''))<>'driver_license' then
    raise exception 'Licencia no encontrada';
  end if;
  perform public.admin_assert_target_environment(v_doc.driver_id,v_channel);
  v_path := case when v_slot='front'
      then nullif(trim(coalesce(v_doc.front_object_path,'')),'')
      else nullif(trim(coalesce(v_doc.back_object_path,'')),'') end;
  if v_path is null then raise exception 'La fotografía no está cargada'; end if;

  v_entry := coalesce(v_doc.review_parts,'{}'::jsonb)->v_slot;
  v_current := coalesce((v_entry->>'version')::integer,0);
  if p_expected_version is null or v_current<>p_expected_version then
    raise exception 'La imagen fue actualizada. Refresca la ficha antes de decidir';
  end if;
  v_previous := coalesce(v_entry->>'status',
     case when v_doc.status='verified' then 'approved'
          when v_doc.status='rejected' then 'rejected'
          else 'pending' end);
  if v_previous=v_status then
    return jsonb_build_object('ok',true,'unchanged',true,
      'document_status',v_doc.status);
  end if;

  update public.driver_documents
     set review_parts=jsonb_set(coalesce(review_parts,'{}'::jsonb),
         array[v_slot],
         jsonb_build_object(
           'status',v_status,'reason',case when v_status='rejected'
                then left(v_reason,600) else null end,
           'path',v_path,'version',v_current+1,
           'reviewed_by',auth.uid(),'reviewed_at',now()),true),
         reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now()
   where id=v_doc.id
   returning * into v_updated;

  perform public.admin_log_action(
    'driver_license_photo_review','driver_document',v_doc.id::text,
    jsonb_build_object('slot',v_slot,'channel',v_channel,
      'from_status',v_previous,'to_status',v_status,'version',v_current+1));

  insert into public.notifications(user_id,title,body,type,channel,metadata)
  values (
    v_doc.driver_id,
    case when v_status='approved' then 'Foto de licencia aprobada'
         when v_status='rejected' then 'Corrige tu licencia'
         else 'Fotografía de licencia en revisión' end,
    case when v_status='approved' then
      'Tu '||case v_slot when 'front' then 'frente' else 'reverso' end||
      ' de licencia fue aprobado.'
    when v_status='rejected' then
      'Debes corregir el '||case v_slot when 'front' then 'frente'
          else 'reverso' end||' de tu licencia. '||left(v_reason,250)
    else 'Una fotografía de tu licencia volvió a revisión.' end,
    'driver_document_review',v_channel,
    jsonb_build_object('document_id',v_doc.id,'slot',v_slot,
      'status',v_status,'review_version',v_current+1,'channel',v_channel));

  return jsonb_build_object('ok',true,'document_id',v_doc.id,
    'slot',v_slot,'slot_status',v_status,
    'document_status',v_updated.status,'version',v_current+1,
    'driver_auto_approved',public.driver_auto_approve_if_complete(v_doc.driver_id));
end;
$$;

revoke all on function public.admin_driver_license_review_part(
  uuid,text,text,text,integer,text) from public,anon;
grant execute on function public.admin_driver_license_review_part(
  uuid,text,text,text,integer,text) to authenticated;
