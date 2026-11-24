import 'package:flutter_test/flutter_test.dart';
import 'package:edu237/core/constants/education_catalogue.dart';
import 'package:edu237/core/models/student.dart';

void main() {
  group('Student', () {
    test('parses from a valid map', () {
      final model = Student.fromMap({
        'id': 'stu-1',
        'parent_id': 'parent-1',
        'name': 'Junior',
        'date_of_birth': '2012-05-01T00:00:00.000Z',
        'school_level': 'Form 4',
        'notes': 'Struggles with algebra',
        'created_at': '2023-01-01T00:00:00.000Z',
        'updated_at': '2023-01-01T00:00:00.000Z',
      });

      expect(model.id, 'stu-1');
      expect(model.parentId, 'parent-1');
      expect(model.name, 'Junior');
      expect(model.dateOfBirth, DateTime.parse('2012-05-01T00:00:00.000Z'));
      expect(model.schoolLevel, 'Form 4');
      expect(model.notes, 'Struggles with algebra');
    });

    test('parses subjects from a text[] column', () {
      final model = Student.fromMap({
        'id': 'stu-1',
        'parent_id': 'parent-1',
        'name': 'Junior',
        'school_level': 'Form 4',
        'subjects': ['Mathematics', 'Physics', 'Chemistry'],
        'created_at': '2023-01-01T00:00:00.000Z',
        'updated_at': '2023-01-01T00:00:00.000Z',
      });
      expect(model.subjects, ['Mathematics', 'Physics', 'Chemistry']);
    });

    test('a legacy row without a subjects column defaults to empty (Grace)', () {
      // Simulates the existing "Grace / Form 3" row created before subjects
      // existed: no `subjects` key at all.
      final grace = Student.fromMap({
        'id': 'grace-1',
        'parent_id': 'parent-1',
        'name': 'Grace',
        'school_level': 'Form 3',
        'created_at': '2026-08-11T19:22:01.000Z',
        'updated_at': '2026-08-11T19:22:01.000Z',
      });
      expect(grace.name, 'Grace');
      expect(grace.schoolLevel, 'Form 3');
      expect(grace.subjects, isEmpty);
    });

    test('subjects defaults to an empty list on the constructor', () {
      final model = Student(
        id: '',
        parentId: 'parent-1',
        name: 'Sam',
        createdAt: DateTime(2023),
        updatedAt: DateTime(2023),
      );
      expect(model.subjects, isEmpty);
    });

    test('a student is owned by a parent (parent_id)', () {
      final model = Student.fromMap({
        'id': 'stu-2',
        'parent_id': 'parent-abc',
        'name': 'Ada',
        'created_at': '2023-01-01T00:00:00.000Z',
        'updated_at': '2023-01-01T00:00:00.000Z',
      });
      expect(model.parentId, 'parent-abc');
    });

    test('tolerates missing optional fields', () {
      final model = Student.fromMap({
        'id': 'stu-3',
        'parent_id': 'parent-1',
        'name': 'Sam',
        'created_at': '2023-01-01T00:00:00.000Z',
        'updated_at': '2023-01-01T00:00:00.000Z',
      });
      expect(model.dateOfBirth, isNull);
      expect(model.schoolLevel, isNull);
      expect(model.notes, isNull);
    });

    test('throws FormatException when required fields are missing', () {
      expect(
        () => Student.fromMap({
          'id': 'stu-4',
          'parent_id': 'parent-1',
          // missing name
          'created_at': '2023-01-01T00:00:00.000Z',
          'updated_at': '2023-01-01T00:00:00.000Z',
        }),
        throwsFormatException,
      );
    });

    test('a self-managed student row has no parent but does have a user_id',
        () {
      final model = Student.fromMap({
        'id': 'stu-5',
        // No parent_id: this learner signed up themselves.
        'user_id': 'auth-user-9',
        'name': 'Ngwa',
        'level_code': 'fr.sec.c1.4e',
        'created_at': '2026-08-14T00:00:00.000Z',
        'updated_at': '2026-08-14T00:00:00.000Z',
      });

      expect(model.parentId, isEmpty);
      expect(model.hasParent, isFalse);
      expect(model.userId, 'auth-user-9');
      expect(model.hasAccount, isTrue);
    });

    test('has no authentication fields — insert payload never carries '
        'email/password/phone', () {
      final student = Student(
        id: '',
        parentId: 'parent-1',
        name: 'Junior',
        subjects: const ['Mathematics'],
        createdAt: DateTime(2023),
        updatedAt: DateTime(2023),
      );
      final insert = student.toInsertMap(parentId: 'parent-1');

      expect(insert.containsKey('email'), isFalse);
      expect(insert.containsKey('password'), isFalse);
      expect(insert.containsKey('phone'), isFalse);
      // Only the expected domain columns are present.
      expect(
        insert.keys.toSet(),
        {
          'parent_id',
          'name',
          'date_of_birth',
          'school_level',
          'subsystem',
          'school_stage',
          'cycle',
          'level_code',
          'series_code',
          'subjects',
          'notes',
        },
      );
      expect(insert['subjects'], ['Mathematics']);
    });
  });

  group('Student academic profile', () {
    Student withLevel(String levelCode, {String? seriesCode}) => Student(
          id: 'stu-1',
          parentId: 'parent-1',
          name: 'Daniel',
          levelCode: levelCode,
          seriesCode: seriesCode,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('derives subsystem, stage and cycle from the level code alone', () {
      final child = withLevel('en.sec.ol.form4');

      expect(child.effectiveSubsystem, EducationSubsystem.english);
      expect(child.effectiveStage, SchoolStage.secondary);
      expect(child.effectiveCycle, EducationCycle.ordinaryLevel);
      expect(child.level?.label, 'Form 4');
    });

    test('a French 4eme is a different level from an English Form 4', () {
      final french = withLevel('fr.sec.c1.4e');
      final english = withLevel('en.sec.ol.form4');

      expect(french.effectiveSubsystem, EducationSubsystem.french);
      expect(english.effectiveSubsystem, EducationSubsystem.english);
      expect(french.levelCode, isNot(english.levelCode));
      expect(french.qualifiedLevelLabel, 'French · 4ème');
      expect(english.qualifiedLevelLabel, 'English · Form 4');
    });

    test('school_level is re-derived from level_code so it cannot drift', () {
      final child = Student(
        id: 'stu-1',
        parentId: 'parent-1',
        name: 'Daniel',
        // A stale label that disagrees with the structured level.
        schoolLevel: 'Form 1',
        levelCode: 'en.sec.ol.form4',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      final fields = child.toWriteFields();
      expect(fields['school_level'], 'Form 4');
      expect(fields['level_code'], 'en.sec.ol.form4');
      expect(fields['subsystem'], 'english');
      expect(fields['school_stage'], 'secondary');
      expect(fields['cycle'], 'en.sec.ol');
    });

    test('an upper-secondary learner keeps their series', () {
      final child = withLevel('en.sec.al.upper6', seriesCode: 'en.al.s2');

      expect(child.effectiveCycle, EducationCycle.advancedLevel);
      expect(child.series?.label, 'S2');
      expect(child.educationSummary, contains('Science S2'));
    });

    test('educationSummary reads as a hierarchy, not a single label', () {
      expect(
        withLevel('en.sec.ol.form4').educationSummary,
        'English Subsystem · Secondary School · Ordinary Level '
        '· Form 4',
      );
    });
  });

  group('Legacy education records', () {
    Student legacy(String? schoolLevel) => Student(
          id: 'stu-legacy',
          parentId: 'parent-1',
          name: 'Grace',
          schoolLevel: schoolLevel,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('a legacy "Form 3" resolves to the English subsystem', () {
      final grace = legacy('Form 3');

      expect(grace.levelCode, isNull);
      expect(grace.level?.code, 'en.sec.ol.form3');
      expect(grace.effectiveSubsystem, EducationSubsystem.english);
      expect(grace.needsEducationReview, isFalse);
    });

    test('an unrecognised class is preserved and flagged for review, never '
        'guessed', () {
      final odd = legacy('Upper 6 Arts');

      expect(odd.level, isNull);
      expect(odd.effectiveSubsystem, isNull);
      expect(odd.needsEducationReview, isTrue);
      // The original value survives so the parent can confirm it.
      expect(odd.qualifiedLevelLabel, 'Upper 6 Arts');
      expect(odd.toWriteFields()['school_level'], 'Upper 6 Arts');
    });

    test('a record with no class at all does not ask for review', () {
      expect(legacy(null).needsEducationReview, isFalse);
    });
  });
}
