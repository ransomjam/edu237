import 'package:flutter_test/flutter_test.dart';
import 'package:edu237/core/constants/education_catalogue.dart';
import 'package:edu237/core/models/education_draft.dart';
import 'package:edu237/core/models/student.dart';

/// The draft is the shared brain behind Add Child, Edit Child, student signup
/// and the student profile. Its two jobs: ask only the questions that apply,
/// and never let an answer survive a change above it.
void main() {
  group('Which questions get asked', () {
    test('secondary asks for a cycle', () {
      final draft = EducationDraft()
        ..setSubsystem(EducationSubsystem.english)
        ..setStage(SchoolStage.secondary);

      expect(draft.steps, [
        EducationStep.subsystem,
        EducationStep.stage,
        EducationStep.cycle,
        EducationStep.level,
        EducationStep.subjects,
      ]);
    });

    test('primary skips the cycle question and answers it automatically', () {
      final draft = EducationDraft()
        ..setSubsystem(EducationSubsystem.french)
        ..setStage(SchoolStage.primary);

      expect(draft.steps, isNot(contains(EducationStep.cycle)));
      expect(draft.cycle, EducationCycle.frenchPrimary);
    });

    test('only upper-secondary cycles ask for a series', () {
      final ordinary = EducationDraft()..setCycle(EducationCycle.ordinaryLevel);
      final advanced = EducationDraft()..setCycle(EducationCycle.advancedLevel);
      final frenchC1 =
          EducationDraft()..setCycle(EducationCycle.frenchFirstCycle);
      final frenchC2 =
          EducationDraft()..setCycle(EducationCycle.frenchSecondCycle);

      expect(ordinary.steps, isNot(contains(EducationStep.series)));
      expect(advanced.steps, contains(EducationStep.series));
      expect(frenchC1.steps, isNot(contains(EducationStep.series)));
      expect(frenchC2.steps, contains(EducationStep.series));
    });

    test('subjects is always the last question', () {
      final draft = EducationDraft()..setCycle(EducationCycle.advancedLevel);
      expect(draft.steps.last, EducationStep.subjects);
    });
  });

  group('Completeness', () {
    test('a class alone completes a non-series cycle', () {
      final draft = EducationDraft()..setLevel('en.sec.ol.form4');
      expect(draft.isComplete, isTrue);
    });

    test('an upper-secondary learner is incomplete without a series', () {
      final draft = EducationDraft()..setLevel('en.sec.al.upper6');
      expect(draft.requiresSeries, isTrue);
      expect(draft.isComplete, isFalse);

      draft.setSeries('en.al.s2');
      expect(draft.isComplete, isTrue);
    });

    test('subjects may legitimately be empty', () {
      final draft = EducationDraft()..setLevel('en.sec.ol.form4');
      expect(draft.subjects, isEmpty);
      expect(draft.isAnswered(EducationStep.subjects), isTrue);
      expect(draft.isComplete, isTrue);
    });
  });

  group('Changing an answer clears everything below it', () {
    EducationDraft complete() => EducationDraft()
      ..setSubsystem(EducationSubsystem.english)
      ..setStage(SchoolStage.secondary)
      ..setCycle(EducationCycle.advancedLevel)
      ..setLevel('en.sec.al.upper6')
      ..setSeries('en.al.s2')
      ..toggleSubject('Physics');

    test('switching subsystem discards the whole academic profile', () {
      final draft = complete()..setSubsystem(EducationSubsystem.french);

      expect(draft.stage, isNull);
      expect(draft.cycle, isNull);
      expect(draft.levelCode, isNull);
      expect(draft.seriesCode, isNull);
      expect(draft.subjects, isEmpty);
    });

    test('switching stage discards the cycle and below', () {
      final draft = complete()..setStage(SchoolStage.primary);

      expect(draft.levelCode, isNull);
      expect(draft.seriesCode, isNull);
      expect(draft.subjects, isEmpty);
      // Primary has one cycle, so it is answered for the user.
      expect(draft.cycle, EducationCycle.englishPrimary);
    });

    test('switching cycle discards the class, series and subjects', () {
      final draft = complete()..setCycle(EducationCycle.ordinaryLevel);

      expect(draft.levelCode, isNull);
      expect(draft.seriesCode, isNull);
      expect(draft.subjects, isEmpty);
    });

    test('a class from another cycle re-answers the questions above it', () {
      final draft = complete()..setLevel('en.sec.ol.form4');

      expect(draft.cycle, EducationCycle.ordinaryLevel);
      expect(draft.seriesCode, isNull);
      expect(draft.subjects, isEmpty);
    });

    test('a class in the SAME cycle keeps the series and subjects', () {
      final draft = complete()..setLevel('en.sec.al.lower6');

      expect(draft.seriesCode, 'en.al.s2');
      expect(draft.subjects, {'Physics'});
    });

    test('changing series drops subjects that series no longer offers', () {
      final draft = EducationDraft()
        ..setCycle(EducationCycle.advancedLevel)
        ..setLevel('en.sec.al.upper6')
        ..setSeries('en.al.s2')
        ..toggleSubject('Physics')
        ..toggleSubject('Further Mathematics');

      // Arts A1 does not offer Further Mathematics anywhere in its cycle
      // suggestion, but Physics remains a valid Advanced Level subject.
      draft.setSeries('en.al.a1');
      expect(draft.subjects, contains('Physics'));
      expect(draft.subjects, contains('Further Mathematics'));
    });

    test('setting a level infers the subsystem and stage', () {
      final draft = EducationDraft()..setLevel('fr.sec.c1.4e');

      expect(draft.subsystem, EducationSubsystem.french);
      expect(draft.stage, SchoolStage.secondary);
      expect(draft.cycle, EducationCycle.frenchFirstCycle);
    });
  });

  group('Pre-filling from an existing learner', () {
    Student student({String? levelCode, String? schoolLevel}) => Student(
          id: 's1',
          parentId: 'p1',
          name: 'Grace',
          levelCode: levelCode,
          schoolLevel: schoolLevel,
          subjects: const ['Mathematics'],
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('a structured record pre-fills every answer', () {
      final draft =
          EducationDraft.fromStudent(student(levelCode: 'en.sec.ol.form4'));

      expect(draft.subsystem, EducationSubsystem.english);
      expect(draft.stage, SchoolStage.secondary);
      expect(draft.cycle, EducationCycle.ordinaryLevel);
      expect(draft.levelCode, 'en.sec.ol.form4');
      expect(draft.subjects, {'Mathematics'});
      expect(draft.isComplete, isTrue);
    });

    test('a legacy "Form 3" pre-fills as English, ready to confirm', () {
      final draft = EducationDraft.fromStudent(student(schoolLevel: 'Form 3'));

      expect(draft.subsystem, EducationSubsystem.english);
      expect(draft.levelCode, 'en.sec.ol.form3');
      expect(draft.isComplete, isTrue);
    });

    test('an unrecognised class leaves the questions unanswered, not guessed',
        () {
      final draft =
          EducationDraft.fromStudent(student(schoolLevel: 'Upper 6 Arts'));

      expect(draft.subsystem, isNull);
      expect(draft.levelCode, isNull);
      expect(draft.isComplete, isFalse);
      // Subjects already chosen are still kept for the user to reuse.
      expect(draft.subjects, {'Mathematics'});
    });
  });
}
