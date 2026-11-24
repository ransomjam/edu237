import '../constants/education_catalogue.dart';
import 'teaching_mode.dart';

/// A teacher's public teaching profile, used for discovery by parents.
///
/// Holds only what helps a parent find the right teacher — no home address,
/// phone number, or date of birth. [userId] is the teacher's Supabase Auth id.
///
/// Location privacy: [city] / [area] are coarse, and [latitude] / [longitude]
/// (when present) describe an APPROXIMATE teaching/service area, never a precise
/// home. Coordinates are optional; a teacher with only a city/area still appears
/// in discovery (List view, and on the map via a city gazetteer fallback).
class TeacherProfile {
  const TeacherProfile({
    required this.id,
    required this.userId,
    required this.displayName,
    this.title,
    this.subjects = const <String>[],
    this.forms = const <String>[],
    this.levelCodes = const <String>[],
    this.seriesCodes = const <String>[],
    this.bio,
    this.city,
    this.area,
    this.latitude,
    this.longitude,
    this.teachingMode = TeachingMode.inPerson,
    this.photoUrl,
    this.coverUrl,
    this.hourlyRate = 5000,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// The Supabase Auth user id of the teacher who owns this profile.
  final String userId;

  final String displayName;

  /// Honorific title, e.g. "Mr", "Mrs", "Dr", "Prof", "Engr". Optional.
  final String? title;

  /// Subjects taught, stored as the labels of [EducationCatalogue] subjects in
  /// the wording of the subsystem they teach (e.g. "Mathematics" or
  /// "Mathématiques"). Exactly the same catalogue the learner side uses.
  final List<String> subjects;

  /// Human labels of the classes taught, e.g. "Form 4", "4ème".
  ///
  /// Denormalised from [levelCodes] on every write so historical rows and
  /// older screens keep working. Labels are unique across both subsystems.
  final List<String> forms;

  /// Stable level ids from [EducationCatalogue], e.g. `en.sec.ol.form4`. This
  /// is the canonical field matching reads: it carries the subsystem, so a
  /// French 4ème teacher can never match an English Form 4 learner.
  final List<String> levelCodes;

  /// Stable series ids taught at upper-secondary level, e.g. `en.al.s2`.
  final List<String> seriesCodes;

  final String? bio;

  /// City the teacher is based in (e.g. "Bamenda"). Coarse location only.
  final String? city;

  /// Neighbourhood / area within the city (e.g. "Nkwen"). Never a precise
  /// street address — discovery only ever needs an approximate area.
  final String? area;

  /// Approximate latitude of the teaching/service area. Optional. Deliberately
  /// coarse — never a precise residential coordinate.
  final double? latitude;

  /// Approximate longitude of the teaching/service area. Optional.
  final double? longitude;

  /// Whether the teacher teaches online, in person, or both.
  final TeachingMode teachingMode;

  /// Optional avatar photo URL. When absent, an initials avatar is used.
  final String? photoUrl;

  /// Optional cover photo URL. When absent, the default placeholder is used.
  final String? coverUrl;

  /// Rate per GCE lesson in FCFA (default 5000).
  final int hourlyRate;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// True when this profile carries its own approximate coordinates.
  bool get hasCoordinates => latitude != null && longitude != null;

  /// The resolved levels this teacher covers.
  ///
  /// Falls back to interpreting the legacy [forms] labels for profiles saved
  /// before the structured catalogue existed, so an older teacher profile is
  /// still matchable without a rewrite.
  List<EducationLevel> get levels {
    final resolved = levelCodes
        .map(EducationCatalogue.levelByCode)
        .whereType<EducationLevel>()
        .toList(growable: false);
    if (resolved.isNotEmpty) return resolved;
    return forms
        .map(EducationCatalogue.interpretLegacyLevel)
        .whereType<EducationLevel>()
        .toList(growable: false);
  }

  List<EducationSeries> get series => seriesCodes
      .map(EducationCatalogue.seriesByCode)
      .whereType<EducationSeries>()
      .toList(growable: false);

  /// Subsystems this teacher covers, derived from the levels they teach.
  Set<EducationSubsystem> get subsystems =>
      levels.map((l) => l.subsystem).toSet();

  Set<EducationCycle> get cycles => levels.map((l) => l.cycle).toSet();

  Set<SchoolStage> get stages => levels.map((l) => l.stage).toSet();

  /// True when this teacher teaches [levelCode] (a canonical level id).
  bool teachesLevel(String? levelCode) {
    if (levelCode == null || levelCode.isEmpty) return false;
    return levels.any((l) => l.code == levelCode);
  }

  /// Classes grouped for display, e.g. "English · Form 3, Form 4".
  /// Keeps mixed-subsystem profiles unambiguous.
  List<String> get qualifiedLevelLabels {
    final grouped = <EducationSubsystem, List<String>>{};
    for (final level in levels) {
      (grouped[level.subsystem] ??= <String>[]).add(level.label);
    }
    if (grouped.isEmpty) return forms;
    return [
      for (final entry in grouped.entries)
        '${entry.key.shortLabel} · ${entry.value.join(', ')}',
    ];
  }

  /// Formatted name with title (e.g. "Mr. Jam Ransom" or "Dr. Marie Nkeng").
  String get fullNameWithTitle {
    final rawTitle = (title ?? '').trim();
    final d = displayName.trim();
    if (rawTitle.isEmpty) return d;
    final t = rawTitle;
    final tLower = t.toLowerCase();
    final dLower = d.toLowerCase();
    if (dLower.startsWith('$tLower.') || dLower.startsWith('$tLower ')) return d;
    final prefix = t.endsWith('.') ? t : '$t.';
    return '$prefix $d';
  }

  /// A short human-readable location, e.g. "Nkwen, Bamenda" or "Bamenda".
  String? get locationLabel {
    final c = (city ?? '').trim();
    final a = (area ?? '').trim();
    if (a.isNotEmpty && c.isNotEmpty) return '$a, $c';
    if (c.isNotEmpty) return c;
    if (a.isNotEmpty) return a;
    return null;
  }

  factory TeacherProfile.fromMap(Map<String, dynamic> map) {
    final id = map['id'] as String?;
    final userId = map['user_id'] as String?;
    final displayName = map['display_name'] as String?;
    final createdAt = map['created_at'] as String?;
    final updatedAt = map['updated_at'] as String?;

    if (id == null ||
        userId == null ||
        displayName == null ||
        createdAt == null ||
        updatedAt == null) {
      throw const FormatException('Teacher profile row is missing required data.');
    }

    List<String> stringList(Object? raw) => raw is List
        ? raw.map((e) => e.toString()).toList(growable: false)
        : const <String>[];

    // Coordinates arrive as num (double or int) from PostgREST; be tolerant.
    double? toDouble(Object? raw) {
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw);
      return null;
    }

    return TeacherProfile(
      id: id,
      userId: userId,
      displayName: displayName,
      title: map['title'] as String?,
      subjects: stringList(map['subjects']),
      forms: stringList(map['forms']),
      levelCodes: stringList(map['level_codes']),
      seriesCodes: stringList(map['series_codes']),
      bio: map['bio'] as String?,
      city: map['city'] as String?,
      area: map['area'] as String?,
      latitude: toDouble(map['latitude']),
      longitude: toDouble(map['longitude']),
      teachingMode: TeachingMode.fromString(map['teaching_mode'] as String?),
      photoUrl: map['photo_url'] as String?,
      coverUrl: (map['cover_photo_url'] ?? map['cover_url']) as String?,
      hourlyRate: map['hourly_rate'] as int? ?? 5000,
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
    );
  }

  /// Fields a teacher may write. Excludes identity/timestamps.
  ///
  /// `forms` is always re-derived from [levelCodes] so the label column can
  /// never drift from the canonical codes. Profiles that predate the
  /// catalogue and have no codes keep their existing labels untouched.
  Map<String, dynamic> toWriteFields({bool includeOptionalColumns = true}) {
    final resolved = levelCodes
        .map(EducationCatalogue.levelByCode)
        .whereType<EducationLevel>()
        .toList(growable: false);
    final formLabels = resolved.isEmpty
        ? forms
        : resolved.map((l) => l.label).toList(growable: false);

    final map = <String, dynamic>{
      'display_name': displayName.trim(),
      'subjects': subjects,
      'forms': formLabels,
      'bio': (bio?.trim().isEmpty ?? true) ? null : bio!.trim(),
      'hourly_rate': hourlyRate,
    };
    if (includeOptionalColumns) {
      map['level_codes'] = levelCodes;
      map['series_codes'] = seriesCodes;
      map['title'] = (title?.trim().isEmpty ?? true) ? null : title!.trim();
      map['city'] = (city?.trim().isEmpty ?? true) ? null : city!.trim();
      map['area'] = (area?.trim().isEmpty ?? true) ? null : area!.trim();
      map['latitude'] = latitude;
      map['longitude'] = longitude;
      map['teaching_mode'] = teachingMode.value;
      map['photo_url'] = photoUrl;
      // cover_photo_url is a newer column that may not exist on all
      // deployments yet. It's included in the full payload but excluded in
      // the fallback path (includeOptionalColumns: false) so a missing
      // migration never blanks out the rest of the profile.
      map['cover_photo_url'] = coverUrl;
    }
    return map;
  }

  /// Upsert payload for the signed-in teacher ([userId] is the conflict key).
  Map<String, dynamic> toUpsertMap({
    required String userId,
    bool includeOptionalColumns = true,
  }) {
    return {
      'user_id': userId,
      ...toWriteFields(includeOptionalColumns: includeOptionalColumns),
    };
  }

  TeacherProfile copyWith({
    String? displayName,
    String? title,
    List<String>? subjects,
    List<String>? forms,
    List<String>? levelCodes,
    List<String>? seriesCodes,
    String? bio,
    String? city,
    String? area,
    double? latitude,
    double? longitude,
    TeachingMode? teachingMode,
    String? photoUrl,
    String? coverUrl,
    int? hourlyRate,
  }) {
    return TeacherProfile(
      id: id,
      userId: userId,
      displayName: displayName ?? this.displayName,
      title: title ?? this.title,
      subjects: subjects ?? this.subjects,
      forms: forms ?? this.forms,
      levelCodes: levelCodes ?? this.levelCodes,
      seriesCodes: seriesCodes ?? this.seriesCodes,
      bio: bio ?? this.bio,
      city: city ?? this.city,
      area: area ?? this.area,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      teachingMode: teachingMode ?? this.teachingMode,
      photoUrl: photoUrl ?? this.photoUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
