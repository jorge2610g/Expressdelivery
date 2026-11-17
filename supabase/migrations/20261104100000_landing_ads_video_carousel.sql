-- Own advertising carousel for the passenger home (no AdMob).
-- Extends passenger_landing_banners with video, per-ad display time and the
-- advertiser record. Adds a lead table for the "Publicita tu marca" page.
-- Additive only: existing image banners keep working unchanged.
begin;

alter table public.passenger_landing_banners
  add column if not exists media_type text not null default 'image'
    check (media_type in ('image','video')),
  add column if not exists media_url text,
  add column if not exists display_seconds integer not null default 5
    check (display_seconds between 3 and 60),
  add column if not exists advertiser_name text not null default ''
    check (char_length(advertiser_name) <= 80),
  add column if not exists advertiser_contact text not null default ''
    check (char_length(advertiser_contact) <= 120),
  add column if not exists amount_bs numeric(12,2)
    check (amount_bs is null or amount_bs >= 0),
  add column if not exists payment_status text not null default 'unpaid'
    check (payment_status in ('unpaid','paid','exempt'));

alter table public.passenger_landing_banners
  add constraint landing_banner_video_needs_https_media
  check (media_type = 'image' or (media_url is not null and media_url ~ '^https://'));

-- Videos are allowed in the same public bucket. Short clips only (30 MB).
update storage.buckets
set allowed_mime_types = array['image/jpeg','image/png','image/webp','video/mp4','video/webm'],
    file_size_limit = 31457280
where id = 'express-landing-banners';

-- Public "Publicita tu marca" leads. Anonymous users can only send a lead
-- through the RPC below; they cannot read the table.
create table if not exists public.ad_inquiries (
  id uuid primary key default gen_random_uuid(),
  company text not null check (char_length(trim(company)) between 2 and 120),
  contact_name text not null default '' check (char_length(contact_name) <= 120),
  phone text not null default '' check (char_length(phone) <= 30),
  email text not null default '' check (char_length(email) <= 160),
  message text not null default '' check (char_length(message) <= 1000),
  status text not null default 'new' check (status in ('new','contacted','closed')),
  created_at timestamptz not null default now()
);

alter table public.ad_inquiries enable row level security;
revoke all on table public.ad_inquiries from public, anon, authenticated;

create or replace function public.submit_ad_inquiry(
  p_company text,
  p_contact_name text,
  p_phone text,
  p_email text,
  p_message text
) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if char_length(trim(coalesce(p_company,''))) < 2 then
    raise exception 'Indica el nombre de tu empresa o marca';
  end if;
  if coalesce(p_email,'') = '' and coalesce(p_phone,'') = '' then
    raise exception 'Deja un correo o un teléfono para contactarte';
  end if;
  insert into public.ad_inquiries(company, contact_name, phone, email, message)
  values (trim(p_company), trim(coalesce(p_contact_name,'')), trim(coalesce(p_phone,'')),
          trim(coalesce(p_email,'')), trim(coalesce(p_message,'')));
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.submit_ad_inquiry(text,text,text,text,text) from public;
grant execute on function public.submit_ad_inquiry(text,text,text,text,text) to anon, authenticated;

commit;
