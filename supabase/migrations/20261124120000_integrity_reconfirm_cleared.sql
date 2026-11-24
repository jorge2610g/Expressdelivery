-- Una irregularidad descartada se puede volver a confirmar. Como al descartar se revirtió la
-- advertencia del conductor, al confirmar de nuevo esa advertencia vuelve a sumar (tope 3). Si la
-- irregularidad había generado una suspensión o un escalamiento, no se reaplica sola: se avisa que
-- debe hacerse desde las acciones del conductor.
do $m$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'admin_trip_integrity_review';
  v_new := replace(v_def, E'  update public.trip_integrity_flags\n     set review_status = p_decision',
E'  if p_decision = ''confirmed'' and f.review_status = ''cleared'' then\n    if f.action_taken in (''suspension'', ''escalation'') then\n      raise exception ''Esta irregularidad había generado una suspensión o un escalamiento que se levantó. Para volver a aplicarlo usa las acciones del conductor.'';\n    elsif f.action_taken = ''warning'' then\n      update public.driver_integrity_state\n         set warnings_in_cycle = least(3, warnings_in_cycle + 1), updated_at = now()\n       where driver_id = f.driver_id;\n    end if;\n  end if;\n  update public.trip_integrity_flags\n     set review_status = p_decision');
  if v_new = v_def then raise exception 'No se pudo parchear admin_trip_integrity_review'; end if;
  execute v_new;
end $m$;
