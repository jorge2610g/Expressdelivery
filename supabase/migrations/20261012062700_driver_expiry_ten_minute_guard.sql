-- Safety: run at every ten-minute boundary, including local midnight
-- (Chile/Bolivia/Peru use whole-hour UTC offsets). All costly work is limited
-- to Preview through driver_expiration_channel_settings.
do $expiration_frequency$
declare v_job_id bigint;
begin
  select jobid into v_job_id
    from cron.job where jobname='driver-document-expiry-hourly';
  if v_job_id is not null then
    perform cron.alter_job(v_job_id,
      schedule=>'*/10 * * * *');
  end if;
end;
$expiration_frequency$;
