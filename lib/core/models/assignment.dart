import 'package:flutter/foundation.dart';

@immutable
class Assignment {
  const Assignment({
    required this.id,
    required this.lessonId,
    required this.teacherId,
    required this.title,
    required this.instructions,
    this.dueAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String lessonId;
  final String teacherId;
  final String title;
  final String instructions;
  final DateTime? dueAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Assignment.fromJson(Map<String, dynamic> json) {
    return Assignment(
      id: json['id'] as String,
      lessonId: json['lesson_id'] as String,
      teacherId: json['teacher_id'] as String,
      title: json['title'] as String,
      instructions: json['instructions'] as String,
      dueAt: json['due_at'] != null ? DateTime.parse(json['due_at'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'lesson_id': lessonId,
      'teacher_id': teacherId,
      'title': title,
      'instructions': instructions,
      if (dueAt != null) 'due_at': dueAt!.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Assignment copyWith({
    String? title,
    String? instructions,
    DateTime? dueAt,
  }) {
    return Assignment(
      id: id,
      lessonId: lessonId,
      teacherId: teacherId,
      title: title ?? this.title,
      instructions: instructions ?? this.instructions,
      dueAt: dueAt ?? this.dueAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

@immutable
class AssignmentRecipient {
  const AssignmentRecipient({
    required this.assignmentId,
    required this.studentId,
    required this.assignedAt,
  });

  final String assignmentId;
  final String studentId;
  final DateTime assignedAt;

  factory AssignmentRecipient.fromJson(Map<String, dynamic> json) {
    return AssignmentRecipient(
      assignmentId: json['assignment_id'] as String,
      studentId: json['student_id'] as String,
      assignedAt: DateTime.parse(json['assigned_at'] as String),
    );
  }
}
