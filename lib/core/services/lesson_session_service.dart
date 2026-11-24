import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/lesson_session.dart';
import '../models/teaching_mode.dart';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

sealed class LessonSessionResult {
  const LessonSessionResult();
}

final class LessonSessionSuccess extends LessonSessionResult {
  const LessonSessionSuccess(this.session);
  final LessonSession session;
}

final class LessonSessionListSuccess extends LessonSessionResult {
  const LessonSessionListSuccess(this.sessions);
  final List<LessonSession> sessions;
}

final class LessonSessionFailure extends LessonSessionResult {
  const LessonSessionFailure(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// All `lesson_sessions` table operations go through this interface. Screens
/// must never call Supabase directly.
///
/// The MVP is teacher-created scheduling: a teacher creates a session on an
/// accepted relationship they own; the parent reads it. These bounds are
/// enforced here and, authoritatively, by row-level security.
abstract class LessonSessionService {
  /// Creates a scheduled session on an accepted relationship the signed-in
  /// teacher owns. Identity fields are derived server-side from
  /// [relationshipId] — the caller never supplies teacher/student/parent ids.
  Future<LessonSessionResult> createSession({
    required String relationshipId,
    required String subject,
    required DateTime scheduledAt,
    required int durationMinutes,
    required TeachingMode teachingMode,
    String? locationArea,
    String? locationCity,
    int reminderMinutesBefore,
  });

  /// The signed-in teacher's sessions (all children), soonest first.
  Future<LessonSessionResult> fetchMyTeacherSessions();

  /// The signed-in teacher's sessions for one student.
  Future<LessonSessionResult> fetchTeacherSessionsForStudent(String studentId);

  /// The signed-in parent's sessions across all their children, soonest first.
  Future<LessonSessionResult> fetchMyParentSessions();

  /// Sessions for the signed-in student's own learner record, soonest first.
  /// Scoped purely by row-level security: a student may only read sessions on
  /// the `students` row their account is linked to.
  Future<LessonSessionResult> fetchMyStudentSessions(String studentId);

  /// Updates the status (and optional note) of a session the teacher owns.
  Future<LessonSessionResult> updateSessionStatus({
    required String sessionId,
    required SessionStatus status,
    String? note,
  });
}

// ---------------------------------------------------------------------------
// Supabase implementation
// ---------------------------------------------------------------------------

class SupabaseLessonSessionService implements LessonSessionService {
  SupabaseLessonSessionService(this._client);

  final SupabaseClient _client;

  @override
  Future<LessonSessionResult> createSession({
    required String relationshipId,
    required String subject,
    required DateTime scheduledAt,
    required int durationMinutes,
    required TeachingMode teachingMode,
    String? locationArea,
    String? locationCity,
    int reminderMinutesBefore = 30,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const LessonSessionFailure('Please sign in again.');
    }

    // Build a transient session purely to reuse its insert payload shape. The
    // identity fields here are placeholders — the database overwrites them from
    // the relationship.
    final draft = LessonSession(
      id: '',
      relationshipId: relationshipId,
      teacherId: user.id,
      studentId: '',
      parentId: '',
      subject: subject,
      scheduledAt: scheduledAt,
      durationMinutes: durationMinutes,
      teachingMode: teachingMode,
      locationArea: locationArea,
      locationCity: locationCity,
      status: SessionStatus.scheduled,
      reminderMinutesBefore: reminderMinutesBefore,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      final row = await _client
          .from('lesson_sessions')
          .insert(draft.toInsertMap())
          .select()
          .single();
      return LessonSessionSuccess(LessonSession.fromMap(row));
    } catch (e) {
      return LessonSessionFailure(_friendlyError(e));
    }
  }

  @override
  Future<LessonSessionResult> fetchMyTeacherSessions() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const LessonSessionFailure('Please sign in again.');
    }
    return _fetchBy(column: 'teacher_id', id: user.id);
  }

  @override
  Future<LessonSessionResult> fetchTeacherSessionsForStudent(
      String studentId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const LessonSessionFailure('Please sign in again.');
    }
    return _fetchBy(
      column: 'teacher_id',
      id: user.id,
      studentId: studentId,
    );
  }

  @override
  Future<LessonSessionResult> fetchMyParentSessions() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const LessonSessionFailure('Please sign in again.');
    }
    return _fetchBy(column: 'parent_id', id: user.id);
  }

  @override
  Future<LessonSessionResult> fetchMyStudentSessions(String studentId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const LessonSessionFailure('Please sign in again.');
    }
    return _fetchBy(column: 'student_id', id: studentId);
  }

  Future<LessonSessionResult> _fetchBy({
    required String column,
    required String id,
    String? studentId,
  }) async {
    try {
      var query =
          _client.from('lesson_sessions').select().eq(column, id);
      if (studentId != null) {
        query = query.eq('student_id', studentId);
      }
      final rows = await query.order('scheduled_at', ascending: true);
      final sessions = (rows as List<dynamic>)
          .map((r) => LessonSession.fromMap(r as Map<String, dynamic>))
          .toList();
      return LessonSessionListSuccess(sessions);
    } catch (e, st) {
      debugPrint('_fetchBy($column=$id) error: $e\n$st');
      return LessonSessionFailure(_friendlyError(e));
    }
  }

  @override
  Future<LessonSessionResult> updateSessionStatus({
    required String sessionId,
    required SessionStatus status,
    String? note,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const LessonSessionFailure('Please sign in again.');
    }
    try {
      final payload = <String, dynamic>{'status': status.value};
      // Only write the note when one is provided; never blank an existing note
      // by accident when just changing status.
      if (note != null) {
        payload['note'] = note.trim().isEmpty ? null : note.trim();
      }
      final row = await _client
          .from('lesson_sessions')
          .update(payload)
          .eq('id', sessionId)
          .select()
          .maybeSingle();
      if (row == null) {
        return const LessonSessionFailure('Lesson not found.');
      }
      return LessonSessionSuccess(LessonSession.fromMap(row));
    } catch (e) {
      return LessonSessionFailure(_friendlyError(e));
    }
  }

  String _friendlyError(Object e) {
    debugPrint('SupabaseLessonSessionService error: $e');
    final message = e.toString().toLowerCase();
    if (message.contains('overlap') ||
        message.contains('exclu') ||
        message.contains('clash') ||
        message.contains('23p01')) {
      return 'That time clashes with another lesson. Please pick a different time.';
    }
    if (message.contains('not active') || message.contains('accepted')) {
      return 'You can only schedule lessons with a connected student.';
    }
    if (message.contains('network') || message.contains('connection')) {
      return 'No connection. Please check your internet.';
    }
    if (message.contains('permission') ||
        message.contains('rls') ||
        message.contains('policy')) {
      return 'Permission denied. Please sign in again.';
    }
    return 'Something went wrong. Please try again. ($e)';
  }
}

// ---------------------------------------------------------------------------
// Unconfigured fallback
// ---------------------------------------------------------------------------

class UnconfiguredLessonSessionService implements LessonSessionService {
  const UnconfiguredLessonSessionService();

  static const _message =
      'The app is not connected to a backend. Please contact support.';

  @override
  Future<LessonSessionResult> createSession({
    required String relationshipId,
    required String subject,
    required DateTime scheduledAt,
    required int durationMinutes,
    required TeachingMode teachingMode,
    String? locationArea,
    String? locationCity,
    int reminderMinutesBefore = 30,
  }) async =>
      const LessonSessionFailure(_message);

  @override
  Future<LessonSessionResult> fetchMyTeacherSessions() async =>
      const LessonSessionFailure(_message);

  @override
  Future<LessonSessionResult> fetchTeacherSessionsForStudent(
          String studentId) async =>
      const LessonSessionFailure(_message);

  @override
  Future<LessonSessionResult> fetchMyStudentSessions(String studentId) async =>
      const LessonSessionFailure(_message);

  @override
  Future<LessonSessionResult> fetchMyParentSessions() async =>
      const LessonSessionFailure(_message);

  @override
  Future<LessonSessionResult> updateSessionStatus({
    required String sessionId,
    required SessionStatus status,
    String? note,
  }) async =>
      const LessonSessionFailure(_message);
}

// ---------------------------------------------------------------------------
// Widget tree injection
// ---------------------------------------------------------------------------

class LessonSessionServiceScope extends InheritedWidget {
  const LessonSessionServiceScope({
    super.key,
    required this.service,
    required super.child,
  });

  final LessonSessionService service;

  static LessonSessionService of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<LessonSessionServiceScope>();
    assert(scope != null, 'No LessonSessionServiceScope found in widget tree.');
    return scope!.service;
  }

  @override
  bool updateShouldNotify(LessonSessionServiceScope oldWidget) =>
      service != oldWidget.service;
}
