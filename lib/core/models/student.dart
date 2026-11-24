import '../constants/education_catalogue.dart';

/// A learner record.
///
/// `students` is the canonical learner entity. There is exactly one row per
/// real child; it is never duplicated when that child also gains a login.
///
/// Two ownership shapes are supported by the same row:
///   * **Parent-managed** — [parentId] is the owning parent's Supabase Auth id
///     and [userId] is null. The child has no account. This is the original
///     shape and keeps working unchanged.
///   * **Student-managed** — [userId] is the learner's own Supabase Auth id.
///     [parentId] may additionally be set once a parent links the account, so
///     a linked child is still one row, not two.
///
/// Academic profile
/// ----------------
/// The learner's class is structured, not free text: [subsystem], [stage],
/// [cycle], [levelCode] and (upper secondary only) [seriesCode]. [schoolLevel]
/// remains as the human label of the same level ("Form 4", "4ème") so existing
/// rows, SQL policies and older screens keep working — see
/// [EducationCatalogue] for the storage contract.
class Student {
  const Student({
    required this.id,
    required this.parentId,
    this.userId,
    required this.name,
    this.dateOfBirth,
    this.schoolLevel,
    this.subsystem,
    this.stage,
    this.cycle,
    this.levelCode,
    this.seriesCode,
    this.subjects = const <String>[],
    this.notes,
    this.linkCode,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// The Supabase Auth user id of the owning parent. Empty for a student who
  /// signed up on their own and is not yet linked to a parent.
  final String parentId;

  /// The Supabase Auth user id of the learner's own account, when they have
  /// one. Null for a parent-managed child with no login.
  final String? userId;

  final String name;

  /// Optional date of birth. Only ever collected from parents; student signup
  /// never asks for it.
  final DateTime? dateOfBirth;

  /// Human label of the learner's class, e.g. "Form 4" or "4ème".
  ///
  /// Denormalised from [levelCode] on every write. For historical rows written
  /// before the structured catalogue existed this may be the only education
  /// data present — see [needsEducationReview].
  final String? schoolLevel;

  /// Which of Cameroon's two general-education subsystems the learner is in.
  final EducationSubsystem? subsystem;

  final SchoolStage? stage;

  final EducationCycle? cycle;

  /// Stable level id from [EducationCatalogue], e.g. `en.sec.ol.form4`.
  final String? levelCode;

  /// Stable series id for upper-secondary learners, e.g. `en.al.s2` or
  /// `fr.c2.d`. Null for primary and lower-secondary levels.
  final String? seriesCode;

  /// The learner's current subject profile, stored as subsystem-appropriate
  /// labels. Never null — an empty list means no subjects chosen yet.
  final List<String> subjects;

  final String? notes;

  /// A one-time code a parent hands to their child so the child's new account
  /// attaches to THIS record instead of creating a second one. Cleared the
  /// moment it is used. Null when no invite is outstanding.
  ///
  /// Read-only here: it is set through [StudentService.createLinkCode] and
  /// consumed server-side, never written as part of an ordinary profile edit.
  final String? linkCode;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// The resolved level, from [levelCode] when present, otherwise interpreted
  /// from the legacy [schoolLevel] label.
  EducationLevel? get level =>
      EducationCatalogue.levelByCode(levelCode) ??
      EducationCatalogue.interpretLegacyLevel(schoolLevel);

  EducationSeries? get series => EducationCatalogue.seriesByCode(seriesCode);

  /// The subsystem to use for display and matching: the stored one, else the
  /// one implied by the resolved level.
  EducationSubsystem? get effectiveSubsystem => subsystem ?? level?.subsystem;

  EducationCycle? get effectiveCycle => cycle ?? level?.cycle;

  SchoolStage? get effectiveStage => stage ?? level?.stage;

  /// True when this row still carries a class but no structured level we can
  /// resolve — i.e. a historical value whose subsystem is genuinely unknown.
  /// The Edit Child flow asks the parent to confirm it rather than guessing.
  bool get needsEducationReview =>
      (schoolLevel?.trim().isNotEmpty ?? false) && level == null;

  /// True when a learner account is attached to this record.
  bool get hasAccount => (userId?.isNotEmpty ?? false);

  /// True when a parent has issued a code the child has not used yet.
  bool get hasPendingLinkCode =>
      !hasAccount && (linkCode?.isNotEmpty ?? false);

  /// True when a parent owns this record.
  bool get hasParent => parentId.isNotEmpty;

  /// Level label qualified by subsystem, e.g. "English · Form 4". Falls back to
  /// the raw stored label for records that still need review.
  String? get qualifiedLevelLabel {
    final resolved = level;
    if (resolved != null) return resolved.qualifiedLabel;
    final raw = schoolLevel?.trim();
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  /// One-line academic summary used by review and profile screens, e.g.
  /// "English Subsystem · Secondary School · Ordinary Level · Form 4 · S2".
  String get educationSummary {
    final parts = <String>[];
    final sub = effectiveSubsystem;
    final st = effectiveStage;
    final cy = effectiveCycle;
    if (sub != null) parts.add(sub.label);
    if (sub != null && st != null) parts.add(st.labelFor(sub));
    if (cy != null) parts.add(cy.label);
    final lvl = level;
    if (lvl != null) {
      parts.add(lvl.label);
    } else if ((schoolLevel?.trim().isNotEmpty ?? false)) {
      parts.add(schoolLevel!.trim());
    }
    final ser = series;
    if (ser != null) parts.add(ser.qualifiedLabel);
    return parts.join(' · ');
  }

  factory Student.fromMap(Map<String, dynamic> map) {
    final id = map['id'] as String?;
    final name = map['name'] as String?;
    final createdAt = map['created_at'] as String?;
    final updatedAt = map['updated_at'] as String?;

    if (id == null || name == null || createdAt == null || updatedAt == null) {
      throw const FormatException('Student row is missing required data.');
    }

    // parent_id is nullable from the student-account migration onward: a
    // learner who signed up themselves has no parent until one links them.
    final parentId = (map['parent_id'] as String?) ?? '';

    final dob = map['date_of_birth'] as String?;

    // subjects is a Postgres text[] (JSON array via PostgREST). Older rows
    // created before the column existed arrive as null → treat as empty.
    final rawSubjects = map['subjects'];
    final subjects = rawSubjects is List
        ? rawSubjects.map((e) => e.toString()).toList(growable: false)
        : const <String>[];

    final levelCode = map['level_code'] as String?;
    final resolvedLevel = EducationCatalogue.levelByCode(levelCode);

    return Student(
      id: id,
      parentId: parentId,
      userId: map['user_id'] as String?,
      name: name,
      dateOfBirth: dob == null ? null : DateTime.parse(dob),
      schoolLevel: map['school_level'] as String?,
      // Fall back to what the level itself implies so a row written by an
      // older client is still fully structured in memory.
      subsystem: EducationSubsystem.fromCode(map['subsystem'] as String?) ??
          resolvedLevel?.subsystem,
      stage: SchoolStage.fromCode(map['school_stage'] as String?) ??
          resolvedLevel?.stage,
      cycle: EducationCycle.fromCode(map['cycle'] as String?) ??
          resolvedLevel?.cycle,
      levelCode: levelCode,
      seriesCode: map['series_code'] as String?,
      subjects: subjects,
      notes: map['notes'] as String?,
      linkCode: map['link_code'] as String?,
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
    );
  }

  /// Builds the insert payload for a new student owned by [parentId].
  /// The database assigns [id], [createdAt], and [updatedAt].
  Map<String, dynamic> toInsertMap({required String parentId}) {
    return {
      'parent_id': parentId,
      ...toWriteFields(),
    };
  }

  /// Builds the insert payload for a learner creating their own record during
  /// student signup. No parent is attached; one may link later.
  Map<String, dynamic> toSelfInsertMap({required String userId}) {
    return {
      'user_id': userId,
      ...toWriteFields(),
    };
  }

  /// The mutable, editable academic fields shared by insert and update.
  /// Excludes ownership/identity/timestamps.
  ///
  /// [schoolLevel] is always re-derived from [levelCode] when a structured
  /// level is set, so the label column can never drift from the code.
  Map<String, dynamic> toWriteFields() {
    final resolved = EducationCatalogue.levelByCode(levelCode);
    final label = resolved?.label ??
        ((schoolLevel?.trim().isEmpty ?? true) ? null : schoolLevel!.trim());

    return {
      'name': name.trim(),
      'date_of_birth': dateOfBirth?.toIso8601String(),
      'school_level': label,
      'subsystem': (subsystem ?? resolved?.subsystem)?.code,
      'school_stage': (stage ?? resolved?.stage)?.code,
      'cycle': (cycle ?? resolved?.cycle)?.code,
      'level_code': (levelCode?.trim().isEmpty ?? true) ? null : levelCode,
      'series_code': (seriesCode?.trim().isEmpty ?? true) ? null : seriesCode,
      'subjects': subjects,
      'notes': (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
    };
  }

  Student copyWith({
    String? id,
    String? parentId,
    String? userId,
    String? name,
    DateTime? dateOfBirth,
    String? schoolLevel,
    EducationSubsystem? subsystem,
    SchoolStage? stage,
    EducationCycle? cycle,
    String? levelCode,
    String? seriesCode,
    List<String>? subjects,
    String? notes,
    String? linkCode,
  }) {
    return Student(
      id: id ?? this.id,
      parentId: parentId ?? this.parentId,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      schoolLevel: schoolLevel ?? this.schoolLevel,
      subsystem: subsystem ?? this.subsystem,
      stage: stage ?? this.stage,
      cycle: cycle ?? this.cycle,
      levelCode: levelCode ?? this.levelCode,
      seriesCode: seriesCode ?? this.seriesCode,
      subjects: subjects ?? this.subjects,
      notes: notes ?? this.notes,
      linkCode: linkCode ?? this.linkCode,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
