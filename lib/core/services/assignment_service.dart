import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/assignment.dart';

sealed class AssignmentResult {}

class AssignmentSuccess extends AssignmentResult {
  AssignmentSuccess(this.assignment);
  final Assignment assignment;
}

class AssignmentListSuccess extends AssignmentResult {
  AssignmentListSuccess(this.assignments);
  final List<Assignment> assignments;
}

class AssignmentEmpty extends AssignmentResult {}

class AssignmentFailure extends AssignmentResult {
  AssignmentFailure(this.message);
  final String message;
}

abstract interface class AssignmentService {
  Future<AssignmentResult> createAssignment({
    required String lessonId,
    required String title,
    required String instructions,
    DateTime? dueAt,
    required List<String> studentIds,
  });

  Future<AssignmentResult> fetchTeacherAssignments();
  Future<AssignmentResult> fetchStudentAssignments(String studentId);
  Future<AssignmentResult> fetchAssignment(String assignmentId);
  Future<AssignmentResult> updateAssignment(Assignment assignment);
  Future<AssignmentResult> deleteAssignment(String assignmentId);
  Future<List<AssignmentRecipient>> fetchRecipients(String assignmentId);
}

class SupabaseAssignmentService implements AssignmentService {
  const SupabaseAssignmentService(this._client);
  final SupabaseClient _client;

  @override
  Future<AssignmentResult> createAssignment({
    required String lessonId,
    required String title,
    required String instructions,
    DateTime? dueAt,
    required List<String> studentIds,
  }) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        return AssignmentFailure('You must be signed in to create an assignment.');
      }

      if (studentIds.isEmpty) {
        return AssignmentFailure('You must select at least one student.');
      }

      // Create the assignment
      final data = await _client.from('assignments').insert({
        'lesson_id': lessonId,
        'teacher_id': user.id,
        'title': title,
        'instructions': instructions,
        if (dueAt != null) 'due_at': dueAt.toIso8601String(),
      }).select().single();

      final assignment = Assignment.fromJson(data);

      // Create the recipients. If any fail, they just won't be assigned, but
      // we'll try to insert them all.
      // (For robustness, we'd use a postgres function, but multiple inserts work too).
      final recipientRecords = studentIds.map((id) => {
        'assignment_id': assignment.id,
        'student_id': id,
      }).toList();

      await _client.from('assignment_recipients').insert(recipientRecords);

      return AssignmentSuccess(assignment);
    } catch (e) {
      return AssignmentFailure('Could not create assignment. Please try again.');
    }
  }

  @override
  Future<AssignmentResult> fetchTeacherAssignments() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        return AssignmentFailure('You must be signed in to view your assignments.');
      }

      final data = await _client
          .from('assignments')
          .select()
          .eq('teacher_id', user.id)
          .order('created_at', ascending: false);

      if (data.isEmpty) return AssignmentEmpty();
      
      return AssignmentListSuccess(data.map(Assignment.fromJson).toList());
    } catch (e) {
      return AssignmentFailure('Could not fetch your assignments.');
    }
  }

  @override
  Future<AssignmentResult> fetchStudentAssignments(String studentId) async {
    try {
      // The parent RLS allows reading assignments if the student is a recipient.
      // However, we still need to filter assignments down to just this student.
      // We can query the `assignment_recipients` and join `assignments`.
      
      final res = await _client
          .from('assignment_recipients')
          .select('assignments(*)')
          .eq('student_id', studentId)
          .order('assigned_at', ascending: false);

      if (res.isEmpty) return AssignmentEmpty();

      final assignments = res.map((r) => Assignment.fromJson(r['assignments'] as Map<String, dynamic>)).toList();
      return AssignmentListSuccess(assignments);
    } catch (e) {
      return AssignmentFailure('Could not fetch assignments for this student.');
    }
  }

  @override
  Future<AssignmentResult> fetchAssignment(String assignmentId) async {
    try {
      final data = await _client.from('assignments').select().eq('id', assignmentId).maybeSingle();
      if (data == null) {
        return AssignmentFailure('Assignment not found.');
      }
      return AssignmentSuccess(Assignment.fromJson(data));
    } catch (e) {
      return AssignmentFailure('Could not fetch assignment.');
    }
  }

  @override
  Future<AssignmentResult> updateAssignment(Assignment assignment) async {
    try {
      final data = await _client
          .from('assignments')
          .update({
            'title': assignment.title,
            'instructions': assignment.instructions,
            'due_at': assignment.dueAt?.toIso8601String(),
          })
          .eq('id', assignment.id)
          .select()
          .single();
      return AssignmentSuccess(Assignment.fromJson(data));
    } catch (e) {
      return AssignmentFailure('Could not update assignment.');
    }
  }

  @override
  Future<AssignmentResult> deleteAssignment(String assignmentId) async {
    try {
      await _client.from('assignments').delete().eq('id', assignmentId);
      return AssignmentEmpty();
    } catch (e) {
      return AssignmentFailure('Could not delete assignment.');
    }
  }
  
  @override
  Future<List<AssignmentRecipient>> fetchRecipients(String assignmentId) async {
    try {
      final data = await _client.from('assignment_recipients').select().eq('assignment_id', assignmentId);
      return data.map(AssignmentRecipient.fromJson).toList();
    } catch (e) {
      return [];
    }
  }
}

class UnconfiguredAssignmentService implements AssignmentService {
  const UnconfiguredAssignmentService();

  @override
  Future<AssignmentResult> createAssignment({
    required String lessonId,
    required String title,
    required String instructions,
    DateTime? dueAt,
    required List<String> studentIds,
  }) async => AssignmentFailure('Backend not configured.');

  @override
  Future<AssignmentResult> fetchTeacherAssignments() async => AssignmentFailure('Backend not configured.');
  
  @override
  Future<AssignmentResult> fetchStudentAssignments(String studentId) async => AssignmentFailure('Backend not configured.');

  @override
  Future<AssignmentResult> fetchAssignment(String assignmentId) async => AssignmentFailure('Backend not configured.');

  @override
  Future<AssignmentResult> updateAssignment(Assignment assignment) async => AssignmentFailure('Backend not configured.');

  @override
  Future<AssignmentResult> deleteAssignment(String assignmentId) async => AssignmentFailure('Backend not configured.');
  
  @override
  Future<List<AssignmentRecipient>> fetchRecipients(String assignmentId) async => [];
}

class AssignmentServiceScope extends InheritedWidget {
  const AssignmentServiceScope({
    super.key,
    required this.assignmentService,
    required super.child,
  });

  final AssignmentService assignmentService;

  static AssignmentService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AssignmentServiceScope>();
    assert(scope != null, 'No AssignmentServiceScope found in widget tree.');
    return scope!.assignmentService;
  }

  @override
  bool updateShouldNotify(AssignmentServiceScope oldWidget) {
    return assignmentService != oldWidget.assignmentService;
  }
}
