import 'package:edu237/core/constants/education_catalogue.dart';
import 'package:edu237/core/models/student.dart';
import 'package:edu237/core/services/student_service.dart';

/// An in-memory [StudentService] for widget tests.
///
/// It simulates the real parent-scoping contract: every student created is
/// stamped with [parentId], and fetches only return students for that parent.
/// This is test infrastructure — never wired into the real app flow.
class FakeStudentService implements StudentService {
  FakeStudentService({this.parentId = 'parent-1', this.studentUserId});

  final String parentId;

  /// The auth id of a signed-in student account, when the test is exercising
  /// the student experience. Learner records are linked through this.
  final String? studentUserId;
  final List<Student> _students = [];
  int _seq = 0;

  List<Student> get students => List.unmodifiable(_students);

  /// The database stores `school_level` as the label of `level_code`; only a
  /// legacy row with no structured level keeps its raw text.
  static String? _label(String? levelCode, String? schoolLevel) {
    final resolved = EducationCatalogue.levelByCode(levelCode);
    if (resolved != null) return resolved.label;
    final raw = schoolLevel?.trim();
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  /// Seed a pre-existing student (e.g. to simulate a legacy row).
  void seed(Student student) => _students.add(student);

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
    final now = DateTime.now();
    final student = Student(
      id: 'stu-${++_seq}',
      parentId: parentId,
      name: name.trim(),
      dateOfBirth: dateOfBirth,
      levelCode: levelCode,
      seriesCode: seriesCode,
      schoolLevel: _label(levelCode, schoolLevel),
      subjects: List<String>.from(subjects),
      notes: (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
      createdAt: now,
      updatedAt: now,
    );
    _students.add(student);
    return StudentSuccess(student);
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
    final index =
        _students.indexWhere((s) => s.id == studentId && s.parentId == parentId);
    if (index < 0) {
      return const StudentFailure('Student not found.');
    }
    final existing = _students[index];
    final updated = Student(
      id: existing.id,
      parentId: existing.parentId,
      name: name.trim(),
      dateOfBirth: dateOfBirth,
      levelCode: levelCode ?? existing.levelCode,
      seriesCode: seriesCode ?? existing.seriesCode,
      schoolLevel: _label(levelCode ?? existing.levelCode, schoolLevel),
      subjects: List<String>.from(subjects),
      notes: (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );
    _students[index] = updated;
    return StudentSuccess(updated);
  }

  @override
  Future<StudentResult> fetchMyStudents() async {
    final mine = _students.where((s) => s.parentId == parentId).toList();
    return StudentListSuccess(mine);
  }

  @override
  Future<StudentResult> fetchStudent(String studentId) async {
    for (final s in _students) {
      if (s.id == studentId && s.parentId == parentId) {
        return StudentSuccess(s);
      }
    }
    return const StudentFailure('Student not found.');
  }

  @override
  Future<StudentResult> fetchStudentsByIds(List<String> ids) async {
    final idSet = ids.toSet();
    final matched = _students.where((s) => idSet.contains(s.id)).toList();
    return StudentListSuccess(matched);
  }

  @override
  Future<StudentResult> fetchMyStudentRecord() async {
    for (final s in _students) {
      if (s.userId != null && s.userId == studentUserId) {
        return StudentSuccess(s);
      }
    }
    return const StudentNotFound();
  }

  @override
  Future<StudentResult> createMyStudentRecord({
    required String name,
    required String levelCode,
    String? seriesCode,
    List<String> subjects = const <String>[],
  }) async {
    // Mirrors the real service: an account already linked to a learner record
    // never gets a second one.
    final existing = await fetchMyStudentRecord();
    if (existing is StudentSuccess) return existing;

    final now = DateTime.now();
    final student = Student(
      id: 'stu-${++_seq}',
      // A self-managed learner has no parent.
      parentId: '',
      userId: studentUserId,
      name: name.trim(),
      levelCode: levelCode,
      seriesCode: seriesCode,
      schoolLevel: _label(levelCode, null),
      subjects: List<String>.from(subjects),
      createdAt: now,
      updatedAt: now,
    );
    _students.add(student);
    return StudentSuccess(student);
  }

  @override
  Future<StudentResult> createLinkCode(String studentId) async {
    final index = _students.indexWhere(
        (s) => s.id == studentId && s.parentId == parentId);
    if (index < 0) return const StudentFailure('Student not found.');
    if (_students[index].hasAccount) {
      return const StudentFailure('This child already has their own login.');
    }
    final updated =
        _students[index].copyWith(linkCode: 'CODE${index + 1}');
    _students[index] = updated;
    return StudentSuccess(updated);
  }

  @override
  Future<StudentResult> linkMyAccountWithCode(String code) async {
    // Mirrors the server function: one account links to at most one learner,
    // the code must be outstanding, and it is consumed on use.
    final already = await fetchMyStudentRecord();
    if (already is StudentSuccess) {
      return const StudentFailure(
          'This account is already linked to a student.');
    }

    final needle = code.trim().toUpperCase();
    final index = _students.indexWhere(
        (s) => s.linkCode == needle && !s.hasAccount);
    if (index < 0) {
      return const StudentFailure(
          'That code is not valid, or it has already been used.');
    }

    final existing = _students[index];
    final linked = Student(
      id: existing.id,
      parentId: existing.parentId,
      userId: studentUserId,
      name: existing.name,
      dateOfBirth: existing.dateOfBirth,
      schoolLevel: existing.schoolLevel,
      levelCode: existing.levelCode,
      seriesCode: existing.seriesCode,
      subjects: existing.subjects,
      notes: existing.notes,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );
    _students[index] = linked;
    return StudentSuccess(linked);
  }

  @override
  Future<StudentResult> updateMyStudentRecord({
    required String name,
    required String levelCode,
    String? seriesCode,
    List<String> subjects = const <String>[],
  }) async {
    final index =
        _students.indexWhere((s) => s.userId != null && s.userId == studentUserId);
    if (index < 0) return const StudentNotFound();

    final existing = _students[index];
    final updated = Student(
      id: existing.id,
      parentId: existing.parentId,
      userId: existing.userId,
      name: name.trim(),
      dateOfBirth: existing.dateOfBirth,
      levelCode: levelCode,
      seriesCode: seriesCode,
      schoolLevel: _label(levelCode, null),
      subjects: List<String>.from(subjects),
      notes: existing.notes,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );
    _students[index] = updated;
    return StudentSuccess(updated);
  }
}
