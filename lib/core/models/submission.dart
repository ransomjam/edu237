import 'package:flutter/foundation.dart';

@immutable
class Submission {
  const Submission({
    required this.id,
    required this.assignmentId,
    required this.studentId,
    required this.content,
    required this.submittedAt,
    required this.updatedAt,
  });

  final String id;
  final String assignmentId;
  final String studentId;
  final String content;
  final DateTime submittedAt;
  final DateTime updatedAt;

  factory Submission.fromJson(Map<String, dynamic> json) {
    return Submission(
      id: json['id'] as String,
      assignmentId: json['assignment_id'] as String,
      studentId: json['student_id'] as String,
      content: json['content'] as String,
      submittedAt: DateTime.parse(json['submitted_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'assignment_id': assignmentId,
      'student_id': studentId,
      'content': content,
      'submitted_at': submittedAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Submission copyWith({
    String? content,
  }) {
    return Submission(
      id: id,
      assignmentId: assignmentId,
      studentId: studentId,
      content: content ?? this.content,
      submittedAt: submittedAt,
      updatedAt: updatedAt,
    );
  }
}
