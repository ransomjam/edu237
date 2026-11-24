import 'package:flutter/foundation.dart';

/// Represents a lesson created by a teacher.
@immutable
class Lesson {
  const Lesson({
    required this.id,
    required this.teacherId,
    required this.title,
    required this.description,
    required this.subject,
    required this.form,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String teacherId;
  final String title;
  final String description;
  final String subject;
  final String form;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Lesson.fromJson(Map<String, dynamic> json) {
    return Lesson(
      id: json['id'] as String,
      teacherId: json['teacher_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      subject: json['subject'] as String,
      form: json['form'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'teacher_id': teacherId,
      'title': title,
      'description': description,
      'subject': subject,
      'form': form,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Lesson copyWith({
    String? title,
    String? description,
    String? subject,
    String? form,
  }) {
    return Lesson(
      id: id,
      teacherId: teacherId,
      title: title ?? this.title,
      description: description ?? this.description,
      subject: subject ?? this.subject,
      form: form ?? this.form,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Lesson &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          teacherId == other.teacherId &&
          title == other.title &&
          description == other.description &&
          subject == other.subject &&
          form == other.form &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      id.hashCode ^
      teacherId.hashCode ^
      title.hashCode ^
      description.hashCode ^
      subject.hashCode ^
      form.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode;
}
