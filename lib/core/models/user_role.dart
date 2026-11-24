/// Represents the authenticated role a user is operating under.
///
/// Camiva has three authenticated roles: [parent], [teacher] and [student].
///
/// A [student] account is a *login attached to an existing learner record* —
/// it never creates a second learner. See `students.user_id`.
///
/// Role switching and multi-role accounts are post-MVP.
enum UserRole {
  parent,
  teacher,
  student;

  bool get isTeacher => this == UserRole.teacher;
  bool get isParent => this == UserRole.parent;
  bool get isStudent => this == UserRole.student;
}
