import 'package:flutter_test/flutter_test.dart';
import 'package:edu237/core/models/student.dart';
import 'package:edu237/core/models/teacher_profile.dart';
import 'package:edu237/core/services/teacher_matching.dart';

TeacherProfile _teacher(
  String name, {
  required List<String> forms,
  required List<String> subjects,
}) =>
    TeacherProfile(
      id: name,
      userId: 'u-$name',
      displayName: name,
      subjects: subjects,
      forms: forms,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Student _child({String? form, List<String> subjects = const []}) => Student(
      id: 'c1',
      parentId: 'p1',
      name: 'Child',
      schoolLevel: form,
      subjects: subjects,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  // The four deliberate cases from the brief.
  final teacherA =
      _teacher('A', forms: ['Form 4'], subjects: ['Mathematics', 'Physics']);
  final teacherB = _teacher('B', forms: ['Form 1'], subjects: ['Biology']);
  final teacherC = _teacher('C', forms: ['Form 4'], subjects: ['History']);
  final teacherD = _teacher('D', forms: ['Form 4'], subjects: ['Mathematics']);
  final all = [teacherA, teacherB, teacherC, teacherD];

  group('rankTeachersForChild — Form 4 child taking Maths + Physics', () {
    final child = _child(form: 'Form 4', subjects: ['Mathematics', 'Physics']);
    late List<TeacherMatch> ranked;

    setUp(() => ranked = rankTeachersForChild(child, all));

    test('Teacher B (Form 1, Biology) is excluded as irrelevant', () {
      expect(ranked.map((m) => m.teacher.displayName), isNot(contains('B')));
    });

    test('Teachers A and D are relevant and ranked above C', () {
      final names = ranked.map((m) => m.teacher.displayName).toList();
      expect(names, containsAll(<String>['A', 'D', 'C']));
      expect(names.indexOf('A'), lessThan(names.indexOf('C')));
      expect(names.indexOf('D'), lessThan(names.indexOf('C')));
    });

    test('Teacher A is the single most relevant (form + both subjects)', () {
      expect(ranked.first.teacher.displayName, 'A');
      expect(ranked.first.matchedSubjects.toSet(),
          {'Mathematics', 'Physics'});
    });

    test('Teacher C is included but lowest (same form, subject mismatch)', () {
      expect(ranked.last.teacher.displayName, 'C');
      expect(ranked.last.matchedSubjects, isEmpty);
      expect(ranked.last.formMatches, isTrue);
    });
  });

  test('child with no subjects → only teachers of the same form appear', () {
    final child = _child(form: 'Form 4', subjects: const []);
    final ranked = rankTeachersForChild(child, all);
    final names = ranked.map((m) => m.teacher.displayName).toSet();
    // A, C, D teach Form 4; B teaches Form 1.
    expect(names, {'A', 'C', 'D'});
    expect(names, isNot(contains('B')));
  });

  test('child with one subject → subject + form overlap ranks highest', () {
    final child = _child(form: 'Form 4', subjects: ['Mathematics']);
    final ranked = rankTeachersForChild(child, all);
    final names = ranked.map((m) => m.teacher.displayName).toList();
    // A and D both match Maths+form (score 15); C only form (score 5).
    expect(names.first, anyOf('A', 'D'));
    expect(names.last, 'C');
    expect(names, isNot(contains('B')));
  });

  test('child with multiple subjects → more overlap scores higher', () {
    final child = _child(form: 'Form 4', subjects: ['Mathematics', 'Physics']);
    final ranked = rankTeachersForChild(child, all);
    expect(ranked.first.teacher.displayName, 'A'); // 2 overlaps beats 1
    expect(ranked.map((m) => m.teacher.displayName).toList().indexOf('D'),
        greaterThan(0));
  });

  test('no matching teachers → empty result', () {
    final child = _child(form: 'Form 6', subjects: ['Accounting']);
    final ranked = rankTeachersForChild(child, all);
    expect(ranked, isEmpty);
  });

  test('child with no form and no subjects → empty result', () {
    final child = _child(form: null, subjects: const []);
    expect(rankTeachersForChild(child, all), isEmpty);
  });

  // ---------------------------------------------------------------------------
  // Subsystem-aware matching — the critical distinction
  // ---------------------------------------------------------------------------
  group('subsystem is a hard gate', () {
    TeacherProfile structured(
      String name, {
      required List<String> levelCodes,
      required List<String> subjects,
      List<String> seriesCodes = const [],
    }) =>
        TeacherProfile(
          id: name,
          userId: 'u-$name',
          displayName: name,
          subjects: subjects,
          levelCodes: levelCodes,
          seriesCodes: seriesCodes,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    Student learner(
      String levelCode, {
      List<String> subjects = const [],
      String? seriesCode,
    }) =>
        Student(
          id: 'c1',
          parentId: 'p1',
          name: 'Child',
          levelCode: levelCode,
          seriesCode: seriesCode,
          subjects: subjects,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    final englishForm4 = structured('English Form 4',
        levelCodes: ['en.sec.ol.form4'], subjects: ['Mathematics']);
    final french4eme = structured('French 4ème',
        levelCodes: ['fr.sec.c1.4e'], subjects: ['Mathématiques']);

    test('a French 4ème learner is NOT matched with an English Form 4 teacher',
        () {
      final child = learner('fr.sec.c1.4e', subjects: ['Mathématiques']);
      final ranked = rankTeachersForChild(child, [englishForm4, french4eme]);

      expect(ranked.map((m) => m.teacher.displayName), ['French 4ème']);
    });

    test('an English Form 4 learner is NOT matched with a French 4ème teacher',
        () {
      final child = learner('en.sec.ol.form4', subjects: ['Mathematics']);
      final ranked = rankTeachersForChild(child, [englishForm4, french4eme]);

      expect(ranked.map((m) => m.teacher.displayName), ['English Form 4']);
    });

    test('the subsystem gate holds even when subject labels are shared', () {
      // "Informatique" would be the label on both sides if a teacher taught
      // both; the subsystem still decides.
      final bilingual = structured('Bilingual',
          levelCodes: ['en.sec.ol.form4', 'fr.sec.c1.4e'],
          subjects: ['Mathematics', 'Mathématiques']);

      final english = learner('en.sec.ol.form4', subjects: ['Mathematics']);
      final french = learner('fr.sec.c1.4e', subjects: ['Mathématiques']);

      // A teacher covering both subsystems matches both learners...
      expect(rankTeachersForChild(english, [bilingual]).single.formMatches,
          isTrue);
      expect(rankTeachersForChild(french, [bilingual]).single.formMatches,
          isTrue);

      // ...but is scored only on the half that applies.
      expect(
        rankTeachersForChild(english, [bilingual]).single.matchedSubjects,
        ['Mathematics'],
      );
    });

    test('teacherIsCompatibleWith reflects the same rule', () {
      final french = learner('fr.sec.c1.4e');
      expect(teacherIsCompatibleWith(englishForm4, french), isFalse);
      expect(teacherIsCompatibleWith(french4eme, french), isTrue);
    });

    test('a legacy teacher with no structured levels is not filtered out', () {
      final legacy = _teacher('Legacy',
          forms: const ['Form 4'], subjects: const ['Mathematics']);
      final child = learner('en.sec.ol.form4', subjects: ['Mathematics']);

      final ranked = rankTeachersForChild(child, [legacy]);
      expect(ranked.single.formMatches, isTrue);
    });

    test('a matching series adds relevance on top of the class', () {
      final withSeries = structured('With series',
          levelCodes: ['en.sec.al.upper6'],
          seriesCodes: ['en.al.s2'],
          subjects: ['Physics']);
      final withoutSeries = structured('Without series',
          levelCodes: ['en.sec.al.upper6'], subjects: ['Physics']);

      final child = learner('en.sec.al.upper6',
          seriesCode: 'en.al.s2', subjects: ['Physics']);
      final ranked =
          rankTeachersForChild(child, [withoutSeries, withSeries]);

      expect(ranked.first.teacher.displayName, 'With series');
      expect(ranked.first.seriesMatches, isTrue);
      expect(ranked.last.seriesMatches, isFalse);
    });

    test('same cycle beats a different cycle in the same subsystem', () {
      final sameCycle = structured('Same cycle',
          levelCodes: ['en.sec.ol.form5'], subjects: ['Mathematics']);
      final otherCycle = structured('Other cycle',
          levelCodes: ['en.sec.al.lower6'], subjects: ['Mathematics']);

      final child = learner('en.sec.ol.form4', subjects: ['Mathematics']);
      final ranked = rankTeachersForChild(child, [otherCycle, sameCycle]);

      expect(ranked.first.teacher.displayName, 'Same cycle');
      expect(ranked.first.cycleMatches, isTrue);
      expect(ranked.last.cycleMatches, isFalse);
    });
  });
}
