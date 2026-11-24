import 'package:flutter_test/flutter_test.dart';
import 'package:edu237/core/constants/education_catalogue.dart';

/// The catalogue is product data that the whole app depends on, so these tests
/// assert the *structure* Cameroon actually uses rather than re-listing every
/// label. If a structural rule here breaks, matching and discovery break too.
void main() {
  group('Subsystems and stages', () {
    test('exactly two general-education subsystems', () {
      expect(
        EducationSubsystem.values.map((s) => s.code),
        ['english', 'french'],
      );
    });

    test('each subsystem offers primary and secondary', () {
      for (final subsystem in EducationSubsystem.values) {
        expect(
          EducationCatalogue.stagesFor(subsystem),
          [SchoolStage.primary, SchoolStage.secondary],
        );
      }
    });

    test('stage names follow the subsystem wording', () {
      expect(SchoolStage.secondary.labelFor(EducationSubsystem.english),
          'Secondary School');
      expect(SchoolStage.secondary.labelFor(EducationSubsystem.french),
          'Enseignement Secondaire');
    });
  });

  group('English subsystem', () {
    test('primary is a six-year cycle, Class 1 to Class 6', () {
      final levels = EducationCatalogue.levelsForCycle(
          EducationCycle.englishPrimary);
      expect(levels.length, 6);
      expect(levels.map((l) => l.label),
          ['Class 1', 'Class 2', 'Class 3', 'Class 4', 'Class 5', 'Class 6']);
    });

    test('secondary splits into Ordinary and Advanced Level', () {
      final cycles = EducationCatalogue.cyclesFor(
          EducationSubsystem.english, SchoolStage.secondary);
      expect(cycles,
          [EducationCycle.ordinaryLevel, EducationCycle.advancedLevel]);
    });

    test('the first cycle is five years, Form 1 to Form 5', () {
      final levels =
          EducationCatalogue.levelsForCycle(EducationCycle.ordinaryLevel);
      expect(levels.length, 5);
      expect(levels.map((l) => l.label),
          ['Form 1', 'Form 2', 'Form 3', 'Form 4', 'Form 5']);
    });

    test('the second cycle is two years: Lower and Upper Sixth', () {
      final levels =
          EducationCatalogue.levelsForCycle(EducationCycle.advancedLevel);
      expect(levels.map((l) => l.label), ['Lower Sixth', 'Upper Sixth']);
    });
  });

  group('French subsystem', () {
    test('primary is SIL, CP, CE1, CE2, CM1, CM2', () {
      final levels =
          EducationCatalogue.levelsForCycle(EducationCycle.frenchPrimary);
      expect(levels.map((l) => l.label),
          ['SIL', 'CP', 'CE1', 'CE2', 'CM1', 'CM2']);
      expect(levels.first.alternateLabel, "Section d'Initiation au Langage");
    });

    test('the first cycle is four years, 6ème to 3ème', () {
      final levels =
          EducationCatalogue.levelsForCycle(EducationCycle.frenchFirstCycle);
      expect(levels.length, 4);
      expect(levels.map((l) => l.label), ['6ème', '5ème', '4ème', '3ème']);
    });

    test('the second cycle is Seconde, Première, Terminale', () {
      final levels =
          EducationCatalogue.levelsForCycle(EducationCycle.frenchSecondCycle);
      expect(levels.map((l) => l.label),
          ['Seconde', 'Première', 'Terminale']);
    });
  });

  group('Level identity', () {
    test('every level code is unique', () {
      final codes = EducationCatalogue.allLevels.map((l) => l.code).toList();
      expect(codes.toSet().length, codes.length);
    });

    test('every level label is unique across BOTH subsystems', () {
      // This is what makes the denormalised label columns (school_level,
      // teacher_profiles.forms) safe: a label can only mean one class.
      final labels = EducationCatalogue.allLevels
          .map((l) => l.label.toLowerCase())
          .toList();
      expect(labels.toSet().length, labels.length);
    });

    test('a level carries its own subsystem, stage and cycle', () {
      final form4 = EducationCatalogue.levelByCode('en.sec.ol.form4')!;
      expect(form4.subsystem, EducationSubsystem.english);
      expect(form4.stage, SchoolStage.secondary);
      expect(form4.cycle, EducationCycle.ordinaryLevel);
    });

    test('labels are qualified by subsystem so they are never ambiguous', () {
      expect(EducationCatalogue.levelByCode('en.sec.ol.form4')!.qualifiedLabel,
          'English · Form 4');
      expect(EducationCatalogue.levelByCode('fr.sec.c1.4e')!.qualifiedLabel,
          'French · 4ème');
    });

    test('legacy labels resolve, unknown ones return null rather than guess',
        () {
      expect(EducationCatalogue.interpretLegacyLevel('Form 3')?.code,
          'en.sec.ol.form3');
      expect(EducationCatalogue.interpretLegacyLevel('  form 3  ')?.code,
          'en.sec.ol.form3');
      expect(EducationCatalogue.interpretLegacyLevel('4ème')?.code,
          'fr.sec.c1.4e');
      expect(EducationCatalogue.interpretLegacyLevel('Upper 6 Arts'), isNull);
      expect(EducationCatalogue.interpretLegacyLevel(''), isNull);
      expect(EducationCatalogue.interpretLegacyLevel(null), isNull);
    });
  });

  group('Series', () {
    test('only the two upper-secondary cycles carry a series', () {
      for (final cycle in EducationCycle.values) {
        final hasSeries = EducationCatalogue.seriesForCycle(cycle).isNotEmpty;
        expect(hasSeries, cycle.hasSeries, reason: cycle.code);
      }
      expect(
        EducationCycle.values.where((c) => c.hasSeries),
        [EducationCycle.advancedLevel, EducationCycle.frenchSecondCycle],
      );
    });

    test('GCE Advanced Level offers Arts A1–A5 and Science S1–S4', () {
      final series = EducationCatalogue.advancedLevelSeries;
      expect(
        series.where((s) => s.group == SeriesGroup.arts).map((s) => s.label),
        ['A1', 'A2', 'A3', 'A4', 'A5'],
      );
      expect(
        series.where((s) => s.group == SeriesGroup.science).map((s) => s.label),
        ['S1', 'S2', 'S3', 'S4'],
      );
    });

    test('the French second cycle offers A1–A5, C, D, TI and BIL', () {
      final series = EducationCatalogue.frenchSecondCycleSeries;
      expect(series.map((s) => s.label),
          ['A1', 'A2', 'A3', 'A4', 'A5', 'C', 'D', 'TI', 'BIL']);
      expect(
        series.where((s) => s.group == SeriesGroup.science).map((s) => s.label),
        ['C', 'D'],
      );
      expect(
        series
            .where((s) => s.group == SeriesGroup.specialised)
            .map((s) => s.label),
        ['TI', 'BIL'],
      );
    });

    test('every series code is unique and namespaced by subsystem', () {
      final codes = EducationCatalogue.allSeries.map((s) => s.code).toList();
      expect(codes.toSet().length, codes.length);
      // English A1 and French A1 share a label but never a code.
      expect(EducationCatalogue.seriesByCode('en.al.a1')!.subsystem,
          EducationSubsystem.english);
      expect(EducationCatalogue.seriesByCode('fr.c2.a1')!.subsystem,
          EducationSubsystem.french);
    });

    test('a series belongs to its own cycle only', () {
      for (final series in EducationCatalogue.advancedLevelSeries) {
        expect(series.cycle, EducationCycle.advancedLevel);
      }
      for (final series in EducationCatalogue.frenchSecondCycleSeries) {
        expect(series.cycle, EducationCycle.frenchSecondCycle);
      }
    });
  });

  group('Subject catalogue is context-aware', () {
    test('no cycle is shown the whole catalogue', () {
      for (final cycle in EducationCycle.values) {
        final codes = EducationCatalogue.subjectCodesForCycle(cycle);
        expect(codes, isNotEmpty, reason: cycle.code);
        expect(codes.length,
            lessThan(EducationCatalogue.allSubjects.length),
            reason: cycle.code);
      }
    });

    test('primary does not offer Ordinary Level specialisms', () {
      final primary = EducationCatalogue.subjectCodesForCycle(
          EducationCycle.englishPrimary);
      expect(primary, contains('mathematics'));
      expect(primary, contains('general_science'));
      expect(primary, isNot(contains('additional_mathematics')));
      expect(primary, isNot(contains('further_mathematics')));
    });

    test('Further Mathematics is Advanced Level only', () {
      expect(
        EducationCatalogue.subjectCodesForCycle(EducationCycle.ordinaryLevel),
        isNot(contains('further_mathematics')),
      );
      expect(
        EducationCatalogue.subjectCodesForCycle(EducationCycle.advancedLevel),
        contains('further_mathematics'),
      );
    });

    test('subject labels follow the subsystem, from one shared definition', () {
      final maths = EducationCatalogue.subjectByCode('mathematics')!;
      expect(maths.labelFor(EducationSubsystem.english), 'Mathematics');
      expect(maths.labelFor(EducationSubsystem.french), 'Mathématiques');

      expect(
        EducationCatalogue.subjectLabelsFor(
            cycle: EducationCycle.frenchFirstCycle),
        contains('Mathématiques'),
      );
      expect(
        EducationCatalogue.subjectLabelsFor(
            cycle: EducationCycle.ordinaryLevel),
        contains('Mathematics'),
      );
    });

    test('every subject code referenced by a cycle exists', () {
      for (final cycle in EducationCycle.values) {
        for (final code in EducationCatalogue.subjectCodesForCycle(cycle)) {
          expect(EducationCatalogue.subjectByCode(code), isNotNull,
              reason: '$code (${cycle.code})');
        }
      }
    });

    test('every series suggestion is a real subject of its own cycle', () {
      for (final series in EducationCatalogue.allSeries) {
        final cycleCodes =
            EducationCatalogue.subjectCodesForCycle(series.cycle);
        for (final code in series.suggestedSubjectCodes) {
          expect(EducationCatalogue.subjectByCode(code), isNotNull,
              reason: '$code (${series.code})');
          expect(cycleCodes, contains(code), reason: '$code (${series.code})');
        }
      }
    });

    test('choosing a series narrows the subjects offered', () {
      final all = EducationCatalogue.subjectLabelsFor(
          cycle: EducationCycle.advancedLevel);
      final arts = EducationCatalogue.subjectLabelsFor(
        cycle: EducationCycle.advancedLevel,
        series: EducationCatalogue.seriesByCode('en.al.a1'),
      );

      expect(arts.length, lessThan(all.length));
      expect(arts, contains('Literature in English'));
      expect(arts, isNot(contains('Further Mathematics')));
    });

    test('the rest of the cycle can still be revealed under a series', () {
      final expanded = EducationCatalogue.subjectLabelsFor(
        cycle: EducationCycle.advancedLevel,
        series: EducationCatalogue.seriesByCode('en.al.a1'),
        includeAllForCycle: true,
      );

      expect(expanded, contains('Further Mathematics'));
      // Suggestions still come first, and nothing is duplicated.
      expect(expanded.first, 'Literature in English');
      expect(expanded.toSet().length, expanded.length);
    });

    test('a subsystem never sees the other subsystem\'s labels', () {
      final english =
          EducationCatalogue.allSubjectLabelsFor(EducationSubsystem.english);
      final french =
          EducationCatalogue.allSubjectLabelsFor(EducationSubsystem.french);

      expect(english, contains('Mathematics'));
      expect(english, isNot(contains('Mathématiques')));
      expect(french, contains('Mathématiques'));
      expect(french, isNot(contains('Mathematics')));
    });
  });
}
