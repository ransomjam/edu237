import 'package:flutter_test/flutter_test.dart';
import 'package:edu237/core/models/teacher_request.dart';
import 'package:edu237/core/models/teacher_request_view.dart';

void main() {
  group('TeacherRequest snapshot payload', () {
    test('fromMap parses the child identity snapshot', () {
      final r = TeacherRequest.fromMap({
        'id': 'req-1',
        'parent_id': 'p1',
        'student_id': 's1',
        'teacher_id': 't1',
        'status': 'pending',
        'student_name': 'Daniel',
        'student_form': 'Form 4',
        'student_subjects': ['Mathematics', 'Physics'],
        'created_at': '2026-08-12T09:00:00.000Z',
        'updated_at': '2026-08-12T09:00:00.000Z',
      });
      expect(r.studentName, 'Daniel');
      expect(r.studentForm, 'Form 4');
      expect(r.studentSubjects, ['Mathematics', 'Physics']);
      expect(r.hasChildContext, isTrue);
      expect(r.childName, 'Daniel');
    });

    test('tolerates a missing snapshot (legacy rows)', () {
      final r = TeacherRequest.fromMap({
        'id': 'req-2',
        'parent_id': 'p1',
        'student_id': 's1',
        'teacher_id': 't1',
        'status': 'declined',
        'created_at': '2026-08-12T09:00:00.000Z',
        'updated_at': '2026-08-12T09:00:00.000Z',
      });
      expect(r.studentName, isNull);
      expect(r.studentSubjects, isEmpty);
      expect(r.hasChildContext, isFalse);
      expect(r.childName, 'Child'); // safe fallback
    });

    test('the client insert payload never carries the snapshot (server fills it)',
        () {
      final r = TeacherRequest(
        id: '',
        parentId: 'p1',
        studentId: 's1',
        teacherId: 't1',
        status: TeacherRequestStatus.pending,
        studentName: 'Daniel',
        studentForm: 'Form 4',
        studentSubjects: const ['Mathematics'],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final insert = r.toInsertMap();
      expect(insert.containsKey('student_name'), isFalse);
      expect(insert.containsKey('student_form'), isFalse);
      expect(insert.containsKey('student_subjects'), isFalse);
      expect(insert.keys.toSet(),
          {'parent_id', 'student_id', 'teacher_id', 'status'});
    });
  });

  group('TeacherRequestView', () {
    TeacherRequest req({
      String status = 'pending',
      String? name = 'Daniel',
      String? form = 'Form 4',
      List<String> subjects = const ['Mathematics', 'Physics'],
    }) =>
        TeacherRequest(
          id: 'req-1',
          parentId: 'p1',
          studentId: 's1',
          teacherId: 't1',
          status: TeacherRequestStatus.fromString(status),
          studentName: name,
          studentForm: form,
          studentSubjects: subjects,
          createdAt: DateTime(2026, 8, 12),
          updatedAt: DateTime(2026, 8, 12),
        );

    test('exposes child identity from the snapshot', () {
      final v = TeacherRequestView(request: req());
      expect(v.childName, 'Daniel');
      expect(v.childForm, 'Form 4');
      expect(v.childSubjects, ['Mathematics', 'Physics']);
      expect(v.hasChildContext, isTrue);
    });

    test('parentLabel identifies the parent safely by their child', () {
      expect(TeacherRequestView(request: req()).parentLabel,
          'Parent of Daniel');
    });

    test('matchedSubjectsFor returns the overlap, child order preserved', () {
      final v = TeacherRequestView(request: req());
      expect(v.matchedSubjectsFor(['physics', 'chemistry']), ['Physics']);
      expect(v.matchedSubjectsFor(['Mathematics', 'Physics']),
          ['Mathematics', 'Physics']);
      expect(v.matchedSubjectsFor(const []), isEmpty);
    });

    test('carries the resolved teacher name on the parent side', () {
      final v = TeacherRequestView(request: req(), teacherName: 'Teacher A');
      expect(v.teacherName, 'Teacher A');
    });
  });
}
