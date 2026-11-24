import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/submission.dart';

sealed class SubmissionResult {}

class SubmissionSuccess extends SubmissionResult {
  SubmissionSuccess(this.submission);
  final Submission submission;
}

class SubmissionListSuccess extends SubmissionResult {
  SubmissionListSuccess(this.submissions);
  final List<Submission> submissions;
}

class SubmissionEmpty extends SubmissionResult {}

class SubmissionFailure extends SubmissionResult {
  SubmissionFailure(this.message);
  final String message;
}

abstract interface class SubmissionService {
  /// Submit or update a student's answer for an assignment.
  Future<SubmissionResult> submitWork({
    required String assignmentId,
    required String studentId,
    required String content,
  });

  /// Fetch a student's submission for a specific assignment (null if none).
  Future<SubmissionResult> fetchSubmissionForStudent({
    required String assignmentId,
    required String studentId,
  });

  /// Fetch all submissions for an assignment (teacher view).
  Future<SubmissionResult> fetchSubmissionsForAssignment(String assignmentId);
}

class SupabaseSubmissionService implements SubmissionService {
  const SupabaseSubmissionService(this._client);
  final SupabaseClient _client;

  @override
  Future<SubmissionResult> submitWork({
    required String assignmentId,
    required String studentId,
    required String content,
  }) async {
    try {
      // Upsert: if a row exists for this assignment+student, update it.
      final data = await _client.from('submissions').upsert(
        {
          'assignment_id': assignmentId,
          'student_id': studentId,
          'content': content,
          'submitted_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'assignment_id,student_id',
      ).select().single();

      return SubmissionSuccess(Submission.fromJson(data));
    } catch (e) {
      return SubmissionFailure('Could not submit your answer. Please try again.');
    }
  }

  @override
  Future<SubmissionResult> fetchSubmissionForStudent({
    required String assignmentId,
    required String studentId,
  }) async {
    try {
      final data = await _client
          .from('submissions')
          .select()
          .eq('assignment_id', assignmentId)
          .eq('student_id', studentId)
          .maybeSingle();

      if (data == null) return SubmissionEmpty();
      return SubmissionSuccess(Submission.fromJson(data));
    } catch (e) {
      return SubmissionFailure('Could not fetch submission.');
    }
  }

  @override
  Future<SubmissionResult> fetchSubmissionsForAssignment(String assignmentId) async {
    try {
      final data = await _client
          .from('submissions')
          .select()
          .eq('assignment_id', assignmentId)
          .order('submitted_at', ascending: false);

      if (data.isEmpty) return SubmissionEmpty();
      return SubmissionListSuccess(data.map(Submission.fromJson).toList());
    } catch (e) {
      return SubmissionFailure('Could not fetch submissions.');
    }
  }
}

class UnconfiguredSubmissionService implements SubmissionService {
  const UnconfiguredSubmissionService();

  @override
  Future<SubmissionResult> submitWork({
    required String assignmentId,
    required String studentId,
    required String content,
  }) async => SubmissionFailure('Backend not configured.');

  @override
  Future<SubmissionResult> fetchSubmissionForStudent({
    required String assignmentId,
    required String studentId,
  }) async => SubmissionFailure('Backend not configured.');

  @override
  Future<SubmissionResult> fetchSubmissionsForAssignment(String assignmentId) async =>
      SubmissionFailure('Backend not configured.');
}

class SubmissionServiceScope extends InheritedWidget {
  const SubmissionServiceScope({
    super.key,
    required this.submissionService,
    required super.child,
  });

  final SubmissionService submissionService;

  static SubmissionService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SubmissionServiceScope>();
    assert(scope != null, 'No SubmissionServiceScope found in widget tree.');
    return scope!.submissionService;
  }

  @override
  bool updateShouldNotify(SubmissionServiceScope oldWidget) {
    return submissionService != oldWidget.submissionService;
  }
}
