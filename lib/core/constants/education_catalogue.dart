/// The single, canonical education catalogue for Camiva.
///
/// Cameroon runs two parallel general-education subsystems (English and
/// French). Everything in the product that talks about "what class is this
/// learner in" or "what do you teach" MUST come from here — parent children,
/// student profiles, teacher onboarding, teacher profiles and discovery
/// filters all share these constants so there is exactly one level system and
/// exactly one subject system.
///
/// Structure:
///
///   EducationSubsystem
///     └── SchoolStage (primary / secondary)
///           └── EducationCycle
///                 ├── EducationLevel   (the class the learner sits in)
///                 └── EducationSeries  (upper-secondary specialisation)
///                       └── subjects
///
/// Storage contract
/// ----------------
/// * Levels are stored twice, on purpose:
///     - `level_code` — the stable machine id from [EducationLevel.code]
///       (e.g. `en.sec.ol.form4`). Never localised, never renamed.
///     - `school_level` / `forms` — the human label (e.g. "Form 4", "4ème").
///       Kept in sync so older screens, SQL policies and historical rows keep
///       working. Labels are globally unique across both subsystems, so a
///       label never silently means two different classes.
/// * Subjects are stored as their human label for the learner's subsystem
///   ("Mathematics" in the English subsystem, "Mathématiques" in the French
///   one), which is what the existing `subjects text[]` columns already hold.
///
/// Factual accuracy
/// ----------------
/// The stage/cycle/level structure follows the published MINEDUB (basic
/// education) and MINESEC (secondary education) descriptions of the two
/// subsystems. Where an official *subject combination* per series could not be
/// confirmed, this file deliberately exposes a clearly-labelled **suggested**
/// subject pool for the series group rather than presenting an invented
/// "official" combination — see [EducationSeries.suggestedSubjectCodes] and
/// [seriesSuggestionNote].
library;

// ---------------------------------------------------------------------------
// Subsystem
// ---------------------------------------------------------------------------

/// One of Cameroon's two general-education subsystems.
enum EducationSubsystem {
  english('english', 'English Subsystem', 'English'),
  french('french', 'French Subsystem', 'French');

  const EducationSubsystem(this.code, this.label, this.shortLabel);

  /// Stable machine id persisted in the database.
  final String code;

  /// Full human label, e.g. "English Subsystem".
  final String label;

  /// Short qualifier used in mixed lists, e.g. the "English" of
  /// "English · Form 4".
  final String shortLabel;

  static EducationSubsystem? fromCode(String? code) {
    return switch (code) {
      'english' => EducationSubsystem.english,
      'french' => EducationSubsystem.french,
      _ => null,
    };
  }
}

// ---------------------------------------------------------------------------
// School stage
// ---------------------------------------------------------------------------

/// Primary or secondary schooling. Technical/vocational tracks are explicitly
/// out of scope for this general-education catalogue.
enum SchoolStage {
  primary('primary'),
  secondary('secondary');

  const SchoolStage(this.code);

  final String code;

  static SchoolStage? fromCode(String? code) {
    return switch (code) {
      'primary' => SchoolStage.primary,
      'secondary' => SchoolStage.secondary,
      _ => null,
    };
  }

  /// Stage name in the wording of [subsystem].
  String labelFor(EducationSubsystem subsystem) {
    return switch ((this, subsystem)) {
      (SchoolStage.primary, EducationSubsystem.english) => 'Primary School',
      (SchoolStage.secondary, EducationSubsystem.english) => 'Secondary School',
      (SchoolStage.primary, EducationSubsystem.french) => 'École Primaire',
      (SchoolStage.secondary, EducationSubsystem.french) =>
        'Enseignement Secondaire',
    };
  }
}

// ---------------------------------------------------------------------------
// Cycle
// ---------------------------------------------------------------------------

/// A cycle within a stage. The two subsystems divide secondary school
/// differently, so cycles are subsystem-specific by construction — this is what
/// stops an English Form 4 being confused with a French 4ème.
enum EducationCycle {
  englishPrimary(
    'en.primary',
    EducationSubsystem.english,
    SchoolStage.primary,
    'Primary',
    'Class 1 – Class 6',
  ),
  ordinaryLevel(
    'en.sec.ol',
    EducationSubsystem.english,
    SchoolStage.secondary,
    'Ordinary Level',
    'First cycle · Form 1 – Form 5 · GCE Ordinary Level',
  ),
  advancedLevel(
    'en.sec.al',
    EducationSubsystem.english,
    SchoolStage.secondary,
    'Advanced Level',
    'Second cycle · Lower & Upper Sixth · GCE Advanced Level',
  ),
  frenchPrimary(
    'fr.primary',
    EducationSubsystem.french,
    SchoolStage.primary,
    'Primaire',
    'SIL – CM2',
  ),
  frenchFirstCycle(
    'fr.sec.c1',
    EducationSubsystem.french,
    SchoolStage.secondary,
    'Premier Cycle',
    'Collège · 6ème – 3ème · BEPC',
  ),
  frenchSecondCycle(
    'fr.sec.c2',
    EducationSubsystem.french,
    SchoolStage.secondary,
    'Second Cycle',
    'Lycée · Seconde – Terminale · Probatoire & Baccalauréat',
  );

  const EducationCycle(
    this.code,
    this.subsystem,
    this.stage,
    this.label,
    this.subtitle,
  );

  /// Stable machine id persisted in the database.
  final String code;
  final EducationSubsystem subsystem;
  final SchoolStage stage;

  /// Short human label, e.g. "Ordinary Level".
  final String label;

  /// One-line explanation shown under the label in selectors.
  final String subtitle;

  /// True for the two upper-secondary cycles that carry a series.
  bool get hasSeries =>
      this == EducationCycle.advancedLevel ||
      this == EducationCycle.frenchSecondCycle;

  static EducationCycle? fromCode(String? code) {
    if (code == null) return null;
    for (final cycle in EducationCycle.values) {
      if (cycle.code == code) return cycle;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Level
// ---------------------------------------------------------------------------

/// A single class/level a learner sits in.
class EducationLevel {
  const EducationLevel({
    required this.code,
    required this.label,
    required this.cycle,
    required this.ordinal,
    this.alternateLabel,
  });

  /// Stable machine id, e.g. `en.sec.ol.form4`. Never localised.
  final String code;

  /// Canonical human label, e.g. "Form 4" or "4ème". Unique across the whole
  /// catalogue, which is what makes the denormalised `school_level` /
  /// `forms` label columns safe.
  final String label;

  /// A commonly used equivalent name, e.g. "SIL" → "Section d'Initiation au
  /// Langage", or "Class 1" → "Class One". Shown as a hint, never stored.
  final String? alternateLabel;

  final EducationCycle cycle;

  /// Position within the cycle, 1-based. Used for ordering only.
  final int ordinal;

  EducationSubsystem get subsystem => cycle.subsystem;
  SchoolStage get stage => cycle.stage;

  /// Label with its subsystem, e.g. "English · Form 4" or "French · 4ème".
  /// Use this anywhere levels from both subsystems can appear together.
  String get qualifiedLabel => '${subsystem.shortLabel} · $label';
}

// ---------------------------------------------------------------------------
// Series
// ---------------------------------------------------------------------------

/// Broad family a series belongs to. Used to group the picker and to choose a
/// suggested subject pool.
enum SeriesGroup {
  arts('Arts'),
  science('Science'),
  specialised('Other / Specialised');

  const SeriesGroup(this.label);
  final String label;
}

/// An upper-secondary specialisation (GCE A Level series in the English
/// subsystem, série in the French one).
class EducationSeries {
  const EducationSeries({
    required this.code,
    required this.label,
    required this.cycle,
    required this.group,
    required this.suggestedSubjectCodes,
    this.description,
  });

  /// Stable machine id, e.g. `en.al.s2` or `fr.c2.d`.
  final String code;

  /// Human label as printed on school documents, e.g. "S2" or "D".
  final String label;

  final EducationCycle cycle;
  final SeriesGroup group;

  /// Optional short note, e.g. "Bilingual".
  final String? description;

  /// A **suggested** pool of subjects for this series — not an official,
  /// prescribed combination. See [seriesSuggestionNote].
  final List<String> suggestedSubjectCodes;

  EducationSubsystem get subsystem => cycle.subsystem;

  /// "Arts A2" / "Série D" style label used in review screens.
  String get qualifiedLabel => switch (subsystem) {
        EducationSubsystem.english => '${group.label} $label',
        EducationSubsystem.french => 'Série $label',
      };
}

/// Shown next to any series-driven subject list so the suggestion is never
/// mistaken for an official prescription.
const String seriesSuggestionNote =
    'Suggested subjects for this series. The exact combination varies by '
    'school — choose the subjects actually taken.';

// ---------------------------------------------------------------------------
// Subject
// ---------------------------------------------------------------------------

/// A teachable subject. One entry serves both subsystems; only the label
/// differs, so teacher profiles and learner profiles never drift apart.
class EducationSubject {
  const EducationSubject({
    required this.code,
    required this.englishLabel,
    required this.frenchLabel,
  });

  /// Stable machine id, e.g. `additional_mathematics`.
  final String code;

  /// Label used in the English subsystem.
  final String englishLabel;

  /// Label used in the French subsystem.
  final String frenchLabel;

  String labelFor(EducationSubsystem subsystem) =>
      subsystem == EducationSubsystem.french ? frenchLabel : englishLabel;
}

// ---------------------------------------------------------------------------
// Catalogue
// ---------------------------------------------------------------------------

abstract final class EducationCatalogue {
  // -- Levels ---------------------------------------------------------------

  /// English subsystem primary cycle — six years (MINEDUB).
  static const List<EducationLevel> englishPrimaryLevels = <EducationLevel>[
    EducationLevel(
      code: 'en.pri.class1',
      label: 'Class 1',
      alternateLabel: 'Class One',
      cycle: EducationCycle.englishPrimary,
      ordinal: 1,
    ),
    EducationLevel(
      code: 'en.pri.class2',
      label: 'Class 2',
      alternateLabel: 'Class Two',
      cycle: EducationCycle.englishPrimary,
      ordinal: 2,
    ),
    EducationLevel(
      code: 'en.pri.class3',
      label: 'Class 3',
      alternateLabel: 'Class Three',
      cycle: EducationCycle.englishPrimary,
      ordinal: 3,
    ),
    EducationLevel(
      code: 'en.pri.class4',
      label: 'Class 4',
      alternateLabel: 'Class Four',
      cycle: EducationCycle.englishPrimary,
      ordinal: 4,
    ),
    EducationLevel(
      code: 'en.pri.class5',
      label: 'Class 5',
      alternateLabel: 'Class Five',
      cycle: EducationCycle.englishPrimary,
      ordinal: 5,
    ),
    EducationLevel(
      code: 'en.pri.class6',
      label: 'Class 6',
      alternateLabel: 'Class Six',
      cycle: EducationCycle.englishPrimary,
      ordinal: 6,
    ),
  ];

  /// English subsystem first cycle — five years leading to GCE Ordinary Level.
  static const List<EducationLevel> ordinaryLevelLevels = <EducationLevel>[
    EducationLevel(
      code: 'en.sec.ol.form1',
      label: 'Form 1',
      cycle: EducationCycle.ordinaryLevel,
      ordinal: 1,
    ),
    EducationLevel(
      code: 'en.sec.ol.form2',
      label: 'Form 2',
      cycle: EducationCycle.ordinaryLevel,
      ordinal: 2,
    ),
    EducationLevel(
      code: 'en.sec.ol.form3',
      label: 'Form 3',
      cycle: EducationCycle.ordinaryLevel,
      ordinal: 3,
    ),
    EducationLevel(
      code: 'en.sec.ol.form4',
      label: 'Form 4',
      cycle: EducationCycle.ordinaryLevel,
      ordinal: 4,
    ),
    EducationLevel(
      code: 'en.sec.ol.form5',
      label: 'Form 5',
      cycle: EducationCycle.ordinaryLevel,
      ordinal: 5,
    ),
  ];

  /// English subsystem second cycle — two years leading to GCE Advanced Level.
  static const List<EducationLevel> advancedLevelLevels = <EducationLevel>[
    EducationLevel(
      code: 'en.sec.al.lower6',
      label: 'Lower Sixth',
      cycle: EducationCycle.advancedLevel,
      ordinal: 1,
    ),
    EducationLevel(
      code: 'en.sec.al.upper6',
      label: 'Upper Sixth',
      cycle: EducationCycle.advancedLevel,
      ordinal: 2,
    ),
  ];

  /// French subsystem primary cycle — six years (MINEDUB).
  static const List<EducationLevel> frenchPrimaryLevels = <EducationLevel>[
    EducationLevel(
      code: 'fr.pri.sil',
      label: 'SIL',
      alternateLabel: "Section d'Initiation au Langage",
      cycle: EducationCycle.frenchPrimary,
      ordinal: 1,
    ),
    EducationLevel(
      code: 'fr.pri.cp',
      label: 'CP',
      alternateLabel: 'Cours Préparatoire',
      cycle: EducationCycle.frenchPrimary,
      ordinal: 2,
    ),
    EducationLevel(
      code: 'fr.pri.ce1',
      label: 'CE1',
      alternateLabel: 'Cours Élémentaire 1',
      cycle: EducationCycle.frenchPrimary,
      ordinal: 3,
    ),
    EducationLevel(
      code: 'fr.pri.ce2',
      label: 'CE2',
      alternateLabel: 'Cours Élémentaire 2',
      cycle: EducationCycle.frenchPrimary,
      ordinal: 4,
    ),
    EducationLevel(
      code: 'fr.pri.cm1',
      label: 'CM1',
      alternateLabel: 'Cours Moyen 1',
      cycle: EducationCycle.frenchPrimary,
      ordinal: 5,
    ),
    EducationLevel(
      code: 'fr.pri.cm2',
      label: 'CM2',
      alternateLabel: 'Cours Moyen 2',
      cycle: EducationCycle.frenchPrimary,
      ordinal: 6,
    ),
  ];

  /// French subsystem first cycle — four years leading to the BEPC.
  static const List<EducationLevel> frenchFirstCycleLevels = <EducationLevel>[
    EducationLevel(
      code: 'fr.sec.c1.6e',
      label: '6ème',
      alternateLabel: 'Sixième',
      cycle: EducationCycle.frenchFirstCycle,
      ordinal: 1,
    ),
    EducationLevel(
      code: 'fr.sec.c1.5e',
      label: '5ème',
      alternateLabel: 'Cinquième',
      cycle: EducationCycle.frenchFirstCycle,
      ordinal: 2,
    ),
    EducationLevel(
      code: 'fr.sec.c1.4e',
      label: '4ème',
      alternateLabel: 'Quatrième',
      cycle: EducationCycle.frenchFirstCycle,
      ordinal: 3,
    ),
    EducationLevel(
      code: 'fr.sec.c1.3e',
      label: '3ème',
      alternateLabel: 'Troisième',
      cycle: EducationCycle.frenchFirstCycle,
      ordinal: 4,
    ),
  ];

  /// French subsystem second cycle — Probatoire then Baccalauréat.
  static const List<EducationLevel> frenchSecondCycleLevels = <EducationLevel>[
    EducationLevel(
      code: 'fr.sec.c2.2nde',
      label: 'Seconde',
      cycle: EducationCycle.frenchSecondCycle,
      ordinal: 1,
    ),
    EducationLevel(
      code: 'fr.sec.c2.1ere',
      label: 'Première',
      cycle: EducationCycle.frenchSecondCycle,
      ordinal: 2,
    ),
    EducationLevel(
      code: 'fr.sec.c2.tle',
      label: 'Terminale',
      cycle: EducationCycle.frenchSecondCycle,
      ordinal: 3,
    ),
  ];

  /// Every level in the catalogue, in structural order.
  static const List<EducationLevel> allLevels = <EducationLevel>[
    ...englishPrimaryLevels,
    ...ordinaryLevelLevels,
    ...advancedLevelLevels,
    ...frenchPrimaryLevels,
    ...frenchFirstCycleLevels,
    ...frenchSecondCycleLevels,
  ];

  // -- Series ---------------------------------------------------------------

  /// GCE Advanced Level series.
  ///
  /// MINESEC's English-subsystem general-education listing runs further than
  /// this (Arts series beyond A5 exist); only the series whose place in the
  /// current general-education structure is unambiguous are modelled here
  /// rather than inventing entries.
  static const List<EducationSeries> advancedLevelSeries = <EducationSeries>[
    EducationSeries(
      code: 'en.al.a1',
      label: 'A1',
      cycle: EducationCycle.advancedLevel,
      group: SeriesGroup.arts,
      suggestedSubjectCodes: _englishArtsSuggestions,
    ),
    EducationSeries(
      code: 'en.al.a2',
      label: 'A2',
      cycle: EducationCycle.advancedLevel,
      group: SeriesGroup.arts,
      suggestedSubjectCodes: _englishArtsSuggestions,
    ),
    EducationSeries(
      code: 'en.al.a3',
      label: 'A3',
      cycle: EducationCycle.advancedLevel,
      group: SeriesGroup.arts,
      suggestedSubjectCodes: _englishArtsSuggestions,
    ),
    EducationSeries(
      code: 'en.al.a4',
      label: 'A4',
      cycle: EducationCycle.advancedLevel,
      group: SeriesGroup.arts,
      suggestedSubjectCodes: _englishArtsSuggestions,
    ),
    EducationSeries(
      code: 'en.al.a5',
      label: 'A5',
      cycle: EducationCycle.advancedLevel,
      group: SeriesGroup.arts,
      suggestedSubjectCodes: _englishArtsSuggestions,
    ),
    EducationSeries(
      code: 'en.al.s1',
      label: 'S1',
      cycle: EducationCycle.advancedLevel,
      group: SeriesGroup.science,
      suggestedSubjectCodes: _englishScienceSuggestions,
    ),
    EducationSeries(
      code: 'en.al.s2',
      label: 'S2',
      cycle: EducationCycle.advancedLevel,
      group: SeriesGroup.science,
      suggestedSubjectCodes: _englishScienceSuggestions,
    ),
    EducationSeries(
      code: 'en.al.s3',
      label: 'S3',
      cycle: EducationCycle.advancedLevel,
      group: SeriesGroup.science,
      suggestedSubjectCodes: _englishScienceSuggestions,
    ),
    EducationSeries(
      code: 'en.al.s4',
      label: 'S4',
      cycle: EducationCycle.advancedLevel,
      group: SeriesGroup.science,
      suggestedSubjectCodes: _englishScienceSuggestions,
    ),
  ];

  /// French subsystem second-cycle general series.
  ///
  /// Only general education is modelled. Technical and vocational streams are
  /// a separate education track and are deliberately NOT mixed in here.
  static const List<EducationSeries> frenchSecondCycleSeries =
      <EducationSeries>[
    EducationSeries(
      code: 'fr.c2.a1',
      label: 'A1',
      cycle: EducationCycle.frenchSecondCycle,
      group: SeriesGroup.arts,
      suggestedSubjectCodes: _frenchLiterarySuggestions,
    ),
    EducationSeries(
      code: 'fr.c2.a2',
      label: 'A2',
      cycle: EducationCycle.frenchSecondCycle,
      group: SeriesGroup.arts,
      suggestedSubjectCodes: _frenchLiterarySuggestions,
    ),
    EducationSeries(
      code: 'fr.c2.a3',
      label: 'A3',
      cycle: EducationCycle.frenchSecondCycle,
      group: SeriesGroup.arts,
      suggestedSubjectCodes: _frenchLiterarySuggestions,
    ),
    EducationSeries(
      code: 'fr.c2.a4',
      label: 'A4',
      cycle: EducationCycle.frenchSecondCycle,
      group: SeriesGroup.arts,
      suggestedSubjectCodes: _frenchLiterarySuggestions,
    ),
    EducationSeries(
      code: 'fr.c2.a5',
      label: 'A5',
      cycle: EducationCycle.frenchSecondCycle,
      group: SeriesGroup.arts,
      suggestedSubjectCodes: _frenchLiterarySuggestions,
    ),
    EducationSeries(
      code: 'fr.c2.c',
      label: 'C',
      cycle: EducationCycle.frenchSecondCycle,
      group: SeriesGroup.science,
      suggestedSubjectCodes: _frenchScienceCSuggestions,
    ),
    EducationSeries(
      code: 'fr.c2.d',
      label: 'D',
      cycle: EducationCycle.frenchSecondCycle,
      group: SeriesGroup.science,
      suggestedSubjectCodes: _frenchScienceDSuggestions,
    ),
    EducationSeries(
      code: 'fr.c2.ti',
      label: 'TI',
      description: "Technologies de l'Information",
      cycle: EducationCycle.frenchSecondCycle,
      group: SeriesGroup.specialised,
      suggestedSubjectCodes: _frenchTiSuggestions,
    ),
    EducationSeries(
      code: 'fr.c2.bil',
      label: 'BIL',
      description: 'Bilingue',
      cycle: EducationCycle.frenchSecondCycle,
      group: SeriesGroup.specialised,
      suggestedSubjectCodes: _frenchBilSuggestions,
    ),
  ];

  static const List<EducationSeries> allSeries = <EducationSeries>[
    ...advancedLevelSeries,
    ...frenchSecondCycleSeries,
  ];

  // -- Subjects -------------------------------------------------------------

  /// Every subject the catalogue knows about, keyed by [EducationSubject.code].
  static const List<EducationSubject> allSubjects = <EducationSubject>[
    EducationSubject(
      code: 'mathematics',
      englishLabel: 'Mathematics',
      frenchLabel: 'Mathématiques',
    ),
    EducationSubject(
      code: 'additional_mathematics',
      englishLabel: 'Additional Mathematics',
      frenchLabel: 'Mathématiques complémentaires',
    ),
    EducationSubject(
      code: 'further_mathematics',
      englishLabel: 'Further Mathematics',
      frenchLabel: 'Mathématiques approfondies',
    ),
    EducationSubject(
      code: 'english_language',
      englishLabel: 'English Language',
      frenchLabel: 'Anglais',
    ),
    EducationSubject(
      code: 'french',
      englishLabel: 'French',
      frenchLabel: 'Français',
    ),
    EducationSubject(
      code: 'bilingual_french',
      englishLabel: 'Special Bilingual Education French',
      frenchLabel: 'Français bilingue',
    ),
    EducationSubject(
      code: 'literature_in_english',
      englishLabel: 'Literature in English',
      frenchLabel: 'Littérature anglaise',
    ),
    EducationSubject(
      code: 'french_literature',
      englishLabel: 'French Literature',
      frenchLabel: 'Littérature',
    ),
    EducationSubject(
      code: 'philosophy',
      englishLabel: 'Philosophy',
      frenchLabel: 'Philosophie',
    ),
    EducationSubject(
      code: 'physics',
      englishLabel: 'Physics',
      frenchLabel: 'Physique',
    ),
    EducationSubject(
      code: 'chemistry',
      englishLabel: 'Chemistry',
      frenchLabel: 'Chimie',
    ),
    EducationSubject(
      code: 'physical_sciences',
      englishLabel: 'Physical Sciences',
      frenchLabel: 'Physique-Chimie',
    ),
    EducationSubject(
      code: 'biology',
      englishLabel: 'Biology',
      frenchLabel: 'Biologie',
    ),
    EducationSubject(
      code: 'human_biology',
      englishLabel: 'Human Biology',
      frenchLabel: 'Biologie humaine',
    ),
    EducationSubject(
      code: 'life_earth_sciences',
      englishLabel: 'Life and Earth Sciences',
      frenchLabel: 'Sciences de la Vie et de la Terre',
    ),
    EducationSubject(
      code: 'general_science',
      englishLabel: 'Science and Technology',
      frenchLabel: 'Sciences et Technologie',
    ),
    EducationSubject(
      code: 'geology',
      englishLabel: 'Geology',
      frenchLabel: 'Géologie',
    ),
    EducationSubject(
      code: 'geography',
      englishLabel: 'Geography',
      frenchLabel: 'Géographie',
    ),
    EducationSubject(
      code: 'history',
      englishLabel: 'History',
      frenchLabel: 'Histoire',
    ),
    EducationSubject(
      code: 'social_studies',
      englishLabel: 'Social Studies',
      frenchLabel: 'Sciences humaines et sociales',
    ),
    EducationSubject(
      code: 'economics',
      englishLabel: 'Economics',
      frenchLabel: 'Économie',
    ),
    EducationSubject(
      code: 'commerce',
      englishLabel: 'Commerce',
      frenchLabel: 'Commerce',
    ),
    EducationSubject(
      code: 'accounting',
      englishLabel: 'Accounting',
      frenchLabel: 'Comptabilité',
    ),
    EducationSubject(
      code: 'computer_science',
      englishLabel: 'Computer Science',
      frenchLabel: 'Informatique',
    ),
    EducationSubject(
      code: 'ict',
      englishLabel: 'Computer Studies (ICT)',
      frenchLabel: 'Informatique (TIC)',
    ),
    EducationSubject(
      code: 'technology',
      englishLabel: 'Technology',
      frenchLabel: 'Technologie',
    ),
    EducationSubject(
      code: 'citizenship',
      englishLabel: 'Citizenship Education',
      frenchLabel: 'Éducation à la Citoyenneté',
    ),
    EducationSubject(
      code: 'religious_studies',
      englishLabel: 'Religious Studies',
      frenchLabel: 'Éducation religieuse et morale',
    ),
    EducationSubject(
      code: 'food_nutrition',
      englishLabel: 'Food and Nutrition',
      frenchLabel: 'Alimentation et nutrition',
    ),
    EducationSubject(
      code: 'logic',
      englishLabel: 'Logic',
      frenchLabel: 'Logique',
    ),
    EducationSubject(
      code: 'modern_languages',
      englishLabel: 'Modern Languages',
      frenchLabel: 'Langues vivantes',
    ),
    EducationSubject(
      code: 'national_languages',
      englishLabel: 'National Languages and Cultures',
      frenchLabel: 'Langues et cultures nationales',
    ),
    EducationSubject(
      code: 'arts',
      englishLabel: 'Arts and Creative Activities',
      frenchLabel: 'Arts et activités créatives',
    ),
    EducationSubject(
      code: 'physical_education',
      englishLabel: 'Physical Education and Sport',
      frenchLabel: 'Éducation Physique et Sportive',
    ),
  ];

  /// Primary-school subjects. The same core set serves both subsystems; only
  /// the labels differ.
  static const List<String> primarySubjectCodes = <String>[
    'mathematics',
    'english_language',
    'french',
    'general_science',
    'social_studies',
    'citizenship',
    'ict',
    'religious_studies',
    'physical_education',
    'arts',
    'national_languages',
  ];

  /// English-subsystem Ordinary Level subjects.
  static const List<String> ordinaryLevelSubjectCodes = <String>[
    'mathematics',
    'additional_mathematics',
    'english_language',
    'literature_in_english',
    'french',
    'bilingual_french',
    'physics',
    'chemistry',
    'biology',
    'human_biology',
    'geography',
    'geology',
    'history',
    'economics',
    'commerce',
    'accounting',
    'computer_science',
    'citizenship',
    'religious_studies',
    'food_nutrition',
    'logic',
  ];

  /// English-subsystem Advanced Level subjects.
  static const List<String> advancedLevelSubjectCodes = <String>[
    'mathematics',
    'further_mathematics',
    'physics',
    'chemistry',
    'biology',
    'geology',
    'geography',
    'economics',
    'history',
    'literature_in_english',
    'french',
    'computer_science',
  ];

  /// French-subsystem first-cycle (collège) subjects.
  static const List<String> frenchFirstCycleSubjectCodes = <String>[
    'mathematics',
    'french',
    'english_language',
    'history',
    'geography',
    'life_earth_sciences',
    'physical_sciences',
    'physics',
    'chemistry',
    'technology',
    'computer_science',
    'citizenship',
    'physical_education',
    'modern_languages',
    'arts',
    'national_languages',
  ];

  /// French-subsystem second-cycle (lycée) subjects.
  static const List<String> frenchSecondCycleSubjectCodes = <String>[
    'mathematics',
    'french',
    'french_literature',
    // Offered here for the bilingual (BIL) series.
    'literature_in_english',
    'philosophy',
    'english_language',
    'history',
    'geography',
    'life_earth_sciences',
    'physics',
    'chemistry',
    'physical_sciences',
    'technology',
    'computer_science',
    'economics',
    'citizenship',
    'physical_education',
    'modern_languages',
    'arts',
    'national_languages',
  ];

  // Series suggestion pools. Broad on purpose — see [seriesSuggestionNote].
  static const List<String> _englishArtsSuggestions = <String>[
    'literature_in_english',
    'french',
    'history',
    'geography',
    'economics',
    'mathematics',
    'computer_science',
  ];

  static const List<String> _englishScienceSuggestions = <String>[
    'mathematics',
    'further_mathematics',
    'physics',
    'chemistry',
    'biology',
    'geology',
    'geography',
    'computer_science',
    'economics',
  ];

  static const List<String> _frenchLiterarySuggestions = <String>[
    'french',
    'french_literature',
    'philosophy',
    'history',
    'geography',
    'english_language',
    'modern_languages',
    'mathematics',
  ];

  static const List<String> _frenchScienceCSuggestions = <String>[
    'mathematics',
    'physics',
    'chemistry',
    'life_earth_sciences',
    'computer_science',
    'french',
    'english_language',
    'philosophy',
  ];

  static const List<String> _frenchScienceDSuggestions = <String>[
    'life_earth_sciences',
    'chemistry',
    'physics',
    'mathematics',
    'french',
    'english_language',
    'philosophy',
    'computer_science',
  ];

  static const List<String> _frenchTiSuggestions = <String>[
    'computer_science',
    'mathematics',
    'physics',
    'chemistry',
    'technology',
    'french',
    'english_language',
  ];

  static const List<String> _frenchBilSuggestions = <String>[
    'french',
    'english_language',
    'french_literature',
    'literature_in_english',
    'history',
    'geography',
    'philosophy',
    'mathematics',
  ];

  // -- Lookups --------------------------------------------------------------

  /// Stages available in [subsystem]. Both subsystems currently offer primary
  /// and secondary general education.
  static List<SchoolStage> stagesFor(EducationSubsystem subsystem) =>
      const <SchoolStage>[SchoolStage.primary, SchoolStage.secondary];

  /// Cycles inside a stage of a subsystem, in progression order.
  static List<EducationCycle> cyclesFor(
    EducationSubsystem subsystem,
    SchoolStage stage,
  ) {
    return EducationCycle.values
        .where((c) => c.subsystem == subsystem && c.stage == stage)
        .toList(growable: false);
  }

  /// Levels inside a cycle, in progression order.
  static List<EducationLevel> levelsForCycle(EducationCycle cycle) {
    return switch (cycle) {
      EducationCycle.englishPrimary => englishPrimaryLevels,
      EducationCycle.ordinaryLevel => ordinaryLevelLevels,
      EducationCycle.advancedLevel => advancedLevelLevels,
      EducationCycle.frenchPrimary => frenchPrimaryLevels,
      EducationCycle.frenchFirstCycle => frenchFirstCycleLevels,
      EducationCycle.frenchSecondCycle => frenchSecondCycleLevels,
    };
  }

  /// Every level in a subsystem, optionally narrowed to a stage.
  static List<EducationLevel> levelsForSubsystem(
    EducationSubsystem subsystem, {
    SchoolStage? stage,
  }) {
    return allLevels
        .where((l) =>
            l.subsystem == subsystem && (stage == null || l.stage == stage))
        .toList(growable: false);
  }

  /// Series available in a cycle. Empty for every cycle except the two
  /// upper-secondary ones.
  static List<EducationSeries> seriesForCycle(EducationCycle cycle) {
    return switch (cycle) {
      EducationCycle.advancedLevel => advancedLevelSeries,
      EducationCycle.frenchSecondCycle => frenchSecondCycleSeries,
      _ => const <EducationSeries>[],
    };
  }

  /// Series grouped by [SeriesGroup], preserving catalogue order. Groups with
  /// no series in this cycle are omitted.
  static Map<SeriesGroup, List<EducationSeries>> seriesByGroup(
    EducationCycle cycle,
  ) {
    final result = <SeriesGroup, List<EducationSeries>>{};
    for (final series in seriesForCycle(cycle)) {
      (result[series.group] ??= <EducationSeries>[]).add(series);
    }
    return result;
  }

  static EducationLevel? levelByCode(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final level in allLevels) {
      if (level.code == code) return level;
    }
    return null;
  }

  static EducationSeries? seriesByCode(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final series in allSeries) {
      if (series.code == code) return series;
    }
    return null;
  }

  static EducationSubject? subjectByCode(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final subject in allSubjects) {
      if (subject.code == code) return subject;
    }
    return null;
  }

  /// Resolves a stored human label (e.g. "Form 4", "4ème") back to a level.
  ///
  /// Labels are unique across the whole catalogue, so this is unambiguous. It
  /// is how legacy `school_level` / `forms` values are understood without a
  /// destructive rewrite.
  static EducationLevel? levelByLabel(String? label) {
    final needle = label?.trim().toLowerCase();
    if (needle == null || needle.isEmpty) return null;
    for (final level in allLevels) {
      if (level.label.toLowerCase() == needle) return level;
    }
    return null;
  }

  /// Best-effort interpretation of a historical `school_level` string.
  ///
  /// Only exact catalogue labels are accepted. Anything else returns null so
  /// the caller can preserve the raw value and ask the user to confirm it,
  /// rather than guessing a subsystem.
  static EducationLevel? interpretLegacyLevel(String? raw) =>
      levelByLabel(raw);

  // -- Subject resolution ---------------------------------------------------

  /// Subject codes appropriate for a cycle. Never returns the whole catalogue.
  static List<String> subjectCodesForCycle(EducationCycle cycle) {
    return switch (cycle) {
      EducationCycle.englishPrimary => primarySubjectCodes,
      EducationCycle.frenchPrimary => primarySubjectCodes,
      EducationCycle.ordinaryLevel => ordinaryLevelSubjectCodes,
      EducationCycle.advancedLevel => advancedLevelSubjectCodes,
      EducationCycle.frenchFirstCycle => frenchFirstCycleSubjectCodes,
      EducationCycle.frenchSecondCycle => frenchSecondCycleSubjectCodes,
    };
  }

  /// The subjects to offer for a learner or teacher in this context.
  ///
  /// When [series] is given, its suggested pool is returned first; pass
  /// `includeAllForCycle: true` to append the rest of the cycle's subjects
  /// under a "more subjects" affordance.
  static List<EducationSubject> subjectsFor({
    required EducationCycle cycle,
    EducationSeries? series,
    bool includeAllForCycle = false,
  }) {
    final cycleCodes = subjectCodesForCycle(cycle);

    List<String> codes;
    if (series != null) {
      final suggested =
          series.suggestedSubjectCodes.where(cycleCodes.contains).toList();
      codes = includeAllForCycle
          ? <String>[
              ...suggested,
              ...cycleCodes.where((c) => !suggested.contains(c)),
            ]
          : suggested;
    } else {
      codes = cycleCodes;
    }

    return codes
        .map(subjectByCode)
        .whereType<EducationSubject>()
        .toList(growable: false);
  }

  /// The display labels for [subjectsFor], in the wording of the subsystem.
  /// This is what is written to the `subjects text[]` columns.
  static List<String> subjectLabelsFor({
    required EducationCycle cycle,
    EducationSeries? series,
    bool includeAllForCycle = false,
  }) {
    return subjectsFor(
      cycle: cycle,
      series: series,
      includeAllForCycle: includeAllForCycle,
    ).map((s) => s.labelFor(cycle.subsystem)).toList(growable: false);
  }

  /// Every subject label a subsystem can produce. Used by teacher-side
  /// pickers that span several cycles, and by discovery filters.
  static List<String> allSubjectLabelsFor(EducationSubsystem subsystem) {
    final seen = <String>{};
    final labels = <String>[];
    for (final cycle
        in EducationCycle.values.where((c) => c.subsystem == subsystem)) {
      for (final label in subjectLabelsFor(cycle: cycle)) {
        if (seen.add(label)) labels.add(label);
      }
    }
    return labels;
  }
}
