import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/learning_activity.dart';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

sealed class ActivityResult {
  const ActivityResult();
}

final class ActivitySuccess extends ActivityResult {
  const ActivitySuccess(this.activity);
  final LearningActivity activity;
}

final class ActivityListSuccess extends ActivityResult {
  const ActivityListSuccess(this.activities);
  final List<LearningActivity> activities;
}

final class RecipientListSuccess extends ActivityResult {
  const RecipientListSuccess(this.recipients);
  final List<ActivityRecipient> recipients;
}

final class RecipientSuccess extends ActivityResult {
  const RecipientSuccess(this.recipient);
  final ActivityRecipient recipient;
}

final class ActivityEmpty extends ActivityResult {
  const ActivityEmpty();
}

final class ActivityFailure extends ActivityResult {
  const ActivityFailure(this.message);
  final String message;
}

/// Dashboard summary counts for a teacher.
class TeacherSummary {
  const TeacherSummary({
    required this.todayCount,
    required this.needsAttentionCount,
    required this.recentActivities,
  });
  final int todayCount;
  final int needsAttentionCount;
  final List<LearningActivity> recentActivities;
}

/// Dashboard summary for a parent viewing a student.
class ParentSummary {
  const ParentSummary({
    required this.totalCount,
    required this.needsAttentionCount,
  });
  final int totalCount;
  final int needsAttentionCount;
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

abstract interface class LearningActivityService {
  /// Create a new learning activity and assign it to the given students.
  Future<ActivityResult> createActivity({
    required String subject,
    required String form,
    required String topic,
    required ActivityType activityType,
    String? note,
    DateTime? dueDate,
    required List<String> studentIds,
  });

  /// Fetch activities for a specific student (used by both teacher and parent).
  Future<ActivityResult> fetchActivitiesForStudent(String studentId);

  /// Fetch all activities created by the authenticated teacher.
  Future<ActivityResult> fetchTeacherActivities();

  /// Fetch recipients for a specific activity.
  Future<ActivityResult> fetchRecipientsForActivity(String activityId);

  /// Update a recipient's status (e.g. mark completed).
  Future<ActivityResult> updateRecipientStatus({
    required String recipientId,
    required ActivityStatus status,
    String? teacherNote,
  });

  /// Dashboard summary for the authenticated teacher.
  Future<TeacherSummary> fetchTeacherSummary();

  /// Dashboard summary for a parent viewing a specific child.
  Future<ParentSummary> fetchParentSummary(String studentId);
}

// ---------------------------------------------------------------------------
// Supabase implementation
// ---------------------------------------------------------------------------

class SupabaseLearningActivityService implements LearningActivityService {
  SupabaseLearningActivityService(this._client);

  final SupabaseClient _client;

  @override
  Future<ActivityResult> createActivity({
    required String subject,
    required String form,
    required String topic,
    required ActivityType activityType,
    String? note,
    DateTime? dueDate,
    required List<String> studentIds,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return const ActivityFailure('Please sign in again.');
    if (studentIds.isEmpty) {
      return const ActivityFailure('Please select at least one student.');
    }

    try {
      // 1. Insert the activity
      final activityRow = await _client
          .from('learning_activities')
          .insert({
            'teacher_id': user.id,
            'subject': subject,
            'form': form,
            'topic': topic,
            'activity_type': activityType.name,
            'note': note?.trim().isEmpty == true ? null : note?.trim(),
            'due_date': dueDate?.toIso8601String().split('T')[0],
          })
          .select()
          .single();

      final activity =
          LearningActivity.fromMap(activityRow);

      // 2. Insert recipients
      final recipientRows = studentIds
          .map((sid) => {
                'activity_id': activity.id,
                'student_id': sid,
                'status': 'upcoming',
              })
          .toList();

      await _client.from('learning_activity_recipients').insert(recipientRows);

      return ActivitySuccess(activity);
    } catch (e) {
      return ActivityFailure(_friendlyError(e));
    }
  }

  @override
  Future<ActivityResult> fetchActivitiesForStudent(String studentId) async {
    try {
      // Get activity IDs where this student is a recipient
      final recipientRows = await _client
          .from('learning_activity_recipients')
          .select('activity_id')
          .eq('student_id', studentId);

      final activityIds = (recipientRows as List<dynamic>)
          .map((r) => (r as Map<String, dynamic>)['activity_id'] as String)
          .toSet()
          .toList();

      if (activityIds.isEmpty) return const ActivityListSuccess([]);

      final rows = await _client
          .from('learning_activities')
          .select()
          .inFilter('id', activityIds)
          .order('created_at', ascending: false);

      final activities = (rows as List<dynamic>)
          .map((r) => LearningActivity.fromMap(r as Map<String, dynamic>))
          .toList();

      return ActivityListSuccess(activities);
    } catch (e) {
      return ActivityFailure(_friendlyError(e));
    }
  }

  @override
  Future<ActivityResult> fetchTeacherActivities() async {
    final user = _client.auth.currentUser;
    if (user == null) return const ActivityFailure('Please sign in again.');

    try {
      final rows = await _client
          .from('learning_activities')
          .select()
          .eq('teacher_id', user.id)
          .order('created_at', ascending: false);

      final activities = (rows as List<dynamic>)
          .map((r) => LearningActivity.fromMap(r as Map<String, dynamic>))
          .toList();

      return ActivityListSuccess(activities);
    } catch (e) {
      return ActivityFailure(_friendlyError(e));
    }
  }

  @override
  Future<ActivityResult> fetchRecipientsForActivity(String activityId) async {
    try {
      final rows = await _client
          .from('learning_activity_recipients')
          .select()
          .eq('activity_id', activityId)
          .order('created_at');

      final recipients = (rows as List<dynamic>)
          .map((r) => ActivityRecipient.fromMap(r as Map<String, dynamic>))
          .toList();

      return RecipientListSuccess(recipients);
    } catch (e) {
      return ActivityFailure(_friendlyError(e));
    }
  }

  @override
  Future<ActivityResult> updateRecipientStatus({
    required String recipientId,
    required ActivityStatus status,
    String? teacherNote,
  }) async {
    try {
      final row = await _client
          .from('learning_activity_recipients')
          .update({
            'status': status.value,
            'teacher_note':
                teacherNote?.trim().isEmpty == true ? null : teacherNote?.trim(),
          })
          .eq('id', recipientId)
          .select()
          .single();

      return RecipientSuccess(
          ActivityRecipient.fromMap(row));
    } catch (e) {
      return ActivityFailure(_friendlyError(e));
    }
  }

  @override
  Future<TeacherSummary> fetchTeacherSummary() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const TeacherSummary(
        todayCount: 0,
        needsAttentionCount: 0,
        recentActivities: [],
      );
    }

    try {
      // Recent activities (last 5)
      final recentRows = await _client
          .from('learning_activities')
          .select()
          .eq('teacher_id', user.id)
          .order('created_at', ascending: false)
          .limit(5);

      final recentActivities = (recentRows as List<dynamic>)
          .map((r) => LearningActivity.fromMap(r as Map<String, dynamic>))
          .toList();

      // Today's activity count
      final today = DateTime.now().toIso8601String().split('T')[0];
      final todayRows = await _client
          .from('learning_activities')
          .select('id')
          .eq('teacher_id', user.id)
          .gte('created_at', '${today}T00:00:00');

      final todayCount = (todayRows as List<dynamic>).length;

      // Needs attention count
      final allRows = await _client
          .from('learning_activities')
          .select('id')
          .eq('teacher_id', user.id);

      final allIds = (allRows as List<dynamic>)
          .map((r) => (r as Map<String, dynamic>)['id'] as String)
          .toList();

      int needsAttentionCount = 0;
      if (allIds.isNotEmpty) {
        final naRows = await _client
            .from('learning_activity_recipients')
            .select('id')
            .inFilter('activity_id', allIds)
            .eq('status', 'needs_attention');
        needsAttentionCount = (naRows as List<dynamic>).length;
      }

      return TeacherSummary(
        todayCount: todayCount,
        needsAttentionCount: needsAttentionCount,
        recentActivities: recentActivities,
      );
    } catch (_) {
      return const TeacherSummary(
        todayCount: 0,
        needsAttentionCount: 0,
        recentActivities: [],
      );
    }
  }

  @override
  Future<ParentSummary> fetchParentSummary(String studentId) async {
    try {
      final recipientRows = await _client
          .from('learning_activity_recipients')
          .select('id, status')
          .eq('student_id', studentId);

      final rows = recipientRows as List<dynamic>;
      final total = rows.length;
      final needsAttention = rows
          .where((r) =>
              (r as Map<String, dynamic>)['status'] == 'needs_attention')
          .length;

      return ParentSummary(
        totalCount: total,
        needsAttentionCount: needsAttention,
      );
    } catch (_) {
      return const ParentSummary(totalCount: 0, needsAttentionCount: 0);
    }
  }

  String _friendlyError(Object e) {
    if (e is PostgrestException) return e.message;
    return 'Something went wrong. Please try again.';
  }
}

// ---------------------------------------------------------------------------
// Unconfigured fallback
// ---------------------------------------------------------------------------

class UnconfiguredLearningActivityService implements LearningActivityService {
  const UnconfiguredLearningActivityService();

  static const _msg = 'Learning activity service is not configured.';

  @override
  Future<ActivityResult> createActivity({
    required String subject,
    required String form,
    required String topic,
    required ActivityType activityType,
    String? note,
    DateTime? dueDate,
    required List<String> studentIds,
  }) async =>
      const ActivityFailure(_msg);

  @override
  Future<ActivityResult> fetchActivitiesForStudent(String studentId) async =>
      const ActivityFailure(_msg);

  @override
  Future<ActivityResult> fetchTeacherActivities() async =>
      const ActivityFailure(_msg);

  @override
  Future<ActivityResult> fetchRecipientsForActivity(String activityId) async =>
      const ActivityFailure(_msg);

  @override
  Future<ActivityResult> updateRecipientStatus({
    required String recipientId,
    required ActivityStatus status,
    String? teacherNote,
  }) async =>
      const ActivityFailure(_msg);

  @override
  Future<TeacherSummary> fetchTeacherSummary() async => const TeacherSummary(
        todayCount: 0,
        needsAttentionCount: 0,
        recentActivities: [],
      );

  @override
  Future<ParentSummary> fetchParentSummary(String studentId) async =>
      const ParentSummary(totalCount: 0, needsAttentionCount: 0);
}

// ---------------------------------------------------------------------------
// InheritedWidget scope
// ---------------------------------------------------------------------------

class LearningActivityServiceScope extends InheritedWidget {
  const LearningActivityServiceScope({
    super.key,
    required this.service,
    required super.child,
  });

  final LearningActivityService service;

  static LearningActivityService of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<LearningActivityServiceScope>();
    assert(scope != null,
        'No LearningActivityServiceScope found in widget tree.');
    return scope!.service;
  }

  @override
  bool updateShouldNotify(LearningActivityServiceScope oldWidget) =>
      service != oldWidget.service;
}
