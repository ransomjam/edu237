import '../constants/education_catalogue.dart';
import '../models/student.dart';
import '../models/teacher_profile.dart';

/// A teacher scored for how well they fit a particular learner.
class TeacherMatch {
  const TeacherMatch({
    required this.teacher,
    required this.score,
    required this.matchedSubjects,
    required this.formMatches,
    this.cycleMatches = false,
    this.stageMatches = false,
    this.seriesMatches = false,
  });

  final TeacherProfile teacher;
  final int score;
  final List<String> matchedSubjects;

  /// The teacher teaches the learner's exact class (same subsystem AND same
  /// level) — e.g. English · Form 4, not French · 4ème.
  final bool formMatches;

  /// The teacher teaches the learner's cycle (e.g. Ordinary Level), even if
  /// not that exact class.
  final bool cycleMatches;

  /// The teacher teaches the learner's stage (primary / secondary).
  final bool stageMatches;

  /// The teacher covers the learner's upper-secondary series.
  final bool seriesMatches;
}

/// Ranks teachers for a learner using a simple, transparent rule (no AI, no
/// opaque ranking) over the structured education catalogue.
///
/// **Subsystem is a hard gate.** A French-subsystem 4ème learner is never
/// matched with an English-subsystem Form 4 teacher, and vice versa. The gate
/// only applies when both sides have a known subsystem; a legacy record with
/// no resolvable subsystem stays visible rather than silently disappearing.
///
/// Within a subsystem:
///
///   score = (overlapping subjects × 10)
///         + (exact level     ? 8 : 0)
///         + (same cycle      ? 4 : 0)
///         + (same stage      ? 2 : 0)
///         + (series covered  ? 3 : 0)
///
/// A teacher is only returned if they share at least one subject with the
/// learner or teach the learner's exact class — matching the stage or cycle
/// alone is a tiebreaker, not a reason to appear. Results are sorted most
/// relevant first, breaking ties by shared subjects then name.
///
/// Location, teaching mode and availability are applied downstream in
/// `buildDiscovery`, which has the parent's location and the availability data.
List<TeacherMatch> rankTeachersForChild(
  Student child,
  List<TeacherProfile> teachers,
) {
  final childSubjects = child.subjects.toSet();
  final childSubsystem = child.effectiveSubsystem;
  final childLevel = child.level;
  final childCycle = child.effectiveCycle;
  final childStage = child.effectiveStage;
  final childSeriesCode = child.seriesCode;

  final matches = <TeacherMatch>[];
  for (final teacher in teachers) {
    final teacherLevels = teacher.levels;
    final teacherSubsystems = teacher.subsystems;

    // Hard subsystem gate — only enforced when both sides are known.
    if (childSubsystem != null &&
        teacherSubsystems.isNotEmpty &&
        !teacherSubsystems.contains(childSubsystem)) {
      continue;
    }

    // Everything below compares only levels in the learner's subsystem so a
    // teacher who covers both subsystems is scored on the relevant half.
    final relevantLevels = childSubsystem == null
        ? teacherLevels
        : teacherLevels
            .where((l) => l.subsystem == childSubsystem)
            .toList(growable: false);

    final matchedSubjects =
        teacher.subjects.where(childSubjects.contains).toList(growable: false);

    final formMatches = childLevel != null &&
        relevantLevels.any((l) => l.code == childLevel.code);
    final cycleMatches =
        childCycle != null && relevantLevels.any((l) => l.cycle == childCycle);
    final stageMatches =
        childStage != null && relevantLevels.any((l) => l.stage == childStage);
    final seriesMatches = childSeriesCode != null &&
        teacher.seriesCodes.contains(childSeriesCode);

    if (matchedSubjects.isEmpty && !formMatches) continue;

    final score = matchedSubjects.length * 10 +
        (formMatches ? 8 : 0) +
        (cycleMatches ? 4 : 0) +
        (stageMatches ? 2 : 0) +
        (seriesMatches ? 3 : 0);

    if (score <= 0) continue;

    matches.add(TeacherMatch(
      teacher: teacher,
      score: score,
      matchedSubjects: matchedSubjects,
      formMatches: formMatches,
      cycleMatches: cycleMatches,
      stageMatches: stageMatches,
      seriesMatches: seriesMatches,
    ));
  }

  matches.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final bySubjects =
        b.matchedSubjects.length.compareTo(a.matchedSubjects.length);
    if (bySubjects != 0) return bySubjects;
    return a.teacher.displayName
        .toLowerCase()
        .compareTo(b.teacher.displayName.toLowerCase());
  });

  return matches;
}

/// Whether a teacher can be offered to a learner at all, ignoring ranking.
/// Exposed so request/booking screens can apply the same subsystem rule.
bool teacherIsCompatibleWith(TeacherProfile teacher, Student child) {
  final childSubsystem = child.effectiveSubsystem;
  final teacherSubsystems = teacher.subsystems;
  if (childSubsystem == null || teacherSubsystems.isEmpty) return true;
  return teacherSubsystems.contains(childSubsystem);
}

/// A label describing the learner's class that is unambiguous across
/// subsystems, e.g. "English · Form 4". Falls back to the raw stored value for
/// legacy records whose subsystem is unknown.
String? qualifiedLevelLabel(Student child) => child.qualifiedLevelLabel;

/// Same, for an arbitrary level code.
String? qualifiedLabelForLevelCode(String? levelCode) =>
    EducationCatalogue.levelByCode(levelCode)?.qualifiedLabel;
