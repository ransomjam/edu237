-- =============================================================================
-- Camiva - teacher verification (trust gate, not a revenue gate)
-- =============================================================================
--
-- A teacher submits an identity document and a qualification document. Camiva
-- reviews them remotely - there is no in-person requirement.
--
-- Statuses, and what each one honestly means:
--   'required'  nothing submitted yet
--   'pending'   documents submitted, Camiva has not reviewed them
--   'verified'  an Camiva admin approved them
--   'rejected'  an admin asked for a correction, with a reason
--
-- A teacher is NEVER called verified before an admin approves. Submitting
-- moves them to 'pending' and no further; only admin_review_verification()
-- can write 'verified', and it is admin-only.
--
-- Verification gates the tutoring relationship, NOT payment. It comes before
-- the Platform Charge in the flow because Camiva should not take money to
-- activate a teacher it has not checked.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Private bucket for the documents
-- -----------------------------------------------------------------------------
-- Unlike profile photos, these are identity documents: the bucket is PRIVATE,
-- and nobody can read another teacher's files. Admin review happens through
-- signed URLs generated server-side.
-- -----------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('verification-docs', 'verification-docs', false)
on conflict (id) do nothing;

drop policy if exists "verification-docs: owner can read" on storage.objects;
create policy "verification-docs: owner can read"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'verification-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "verification-docs: admin can read" on storage.objects;
create policy "verification-docs: admin can read"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'verification-docs'
    and public.is_platform_admin()
  );

drop policy if exists "verification-docs: owner can insert" on storage.objects;
create policy "verification-docs: owner can insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'verification-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "verification-docs: owner can update" on storage.objects;
create policy "verification-docs: owner can update"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'verification-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- No delete policy: a submitted document stays until Camiva removes it.


-- -----------------------------------------------------------------------------
-- 2. teacher_verifications
-- -----------------------------------------------------------------------------

create table if not exists public.teacher_verifications (
  teacher_id        uuid        primary key references auth.users (id) on delete cascade,
  status            text        not null default 'required'
                      constraint teacher_verifications_status_check
                      check (status in ('required', 'pending', 'verified', 'rejected')),

  -- Storage paths inside the private bucket, never public URLs.
  identity_doc_path      text,
  identity_doc_type      text
                           constraint teacher_verifications_id_type_check
                           check (identity_doc_type is null
                                  or identity_doc_type in ('national_id', 'passport',
                                                           'drivers_licence')),
  qualification_doc_path text,
  qualification_title    text,

  submitted_at      timestamptz,
  reviewed_at       timestamptz,
  reviewed_by       uuid        references auth.users (id) on delete set null,
  rejection_reason  text,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists teacher_verifications_status_idx
  on public.teacher_verifications (status);

drop trigger if exists teacher_verifications_set_updated_at on public.teacher_verifications;
create trigger teacher_verifications_set_updated_at
  before update on public.teacher_verifications
  for each row execute function public.set_updated_at();

alter table public.teacher_verifications enable row level security;

-- A teacher reads their own record; admins read all. A parent never sees
-- another person's documents or review notes.
drop policy if exists "verification: owner can select" on public.teacher_verifications;
create policy "verification: owner can select"
  on public.teacher_verifications
  for select
  to authenticated
  using (auth.uid() = teacher_id or public.is_platform_admin());

-- Deliberately no insert/update policy: submission and review both go through
-- the functions below, so a teacher can never write their own 'verified'.
grant select on public.teacher_verifications to authenticated;


-- -----------------------------------------------------------------------------
-- 3. Submitting documents
-- -----------------------------------------------------------------------------
-- Moves the teacher to 'pending' and nothing further. Re-submitting after a
-- rejection is allowed and clears the previous decision.
-- -----------------------------------------------------------------------------

create or replace function public.submit_teacher_verification(
  p_identity_doc_path      text,
  p_identity_doc_type      text,
  p_qualification_doc_path text,
  p_qualification_title    text default null
)
returns public.teacher_verifications
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.teacher_verifications;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;
  if coalesce(btrim(p_identity_doc_path), '') = '' then
    raise exception 'An identity document is required';
  end if;
  if coalesce(btrim(p_qualification_doc_path), '') = '' then
    raise exception 'A qualification document is required';
  end if;

  insert into public.teacher_verifications
    (teacher_id, status, identity_doc_path, identity_doc_type,
     qualification_doc_path, qualification_title, submitted_at,
     reviewed_at, reviewed_by, rejection_reason)
  values
    (v_uid, 'pending', p_identity_doc_path, p_identity_doc_type,
     p_qualification_doc_path, nullif(btrim(coalesce(p_qualification_title, '')), ''),
     now(), null, null, null)
  on conflict (teacher_id) do update
    set status                 = 'pending',
        identity_doc_path      = excluded.identity_doc_path,
        identity_doc_type      = excluded.identity_doc_type,
        qualification_doc_path = excluded.qualification_doc_path,
        qualification_title    = excluded.qualification_title,
        submitted_at           = now(),
        reviewed_at            = null,
        reviewed_by            = null,
        rejection_reason       = null
    -- A teacher who is already verified stays verified; re-submitting does not
    -- knock them back to pending.
    where teacher_verifications.status <> 'verified'
  returning * into v_row;

  if v_row is null then
    select * into v_row from public.teacher_verifications where teacher_id = v_uid;
  end if;
  return v_row;
end;
$$;

revoke execute on function
  public.submit_teacher_verification(text, text, text, text) from public, anon;
grant execute on function
  public.submit_teacher_verification(text, text, text, text) to authenticated;


-- The signed-in teacher's own status. Returns 'required' when nothing exists
-- yet, so the app never has to guess.
create or replace function public.my_verification_status()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select v.status from public.teacher_verifications v
      where v.teacher_id = auth.uid()),
    'required'
  );
$$;

grant execute on function public.my_verification_status() to authenticated;


create or replace function public.is_teacher_verified(p_teacher_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.teacher_verifications v
     where v.teacher_id = p_teacher_id and v.status = 'verified'
  );
$$;

grant execute on function public.is_teacher_verified(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- 4. Admin review
-- -----------------------------------------------------------------------------
-- Reviews notify the teacher through the existing in-app reminder inbox, so a
-- verification kind is added rather than borrowing an unrelated one.
alter table public.payment_reminders
  drop constraint if exists payment_reminders_kind_check;
alter table public.payment_reminders
  add constraint payment_reminders_kind_check
  check (kind in ('payment_received',
                  'payment_failed',
                  'payment_due',
                  'service_fee_due',
                  'service_fee_overdue',
                  'relationship_activated',
                  'verification_update',
                  'agreement_update',
                  'withdrawal_update'));


create or replace function public.admin_pending_verifications()
returns table (
  teacher_id             uuid,
  teacher_name           text,
  identity_doc_path      text,
  identity_doc_type      text,
  qualification_doc_path text,
  qualification_title    text,
  submitted_at           timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Not authorised';
  end if;

  return query
    select v.teacher_id, p.name, v.identity_doc_path, v.identity_doc_type,
           v.qualification_doc_path, v.qualification_title, v.submitted_at
      from public.teacher_verifications v
      left join public.user_profiles p on p.id = v.teacher_id
     where v.status = 'pending'
     order by v.submitted_at asc;
end;
$$;

revoke execute on function public.admin_pending_verifications() from public, anon;
grant execute on function public.admin_pending_verifications() to authenticated;


create or replace function public.admin_review_verification(
  p_teacher_id uuid,
  p_approve    boolean,
  p_reason     text default null
)
returns public.teacher_verifications
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row    public.teacher_verifications;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public.is_platform_admin() then
    raise exception 'Not authorised';
  end if;
  if not p_approve and v_reason is null then
    raise exception 'A reason is required when asking for a correction';
  end if;

  update public.teacher_verifications
     set status           = case when p_approve then 'verified' else 'rejected' end,
         reviewed_at      = now(),
         reviewed_by      = auth.uid(),
         rejection_reason = case when p_approve then null else v_reason end
   where teacher_id = p_teacher_id
     and status = 'pending'
  returning * into v_row;

  if not found then
    select * into v_row from public.teacher_verifications where teacher_id = p_teacher_id;
    return v_row;
  end if;

  insert into public.payment_reminders
    (user_id, kind, title, body)
  values
    (p_teacher_id, 'verification_update',
     case when p_approve then 'You are verified' else 'Verification needs a correction' end,
     case when p_approve
          then 'Camiva has approved your documents. You can now set up tutoring.'
          else v_reason end);

  return v_row;
end;
$$;

revoke execute on function
  public.admin_review_verification(uuid, boolean, text) from public, anon;
grant execute on function
  public.admin_review_verification(uuid, boolean, text) to authenticated;
