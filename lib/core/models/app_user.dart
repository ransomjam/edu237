import 'user_role.dart';

/// The authenticated user as seen by the application.
///
/// Constructed from the Supabase session + user_profiles table row.
/// This is the single source of truth for the current user's identity
/// and active role — it replaces the Phase 1 in-memory role once auth exists.
///
/// An authenticated user is a [UserRole.parent], [UserRole.teacher] or
/// [UserRole.student].
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.activeRole,
    this.profileComplete = false,
  });

  final String id;
  final String email;
  final String name;
  final UserRole activeRole;
  /// True once the user has completed onboarding (name + role confirmed).
  final bool profileComplete;

  /// Constructs an [AppUser] from a Supabase user_profiles row.
  factory AppUser.fromMap({
    required String id,
    required String email,
    required Map<String, dynamic> profile,
  }) {
    final activeRoleValue = profile['active_role'] as String?;
    return AppUser(
      id: id,
      email: email,
      name: (profile['name'] as String?) ?? '',
      activeRole: roleFromString(activeRoleValue),
      profileComplete: (profile['profile_complete'] as bool?) ?? false,
    );
  }

  AppUser copyWith({
    String? id,
    String? email,
    String? name,
    UserRole? activeRole,
    bool? profileComplete,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      activeRole: activeRole ?? this.activeRole,
      profileComplete: profileComplete ?? this.profileComplete,
    );
  }

  /// Parses a persisted `active_role` value into a [UserRole].
  ///
  /// Fails safely (throws [FormatException]) for `null` and any unknown
  /// string rather than silently coercing it into a role. Callers construct
  /// [AppUser] through [fromMap], whose exceptions are caught by the
  /// service/app layer and surfaced as a profile-load error.
  static UserRole roleFromString(String? value) {
    return switch (value) {
      'parent' => UserRole.parent,
      'teacher' => UserRole.teacher,
      'student' => UserRole.student,
      _ => throw FormatException('Unsupported active_role: $value'),
    };
  }

  static String roleToString(UserRole role) {
    return switch (role) {
      UserRole.parent => 'parent',
      UserRole.teacher => 'teacher',
      UserRole.student => 'student',
    };
  }
}
