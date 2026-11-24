-- =============================================================================
-- Camiva - admin billing overview, parent reminders, push foundation
-- =============================================================================
--
-- WHAT IS AND IS NOT CLAIMED HERE
-- -----------------------------------------------------------------------------
-- An in-app reminder IS delivered the moment its row exists: the parent sees it
-- in the app. A PUSH notification is a separate thing that needs a device token
-- and a configured sender, so it is recorded separately and honestly:
--
--   push_status = 'not_attempted'   nothing tried yet
--                 'sent'            the push service accepted it
--                 'no_device'       the parent has no registered device
--                 'not_configured'  no push credentials on this project
--                 'failed'          the push service rejected it
--
-- Nothing in the app says "reminder sent" on the strength of a row existing.
-- The admin is told exactly which of the two happened.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Reminders gain a payment-due kind and a truthful push record
-- -----------------------------------------------------------------------------

alter table public.payment_reminders
  add column if not exists push_status text not null default 'not_attempted',
  add column if not exists push_at     timestamptz,
  add column if not exists sent_by     uuid references auth.users (id) on delete set null;

alter table public.payment_reminders
  drop constraint if exists payment_reminders_push_status_check;
alter table public.payment_reminders
  add constraint payment_reminders_push_status_check
  check (push_status in ('not_attempted', 'sent', 'no_device',
                         'not_configured', 'failed'));

-- The full set of kinds, including the ones added by later migrations. A
-- narrower list here would fail on re-run once rows of those later kinds exist,
-- so every definition of this constraint carries the same list.
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

-- The guard allowed only read_at to change; push fields are written by the
-- server after the row exists, so they are now writable too - still never the
-- text of the reminder.
create or replace function public.payment_reminders_guard()
returns trigger
language plpgsql
as $$
begin
  if new.id                is distinct from old.id
     or new.user_id        is distinct from old.user_id
     or new.kind           is distinct from old.kind
     or new.title          is distinct from old.title
     or new.body           is distinct from old.body
     or new.payment_id     is distinct from old.payment_id
     or new.relationship_id is distinct from old.relationship_id
     or new.withdrawal_id  is distinct from old.withdrawal_id
     or new.created_at     is distinct from old.created_at
     or new.sent_by        is distinct from old.sent_by
  then
    raise exception 'payment_reminders: only read_at and push state may change';
  end if;
  return new;
end;
$$;


-- -----------------------------------------------------------------------------
-- 2. Device tokens for push
-- -----------------------------------------------------------------------------
-- Owned entirely by the user they belong to. Nobody can read another person's
-- device token; the sender runs with the service role.
-- -----------------------------------------------------------------------------

create table if not exists public.device_push_tokens (
  token        text        primary key,
  user_id      uuid        not null references auth.users (id) on delete cascade,
  platform     text        not null default 'android'
                 constraint device_push_tokens_platform_check
                 check (platform in ('android', 'ios', 'web')),
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create index if not exists device_push_tokens_user_idx
  on public.device_push_tokens (user_id);

alter table public.device_push_tokens enable row level security;

drop policy if exists "tokens: owner can select" on public.device_push_tokens;
create policy "tokens: owner can select"
  on public.device_push_tokens for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists "tokens: owner can insert" on public.device_push_tokens;
create policy "tokens: owner can insert"
  on public.device_push_tokens for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "tokens: owner can update" on public.device_push_tokens;
create policy "tokens: owner can update"
  on public.device_push_tokens for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "tokens: owner can delete" on public.device_push_tokens;
create policy "tokens: owner can delete"
  on public.device_push_tokens for delete to authenticated
  using (auth.uid() = user_id);

grant select, insert, update, delete on public.device_push_tokens to authenticated;


-- -----------------------------------------------------------------------------
-- 3. Admin billing overview
-- -----------------------------------------------------------------------------
-- One row per active monthly arrangement: who owes what, and by when. Derived
-- from relationship_billing_summary(), so it agrees with what the parent sees.
-- -----------------------------------------------------------------------------

create or replace function public.admin_billing_overview()
returns table (
  relationship_id  uuid,
  parent_id        uuid,
  parent_name      text,
  teacher_name     text,
  child_name       text,
  monthly_amount   integer,
  paid_this_period integer,
  balance          integer,
  currency         text,
  started_on       date,
  next_due_on      date,
  last_paid_at     timestamptz,
  last_reminded_at timestamptz
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
    select b.relationship_id,
           b.parent_id,
           parent.name,
           teacher.name,
           s.name,
           sum.monthly_amount,
           sum.paid_this_period,
           sum.balance,
           sum.currency,
           sum.started_on,
           sum.next_due_on,
           sum.last_paid_at,
           (select max(r.created_at) from public.payment_reminders r
             where r.relationship_id = b.relationship_id
               and r.kind = 'payment_due')
      from public.relationship_billing b
      join public.parent_teacher_relationships rel on rel.id = b.relationship_id
      left join public.user_profiles parent  on parent.id  = b.parent_id
      left join public.user_profiles teacher on teacher.id = b.teacher_id
      left join public.students s            on s.id       = rel.student_id
      cross join lateral public.relationship_billing_summary(b.relationship_id) sum
     where b.active
     order by sum.balance desc, sum.next_due_on asc;
end;
$$;

revoke execute on function public.admin_billing_overview() from public, anon;
grant execute on function public.admin_billing_overview() to authenticated;


-- -----------------------------------------------------------------------------
-- 4. Creating a payment reminder
-- -----------------------------------------------------------------------------
-- Service-role only: the reminder is created by the send-reminder function,
-- which then attempts push and records what actually happened. Creating it here
-- and pushing separately is what keeps the two claims honest.
-- -----------------------------------------------------------------------------

create or replace function public.create_payment_due_reminder(
  p_relationship_id uuid,
  p_sent_by         uuid default null,
  p_message         text default null
)
returns public.payment_reminders
language plpgsql
security definer
set search_path = public
as $$
declare
  rel     public.parent_teacher_relationships;
  v_child text;
  v_row   public.payment_reminders;
  v_bal   integer;
  v_cur   text;
  v_due   date;
  v_body  text;
begin
  select * into rel from public.parent_teacher_relationships where id = p_relationship_id;
  if not found then
    raise exception 'Relationship not found';
  end if;

  select s.name into v_child from public.students s where s.id = rel.student_id;
  select balance, currency, next_due_on into v_bal, v_cur, v_due
    from public.relationship_billing_summary(p_relationship_id);

  v_body := coalesce(
    nullif(btrim(coalesce(p_message, '')), ''),
    coalesce(v_child, 'Your child') || ' - ' ||
      to_char(coalesce(v_bal, 0), 'FM999G999G999') || ' ' || coalesce(v_cur, 'XAF') ||
      ' left for this month' ||
      case when v_due is not null
           then ', due ' || to_char(v_due, 'DD Mon YYYY') else '' end
  );

  insert into public.payment_reminders
    (user_id, kind, title, body, relationship_id, sent_by)
  values
    (rel.parent_id, 'payment_due', 'Tutoring payment reminder', v_body,
     p_relationship_id, p_sent_by)
  returning * into v_row;

  return v_row;
end;
$$;

revoke execute on function
  public.create_payment_due_reminder(uuid, uuid, text) from public, anon, authenticated;


-- Records what the push attempt actually did. Service-role only.
create or replace function public.record_reminder_push(
  p_reminder_id uuid,
  p_status      text
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.payment_reminders
     set push_status = p_status,
         push_at = case when p_status = 'sent' then now() else push_at end
   where id = p_reminder_id;
$$;

revoke execute on function
  public.record_reminder_push(uuid, text) from public, anon, authenticated;


-- The devices to push to. Service-role only - device tokens are never exposed
-- to another user.
create or replace function public.push_tokens_for_user(p_user_id uuid)
returns table (token text, platform text)
language sql
stable
security definer
set search_path = public
as $$
  select t.token, t.platform from public.device_push_tokens t
   where t.user_id = p_user_id;
$$;

revoke execute on function
  public.push_tokens_for_user(uuid) from public, anon, authenticated;
