-- =============================================================================
-- Camiva — teacher_profiles title field (additive)
-- =============================================================================
--
-- Adds honorific title (e.g. 'Mr', 'Mrs', 'Ms', 'Dr', 'Prof', 'Engr') to
-- teacher profiles. Nullable, optional, and defaults to null.
-- =============================================================================

alter table public.teacher_profiles
  add column if not exists title text;
