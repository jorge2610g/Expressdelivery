-- Express Envíos fields and private photographs. Existing Taxi and Marketplace untouched.
alter table public.delivery_requests
  add column if not exists sender_name text,
  add column if not exists sender_phone text,
  add column if not exists recipient_name text,
  add column if not exists recipient_phone text,
  add column if not exists parcel_photo_paths text[] not null default '{}';

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('parcel-evidence','parcel-evidence',false,5242880,
   array['image/jpeg','image/png','image/webp'])
on conflict(id) do nothing;

drop policy if exists parcel_evidence_owner_upload on storage.objects;
create policy parcel_evidence_owner_upload on storage.objects
 for insert to authenticated with check (
   bucket_id='parcel-evidence' and name like (auth.uid()::text || '/%')
 );
drop policy if exists parcel_evidence_owner_read on storage.objects;
create policy parcel_evidence_owner_read on storage.objects
 for select to authenticated using (
   bucket_id='parcel-evidence' and (
     name like (auth.uid()::text || '/%')
     or exists(
       select 1 from public.delivery_requests d
       where d.courier_id=auth.uid() and d.status not in ('cancelled')
        and objects.name=any(d.parcel_photo_paths)
     )
   )
 );
