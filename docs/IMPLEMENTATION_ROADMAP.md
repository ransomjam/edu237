# Camiva — Implementation Roadmap

> This document defines the order in which Camiva will be built.
> Each phase must be complete and stable before the next begins.
> Do not skip phases. Do not build ahead of the current phase.

---

## ⚠️ Domain correction (2026-08-11)

Camiva is a **parent–teacher tutoring platform**, not a Google-Classroom-style
student app. **Parent** and **Teacher** are the only authenticated roles; a
**Student** is a managed learner record owned by a parent and never logs in.

The classroom phases below (join codes, class enrolment, materials,
assignments, submissions) are **retired**. The `Class` entity and its
join-code self-enrolment flow have been removed. Future phases will be
re-planned around the corrected model:

```
Parent → add student → find teacher → request → teacher accepts →
lessons → attendance/feedback → payment
```

Only the foundational correction (roles, Student entity, parent–teacher
relationship, auth/onboarding) has been implemented so far — see the status
table at the bottom. The per-phase descriptions that follow are historical
and describe the retired model.

---

## Guiding principle

Build along the core loop, in order:

```
Join → Access → Complete → Feedback
```

A user cannot join without auth. A user cannot access without a class.
A user cannot complete without assignments. Feedback closes the loop.
Every phase below serves this sequence.

---

## Phase 1 — Application shell

**Goal:** A working app with navigation, localisation foundation, and routing in place.
No real screens yet — just the skeleton the product will live inside.

### Deliverables
- Bottom navigation shell (role-aware: student vs teacher tabs)
- Placeholder screens for each tab (Home, Classes, Assignments, Profile)
- Localisation infrastructure (`AppLocalizations` or equivalent) with English strings
- Route structure updated to reflect all first-release screens
- `AppStrings` — central string constants for all user-facing text

### Done when
- The app launches, shows a bottom nav, and navigates between placeholder tabs
- All user-facing strings are defined centrally, not inline in widgets
- `flutter analyze` passes clean

---

## Phase 2 — Authentication

**Goal:** A real user can create an account and sign in.
Supabase Auth is integrated for the first time.

### Deliverables
- Supabase client initialised in `core/services/supabase_service.dart`
- `AuthService` — wraps Supabase Auth (register, login, logout, current session)
- Login screen
- Register screen
- Auth state listener — routes to Home if authenticated, Login if not
- Splash/entry screen that resolves auth state on launch

### Done when
- A new user can register with name, email, and password
- An existing user can log in
- An authenticated user is taken directly to Home on relaunch
- An unauthenticated user is taken to Login
- Logout works and returns the user to Login

---

## Phase 3 — Onboarding (role selection)

**Goal:** After registration, the user selects their primary role.
This determines their initial navigation experience.

### Deliverables
- Onboarding screen: "How will you use Camiva?" — Student / Teacher
- `activeRole` stored against the user (Supabase user metadata or profiles table)
- Navigation shell adapts based on active role
- Role is readable from a central place in the app (not scattered across widgets)

### Done when
- A newly registered user is asked to pick a role once
- The bottom nav reflects their role
- A returning user's role is restored from their session without asking again

---

## Phase 4 — Classes (teacher side)

**Goal:** A teacher can create a class and share the join code with students.

### Deliverables
- `ClassService` — create class, fetch teacher's classes
- Classes screen (teacher view): list of created classes + "Create class" action
- Create class screen: name, subject, optional description
- Class detail screen (teacher view): shows class info and join code prominently
- Join code is generated server-side (or a simple random code stored in the DB)

### Done when
- A teacher can create a class
- The class appears in their Classes list
- The join code is visible and copyable from the class detail screen

---

## Phase 5 — Classes (student side / join flow)

**Goal:** A student can join a class using a teacher's code.

### Deliverables
- Classes screen (student view): list of enrolled classes + "Join class" action
- Join class screen: enter code → confirm class name → join
- Enrolment written to the database
- Joined class appears in the student's Classes list

### Done when
- A student can enter a valid code and join the correct class
- An invalid code shows a clear error
- The class appears in the student's list after joining

---

## Phase 6 — Materials

**Goal:** A teacher can post materials. A student can read them.

### Deliverables
- `MaterialService` — post material, fetch materials for a class
- Class detail: Materials tab
- Post material screen (teacher): title, body text, optional link
- Material detail screen (student): read-only view of the material
- Empty state when no materials have been posted

### Done when
- A teacher can post a text-based material to a class
- A student enrolled in that class can see and read it
- A student not enrolled cannot access it (RLS enforced)

---

## Phase 7 — Assignments

**Goal:** A teacher can post assignments with deadlines. A student can see what is due.

### Deliverables
- `AssignmentService` — post assignment, fetch assignments for a class, fetch all assignments for a student
- Class detail: Assignments tab
- Post assignment screen (teacher): title, description, due date
- Assignment detail screen (student): title, description, due date, submission status
- Assignments tab (student): all assignments across all enrolled classes, sorted by due date
- Overdue assignments visually distinguished

### Done when
- A teacher can post an assignment with a due date
- A student sees it in their class and in their Assignments tab
- Due dates are displayed clearly
- Overdue items are visually distinct

---

## Phase 8 — Submission

**Goal:** A student can submit an assignment. The teacher can see who has submitted.

### Deliverables
- `SubmissionService` — create submission, fetch submissions for an assignment
- Submit action on Assignment detail (student): text response
- Submission confirmation state (assignment marked as submitted in the UI)
- Assignment detail (teacher view): list of students with submission status (submitted / not submitted)

### Done when
- A student can submit a text response to an assignment
- The assignment is marked as submitted in the student's view
- The teacher can see which students have submitted and which have not

---

## Phase 9 — Feedback

**Goal:** A teacher can acknowledge or grade a submission. The student sees the result.

### Deliverables
- `FeedbackService` (or extend `SubmissionService`) — update submission status, add feedback text
- Teacher can open a submission and mark it as graded with optional feedback text
- Student sees feedback on their submission detail screen
- Submission status updates to "graded"

### Done when
- A teacher can mark a submission as reviewed and leave a comment
- The student sees the feedback when they open the assignment

---

## Phase 10 — Profile

**Goal:** A user can view their account details and log out cleanly.

### Deliverables
- Profile screen: name, email, active role, app version
- Logout — clears session, navigates to Login
- (Post-MVP hook) Role switching UI placeholder, disabled for now

### Done when
- Profile screen shows real user data from the session
- Logout works correctly from any navigation state

---

## Phase 11 — Home screen (activity feed)

**Goal:** The Home tab shows what actually needs attention, drawn from real data.

> Home is built last because it aggregates data from classes, materials, and assignments.
> Building it before those systems exist would require fabricated data, which is not acceptable.

### Deliverables
- Home screen: upcoming assignments (nearest due date first), recent materials
- Each item tappable — navigates to the relevant detail screen
- Empty state for users with no classes yet: prompt to join or create a class
- No statistics, no charts, no fabricated counts

### Done when
- A student with enrolled classes sees their upcoming work
- A teacher with classes sees recent activity
- A user with no classes sees a clear prompt to get started

---

## Out of scope for MVP

The following will not be built until the core loop above is complete and tested:

- Push notifications
- File attachments (materials and submissions)
- Announcements / class feed
- Parent/guardian accounts
- Role switching
- Offline caching
- Search
- QR code joining
- Analytics or progress dashboards
- Direct messaging

---

## Current status

| Phase | Status |
|---|---|
| Foundation (architecture, theme, routing) | ✅ Complete |
| Phase 1 — Application shell | ✅ Complete |
| Phase 2 — Authentication | ✅ Complete |
| Phase 3 — Onboarding (Parent / Teacher) | ✅ Complete |
| **Domain correction — roles, Student entity, parent–teacher relationship** | ✅ Complete |
| Phase 4 — Classes (teacher) | ❌ Retired (join-code model removed) |
| Phase 5 — Classes (student / join) | ❌ Retired (students do not log in) |
| Parent experience (add student, request teacher) | ⬜ Not started |
| Teacher experience (receive/accept requests, roster) | ⬜ Not started |
| Lessons / attendance / progress notes | ⬜ Not started |
| Payments | ⬜ Not started |
| Home (activity feed) | ⬜ Not started |

> The retired Phase 4/5 deliverables (join-code classes) were built and then
> removed by the domain correction. Materials/Assignments/Submission/Feedback
> phases were never built and will be re-planned around lessons under the
> corrected model.
