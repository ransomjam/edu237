import 'package:edu237/core/services/teacher_request_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UnconfiguredTeacherRequestService', () {
    late TeacherRequestService sut;

    setUp(() => sut = const UnconfiguredTeacherRequestService());

    test('createRequest returns TeacherRequestFailure', () async {
      final result = await sut.createRequest(studentId: 's-1', teacherId: 't-1');
      expect(result, isA<TeacherRequestFailure>());
    });

    test('fetchMyRequestsAsParent returns TeacherRequestFailure', () async {
      expect(await sut.fetchMyRequestsAsParent(), isA<TeacherRequestFailure>());
    });

    test('fetchIncomingRequestsAsTeacher returns TeacherRequestFailure', () async {
      expect(await sut.fetchIncomingRequestsAsTeacher(), isA<TeacherRequestFailure>());
    });

    test('cancelRequest returns TeacherRequestFailure', () async {
      expect(await sut.cancelRequest('req-1'), isA<TeacherRequestFailure>());
    });

    test('declineRequest returns TeacherRequestFailure', () async {
      expect(await sut.declineRequest('req-1'), isA<TeacherRequestFailure>());
    });

    test('acceptRequest returns TeacherRequestFailure', () async {
      expect(await sut.acceptRequest('req-1'), isA<TeacherRequestFailure>());
    });

    test('hasActiveRequest returns false', () async {
      expect(await sut.hasActiveRequest(studentId: 's-1', teacherId: 't-1'), isFalse);
    });
  });
}
