import 'package:edu237/core/models/parent_teacher_relationship.dart';
import 'package:edu237/core/models/student.dart';
import 'package:edu237/core/models/teacher_request.dart';
import 'package:edu237/core/services/teacher_request_service.dart';

class FakeTeacherRequestService implements TeacherRequestService {
  FakeTeacherRequestService({required this.userId});

  final String userId;
  final List<TeacherRequest> _requests = [];
  final List<ParentTeacherRelationship> _relationships = [];
  final Map<String, Student> _students = {};

  void seed(TeacherRequest request) {
    _requests.add(request);
  }

  void seedRelationship(ParentTeacherRelationship rel) {
    _relationships.add(rel);
  }

  /// Registers a student so [createRequest] can snapshot its identity onto the
  /// request — mirroring the server-side trigger.
  void registerStudent(Student student) {
    _students[student.id] = student;
  }

  @override
  Future<TeacherRequestResult> createRequest({
    required String studentId,
    required String teacherId,
  }) async {
    final s = _students[studentId];
    final req = TeacherRequest(
      id: 'req-${_requests.length + 1}',
      parentId: userId,
      studentId: studentId,
      teacherId: teacherId,
      status: TeacherRequestStatus.pending,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      studentName: s?.name,
      studentForm: s?.schoolLevel,
      studentSubjects: s?.subjects ?? const <String>[],
    );
    _requests.add(req);
    return TeacherRequestSuccess(req);
  }

  @override
  Future<TeacherRequestResult> fetchMyRequestsAsParent() async {
    final mine = _requests.where((r) => r.parentId == userId).toList();
    return TeacherRequestListSuccess(mine);
  }

  @override
  Future<TeacherRequestResult> fetchIncomingRequestsAsTeacher() async {
    final mine = _requests.where((r) => r.teacherId == userId).toList();
    return TeacherRequestListSuccess(mine);
  }

  @override
  Future<TeacherRequestResult> cancelRequest(String requestId) async {
    final index = _requests.indexWhere((r) => r.id == requestId && r.parentId == userId && r.status == TeacherRequestStatus.pending);
    if (index == -1) return const TeacherRequestFailure('Not found');
    final old = _requests[index];
    final updated = TeacherRequest(
      id: old.id,
      parentId: old.parentId,
      studentId: old.studentId,
      teacherId: old.teacherId,
      status: TeacherRequestStatus.cancelled,
      createdAt: old.createdAt,
      updatedAt: DateTime.now(),
      studentName: old.studentName,
      studentForm: old.studentForm,
      studentSubjects: old.studentSubjects,
    );
    _requests[index] = updated;
    return TeacherRequestSuccess(updated);
  }

  @override
  Future<TeacherRequestResult> declineRequest(String requestId) async {
    final index = _requests.indexWhere((r) => r.id == requestId && r.teacherId == userId && r.status == TeacherRequestStatus.pending);
    if (index == -1) return const TeacherRequestFailure('Not found');
    final old = _requests[index];
    final updated = TeacherRequest(
      id: old.id,
      parentId: old.parentId,
      studentId: old.studentId,
      teacherId: old.teacherId,
      status: TeacherRequestStatus.declined,
      createdAt: old.createdAt,
      updatedAt: DateTime.now(),
      studentName: old.studentName,
      studentForm: old.studentForm,
      studentSubjects: old.studentSubjects,
    );
    _requests[index] = updated;
    return TeacherRequestSuccess(updated);
  }

  @override
  Future<TeacherRequestResult> acceptRequest(String requestId) async {
    final index = _requests.indexWhere((r) => r.id == requestId && r.teacherId == userId && r.status == TeacherRequestStatus.pending);
    if (index == -1) return const TeacherRequestFailure('Not found');
    final old = _requests[index];
    final updated = TeacherRequest(
      id: old.id,
      parentId: old.parentId,
      studentId: old.studentId,
      teacherId: old.teacherId,
      status: TeacherRequestStatus.accepted,
      createdAt: old.createdAt,
      updatedAt: DateTime.now(),
      studentName: old.studentName,
      studentForm: old.studentForm,
      studentSubjects: old.studentSubjects,
    );
    _requests[index] = updated;

    final rel = ParentTeacherRelationship(
      id: 'rel-${_relationships.length + 1}',
      parentId: updated.parentId,
      teacherId: updated.teacherId,
      studentId: updated.studentId,
      subject: '',
      level: '',
      status: RelationshipStatus.accepted,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _relationships.add(rel);

    return TeacherRequestAcceptSuccess(request: updated, relationship: rel);
  }

  @override
  Future<bool> hasActiveRequest({
    required String studentId,
    required String teacherId,
  }) async {
    return _requests.any((r) => r.parentId == userId && r.studentId == studentId && r.teacherId == teacherId && (r.status == TeacherRequestStatus.pending || r.status == TeacherRequestStatus.accepted));
  }
}
