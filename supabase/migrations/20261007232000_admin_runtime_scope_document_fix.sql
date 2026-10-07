-- Correct scoped document wrapper return type to match legacy RPC.

drop function if exists public.admin_upsert_driver_document_v2(
  uuid,uuid,text,text,text,text,timestamptz,text,text
);

create function public.admin_upsert_driver_document_v2(
  p_document_id uuid,
  p_driver_id uuid,
  p_document_type text,
  p_document_number text,
  p_document_url text,
  p_status text,
  p_expires_at timestamptz,
  p_notes text,
  p_channel text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_document jsonb;
begin
  perform public.admin_assert_target_environment(p_driver_id,p_channel);
  v_document := public.admin_upsert_driver_document(
    p_document_id,p_driver_id,p_document_type,p_document_number,p_document_url,
    p_status,p_expires_at,p_notes
  );
  perform public.admin_log_action(
    'admin_scope_confirmed','driver_document',
    coalesce(v_document->>'id',p_document_id::text),
    jsonb_build_object(
      'environment',lower(trim(p_channel)),
      'driver_id',p_driver_id
    )
  );
  return v_document;
end;
$function$;

grant execute on function public.admin_upsert_driver_document_v2(
  uuid,uuid,text,text,text,text,timestamptz,text,text
) to authenticated;
