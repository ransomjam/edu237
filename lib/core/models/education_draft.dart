import '../constants/education_catalogue.dart';
import 'student.dart';

/// A step in the education hierarchy the user is being asked about.
///
/// The list of steps is computed, not fixed: primary school has a single
/// cycle so that question is answered automatically, and only upper-secondary
/// cycles ask for a series.
enum EducationStep {
  subsystem,
  stage,
  cycle,
  level,
  series,
  subjects;

  /// The question shown as the step heading.
  String get question => switch (this) {
        EducationStep.subsystem => 'Which education system?',
        EducationStep.stage => 'Primary or secondary?',
        EducationStep.cycle => 'Which cycle?',
        EducationStep.level => 'Which class?',
        EducationStep.series => 'Which series?',
        EducationStep.subjects => 'Which subjects?',
      };
}

/// Mutable working state for choosing an academic profile.
///
/// Shared by the parent Add/Edit Child flow, student signup and the student
/// profile so all three ask the same questions in the same order and produce
/// the same structured result. Changing an answer clears everything below it,
/// which is what stops an English series being attached to a French class.
class EducationDraft {
  EducationDraft({
    this.subsystem,
    this.stage,
    this.cycle,
    this.levelCode,
    this.seriesCode,
    Set<String>? subjects,
  }) : subjects = subjects ?? <String>{};

  EducationSubsystem? subsystem;
  SchoolStage? stage;
  EducationCycle? cycle;
  String? levelCode;
  String? seriesCode;
  final Set<String> subjects;

  /// Rebuilds a draft from an existing learner record so Edit pre-fills.
  /// A legacy record whose level cannot be resolved comes back empty apart
  /// from its subjects — the user is asked to confirm the class.
  factory EducationDraft.fromStudent(Student student) {
    final level = student.level;
    return EducationDraft(
      subsystem: student.effectiveSubsystem,
      stage: student.effectiveStage,
      cycle: student.effectiveCycle,
      levelCode: level?.code,
      seriesCode: student.seriesCode,
      subjects: student.subjects.toSet(),
    );
  }

  EducationLevel? get level => EducationCatalogue.levelByCode(levelCode);

  EducationSeries? get series => EducationCatalogue.seriesByCode(seriesCode);

  /// True when the chosen cycle carries a series (GCE Advanced Level, or the
  /// French second cycle).
  bool get requiresSeries => cycle?.hasSeries ?? false;

  /// True once there is enough to save a structured academic profile.
  bool get isComplete =>
      levelCode != null && (!requiresSeries || seriesCode != null);

  /// The questions to ask, in order, given the answers so far.
  List<EducationStep> get steps {
    final result = <EducationStep>[EducationStep.subsystem, EducationStep.stage];
    final sub = subsystem;
    final st = stage;
    if (sub != null && st != null) {
      // Skip the cycle question when the stage has only one cycle.
      if (EducationCatalogue.cyclesFor(sub, st).length > 1) {
        result.add(EducationStep.cycle);
      }
      result.add(EducationStep.level);
      if (requiresSeries) result.add(EducationStep.series);
    } else {
      // Nothing chosen yet: assume the common secondary shape so the step
      // count shown to the user does not jump around on the first answer.
      result.add(EducationStep.cycle);
      result.add(EducationStep.level);
    }
    result.add(EducationStep.subjects);
    return result;
  }

  /// True when [step] has been answered.
  bool isAnswered(EducationStep step) => switch (step) {
        EducationStep.subsystem => subsystem != null,
        EducationStep.stage => stage != null,
        EducationStep.cycle => cycle != null,
        EducationStep.level => levelCode != null,
        EducationStep.series => seriesCode != null,
        EducationStep.subjects => true, // subjects may legitimately be empty
      };

  /// The message shown when the user tries to move past an unanswered step.
  String validationMessage(EducationStep step) => switch (step) {
        EducationStep.subsystem => 'Please choose an education system.',
        EducationStep.stage => 'Please choose primary or secondary.',
        EducationStep.cycle => 'Please choose a cycle.',
        EducationStep.level => 'Please choose a class to continue.',
        EducationStep.series => 'Please choose a series to continue.',
        EducationStep.subjects => '',
      };

  // -- Mutations. Each clears everything below it. -------------------------

  void setSubsystem(EducationSubsystem value) {
    if (subsystem == value) return;
    subsystem = value;
    stage = null;
    _clearFromCycle();
  }

  void setStage(SchoolStage value) {
    if (stage == value) return;
    stage = value;
    _clearFromCycle();
    // Auto-answer the cycle when the stage offers exactly one.
    final sub = subsystem;
    if (sub != null) {
      final cycles = EducationCatalogue.cyclesFor(sub, value);
      if (cycles.length == 1) cycle = cycles.single;
    }
  }

  void setCycle(EducationCycle value) {
    if (cycle == value) return;
    cycle = value;
    subsystem = value.subsystem;
    stage = value.stage;
    levelCode = null;
    seriesCode = null;
    subjects.clear();
  }

  void setLevel(String code) {
    if (levelCode == code) return;
    levelCode = code;
    final resolved = EducationCatalogue.levelByCode(code);
    if (resolved != null) {
      subsystem = resolved.subsystem;
      stage = resolved.stage;
      if (cycle != resolved.cycle) {
        cycle = resolved.cycle;
        seriesCode = null;
        subjects.clear();
      }
    }
  }

  void setSeries(String code) {
    if (seriesCode == code) return;
    seriesCode = code;
    // A different series suggests a different subject pool; drop subjects that
    // are no longer offered rather than silently keeping an invalid one.
    final allowed = EducationCatalogue.subjectLabelsFor(
      cycle: cycle!,
      series: EducationCatalogue.seriesByCode(code),
      includeAllForCycle: true,
    ).toSet();
    subjects.removeWhere((s) => !allowed.contains(s));
  }

  void toggleSubject(String label) {
    if (!subjects.remove(label)) subjects.add(label);
  }

  void _clearFromCycle() {
    cycle = null;
    levelCode = null;
    seriesCode = null;
    subjects.clear();
  }
}
