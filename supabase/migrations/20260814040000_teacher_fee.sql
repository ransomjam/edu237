-- =============================================================================
-- Camiva — teacher_profiles hourly_rate field (additive)
-- =============================================================================
alter table public.teacher_profiles
  add column if not exists hourly_rate integer not null default 5000;
