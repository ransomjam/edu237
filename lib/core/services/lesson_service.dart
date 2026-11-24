import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/lesson.dart';

/// Outcomes for lesson operations.
sealed class LessonResult {}

class LessonSuccess extends LessonResult {
  LessonSuccess(this.lesson);
  final Lesson lesson;
}

class LessonListSuccess extends LessonResult {
  LessonListSuccess(this.lessons);
  final List<Lesson> lessons;
}

class LessonEmpty extends LessonResult {}

class LessonFailure extends LessonResult {
  LessonFailure(this.message);
  final String message;
}

/// Service interface for managing lessons.
abstract interface class LessonService {
  /// Create a new lesson for the authenticated teacher.
  Future<LessonResult> createLesson({
    required String title,
    required String description,
    required String subject,
    required String form,
  });

  /// Fetch all lessons created by the authenticated teacher.
  Future<LessonResult> fetchTeacherLessons();

  /// Fetch lessons relevant to a specific student (used by both parent and teacher).
  ///
  /// For parents, the RLS policy will automatically restrict visibility to lessons
  /// created by a teacher with an accepted relationship to the child, where the
  /// lesson matches the child's form and subjects.
  /// For teachers, the RLS policy restricts visibility to their own lessons, so
  /// this will just filter their own lessons down to those that match the student.
  Future<LessonResult> fetchStudentLessons(String studentId);

  /// Fetch a specific lesson by ID.
  Future<LessonResult> fetchLesson(String lessonId);

  /// Update an existing lesson.
  Future<LessonResult> updateLesson(Lesson lesson);

  /// Delete a lesson.
  Future<LessonResult> deleteLesson(String lessonId);
}

/// Supabase implementation of [LessonService].
class SupabaseLessonService implements LessonService {
  const SupabaseLessonService(this._client);
  final SupabaseClient _client;

  @override
  Future<LessonResult> createLesson({
    required String title,
    required String description,
    required String subject,
    required String form,
  }) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        return LessonFailure('You must be signed in to create a lesson.');
      }

      final data = await _client.from('lessons').insert({
        'teacher_id': user.id,
        'title': title,
        'description': description,
        'subject': subject,
        'form': form,
      }).select().single();

      return LessonSuccess(Lesson.fromJson(data));
    } catch (e) {
      return LessonFailure('Could not create lesson. Please try again.');
    }
  }

  @override
  Future<LessonResult> fetchTeacherLessons() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        return LessonFailure('You must be signed in to view your lessons.');
      }

      // RLS naturally restricts to the teacher's own lessons when queried by the teacher.
      final data = await _client
          .from('lessons')
          .select()
          .eq('teacher_id', user.id)
          .order('created_at', ascending: false);

      if (data.isEmpty) return LessonEmpty();
      
      final lessons = data.map(Lesson.fromJson).toList();
      return LessonListSuccess(lessons);
    } catch (e) {
      return LessonFailure('Could not fetch your lessons. Please try again.');
    }
  }

  @override
  Future<LessonResult> fetchStudentLessons(String studentId) async {
    try {
      // The parent's RLS policy on the lessons table will do the heavy lifting here.
      // It dynamically checks if the parent owns the student, if an accepted relationship exists,
      // and if the form and subjects match.
      // However, we still need to tell the query which child we're interested in if we're a parent with multiple children.
      // Wait, the RLS policy says:
      // "exists (select 1 from students s ... where s.parent_id = auth.uid() ... and s.school_level = lessons.form ...)"
      // This policy checks if THERE EXISTS ANY student owned by the parent matching the lesson.
      // If a parent has TWO children (Form 1 and Form 4), the policy allows reading BOTH Form 1 and Form 4 lessons.
      // So the application MUST also filter by the specific student's form/subjects on the client side,
      // or we must pass the specific student's criteria to the query.
      
      // Let's first fetch the specific student to know their form/subjects.
      final studentRes = await _client.from('students').select().eq('id', studentId).maybeSingle();
      if (studentRes == null) {
         return LessonFailure('Student not found.');
      }
      
      final schoolLevel = studentRes['school_level'] as String?;
      final subjects = (studentRes['subjects'] as List<dynamic>?)?.cast<String>() ?? [];
      
      if (schoolLevel == null || schoolLevel.isEmpty) {
         return LessonEmpty(); // A student with no form cannot have matching lessons.
      }
      if (subjects.isEmpty) {
         return LessonEmpty(); // A student with no subjects cannot have matching lessons.
      }
      
      // Now query lessons matching this specific student's form and subjects.
      // The RLS policy will ensure the parent can only actually see these if the teacher is connected.
      final data = await _client
          .from('lessons')
          .select()
          .eq('form', schoolLevel)
          .inFilter('subject', subjects)
          .order('created_at', ascending: false);

      if (data.isEmpty) return LessonEmpty();
      
      final lessons = data.map(Lesson.fromJson).toList();
      return LessonListSuccess(lessons);
    } catch (e) {
      return LessonFailure('Could not fetch lessons for this student.');
    }
  }

  @override
  Future<LessonResult> fetchLesson(String lessonId) async {
    try {
      final data = await _client.from('lessons').select().eq('id', lessonId).maybeSingle();
      if (data == null) {
        return LessonFailure('Lesson not found.');
      }
      return LessonSuccess(Lesson.fromJson(data));
    } catch (e) {
      return LessonFailure('Could not fetch lesson.');
    }
  }

  @override
  Future<LessonResult> updateLesson(Lesson lesson) async {
    try {
      final data = await _client
          .from('lessons')
          .update({
            'title': lesson.title,
            'description': lesson.description,
            'subject': lesson.subject,
            'form': lesson.form,
          })
          .eq('id', lesson.id)
          .select()
          .single();
      return LessonSuccess(Lesson.fromJson(data));
    } catch (e) {
      return LessonFailure('Could not update lesson. Please try again.');
    }
  }

  @override
  Future<LessonResult> deleteLesson(String lessonId) async {
    try {
      await _client.from('lessons').delete().eq('id', lessonId);
      return LessonEmpty(); // Using empty to signal successful deletion with no return data
    } catch (e) {
      return LessonFailure('Could not delete lesson.');
    }
  }
}

/// Fallback for when backend is not configured.
class UnconfiguredLessonService implements LessonService {
  const UnconfiguredLessonService();

  @override
  Future<LessonResult> createLesson({
    required String title,
    required String description,
    required String subject,
    required String form,
  }) async =>
      LessonFailure('Backend not configured.');

  @override
  Future<LessonResult> fetchTeacherLessons() async =>
      LessonFailure('Backend not configured.');

  @override
  Future<LessonResult> fetchStudentLessons(String studentId) async =>
      LessonFailure('Backend not configured.');

  @override
  Future<LessonResult> fetchLesson(String lessonId) async =>
      LessonFailure('Backend not configured.');

  @override
  Future<LessonResult> updateLesson(Lesson lesson) async =>
      LessonFailure('Backend not configured.');

  @override
  Future<LessonResult> deleteLesson(String lessonId) async =>
      LessonFailure('Backend not configured.');
}

/// Scope to provide [LessonService] to the widget tree.
class LessonServiceScope extends InheritedWidget {
  const LessonServiceScope({
    super.key,
    required this.lessonService,
    required super.child,
  });

  final LessonService lessonService;

  static LessonService of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<LessonServiceScope>();
    assert(scope != null, 'No LessonServiceScope found in widget tree.');
    return scope!.lessonService;
  }

  @override
  bool updateShouldNotify(LessonServiceScope oldWidget) {
    return lessonService != oldWidget.lessonService;
  }
}
