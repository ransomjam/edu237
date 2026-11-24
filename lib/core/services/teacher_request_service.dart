import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/parent_teacher_relationship.dart';
import '../models/teacher_request.dart';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

sealed class TeacherRequestResult {
  const TeacherRequestResult();
}

final class TeacherRequestSuccess extends TeacherRequestResult {
  const TeacherRequestSuccess(this.request);
  final TeacherRequest request;
}

final class TeacherRequestListSuccess extends TeacherRequestResult {
  const TeacherRequestListSuccess(this.requests);
  final List<TeacherRequest> requests;
}

final class TeacherRequestFailure extends TeacherRequestResult {
  const TeacherRequestFailure(this.message);
  final String message;
}

/// Returned by [acceptRequest]: carries both the resulting relationship and
/// the updated request, since acceptance is an atomic RPC call.
final class TeacherRequestAcceptSuccess extends TeacherRequestResult {
  const TeacherRequestAcceptSuccess({
    required this.request,
    required this.relationship,
  });
  final TeacherRequest request;
  final ParentTeacherRelationship relationship;
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// All `teacher_requests` table operations go through this interface.
/// Screens must never call Supabase directly.
///
/// Security model (enforced here + by RLS):
///   Parent  : create own pending, read own, cancel own pending.
///   Teacher : read incoming, decline own pending, accept via RPC.
abstract class TeacherRequestService {
  /// Creates a pending request for the signed-in parent's student → teacher.
  Future<TeacherRequestResult> createRequest({
    required String studentId,
    required String teacherId,
  });

  /// All requests owned by the signed-in parent.
  Future<TeacherRequestResult> fetchMyRequestsAsParent();

  /// Incoming requests addressed to the signed-in teacher.
  Future<TeacherRequestResult> fetchIncomingRequestsAsTeacher();

  /// Parent cancels their own pending request (status: cancelled).
  Future<TeacherRequestResult> cancelRequest(String requestId);

  /// Teacher declines an incoming pending request (status: declined).
  Future<TeacherRequestResult> declineRequest(String requestId);

  /// Teacher accepts an incoming pending request via the
  /// `accept_teacher_request` SECURITY DEFINER function. This atomically:
  ///   1. Validates the caller is the teacher.
  ///   2. Marks the request as accepted.
  ///   3. Creates (or reuses) the parent-teacher-student relationship.
  Future<TeacherRequestResult> acceptRequest(String requestId);

  /// Returns true when an active (pending or accepted) request already exists
  /// for the given student → teacher pair. Used to prevent duplicate sends.
  Future<bool> hasActiveRequest({
    required String studentId,
    required String teacherId,
  });
}

// ---------------------------------------------------------------------------
// Real implementation backed by Supabase
// ---------------------------------------------------------------------------

class SupabaseTeacherRequestService implements TeacherRequestService {
  SupabaseTeacherRequestService(this._client);

  final SupabaseClient _client;

  @override
  Future<TeacherRequestResult> createRequest({
    required String studentId,
    required String teacherId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return const TeacherRequestFailure('Please sign in again.');

    final payload = TeacherRequest(
      id: '',
      parentId: user.id,
      studentId: studentId,
      teacherId: teacherId,
      status: TeacherRequestStatus.pending,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ).toInsertMap();

    try {
      final row = await _client
          .from('teacher_requests')
          .insert(payload)
          .select()
          .single();
      return TeacherRequestSuccess(TeacherRequest.fromMap(row));
    } catch (e) {
      return TeacherRequestFailure(_friendlyError(e));
    }
  }

  @override
  Future<TeacherRequestResult> fetchMyRequestsAsParent() async {
    final user = _client.auth.currentUser;
    if (user == null) return const TeacherRequestFailure('Please sign in again.');
    try {
      final rows = await _client
          .from('teacher_requests')
          .select()
          .eq('parent_id', user.id)
          .order('created_at', ascending: false);
      return TeacherRequestListSuccess(_parseList(rows));
    } catch (e) {
      return TeacherRequestFailure(_friendlyError(e));
    }
  }

  @override
  Future<TeacherRequestResult> fetchIncomingRequestsAsTeacher() async {
    final user = _client.auth.currentUser;
    if (user == null) return const TeacherRequestFailure('Please sign in again.');
    try {
      final rows = await _client
          .from('teacher_requests')
          .select()
          .eq('teacher_id', user.id)
          .order('created_at', ascending: false);
      return TeacherRequestListSuccess(_parseList(rows));
    } catch (e) {
      return TeacherRequestFailure(_friendlyError(e));
    }
  }

  @override
  Future<TeacherRequestResult> cancelRequest(String requestId) async {
    final user = _client.auth.currentUser;
    if (user == null) return const TeacherRequestFailure('Please sign in again.');
    try {
      final row = await _client
          .from('teacher_requests')
          .update({'status': TeacherRequestStatus.cancelled.value})
          .eq('id', requestId)
          .eq('parent_id', user.id) // scoped to owner — RLS also enforces
          .eq('status', TeacherRequestStatus.pending.value)
          .select()
          .maybeSingle();
      if (row == null) {
        return const TeacherRequestFailure('Request not found or already actioned.');
      }
      return TeacherRequestSuccess(TeacherRequest.fromMap(row));
    } catch (e) {
      return TeacherRequestFailure(_friendlyError(e));
    }
  }

  @override
  Future<TeacherRequestResult> declineRequest(String requestId) async {
    final user = _client.auth.currentUser;
    if (user == null) return const TeacherRequestFailure('Please sign in again.');
    try {
      final row = await _client
          .from('teacher_requests')
          .update({'status': TeacherRequestStatus.declined.value})
          .eq('id', requestId)
          .eq('teacher_id', user.id) // scoped to teacher — RLS also enforces
          .eq('status', TeacherRequestStatus.pending.value)
          .select()
          .maybeSingle();
      if (row == null) {
        return const TeacherRequestFailure('Request not found or already actioned.');
      }
      return TeacherRequestSuccess(TeacherRequest.fromMap(row));
    } catch (e) {
      return TeacherRequestFailure(_friendlyError(e));
    }
  }

  @override
  Future<TeacherRequestResult> acceptRequest(String requestId) async {
    final user = _client.auth.currentUser;
    if (user == null) return const TeacherRequestFailure('Please sign in again.');
    try {
      // accept_teacher_request() is a SECURITY DEFINER function that:
      //   1. Validates caller == request.teacher_id.
      //   2. Validates request is pending.
      //   3. Creates (or reuses) the relationship.
      //   4. Sets request status = 'accepted'.
      // Returns the relationship row.
      final relRow = await _client
          .rpc('accept_teacher_request', params: {'p_request_id': requestId});

      // After the RPC, fetch the updated request row so we can return it.
      final reqRow = await _client
          .from('teacher_requests')
          .select()
          .eq('id', requestId)
          .single();

      return TeacherRequestAcceptSuccess(
        request: TeacherRequest.fromMap(reqRow),
        relationship: ParentTeacherRelationship.fromMap(
          Map<String, dynamic>.from(relRow as Map),
        ),
      );
    } catch (e) {
      return TeacherRequestFailure(_friendlyError(e));
    }
  }

  @override
  Future<bool> hasActiveRequest({
    required String studentId,
    required String teacherId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    try {
      final rows = await _client
          .from('teacher_requests')
          .select('id, status')
          .eq('parent_id', user.id)
          .eq('student_id', studentId)
          .eq('teacher_id', teacherId)
          .inFilter('status', ['pending', 'accepted']);
      return (rows as List<dynamic>).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  List<TeacherRequest> _parseList(dynamic rows) {
    return (rows as List<dynamic>)
        .map((row) => TeacherRequest.fromMap(row as Map<String, dynamic>))
        .toList();
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
    if (message.contains('duplicate') || message.contains('unique')) {
      return 'A request for this child and teacher already exists.';
    }
    if (message.contains('not authorised') ||
        message.contains('not authorized')) {
      return 'You are not authorised to perform this action.';
    }
    if (message.contains('not pending')) {
      return 'This request has already been actioned.';
    }
    return 'Something went wrong. Please try again.';
  }
}

// ---------------------------------------------------------------------------
// Stub used when Supabase credentials are not configured
// ---------------------------------------------------------------------------

class UnconfiguredTeacherRequestService implements TeacherRequestService {
  const UnconfiguredTeacherRequestService();

  static const _message =
      'The app is not connected to a backend. Please contact support.';

  @override
  Future<TeacherRequestResult> createRequest({
    required String studentId,
    required String teacherId,
  }) async =>
      const TeacherRequestFailure(_message);

  @override
  Future<TeacherRequestResult> fetchMyRequestsAsParent() async =>
      const TeacherRequestFailure(_message);

  @override
  Future<TeacherRequestResult> fetchIncomingRequestsAsTeacher() async =>
      const TeacherRequestFailure(_message);

  @override
  Future<TeacherRequestResult> cancelRequest(String requestId) async =>
      const TeacherRequestFailure(_message);

  @override
  Future<TeacherRequestResult> declineRequest(String requestId) async =>
      const TeacherRequestFailure(_message);

  @override
  Future<TeacherRequestResult> acceptRequest(String requestId) async =>
      const TeacherRequestFailure(_message);

  @override
  Future<bool> hasActiveRequest({
    required String studentId,
    required String teacherId,
  }) async =>
      false;
}

// ---------------------------------------------------------------------------
// Widget tree injection
// ---------------------------------------------------------------------------

class TeacherRequestServiceScope extends InheritedWidget {
  const TeacherRequestServiceScope({
    super.key,
    required this.requestService,
    required super.child,
  });

  final TeacherRequestService requestService;

  static TeacherRequestService of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<TeacherRequestServiceScope>();
    assert(scope != null, 'No TeacherRequestServiceScope found in widget tree.');
    return scope!.requestService;
  }

  /// The service if one is in the tree, otherwise null. Used by widgets that
  /// are useful without it — the shell shows a request badge when it can, and
  /// simply omits it when there is no service to ask.
  static TeacherRequestService? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TeacherRequestServiceScope>()
      ?.requestService;

  @override
  bool updateShouldNotify(TeacherRequestServiceScope oldWidget) =>
      requestService != oldWidget.requestService;
}
