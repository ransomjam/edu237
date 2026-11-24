-- =============================================================================
-- Camiva — Add cover_photo_url to teacher_profiles
-- =============================================================================
-- Allows teachers to personalize their profile banner/cover photo with an image
-- of their choice, falling back to the standard classroom illustration when null.

alter table public.teacher_profiles
  add column if not exists cover_photo_url text;

-- Notify PostgREST to reload its schema cache so the new column is immediately
-- available for reads and writes via the API.
notify pgrst, 'reload schema';
