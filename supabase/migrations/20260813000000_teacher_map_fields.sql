-- =============================================================================
-- Camiva — teacher_profiles map/discovery fields (additive)
-- =============================================================================
--
-- Extends the teacher location foundation (city, area) with the minimum needed
-- for the Teacher Discovery map + relevance experience:
--
--   * latitude / longitude — APPROXIMATE coordinates of the teacher's
--     teaching/service area. These are intentionally coarse and MUST NOT hold a
--     precise residential location. They are optional: a teacher with only a
--     city/area still appears in discovery (List view always; on the map via a
--     client-side city gazetteer fallback).
--   * teaching_mode — 'online' | 'in_person' | 'both'. Lets a parent instantly
--     see whether a teacher can teach physically, remotely, or either.
--   * photo_url — optional avatar photo; discovery falls back to initials.
--
-- All columns are nullable / defaulted, so existing rows are preserved.
--
-- RLS: NO changes. These columns are teacher-owned profile fields covered by
-- the existing teacher_profiles policies:
--   * any authenticated user may READ (discovery),
--   * only the owner (auth.uid() = user_id) may INSERT/UPDATE.
-- Parents can therefore read the coarse location for discovery but can never
-- write it, and no precise residential address is ever stored or exposed.
-- =============================================================================

alter table public.teacher_profiles
  add column if not exists latitude double precision;

alter table public.teacher_profiles
  add column if not exists longitude double precision;

alter table public.teacher_profiles
  add column if not exists teaching_mode text not null default 'in_person';

alter table public.teacher_profiles
  add column if not exists photo_url text;

-- Keep teaching_mode to the known set. Defensive; the app only ever writes
-- these three values.
alter table public.teacher_profiles
  drop constraint if exists teacher_profiles_teaching_mode_check;
alter table public.teacher_profiles
  add constraint teacher_profiles_teaching_mode_check
  check (teaching_mode in ('online', 'in_person', 'both'));
