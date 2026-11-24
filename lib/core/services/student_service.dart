import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/student.dart';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

sealed class StudentResult {
  const StudentResult();
}

final class StudentSuccess extends StudentResult {
  const StudentSuccess(this.student);
  final Student student;
}

final class StudentListSuccess extends StudentResult {
  const StudentListSuccess(this.students);
  final List<Student> students;
}

/// The signed-in student account has no `students` row yet — they still need
/// to complete their student profile.
final class StudentNotFound extends StudentResult {
  const StudentNotFound();
}

final class StudentFailure extends StudentResult {
  const StudentFailure(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// All `students` table operations go through this interface.
/// Screens must never call Supabase directly.
///
/// `students` is the single canonical learner table. A learner is either
/// parent-managed (`parent_id` set, `user_id` null), self-managed (`user_id`
/// set), or both once a parent links the account — never two rows.
///
/// Parent operations are implicitly scoped to the signed-in parent; student
/// operations are scoped to the signed-in learner. Both are additionally
/// enforced by row-level security.
abstract class StudentService {
  // -- Parent-managed children ---------------------------------------------

  Future<StudentResult> createStudent({
    required String name,
    DateTime? dateOfBirth,
    String? levelCode,
    String? seriesCode,
    String? schoolLevel,
    List<String> subjects,
    String? notes,
  });

  /// Updates an existing student the signed-in parent owns.
  Future<StudentResult> updateStudent({
    required String studentId,
    required String name,
    DateTime? dateOfBirth,
    String? levelCode,
    String? seriesCode,
    String? schoolLevel,
    List<String> subjects,
    String? notes,
  });

  /// Fetches the students owned by the signed-in parent.
  Future<StudentResult> fetchMyStudents();

  Future<StudentResult> fetchStudent(String studentId);

  /// Fetches students by id, scoped purely by row-level security.
  ///
  /// Unlike [fetchStudent], this does NOT add a `parent_id = me` filter, so it
  /// works for a teacher reading students they are connected to (RLS allows a
  /// teacher to read a student via an accepted relationship or a pending
  /// request). RLS still restricts the result to rows the caller may read.
  Future<StudentResult> fetchStudentsByIds(List<String> ids);

  // -- Self-managed student account ----------------------------------------

  /// The `students` row belonging to the signed-in student account, if any.
  /// Returns [StudentNotFound] when the account has no learner record yet.
  Future<StudentResult> fetchMyStudentRecord();

  /// Creates the learner record for the signed-in student account.
  ///
  /// Only used during student signup, and only when [fetchMyStudentRecord]
  /// returned [StudentNotFound] — a student account is never allowed to create
  /// a second record for itself.
  Future<StudentResult> createMyStudentRecord({
    required String name,
    required String levelCode,
    String? seriesCode,
    List<String> subjects,
  });

  /// Updates the signed-in student's own learner record.
  Future<StudentResult> updateMyStudentRecord({
    required String name,
    required String levelCode,
    String? seriesCode,
    List<String> subjects,
  });

  // -- Linking a student account to a parent-managed child -----------------

  /// Issues a one-time code for a child the signed-in parent owns, so the
  /// child's own account can attach to THAT record.
  ///
  /// This is the mechanism that stops a parent-created child and a
  /// self-registered student becoming two rows for the same person.
  Future<StudentResult> createLinkCode(String studentId);

  /// Attaches the signed-in student account to the learner record holding
  /// [code], consuming the code. Fails if the account is already linked or the
  /// code is unknown/used — it never falls back to creating a new record.
  Future<StudentResult> linkMyAccountWithCode(String code);
}

// ---------------------------------------------------------------------------
// Real implementation backed by Supabase
// ---------------------------------------------------------------------------

class SupabaseStudentService implements StudentService {
  SupabaseStudentService(this._client);

  final SupabaseClient _client;

  @override
  Future<StudentResult> createStudent({
    required String name,
    DateTime? dateOfBirth,
    String? levelCode,
    String? seriesCode,
    String? schoolLevel,
    List<String> subjects = const <String>[],
    String? notes,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const StudentFailure('Please sign in again.');
    }

    final student = _draft(
      parentId: user.id,
      name: name,
      dateOfBirth: dateOfBirth,
      levelCode: levelCode,
      seriesCode: seriesCode,
      schoolLevel: schoolLevel,
      subjects: subjects,
      notes: notes,
    );

    try {
      final row = await _client
          .from('students')
          .insert(student.toInsertMap(parentId: user.id))
          .select()
          .single();
      return StudentSuccess(Student.fromMap(row));
    } catch (e) {
      return StudentFailure(_friendlyError(e));
    }
  }

  @override
  Future<StudentResult> updateStudent({
    required String studentId,
    required String name,
    DateTime? dateOfBirth,
    String? levelCode,
    String? seriesCode,
    String? schoolLevel,
    List<String> subjects = const <String>[],
    String? notes,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const StudentFailure('Please sign in again.');
    }

    final student = _draft(
      id: studentId,
      parentId: user.id,
      name: name,
      dateOfBirth: dateOfBirth,
      levelCode: levelCode,
      seriesCode: seriesCode,
      schoolLevel: schoolLevel,
      subjects: subjects,
      notes: notes,
    );

    try {
      // Scope the update to a row this parent owns; RLS enforces it too.
      final row = await _client
          .from('students')
          .update(student.toWriteFields())
          .eq('id', studentId)
          .eq('parent_id', user.id)
          .select()
          .maybeSingle();
      if (row == null) {
        return const StudentFailure('Student not found.');
      }
      return StudentSuccess(Student.fromMap(row));
    } catch (e) {
      return StudentFailure(_friendlyError(e));
    }
  }

  @override
  Future<StudentResult> fetchMyStudents() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const StudentFailure('Please sign in again.');
    }

    try {
      final rows = await _client
          .from('students')
          .select()
          .eq('parent_id', user.id)
          .order('created_at', ascending: false);
      final students = (rows as List<dynamic>)
          .map((row) => Student.fromMap(row as Map<String, dynamic>))
          .toList();
      return StudentListSuccess(students);
    } catch (e) {
      return StudentFailure(_friendlyError(e));
    }
  }

  @override
  Future<StudentResult> fetchStudent(String studentId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const StudentFailure('Please sign in again.');
    }

    try {
      final row = await _client
          .from('students')
          .select()
          .eq('id', studentId)
          .eq('parent_id', user.id)
          .maybeSingle();
      if (row == null) {
        return const StudentFailure('Student not found.');
      }
      return StudentSuccess(Student.fromMap(row));
    } catch (e) {
      return StudentFailure(_friendlyError(e));
    }
  }

  @override
  Future<StudentResult> fetchStudentsByIds(List<String> ids) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const StudentFailure('Please sign in again.');
    }
    if (ids.isEmpty) return const StudentListSuccess([]);
    try {
      // No parent_id filter — RLS scopes which of these ids the caller can see.
      final rows = await _client.from('students').select().inFilter('id', ids);
      final students = (rows as List<dynamic>)
          .map((row) => Student.fromMap(row as Map<String, dynamic>))
          .toList();
      return StudentListSuccess(students);
    } catch (e) {
      return StudentFailure(_friendlyError(e));
    }
  }

  @override
  Future<StudentResult> fetchMyStudentRecord() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const StudentFailure('Please sign in again.');
    }
    try {
      final row = await _client
          .from('students')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();
      if (row == null) return const StudentNotFound();
      return StudentSuccess(Student.fromMap(row));
    } catch (e) {
      return StudentFailure(_friendlyError(e));
    }
  }

  @override
  Future<StudentResult> createMyStudentRecord({
    required String name,
    required String levelCode,
    String? seriesCode,
    List<String> subjects = const <String>[],
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const StudentFailure('Please sign in again.');
    }

    // Never create a second record for an account that already has one.
    final existing = await fetchMyStudentRecord();
    if (existing is StudentSuccess) return existing;
    if (existing is StudentFailure) return existing;

    final student = _draft(
      name: name,
      levelCode: levelCode,
      seriesCode: seriesCode,
      subjects: subjects,
    );

    try {
      final row = await _client
          .from('students')
          .insert(student.toSelfInsertMap(userId: user.id))
          .select()
          .single();
      return StudentSuccess(Student.fromMap(row));
    } catch (e) {
      return StudentFailure(_friendlyError(e));
    }
  }

  @override
  Future<StudentResult> updateMyStudentRecord({
    required String name,
    required String levelCode,
    String? seriesCode,
    List<String> subjects = const <String>[],
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const StudentFailure('Please sign in again.');
    }

    final student = _draft(
      name: name,
      levelCode: levelCode,
      seriesCode: seriesCode,
      subjects: subjects,
    );

    try {
      final row = await _client
          .from('students')
          .update(student.toWriteFields())
          .eq('user_id', user.id)
          .select()
          .maybeSingle();
      if (row == null) return const StudentNotFound();
      return StudentSuccess(Student.fromMap(row));
    } catch (e) {
      return StudentFailure(_friendlyError(e));
    }
  }

  @override
  Future<StudentResult> createLinkCode(String studentId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const StudentFailure('Please sign in again.');
    }

    // Codes are short enough to read aloud. Collisions are possible, so retry
    // a few times against the unique index rather than assuming uniqueness.
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        final row = await _client
            .from('students')
            .update({'link_code': _generateLinkCode()})
            .eq('id', studentId)
            .eq('parent_id', user.id)
            .isFilter('user_id', null)
            .select()
            .maybeSingle();
        if (row == null) {
          return const StudentFailure(
            'This child already has their own login.',
          );
        }
        return StudentSuccess(Student.fromMap(row));
      } catch (e) {
        final message = e.toString().toLowerCase();
        final isCollision =
            message.contains('duplicate') || message.contains('unique');
        if (!isCollision) return StudentFailure(_friendlyError(e));
      }
    }
    return const StudentFailure('Could not create a code. Please try again.');
  }

  @override
  Future<StudentResult> linkMyAccountWithCode(String code) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const StudentFailure('Please sign in again.');
    }
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) {
      return const StudentFailure('Please enter the code from your parent.');
    }

    try {
      // A student cannot see, let alone update, a row they do not own yet, so
      // the claim happens in a SECURITY DEFINER function that enforces the
      // one-account-one-learner rule server-side.
      final row = await _client.rpc<dynamic>(
        'link_student_account',
        params: {'p_code': trimmed},
      );
      if (row == null) {
        return const StudentFailure('That code is not valid.');
      }
      final map = row is List ? row.first : row;
      return StudentSuccess(Student.fromMap(map as Map<String, dynamic>));
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('already linked')) {
        return const StudentFailure(
          'This account is already linked to a student.',
        );
      }
      if (message.contains('invalid') || message.contains('used')) {
        return const StudentFailure(
          'That code is not valid, or it has already been used.',
        );
      }
      return StudentFailure(_friendlyError(e));
    }
  }

  /// Six characters from an alphabet with no 0/O or 1/I, so a code read over
  /// the phone cannot be mistyped into a different child's code.
  String _generateLinkCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(
      6,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  /// Builds an in-memory [Student] whose write payload the callers persist.
  /// Structured education fields are derived from [levelCode] by the model.
  Student _draft({
    String id = '',
    String parentId = '',
    required String name,
    DateTime? dateOfBirth,
    String? levelCode,
    String? seriesCode,
    String? schoolLevel,
    List<String> subjects = const <String>[],
    String? notes,
  }) {
    final now = DateTime.now();
    return Student(
      id: id,
      parentId: parentId,
      name: name,
      dateOfBirth: dateOfBirth,
      // Preserved only when there is no structured level to derive it from,
      // so a legacy record is never silently blanked.
      schoolLevel: schoolLevel,
      levelCode: levelCode,
      seriesCode: seriesCode,
      subjects: subjects,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
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

class UnconfiguredStudentService implements StudentService {
  const UnconfiguredStudentService();

  static const _message =
      'The app is not connected to a backend. Please contact support.';

  @override
  Future<StudentResult> createStudent({
    required String name,
    DateTime? dateOfBirth,
    String? levelCode,
    String? seriesCode,
    String? schoolLevel,
    List<String> subjects = const <String>[],
    String? notes,
  }) async =>
      const StudentFailure(_message);

  @override
  Future<StudentResult> updateStudent({
    required String studentId,
    required String name,
    DateTime? dateOfBirth,
    String? levelCode,
    String? seriesCode,
    String? schoolLevel,
    List<String> subjects = const <String>[],
    String? notes,
  }) async =>
      const StudentFailure(_message);

  @override
  Future<StudentResult> fetchMyStudents() async =>
      const StudentFailure(_message);

  @override
  Future<StudentResult> fetchStudent(String studentId) async =>
      const StudentFailure(_message);

  @override
  Future<StudentResult> fetchStudentsByIds(List<String> ids) async =>
      const StudentFailure(_message);

  @override
  Future<StudentResult> fetchMyStudentRecord() async =>
      const StudentFailure(_message);

  @override
  Future<StudentResult> createMyStudentRecord({
    required String name,
    required String levelCode,
    String? seriesCode,
    List<String> subjects = const <String>[],
  }) async =>
      const StudentFailure(_message);

  @override
  Future<StudentResult> updateMyStudentRecord({
    required String name,
    required String levelCode,
    String? seriesCode,
    List<String> subjects = const <String>[],
  }) async =>
      const StudentFailure(_message);

  @override
  Future<StudentResult> createLinkCode(String studentId) async =>
      const StudentFailure(_message);

  @override
  Future<StudentResult> linkMyAccountWithCode(String code) async =>
      const StudentFailure(_message);
}

// ---------------------------------------------------------------------------
// Widget tree injection
// ---------------------------------------------------------------------------

class StudentServiceScope extends InheritedWidget {
  const StudentServiceScope({
    super.key,
    required this.studentService,
    required super.child,
  });

  final StudentService studentService;

  static StudentService of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<StudentServiceScope>();
    assert(scope != null, 'No StudentServiceScope found in widget tree.');
    return scope!.studentService;
  }

  @override
  bool updateShouldNotify(StudentServiceScope oldWidget) =>
      studentService != oldWidget.studentService;
}
