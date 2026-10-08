-- Safety gate: a Bolivia Express-manual driver cannot be activated before
-- a moderator has VERIFIED their national identity document.
-- Preserve the original admin function and all its notification/audit behavior.
create or replace function public.admin_set_driver_approval(
  p_user_id uuid, p_status text
)
returns void language plpgsql security definer
set search_path=public as $$
declare
  v_country text;
  v_manual_onboarding boolean:=false;
  v_document_verified boolean:=false;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  if p_status not in ('pending','approved','rejected','suspended') then
    raise exception 'Estado de conductor inválido';
  end if;

  if p_status='approved' then
    select upper(coalesce(p.country_code,'')) into v_country
    from public.driver_profiles p where p.id=p_user_id;
    if v_country='BO' then
      -- Applies only to new Express-manual onboarding, not legacy registrations.
      select exists(
        select 1 from public.identity_verifications i
        where i.user_id=p_user_id and i.subject_role='driver'
          and i.provider='express_manual'
          and i.document_type='driver_onboarding'
      ) into v_manual_onboarding;

      if v_manual_onboarding then
        select exists(
          select 1
          from public.driver_documents d
          join public.driver_document_requirements r
            on r.id=d.requirement_id
          where d.driver_id=p_user_id
            and d.verification_method='manual'
            and d.status='verified'
            and lower(r.code) in
              ('identity_card','national_id','id_card','identity','carnet','cedula','cédula')
            and nullif(trim(coalesce(d.document_number,'')),'') is not null
            and nullif(trim(coalesce(d.front_object_path,'')),'') is not null
            and nullif(trim(coalesce(d.back_object_path,'')),'') is not null
            and nullif(trim(coalesce(d.selfie_object_path,'')),'') is not null
        ) into v_document_verified;
        if not v_document_verified then
          raise exception
            'No se puede aprobar el conductor: identidad manual pendiente de revisión';
        end if;
      end if;
    end if;
  end if;

  update public.driver_profiles
  set approval_status=p_status,
      online_status=case when p_status='approved' then online_status else 'offline' end,
      updated_at=now()
  where id=p_user_id;
  if not found then raise exception 'Conductor no encontrado'; end if;

  insert into public.notifications(user_id,title,body,type)
  values(
    p_user_id,'Estado de conductor',
    case p_status
      when 'approved' then
        'Tu cuenta de conductor fue aprobada. Ya puedes ponerte en línea.'
      when 'rejected' then
        'Tu solicitud de conductor fue rechazada. Revisa tus datos antes de volver a solicitar.'
      when 'suspended' then
        'Tu cuenta de conductor fue suspendida temporalmente.'
      else
        'Tu cuenta de conductor quedó pendiente de revisión.'
    end,
    'driver_approval'
  );

  perform public.admin_log_action(
    'set_driver_approval','driver_profile',p_user_id::text,
    jsonb_build_object('status',p_status)
  );
end;
$$;
