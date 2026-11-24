-- =============================================================================
-- Camiva — teacher_profiles location (additive)
-- =============================================================================
--
-- Adds coarse location to teacher profiles so parents can see roughly where a
-- teacher is based (and, later, discover nearby teachers). Only a city and a
-- neighbourhood/area are stored — never a precise street address. Both are
-- optional and nullable, so existing rows are preserved unchanged.
--
-- No RLS changes: these columns are covered by the existing teacher_profiles
-- policies (any authenticated user may read; only the owner may write).
-- =============================================================================

alter table public.teacher_profiles
  add column if not exists city text;

alter table public.teacher_profiles
  add column if not exists area text;
