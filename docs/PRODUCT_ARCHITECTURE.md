# Camiva — Product Architecture

> This document defines the product direction for Camiva.
> It is the reference for all implementation decisions.
> Do not implement screens or features that contradict this document without updating it first.
>
> Last updated: 2026-08-11 — foundational domain correction. Camiva is a
> parent–teacher tutoring platform, not a Google-Classroom-style student app.

---

## 0. Domain correction (read first)

Camiva is a **parent–teacher tutoring platform**. It is **not** a student
classroom app.

- **Parent** and **Teacher** are the only authenticated users in the MVP.
- A **Student** is a **managed learner record owned by a parent**. Students are
  the learners receiving the education, but they **never authenticate, never log
  in, and never enter join codes**. The parent manages the digital relationship
  on the child's behalf.
- The core teaching arrangement is the **parent–teacher relationship**, scoped to
  a single student:

  ```
  Parent
    └── Student
          └── Teacher relationship
  ```

- There is **no `Class` entity** in the MVP. The earlier Google-Classroom-style
  `Class` + join-code self-enrolment model has been **retired**.

The sections below are retained for product context but must be read through
this correction: wherever an older section implies a student logs in, joins a
class, or is an app account, that behaviour is superseded by the model above.

---

## 1. Users

### Parent / Guardian
The primary authenticated user. Manages one or more children (students),
finds and requests teachers, and oversees each child's learning relationships.
May have limited or intermittent internet access on a mid-range Android device.

### Teacher / Tutor
An authenticated user. Completes a teacher profile, receives relationship
requests from parents, accepts students, and manages their roster.
May be a formal school teacher or an independent tutor offering private sessions.

### Student (learner)
**Not an authenticated user.** A managed record owned by a parent, holding the
child's name, level, and notes. Students never sign in and have no account.

---

## 2. Core Jobs

### Student
- Find and join a class or tutoring session
- Access materials shared by a teacher
- See what assignments are due and submit them
- Know where they stand (what is done, what is pending)
- Contact their teacher when they have a question

### Teacher / Tutor
- Create a class and invite students
- Share learning materials (documents, links, notes)
- Post assignments with deadlines
- See which students have submitted and who has not
- Send announcements to a class

### Parent / Guardian *(post-MVP)*
- See their child's enrolled classes
- See assignment completion status
- Receive important announcements

---

## 3. Core Product Loop

```
Join a class → Access materials → Complete assignments → Get feedback
```

This loop is the backbone of every screen decision.

- **Join** — a student must be able to find and enter a class with minimal friction
- **Access** — materials must be immediately visible once inside a class
- **Complete** — assignments must be clear: what is required, when it is due
- **Feedback** — teachers close the loop by marking submissions or posting results

Everything outside this loop is secondary.

---

## 4. Information Architecture

### Primary navigation (bottom nav — 4 items max)

| Tab | Who sees it | Purpose |
|---|---|---|
| Home | All | Activity feed: upcoming assignments, recent materials, announcements |
| Classes | All | List of enrolled/managed classes |
| Assignments | Student | All assignments across all classes, sorted by due date |
| Profile | All | Account settings, role, logout |

Teachers see the same tabs. The Classes tab becomes their management surface.
The Assignments tab adapts its content based on role: students see their pending work,
teachers see a summary of submissions requiring attention.

### Secondary navigation (inside a class)

Each class has its own internal sections:

- **Feed** — announcements and recent activity
- **Materials** — files, links, notes posted by the teacher
- **Assignments** — tasks with deadlines
- **Members** — student list (teacher only)

These are tabs or a segmented control inside the class screen, not primary navigation.

### What does NOT get primary navigation

- Statistics / analytics dashboards
- Notifications (accessed via an icon in the AppBar)
- Search (accessed via an icon in the AppBar)
- Settings (inside Profile)

---

## 5. MVP

> **Superseded by the §0 domain correction.** The classroom-style must-haves
> below (create/join class, materials, assignments, submissions) are retired.
> The corrected MVP is: parent and teacher registration/login, onboarding role
> selection (**Parent / Teacher**), a parent managing student records, and the
> parent–teacher relationship lifecycle. The list is kept only as historical
> context.

### Must have (historical — see §0)
- User registration and login (parent and teacher roles)
- Role selection at onboarding (Parent / Teacher)
- ~~Create a class (teacher)~~ *(retired)*
- ~~Join a class via teacher-generated code (student)~~ *(retired — students do not log in)*
- Basic profile screen (name, active role, logout)

### Should have
- Push notifications for new assignments and announcements
- File attachment support for materials
- Teacher announcements / class feed
- Assignment submission with a text response or file

### Later
- Parent/guardian accounts
- Role switching within a single account
- Progress tracking and analytics
- Direct messaging between student and teacher
- Search for public classes
- QR code class joining
- Offline access to materials

---

## 6. First Release Screens

### 1. Splash / Entry
- **Purpose:** Determine whether the user is authenticated and route them correctly
- **Primary user:** All
- **Primary action:** None — automatic routing
- **Important information:** App logo, loading state
- **Navigates to:** Login (if unauthenticated) or Home (if authenticated)

### 2. Login
- **Purpose:** Authenticate an existing user
- **Primary user:** All
- **Primary action:** Sign in with email and password
- **Important information:** Email field, password field, link to Register
- **Navigates to:** Home

### 3. Register
- **Purpose:** Create a new account
- **Primary user:** New student or teacher
- **Primary action:** Submit name, email, password
- **Important information:** Role selection (Student / Teacher) sets the initial experience
- **Navigates to:** Onboarding (role confirmation) or Home

### 4. Home
- **Purpose:** Surface what needs attention right now
- **Primary user:** All
- **Primary action:** Tap into an upcoming assignment or recent material
- **Important information:** Upcoming assignment deadlines, recent materials, class announcements
- **Navigates to:** Assignment detail, Material detail, Class

### 5. Classes
- **Purpose:** List all classes the user is enrolled in or manages
- **Primary user:** All
- **Primary action:** Student — join a class via code. Teacher — create a class.
- **Important information:** Class name, subject, teacher name (for students), student count (for teachers)
- **Navigates to:** Class detail

### 6. Class Detail
- **Purpose:** The central space for a single class
- **Primary user:** All
- **Primary action:** Student — view materials and assignments. Teacher — post material or assignment.
- **Important information:** Class name, internal tabs (Feed / Materials / Assignments / Members)
- **Navigates to:** Material detail, Assignment detail, Post material, Post assignment

### 7. Assignment Detail
- **Purpose:** Show full assignment information and allow submission
- **Primary user:** Student (view + submit), Teacher (view submissions)
- **Primary action:** Student — mark as done or submit response. Teacher — view who submitted.
- **Important information:** Title, description, due date, submission status
- **Navigates to:** Back to class

### 8. Profile
- **Purpose:** Account information and settings
- **Primary user:** All
- **Primary action:** Logout
- **Important information:** Name, email, active role, app version
- **Navigates to:** Login (on logout)

---

## 7. Data Model Direction

### AppUser (authenticated)
The base account for an authenticated user. `activeRole` determines the
experience. **Valid roles: `parent | teacher | student`.**
- id, name, email, activeRole (parent | teacher | student), profileComplete,
  createdAt

### Student (the canonical learner record)
`students` is the single learner table. One real child is one row, whether the
parent manages them, they manage themselves, or both.
- id, parentId (nullable), userId (nullable, unique), name, dateOfBirth,
  notes, linkCode, createdAt, updatedAt
- Academic profile (structured, from `education_catalogue.dart`):
  subsystem, schoolStage, cycle, levelCode, seriesCode, subjects
- `schoolLevel` is kept as the denormalised human label of `levelCode`
  ("Form 4", "4ème") so historical rows and existing SQL policies keep working

**Ownership shapes**
- parent-managed — `parentId` set, `userId` null (a child with no login)
- self-managed — `userId` set, `parentId` null (a student who signed up)
- linked — both set, after the child redeems the parent's one-time `linkCode`

A student account never creates a second learner row: signup either claims an
existing record by code or creates the one record that account will own, and a
unique index on `user_id` enforces it in the database.

### Education catalogue
`lib/core/constants/education_catalogue.dart` is the only source of levels,
cycles, series and subjects. Both Cameroon subsystems are modelled:
- English — Class 1–6, Form 1–5 (GCE O Level), Lower/Upper Sixth (GCE A Level)
  with Arts A1–A5 and Science S1–S4 series
- French — SIL–CM2, 6ème–3ème (BEPC), Seconde–Terminale with A1–A5, C, D, TI
  and BIL series

Level codes carry their subsystem (`en.sec.ol.form4` vs `fr.sec.c1.4e`), so
teacher matching can never treat an English Form 4 as a French 4ème.

### ParentTeacherRelationship (the teaching arrangement)
The core relationship, scoped to a single student. The same teacher can teach
multiple students, including several children of one parent, via distinct rows.
There is **no separate `Class` entity** in the MVP.
- id, parentId, studentId, teacherId, subject, level, status, createdAt, updatedAt
- status: `requested | accepted | rejected | cancelled | suspended`

### Relationships
```
AppUser (parent) ──< Student ──< ParentTeacherRelationship >── AppUser (teacher)
```

> Lessons, attendance, progress notes, materials, assignments, and payments are
> **future** concepts and are intentionally not modelled yet.

---

## 8. Backend

**Supabase** is the chosen backend for the MVP.

Services to be used:
- **Supabase Auth** — email/password authentication
- **PostgreSQL** — primary database, schema mirrors the data model above
- **Row Level Security (RLS)** — enforced at the database level; students only see classes they are enrolled in, teachers only manage their own classes
- **Supabase Storage** — introduced when file uploads are needed (materials, assignment attachments)

### Integration architecture

The application will communicate with Supabase through a thin service layer in `lib/core/services/`.
Screens and features must never call Supabase directly — all data access goes through service classes.
This isolates the backend dependency and makes it replaceable without touching feature code.

Supabase is **not implemented yet**. The service layer will be introduced when authentication is built.

---

## 9. Localisation

The MVP interface is **English-first**.

User-facing strings must not be hard-coded directly inside widgets.
All strings will be defined in a central location so that French (and other languages) can be
introduced as a first-class translation rather than a retrofit.

The localisation mechanism will be established before the first feature screen is built.
French will be added as a supported language in a subsequent release.

---

## 10. Connectivity

Connectivity is treated as a product constraint, not an afterthought.

The application must:
- Show clear loading states during network requests
- Handle errors gracefully with actionable messages
- Never leave the user on a blank screen due to a failed request

The application must be architected so the following can be added later without restructuring:
- Cached classes, materials, and assignments (for offline viewing)
- Queued actions that sync when connectivity is restored

No offline-sync system is built in the MVP. The service layer must not assume a persistent connection.

---

## 11. Product Principles

These apply to every screen and every widget built in Camiva.

1. **Actions first.** Every screen must have one clear primary action. If a screen has no clear action, question whether it should exist.

2. **No fabricated data.** Never show placeholder statistics, fake student counts, or invented progress percentages. Empty states must be honest and helpful.

3. **Design for low connectivity.** Assume the user may be on a slow or intermittent connection. Show loading states. Handle errors gracefully. Never leave the user staring at a blank screen.

4. **Role clarity.** A student and a teacher looking at the same class see different things. Never show a student a teacher control, and never hide a teacher control behind unclear UI.

5. **Minimal navigation depth.** A user should reach any important piece of content in at most 3 taps from Home. Avoid deeply nested screens.

6. **Plain language.** Use simple, direct language appropriate for Cameroon. Avoid EdTech jargon. "Join a class" not "Enrol in a learning module."

7. **Honest empty states.** When a list is empty, explain why and tell the user what to do. "No assignments yet" with a clear next action is better than a blank list.

8. **No dashboard clutter.** Do not build analytics dashboards, progress rings, or statistics cards unless there is real data to show and a real reason the user needs it. The Home screen is an activity feed, not a metrics panel.
