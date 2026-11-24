import 'teacher_request.dart';

/// A display-ready view of a [TeacherRequest] that bundles the safe child
/// identity snapshot carried on the request with any separately-resolved
/// context (the requested teacher's display name, on the parent side).
///
/// Both the parent and teacher request screens consume this, so the two views
/// stay consistent and identity flows from one place.
class TeacherRequestView {
  const TeacherRequestView({
    required this.request,
    this.teacherName,
  });

  final TeacherRequest request;

  /// Parent side: the display name of the requested teacher. Null on the
  /// teacher side (a teacher does not resolve their own name here).
  final String? teacherName;

  TeacherRequestStatus get status => request.status;
  String get id => request.id;
  DateTime get createdAt => request.createdAt;

  /// Child identity (from the request's safe snapshot).
  String get childName => request.childName;
  String get childForm => (request.studentForm ?? '').trim();
  List<String> get childSubjects => request.studentSubjects;
  bool get hasChildContext => request.hasChildContext;

  /// A safe label for the requesting parent. Parent identity is NOT readable by
  /// the teacher under RLS, so we never try to show a real parent name — we
  /// identify them by their child instead.
  String get parentLabel => 'Parent of ${request.childName}';

  /// The child's subjects that overlap the given teacher subjects, preserving
  /// the child's ordering. Used to highlight why a request is relevant.
  List<String> matchedSubjectsFor(List<String> teacherSubjects) {
    final set = teacherSubjects.map((s) => s.toLowerCase()).toSet();
    return childSubjects
        .where((s) => set.contains(s.toLowerCase()))
        .toList(growable: false);
  }
}
