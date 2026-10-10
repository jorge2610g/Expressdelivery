-- Generic per-photo manual review for every configured driver document.
-- This migration is intentionally versioned only; do not apply to Production
-- until the paired Adminexpress UI and driver correction flow pass QA.

create or replace function public.admin_driver_document_review_part_v2(
  p_document_id uuid,
  p_slot text,
  p_status text,
  p_reason text default null,
  p_expected_version integer default null,
  p_channel text default 'production'
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_doc public.driver_documents%rowtype;
  v_req public.driver_document_requirements%rowtype;
  v_slot text := lower(trim(coalesce(p_slot,'')));
  v_status text := lower(trim(coalesce(p_status,'')));
  v_channel text := lower(trim(coalesce(p_channel,'')));
  v_reason text := nullif(trim(coalesce(p_reason,'')),'');
  v_parts jsonb;
  v_entry jsonb;
  v_path text;
  v_previous text;
  v_current integer;
  v_needed integer := 0;
  v_approved integer := 0;
  v_rejected integer := 0;
  v_missing integer := 0;
  v_part_status text;
  v_part_path text;
  v_document_status text;
  v_slot_label text;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  if v_channel not in ('preview','production') then
    raise exception 'Canal inválido';
  end if;
  if v_slot not in ('front','back','selfie') then
    raise exception 'Fotografía inválida';
  end if;
  if v_status not in ('approved','rejected','pending') then
    raise exception 'Estado inválido';
  end if;
  if v_status='rejected' and length(coalesce(v_reason,''))<5 then
    raise exception 'Indica el motivo';
  end if;

  select * into v_doc
  from public.driver_documents
  where id=p_document_id
  for update;

  if v_doc.id is null then
    raise exception 'Documento no encontrado';
  end if;

  select * into v_req
  from public.driver_document_requirements
  where id=v_doc.requirement_id;

  if v_req.id is null then
    raise exception 'Requisito no encontrado';
  end if;

  if lower(coalesce(v_req.code,'')) in (
    'identity_card','national_id','id_card','identity',
    'carnet','cedula','cédula'
  ) then
    raise exception 'La identidad usa su flujo de revisión dedicado';
  end if;

  perform public.admin_assert_target_environment(v_doc.driver_id,v_channel);

  v_parts := coalesce(v_doc.review_parts,'{}'::jsonb);
  v_entry := coalesce(v_parts->v_slot,'{}'::jsonb);
  v_current := coalesce((v_entry->>'version')::integer,0);

  if p_expected_version is null or v_current<>p_expected_version then
    raise exception 'La imagen fue actualizada. Refresca antes de decidir';
  end if;

  v_path := coalesce(
    nullif(v_entry->>'path',''),
    case v_slot
      when 'front' then nullif(trim(v_doc.front_object_path),'')
      when 'back' then nullif(trim(v_doc.back_object_path),'')
      when 'selfie' then nullif(trim(v_doc.selfie_object_path),'')
    end
  );
  if v_path is null then
    raise exception 'No hay fotografía para revisar';
  end if;

  v_previous := coalesce(v_entry->>'status','pending');
  if v_previous=v_status then
    return jsonb_build_object(
      'ok',true,
      'unchanged',true,
      'document_id',v_doc.id,
      'slot',v_slot,
      'slot_status',v_status,
      'document_status',v_doc.status,
      'version',v_current
    );
  end if;

  v_parts := jsonb_set(
    v_parts,
    array[v_slot],
    jsonb_build_object(
      'status',v_status,
      'reason',case when v_status='rejected' then left(v_reason,600) else null end,
      'path',v_path,
      'version',v_current+1,
      'reviewed_at',now(),
      'reviewed_by',auth.uid()
    ),
    true
  );

  foreach v_slot in array array['front','back','selfie'] loop
    if (v_slot='front' and v_req.require_front)
       or (v_slot='back' and v_req.require_back)
       or (v_slot='selfie' and v_req.require_selfie) then
      v_needed := v_needed + 1;
      v_entry := coalesce(v_parts->v_slot,'{}'::jsonb);
      v_part_path := coalesce(
        nullif(v_entry->>'path',''),
        case v_slot
          when 'front' then nullif(trim(v_doc.front_object_path),'')
          when 'back' then nullif(trim(v_doc.back_object_path),'')
          when 'selfie' then nullif(trim(v_doc.selfie_object_path),'')
        end
      );
      v_part_status := coalesce(v_entry->>'status','pending');
      if v_part_path is null then
        v_missing := v_missing + 1;
      elsif v_part_status='approved' then
        v_approved := v_approved + 1;
      elsif v_part_status='rejected' then
        v_rejected := v_rejected + 1;
      end if;
    end if;
  end loop;

  if v_req.require_number
     and nullif(trim(coalesce(v_doc.document_number,'')),'') is null then
    v_missing := v_missing + 1;
  end if;

  if v_rejected>0 then
    v_document_status := 'rejected';
  elsif v_needed>0 and v_missing=0 and v_approved=v_needed then
    v_document_status := 'verified';
  else
    v_document_status := 'pending';
  end if;

  update public.driver_documents
  set review_parts=v_parts,
      status=v_document_status,
      rejection_reason=case
        when v_document_status='rejected' then (
          select string_agg(
            s||': '||
            left(coalesce(v_parts #>> array[s,'reason'],'Corrección necesaria'),250),
            '; '
          )
          from unnest(array['front','back','selfie']) s
          where v_parts #>> array[s,'status']='rejected'
        )
        else null
      end,
      reviewed_at=now(),
      reviewed_by=auth.uid(),
      updated_at=now()
  where id=v_doc.id;

  v_slot_label := case p_slot
    when 'front' then 'frente'
    when 'back' then 'reverso'
    else 'foto facial'
  end;

  insert into public.notifications(
    user_id,title,body,type,channel,metadata
  ) values (
    v_doc.driver_id,
    case
      when p_status='rejected' then 'Corrige un documento'
      when p_status='approved' then 'Fotografía aprobada'
      else 'Fotografía en revisión'
    end,
    case
      when p_status='rejected' then
        'Debes corregir '||coalesce(v_req.label,'tu documento')||
        ' ('||v_slot_label||'). '||left(v_reason,250)
      when p_status='approved' then
        coalesce(v_req.label,'Tu documento')||' · '||v_slot_label||
        ' fue aprobado. No necesitas volver a cargarlo.'
      else
        coalesce(v_req.label,'Tu documento')||' · '||v_slot_label||
        ' volvió a revisión.'
    end,
    'driver_document_review',
    v_channel,
    jsonb_build_object(
      'route','driver_documents',
      'document_id',v_doc.id,
      'requirement_id',v_req.id,
      'requirement_code',v_req.code,
      'requirement_label',v_req.label,
      'slot',p_slot,
      'status',p_status,
      'review_version',v_current+1,
      'channel',v_channel,
      'deep_link','express://driver-documents/'||v_doc.id::text||'/'||p_slot
    )
  );

  perform public.admin_log_action(
    'driver_document_photo_review',
    'driver_document',
    v_doc.id::text,
    jsonb_build_object(
      'requirement_id',v_req.id,
      'requirement_code',v_req.code,
      'slot',p_slot,
      'from_status',v_previous,
      'to_status',p_status,
      'version',v_current+1,
      'environment',v_channel
    )
  );

  return jsonb_build_object(
    'ok',true,
    'document_id',v_doc.id,
    'slot',p_slot,
    'slot_status',p_status,
    'document_status',v_document_status,
    'version',v_current+1,
    'driver_auto_approved',
      public.driver_auto_approve_if_complete(v_doc.driver_id)
  );
end;
$function$;

revoke all on function public.admin_driver_document_review_part_v2(
  uuid,text,text,text,integer,text
) from public, anon;
grant execute on function public.admin_driver_document_review_part_v2(
  uuid,text,text,text,integer,text
) to authenticated, service_role;


-- Keep per-photo state synchronized when the driver replaces a generic
-- document image. Identity documents keep using their dedicated trigger.
create or replace function public.driver_generic_document_part_states()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_req public.driver_document_requirements%rowtype;
  v_parts jsonb := coalesce(new.review_parts,'{}'::jsonb);
  v_entry jsonb;
  v_old_entry jsonb;
  v_slot text;
  v_path text;
  v_old_path text;
  v_required boolean;
  v_version integer;
  v_needed integer := 0;
  v_missing integer := 0;
  v_approved integer := 0;
  v_rejected integer := 0;
  v_part_status text;
begin
  select * into v_req
  from public.driver_document_requirements
  where id=new.requirement_id;

  if v_req.id is null
     or lower(coalesce(v_req.code,'')) in (
       'identity_card','national_id','id_card','identity',
       'carnet','cedula','cédula'
     ) then
    return new;
  end if;

  foreach v_slot in array array['front','back','selfie'] loop
    v_required := case v_slot
      when 'front' then v_req.require_front
      when 'back' then v_req.require_back
      else v_req.require_selfie
    end;
    if not coalesce(v_required,false) then
      continue;
    end if;

    v_needed := v_needed + 1;
    v_path := case v_slot
      when 'front' then nullif(trim(new.front_object_path),'')
      when 'back' then nullif(trim(new.back_object_path),'')
      else nullif(trim(new.selfie_object_path),'')
    end;
    v_old_path := case
      when tg_op='UPDATE' then case v_slot
        when 'front' then nullif(trim(old.front_object_path),'')
        when 'back' then nullif(trim(old.back_object_path),'')
        else nullif(trim(old.selfie_object_path),'')
      end
      else null
    end;

    v_entry := v_parts->v_slot;
    v_old_entry := case
      when tg_op='UPDATE' then coalesce(old.review_parts,'{}'::jsonb)->v_slot
      else null
    end;

    if tg_op='INSERT' and v_path is not null then
      if v_entry is null or jsonb_typeof(v_entry)<>'object' then
        v_entry := jsonb_build_object(
          'status','pending',
          'reason',null,
          'path',v_path,
          'version',1
        );
      elsif nullif(v_entry->>'path','') is null then
        v_entry := jsonb_set(v_entry,'{path}',to_jsonb(v_path),true);
      end if;
    elsif tg_op='UPDATE' and v_path is distinct from v_old_path then
      v_version := coalesce(
        nullif(v_old_entry->>'version','')::integer,
        nullif(v_entry->>'version','')::integer,
        0
      ) + 1;
      v_entry := jsonb_build_object(
        'status','pending',
        'reason',null,
        'path',v_path,
        'version',v_version
      );
    elsif v_path is not null
          and (v_entry is null or jsonb_typeof(v_entry)<>'object') then
      -- Seed legacy generic documents. A previously verified document can
      -- safely retain its approval; older pending/rejected rows are rechecked.
      v_entry := jsonb_build_object(
        'status',case
          when tg_op='UPDATE' and old.status='verified' then 'approved'
          else 'pending'
        end,
        'reason',null,
        'path',v_path,
        'version',0
      );
    end if;

    if v_entry is not null then
      v_parts := jsonb_set(v_parts,array[v_slot],v_entry,true);
    end if;

    if v_path is null then
      v_missing := v_missing + 1;
    else
      v_part_status := coalesce(v_entry->>'status','pending');
      if v_part_status='approved' then
        v_approved := v_approved + 1;
      elsif v_part_status='rejected' then
        v_rejected := v_rejected + 1;
      end if;
    end if;
  end loop;

  if v_needed=0 then
    return new;
  end if;

  if v_req.require_number
     and nullif(trim(coalesce(new.document_number,'')),'') is null then
    v_missing := v_missing + 1;
  end if;

  new.review_parts := v_parts;
  if v_rejected>0 then
    new.status := 'rejected';
  elsif v_missing=0 and v_approved=v_needed then
    new.status := 'verified';
  else
    new.status := 'pending';
  end if;

  new.rejection_reason := case
    when new.status='rejected' then (
      select string_agg(
        case s
          when 'front' then 'Frente'
          when 'back' then 'Reverso'
          else 'Foto facial'
        end || ': ' ||
        left(coalesce(v_parts #>> array[s,'reason'],'Corrección necesaria'),250),
        '; '
      )
      from unnest(array['front','back','selfie']) s
      where v_parts #>> array[s,'status']='rejected'
    )
    else null
  end;

  if tg_op='UPDATE' and new.status in ('verified','rejected') then
    new.reviewed_by := coalesce(new.reviewed_by,old.reviewed_by);
    new.reviewed_at := coalesce(new.reviewed_at,old.reviewed_at);
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_driver_generic_document_part_states
  on public.driver_documents;
create trigger trg_driver_generic_document_part_states
before insert or update on public.driver_documents
for each row execute function public.driver_generic_document_part_states();
