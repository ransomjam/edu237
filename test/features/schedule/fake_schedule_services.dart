import 'package:edu237/core/models/lesson_session.dart';
import 'package:edu237/core/models/parent_teacher_relationship.dart';
import 'package:edu237/core/models/teacher_availability.dart';
import 'package:edu237/core/models/teaching_mode.dart';
import 'package:edu237/core/services/lesson_session_service.dart';
import 'package:edu237/core/services/teacher_availability_service.dart';

/// A shared in-memory store so teacher/parent-scoped fake services see the same
/// relationships and sessions — mirroring what RLS enforces on the real tables.
class FakeScheduleStore {
  final List<ParentTeacherRelationship> relationships = [];
  final List<LessonSession> sessions = [];
  int _seq = 0;

  String nextId() => 'sess-${++_seq}';

  void seedRelationship(ParentTeacherRelationship r) => relationships.add(r);
}

/// In-memory availability service scoped to [userId], documenting the ownership
/// contract the real service + RLS uphold: a caller writes only their own rows,
/// but anyone may read a teacher's availability.
class FakeTeacherAvailabilityService implements TeacherAvailabilityService {
  FakeTeacherAvailabilityService({required this.userId, Map<String, List<AvailabilitySlot>>? store})
      : store = store ?? {};

  final String userId;
  final Map<String, List<AvailabilitySlot>> store;

  @override
  Future<AvailabilityResult> fetchMyAvailability() async =>
      fetchAvailabilityFor(userId);

  @override
  Future<AvailabilityResult> fetchAvailabilityFor(String teacherId) async =>
      AvailabilitySuccess(WeeklyAvailability(store[teacherId] ?? const []));

  @override
  Future<AvailabilityResult> saveMyAvailability(
      List<AvailabilitySlot> slots) async {
    for (final s in slots) {
      if (s.endMinute <= s.startMinute) {
        return const AvailabilityFailure(
            'Each day\'s end time must be after its start time.');
      }
    }
    store[userId] = List.of(slots);
    return AvailabilitySuccess(WeeklyAvailability(slots));
  }
}

/// In-memory lesson-session service scoped to [userId]. Encodes the same bounds
/// as the RLS policies + trigger:
///   * only the teacher of an ACCEPTED relationship may create a session,
///   * identity fields are derived from the relationship (unrelated students
///     are rejected),
///   * a teacher can't double-book,
///   * only the owning teacher may change a session (parents are read-only).
class FakeLessonSessionService implements LessonSessionService {
  FakeLessonSessionService({required this.userId, required this.store});

  final String userId;
  final FakeScheduleStore store;

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
    final rel = store.relationships
        .where((r) => r.id == relationshipId)
        .cast<ParentTeacherRelationship?>()
        .firstWhere((_) => true, orElse: () => null);
    if (rel == null) {
      return const LessonSessionFailure('Relationship not found');
    }
    if (rel.status != RelationshipStatus.accepted) {
      return const LessonSessionFailure(
          'Cannot schedule on a relationship that is not active');
    }
    // The caller must be the relationship's teacher (unrelated students / other
    // teachers are rejected).
    if (rel.teacherId != userId) {
      return const LessonSessionFailure('Permission denied.');
    }

    final start = scheduledAt.toLocal();
    final end = start.add(Duration(minutes: durationMinutes));
    final clash = store.sessions.any((s) =>
        s.teacherId == userId &&
        s.status.isScheduled &&
        start.isBefore(s.localEnd) &&
        s.localStart.isBefore(end));
    if (clash) {
      return const LessonSessionFailure(
          'That time clashes with another lesson.');
    }

    final now = DateTime.now();
    final session = LessonSession(
      id: store.nextId(),
      relationshipId: rel.id,
      teacherId: rel.teacherId,
      studentId: rel.studentId,
      parentId: rel.parentId,
      subject: subject,
      scheduledAt: scheduledAt,
      durationMinutes: durationMinutes,
      teachingMode: teachingMode,
      locationArea: locationArea,
      locationCity: locationCity,
      status: SessionStatus.scheduled,
      reminderMinutesBefore: reminderMinutesBefore,
      studentName: 'Student ${rel.studentId}',
      teacherName: 'Teacher ${rel.teacherId}',
      createdAt: now,
      updatedAt: now,
    );
    store.sessions.add(session);
    return LessonSessionSuccess(session);
  }

  @override
  Future<LessonSessionResult> fetchMyTeacherSessions() async {
    final list = store.sessions.where((s) => s.teacherId == userId).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return LessonSessionListSuccess(list);
  }

  @override
  Future<LessonSessionResult> fetchTeacherSessionsForStudent(
      String studentId) async {
    final list = store.sessions
        .where((s) => s.teacherId == userId && s.studentId == studentId)
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return LessonSessionListSuccess(list);
  }

  @override
  Future<LessonSessionResult> fetchMyParentSessions() async {
    final list = store.sessions.where((s) => s.parentId == userId).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return LessonSessionListSuccess(list);
  }

  @override
  Future<LessonSessionResult> fetchMyStudentSessions(String studentId) async {
    final list = store.sessions.where((s) => s.studentId == studentId).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return LessonSessionListSuccess(list);
  }

  @override
  Future<LessonSessionResult> updateSessionStatus({
    required String sessionId,
    required SessionStatus status,
    String? note,
  }) async {
    final idx = store.sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return const LessonSessionFailure('Lesson not found.');
    final s = store.sessions[idx];
    // Only the owning teacher may change a session.
    if (s.teacherId != userId) {
      return const LessonSessionFailure('Permission denied.');
    }
    final updated = s.copyWith(status: status, note: note);
    store.sessions[idx] = updated;
    return LessonSessionSuccess(updated);
  }
}
