import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/parent_teacher_relationship.dart';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

sealed class RelationshipResult {
  const RelationshipResult();
}

final class RelationshipSuccess extends RelationshipResult {
  const RelationshipSuccess(this.relationship);
  final ParentTeacherRelationship relationship;
}

final class RelationshipListSuccess extends RelationshipResult {
  const RelationshipListSuccess(this.relationships);
  final List<ParentTeacherRelationship> relationships;
}

final class RelationshipFailure extends RelationshipResult {
  const RelationshipFailure(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// All `parent_teacher_relationships` table operations go through this
/// interface. Screens must never call Supabase directly.
///
/// A parent may create relationship requests for students they own and read
/// their own relationships. A teacher may read relationships where they are
/// the teacher and update the status (accept/reject/suspend). These bounds are
/// enforced here and by row-level security.
abstract class ParentTeacherRelationshipService {
  /// Creates a new relationship request (status = requested) for a student
  /// the signed-in parent owns.
  Future<RelationshipResult> requestRelationship({
    required String studentId,
    required String teacherId,
    required String subject,
    required String level,
  });

  /// Relationships owned by the signed-in parent.
  Future<RelationshipResult> fetchMyRelationshipsAsParent();

  /// Relationships where the signed-in teacher is the teacher.
  Future<RelationshipResult> fetchMyRelationshipsAsTeacher();

  /// Relationships for one learner record, scoped purely by row-level
  /// security. Used by the student experience: a signed-in student may only
  /// read relationships on the `students` row their account is linked to.
  Future<RelationshipResult> fetchRelationshipsForStudent(String studentId);

  /// Updates the status of a relationship (e.g. a teacher accepting a request).
  Future<RelationshipResult> updateStatus({
    required String relationshipId,
    required RelationshipStatus status,
  });
}

// ---------------------------------------------------------------------------
// Real implementation backed by Supabase
// ---------------------------------------------------------------------------

class SupabaseParentTeacherRelationshipService
    implements ParentTeacherRelationshipService {
  SupabaseParentTeacherRelationshipService(this._client);

  final SupabaseClient _client;

  @override
  Future<RelationshipResult> requestRelationship({
    required String studentId,
    required String teacherId,
    required String subject,
    required String level,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const RelationshipFailure('Please sign in again.');
    }

    final relationship = ParentTeacherRelationship(
      id: '',
      parentId: user.id,
      studentId: studentId,
      teacherId: teacherId,
      subject: subject,
      level: level,
      status: RelationshipStatus.requested,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      final row = await _client
          .from('parent_teacher_relationships')
          .insert(relationship.toInsertMap(parentId: user.id))
          .select()
          .single();
      return RelationshipSuccess(ParentTeacherRelationship.fromMap(row));
    } catch (e) {
      return RelationshipFailure(_friendlyError(e));
    }
  }

  @override
  Future<RelationshipResult> fetchMyRelationshipsAsParent() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const RelationshipFailure('Please sign in again.');
    }
    return _fetchBy(column: 'parent_id', id: user.id);
  }

  @override
  Future<RelationshipResult> fetchMyRelationshipsAsTeacher() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const RelationshipFailure('Please sign in again.');
    }
    return _fetchBy(column: 'teacher_id', id: user.id);
  }

  @override
  Future<RelationshipResult> fetchRelationshipsForStudent(
      String studentId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const RelationshipFailure('Please sign in again.');
    }
    return _fetchBy(column: 'student_id', id: studentId);
  }

  Future<RelationshipResult> _fetchBy({
    required String column,
    required String id,
  }) async {
    try {
      final rows = await _client
          .from('parent_teacher_relationships')
          .select()
          .eq(column, id)
          .order('created_at', ascending: false);
      final relationships = (rows as List<dynamic>)
          .map((row) =>
              ParentTeacherRelationship.fromMap(row as Map<String, dynamic>))
          .toList();
      return RelationshipListSuccess(relationships);
    } catch (e) {
      return RelationshipFailure(_friendlyError(e));
    }
  }

  @override
  Future<RelationshipResult> updateStatus({
    required String relationshipId,
    required RelationshipStatus status,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const RelationshipFailure('Please sign in again.');
    }

    try {
      final row = await _client
          .from('parent_teacher_relationships')
          .update({'status': status.value})
          .eq('id', relationshipId)
          .select()
          .maybeSingle();
      if (row == null) {
        return const RelationshipFailure('Relationship not found.');
      }
      return RelationshipSuccess(ParentTeacherRelationship.fromMap(row));
    } catch (e) {
      return RelationshipFailure(_friendlyError(e));
    }
  }

  String _friendlyError(Object e) {
    final message = e.toString().toLowerCase();
    if (message.contains('network') || message.contains('connection')) {
      return 'No connection. Please check your internet.';
    }
    if (message.contains('permission') ||
        message.contains('rls') ||
        message.contains('policy')) {
      return 'Permission denied. Please sign in again.';
    }
    return 'Something went wrong. Please try again.';
  }
}

// ---------------------------------------------------------------------------
// Stub used when Supabase credentials are not configured
// ---------------------------------------------------------------------------

class UnconfiguredParentTeacherRelationshipService
    implements ParentTeacherRelationshipService {
  const UnconfiguredParentTeacherRelationshipService();

  static const _message =
      'The app is not connected to a backend. Please contact support.';

  @override
  Future<RelationshipResult> requestRelationship({
    required String studentId,
    required String teacherId,
    required String subject,
    required String level,
  }) async =>
      const RelationshipFailure(_message);

  @override
  Future<RelationshipResult> fetchMyRelationshipsAsParent() async =>
      const RelationshipFailure(_message);

  @override
  Future<RelationshipResult> fetchMyRelationshipsAsTeacher() async =>
      const RelationshipFailure(_message);

  @override
  Future<RelationshipResult> fetchRelationshipsForStudent(
          String studentId) async =>
      const RelationshipFailure(_message);

  @override
  Future<RelationshipResult> updateStatus({
    required String relationshipId,
    required RelationshipStatus status,
  }) async =>
      const RelationshipFailure(_message);
}

// ---------------------------------------------------------------------------
// Widget tree injection
// ---------------------------------------------------------------------------

class ParentTeacherRelationshipServiceScope extends InheritedWidget {
  const ParentTeacherRelationshipServiceScope({
    super.key,
    required this.relationshipService,
    required super.child,
  });

  final ParentTeacherRelationshipService relationshipService;

  static ParentTeacherRelationshipService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<
        ParentTeacherRelationshipServiceScope>();
    assert(scope != null,
        'No ParentTeacherRelationshipServiceScope found in widget tree.');
    return scope!.relationshipService;
  }

  @override
  bool updateShouldNotify(ParentTeacherRelationshipServiceScope oldWidget) =>
      relationshipService != oldWidget.relationshipService;
}
