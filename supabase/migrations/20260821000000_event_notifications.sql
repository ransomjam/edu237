-- =============================================================================
-- Camiva - a reminder for every event, and push for every reminder
-- =============================================================================
--
-- THE SHAPE
-- -----------------------------------------------------------------------------
-- Every notifiable event writes one row into payment_reminders. That row IS the
-- in-app notification. A database webhook on INSERT then hands the row to the
-- push-fanout Edge Function, which sends the push and records what happened.
--
-- One path, one place to look:
--
--   event -> payment_reminders row -> webhook -> push-fanout -> FCM
--
-- Push used to be wired to a single admin action, so every other event was
-- silent. Putting the fanout on the table means anything that creates a
-- reminder is notified automatically - including reminders added later, with no
-- further wiring.
--
-- WHAT IS ADDED HERE
-- -----------------------------------------------------------------------------
-- Reminder rows for the events that had none: a teacher request arriving, a
-- request being accepted or declined, and a lesson being scheduled. These are
-- written by TRIGGERS rather than by the app, so a notification cannot be
-- missed because a screen forgot to send one.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. The kinds
-- -----------------------------------------------------------------------------
-- Every definition of this constraint carries the same list. A narrower one
-- fails on re-run once rows of the newer kinds exist.
-- -----------------------------------------------------------------------------

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
                  'withdrawal_update',
                  'request_received',
                  'request_answered',
                  'lesson_scheduled'));


-- -----------------------------------------------------------------------------
-- 2. A teacher request arriving
-- -----------------------------------------------------------------------------
-- The teacher learns immediately, without opening the app. The child's name is
-- already visible to the teacher through the request itself, so nothing new is
-- revealed here.
-- -----------------------------------------------------------------------------

create or replace function public.notify_teacher_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_child text;
begin
  select s.name into v_child from public.students s where s.id = new.student_id;

  insert into public.payment_reminders (user_id, kind, title, body)
  values (new.teacher_id, 'request_received', 'New tutoring request',
          coalesce(v_child, 'A parent') ||
            ' would like you as a teacher. Open your requests to reply.');
  return new;
end;
$$;

drop trigger if exists teacher_requests_notify_insert on public.teacher_requests;
create trigger teacher_requests_notify_insert
  after insert on public.teacher_requests
  for each row execute function public.notify_teacher_request();


-- -----------------------------------------------------------------------------
-- 3. A request being answered
-- -----------------------------------------------------------------------------
create or replace function public.notify_request_answered()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_child text;
begin
  if new.status is not distinct from old.status then
    return new;
  end if;
  if new.status not in ('accepted', 'declined') then
    return new;
  end if;

  select s.name into v_child from public.students s where s.id = new.student_id;

  insert into public.payment_reminders (user_id, kind, title, body)
  values (
    new.parent_id,
    'request_answered',
    case when new.status = 'accepted'
         then 'Teacher accepted' else 'Teacher declined' end,
    case when new.status = 'accepted'
         then 'Your teacher accepted ' || coalesce(v_child, 'your child') ||
              '. They will send the tutoring details next.'
         else 'Your request for ' || coalesce(v_child, 'your child') ||
              ' was declined. You can find another teacher.'
    end);
  return new;
end;
$$;

drop trigger if exists teacher_requests_notify_answer on public.teacher_requests;
create trigger teacher_requests_notify_answer
  after update on public.teacher_requests
  for each row execute function public.notify_request_answered();


-- -----------------------------------------------------------------------------
-- 4. A lesson being scheduled
-- -----------------------------------------------------------------------------
-- Only where scheduling exists on this project.
-- -----------------------------------------------------------------------------

do $$
begin
  if to_regclass('public.lesson_sessions') is null then
    return;
  end if;

  execute $fn$
    create or replace function public.notify_lesson_scheduled()
    returns trigger
    language plpgsql
    security definer
    set search_path = public
    as $body$
    begin
      insert into public.payment_reminders
        (user_id, kind, title, body, relationship_id)
      values (
        new.parent_id, 'lesson_scheduled', 'Lesson scheduled',
        coalesce(new.student_name, 'Your child') || ' · ' || new.subject ||
          ' · ' || to_char(new.scheduled_at, 'DD Mon at HH24:MI'),
        new.relationship_id);
      return new;
    end;
    $body$;
  $fn$;

  execute 'drop trigger if exists lesson_sessions_notify on public.lesson_sessions';
  execute 'create trigger lesson_sessions_notify
             after insert on public.lesson_sessions
             for each row execute function public.notify_lesson_scheduled()';
end $$;


-- -----------------------------------------------------------------------------
-- 5. What the push fanout reads
-- -----------------------------------------------------------------------------
-- Service-role only: it returns another person's device tokens, which nothing
-- client-side may ever see.
-- -----------------------------------------------------------------------------

create or replace function public.reminder_for_push(p_reminder_id uuid)
returns table (
  id      uuid,
  user_id uuid,
  kind    text,
  title   text,
  body    text,
  tokens  text[]
)
language sql
stable
security definer
set search_path = public
as $$
  select r.id, r.user_id, r.kind, r.title, r.body,
         coalesce(
           array(select t.token from public.device_push_tokens t
                  where t.user_id = r.user_id),
           '{}'::text[])
    from public.payment_reminders r
   where r.id = p_reminder_id;
$$;

revoke execute on function
  public.reminder_for_push(uuid) from public, anon, authenticated;


-- A token FCM reports as dead is removed, so it is not retried forever.
create or replace function public.forget_dead_push_token(p_token text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.device_push_tokens where token = p_token;
$$;

revoke execute on function
  public.forget_dead_push_token(text) from public, anon, authenticated;
