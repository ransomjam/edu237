-- =============================================================================
-- Camiva — profile-photos Supabase Storage bucket + RLS
-- =============================================================================
--
-- Creates a dedicated storage bucket for teacher (and future parent) profile
-- photos. The bucket is PUBLIC so that profile photos can be displayed on
-- public teacher profiles without signed URLs.
--
-- RLS policies:
--   * Anyone (including anonymous) may READ objects — profile photos are
--     intentionally public content.
--   * Only an authenticated user may INSERT / UPDATE / DELETE files under
--     their own path prefix ({user_id}/…). This prevents one user from
--     modifying another's photo.
--
-- The client stores the resulting public URL (or storage path) in the
-- teacher_profiles.photo_url column (already present from an earlier
-- migration).
--
-- Additive only: no existing tables or data are modified.
-- =============================================================================

-- 1. Create the bucket (idempotent — Supabase ignores if it already exists)
insert into storage.buckets (id, name, public)
values ('profile-photos', 'profile-photos', true)
on conflict (id) do nothing;

-- 2. RLS policies on storage.objects for this bucket

-- Allow anyone to read profile photos (they are public content).
drop policy if exists "profile-photos: public read" on storage.objects;
create policy "profile-photos: public read"
  on storage.objects
  for select
  using (bucket_id = 'profile-photos');

-- Allow authenticated users to upload their own photo (path must start with
-- their auth.uid()).
drop policy if exists "profile-photos: owner can insert" on storage.objects;
create policy "profile-photos: owner can insert"
  on storage.objects
  for insert
  with check (
    bucket_id = 'profile-photos'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Allow authenticated users to update (replace) their own photo.
drop policy if exists "profile-photos: owner can update" on storage.objects;
create policy "profile-photos: owner can update"
  on storage.objects
  for update
  using (
    bucket_id = 'profile-photos'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Allow authenticated users to delete their own photo.
drop policy if exists "profile-photos: owner can delete" on storage.objects;
create policy "profile-photos: owner can delete"
  on storage.objects
  for delete
  using (
    bucket_id = 'profile-photos'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );
