-- =============================================================================
-- Camiva — add students.subjects
-- =============================================================================
--
-- Adds the child's current subject profile (a subset of the Cameroon GCE
-- Ordinary Level catalogue) to the students table.
--
-- Representation: a Postgres text[] on the students row. Subjects are a small,
-- always-loaded-with-the-child attribute with no independent lifecycle, so an
-- array column fits the existing single-table, RLS-scoped architecture more
-- cleanly than a join table. No new RLS is needed — the column is covered by
-- the existing students policies.
--
-- Existing rows (e.g. the "Grace / Form 3" test child) are backfilled with an
-- empty array via the DEFAULT, so this migration is non-destructive.
-- =============================================================================

alter table public.students
  add column if not exists subjects text[] not null default '{}';
