-- =============================================================================
-- Camiva — teacher_availability (recurring weekly availability)
-- =============================================================================
--
-- A teacher declares when they are normally available to teach, as a simple
-- recurring weekly schedule: at most ONE window per weekday (e.g. "Monday
-- 4:00 PM – 8:00 PM"). A weekday with no row means "Unavailable".
--
-- Deliberately NOT a calendar: no dates, no recurrence engine, no exceptions.
-- Just the weekly shape that makes availability-aware scheduling possible.
--
-- Representation
--   * weekday       : 1..7 following Dart's DateTime.weekday (Mon=1 … Sun=7),
--                     so the client never has to remap.
--   * start_minute  : minutes from midnight, 0..1439 (e.g. 16:00 → 960).
--   * end_minute    : minutes from midnight, 1..1440 (end may be 24:00 = 1440).
--   * end_minute must be strictly greater than start_minute.
--   * At most one window per (teacher, weekday) — enforced by a unique index.
--
-- RLS
--   * Any authenticated user may READ availability (it is part of the public
--     teacher profile a parent uses to decide before requesting).
--   * Only the owning teacher may INSERT / UPDATE / DELETE their own rows.
--
-- Additive only: no existing table or data is modified.
-- =============================================================================

create table if not exists public.teacher_availability (
  id           uuid        primary key default gen_random_uuid(),
  teacher_id   uuid        not null references auth.users (id) on delete cascade,
  weekday      smallint    not null
                 constraint teacher_availability_weekday_check
                 check (weekday between 1 and 7),
  start_minute integer     not null
                 constraint teacher_availability_start_check
                 check (start_minute between 0 and 1439),
  end_minute   integer     not null
                 constraint teacher_availability_end_check
                 check (end_minute between 1 and 1440),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint teacher_availability_order_check
    check (end_minute > start_minute)
);

-- At most one window per teacher per weekday (MVP: a single daily window).
create unique index if not exists teacher_availability_teacher_weekday_unique
  on public.teacher_availability (teacher_id, weekday);

create index if not exists teacher_availability_teacher_idx
  on public.teacher_availability (teacher_id);

drop trigger if exists teacher_availability_set_updated_at on public.teacher_availability;
create trigger teacher_availability_set_updated_at
  before update on public.teacher_availability
  for each row execute function public.set_updated_at();

alter table public.teacher_availability enable row level security;

-- ---- SELECT: any authenticated user (discovery) ---------------------------
drop policy if exists "ta: authenticated can read" on public.teacher_availability;
create policy "ta: authenticated can read"
  on public.teacher_availability
  for select
  using (auth.uid() is not null);

-- ---- INSERT: owner only ----------------------------------------------------
drop policy if exists "ta: owner can insert" on public.teacher_availability;
create policy "ta: owner can insert"
  on public.teacher_availability
  for insert
  with check (auth.uid() = teacher_id);

-- ---- UPDATE: owner only ----------------------------------------------------
drop policy if exists "ta: owner can update" on public.teacher_availability;
create policy "ta: owner can update"
  on public.teacher_availability
  for update
  using (auth.uid() = teacher_id)
  with check (auth.uid() = teacher_id);

-- ---- DELETE: owner only ----------------------------------------------------
drop policy if exists "ta: owner can delete" on public.teacher_availability;
create policy "ta: owner can delete"
  on public.teacher_availability
  for delete
  using (auth.uid() = teacher_id);
