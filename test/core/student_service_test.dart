import 'package:edu237/core/services/student_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UnconfiguredStudentService', () {
    late StudentService sut;

    setUp(() => sut = const UnconfiguredStudentService());

    test('createStudent returns StudentFailure', () async {
      final result = await sut.createStudent(name: 'Junior');
      expect(result, isA<StudentFailure>());
    });

    test('fetchMyStudents returns StudentFailure', () async {
      expect(await sut.fetchMyStudents(), isA<StudentFailure>());
    });

    test('fetchStudent returns StudentFailure', () async {
      expect(await sut.fetchStudent('stu-1'), isA<StudentFailure>());
    });
  });
}
