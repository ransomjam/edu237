import '../constants/cameroon_places.dart';
import '../models/student.dart';
import '../models/teacher_profile.dart';
import 'geo.dart';
import 'teacher_matching.dart';

/// The small, parent-facing set of filters for discovery. Deliberately tiny —
/// relevance is determined automatically from the child; these just let a parent
/// narrow further.
class DiscoveryFilters {
  const DiscoveryFilters({
    this.subject,
    this.levelCode,
    this.nearby = false,
    this.onlineOnly = false,
    this.availableTeacherUserIds,
  });

  /// Only show teachers who teach this subject (null = any).
  final String? subject;

  /// Only show teachers who teach this class, as a canonical level code from
  /// the education catalogue (null = any). A code, not a label, so the filter
  /// is always subsystem-specific.
  final String? levelCode;

  /// Order by approximate distance (needs the parent's location).
  final bool nearby;

  /// Only show teachers who can teach online.
  final bool onlineOnly;

  /// When non-null, restricts results to these teacher auth ids. Supplied by
  /// the caller from the availability service so "teacher availability" is
  /// part of the same pipeline instead of a separate ad-hoc filter.
  final Set<String>? availableTeacherUserIds;

  bool get hasAny =>
      subject != null ||
      levelCode != null ||
      nearby ||
      onlineOnly ||
      availableTeacherUserIds != null;

  DiscoveryFilters copyWith({
    Object? subject = _sentinel,
    Object? levelCode = _sentinel,
    bool? nearby,
    bool? onlineOnly,
    Object? availableTeacherUserIds = _sentinel,
  }) {
    return DiscoveryFilters(
      subject: subject == _sentinel ? this.subject : subject as String?,
      levelCode:
          levelCode == _sentinel ? this.levelCode : levelCode as String?,
      nearby: nearby ?? this.nearby,
      onlineOnly: onlineOnly ?? this.onlineOnly,
      availableTeacherUserIds: availableTeacherUserIds == _sentinel
          ? this.availableTeacherUserIds
          : availableTeacherUserIds as Set<String>?,
    );
  }

  static const Object _sentinel = Object();
}

/// A teacher prepared for the discovery UI: relevance to the child, an
/// approximate location for the map, and (when known) a distance from the
/// parent. This is what both the List and Map views render.
class DiscoveryTeacher {
  const DiscoveryTeacher({
    required this.teacher,
    required this.score,
    required this.matchedSubjects,
    required this.formMatches,
    this.location,
    this.distanceKm,
    this.isBestMatch = false,
  });

  final TeacherProfile teacher;
  final int score;

  /// Subjects this teacher shares with the child (used for "✓ Mathematics").
  final List<String> matchedSubjects;

  /// Whether this teacher teaches the learner's exact class in the learner's
  /// own subsystem (used for "✓ Form 4").
  final bool formMatches;

  /// Approximate location used for the map: the teacher's own coordinates if
  /// set, otherwise a city/area centroid from the gazetteer. Null when we
  /// genuinely can't place them — they still appear in List view.
  final GeoPoint? location;

  /// Approximate distance from the parent, if the parent shared their location
  /// and this teacher could be placed.
  final double? distanceKm;

  /// True for the single strongest match (shown as "Best match").
  final bool isBestMatch;

  bool get hasLocation => location != null;

  DiscoveryTeacher _asBest() => DiscoveryTeacher(
        teacher: teacher,
        score: score,
        matchedSubjects: matchedSubjects,
        formMatches: formMatches,
        location: location,
        distanceKm: distanceKm,
        isBestMatch: true,
      );
}

/// Resolves a teacher's approximate location: their stored coordinates first,
/// then a gazetteer lookup on city/area. Kept public so the map can place a
/// teacher opened directly (e.g. deep link) too.
GeoPoint? effectiveLocationFor(TeacherProfile teacher) {
  if (teacher.hasCoordinates) {
    return GeoPoint(teacher.latitude!, teacher.longitude!);
  }
  return CameroonPlaces.resolve(city: teacher.city, area: teacher.area);
}

/// Builds the discovery list for a child: ranks by relevance (see
/// [rankTeachersForChild]), attaches an approximate location + distance, applies
/// the small [filters], and orders the result.
///
/// Ordering:
///   * default → most relevant first (form + subject overlap), distance as a
///     gentle tiebreak when known;
///   * "Nearby" on with a known [parentLocation] → nearest first, then the
///     rest (unplaceable teachers last) still by relevance.
///
/// Teachers with a profile area but no coordinates are never dropped — they
/// simply have a null [DiscoveryTeacher.location] and fall to the end of a
/// nearby sort.
List<DiscoveryTeacher> buildDiscovery({
  required Student child,
  required List<TeacherProfile> teachers,
  GeoPoint? parentLocation,
  DiscoveryFilters filters = const DiscoveryFilters(),
}) {
  final ranked = rankTeachersForChild(child, teachers);

  var items = ranked.map((m) {
    final location = effectiveLocationFor(m.teacher);
    final distanceKm = (parentLocation != null && location != null)
        ? Geo.distanceKm(parentLocation, location)
        : null;
    return DiscoveryTeacher(
      teacher: m.teacher,
      score: m.score,
      matchedSubjects: m.matchedSubjects,
      formMatches: m.formMatches,
      location: location,
      distanceKm: distanceKm,
    );
  }).toList();

  // Apply the small filters.
  if (filters.subject != null) {
    final s = filters.subject!.toLowerCase();
    items = items
        .where((d) => d.teacher.subjects.any((x) => x.toLowerCase() == s))
        .toList();
  }
  if (filters.levelCode != null) {
    items = items
        .where((d) => d.teacher.teachesLevel(filters.levelCode))
        .toList();
  }
  if (filters.onlineOnly) {
    items =
        items.where((d) => d.teacher.teachingMode.supportsOnline).toList();
  }
  final availableIds = filters.availableTeacherUserIds;
  if (availableIds != null) {
    items =
        items.where((d) => availableIds.contains(d.teacher.userId)).toList();
  }

  // Ordering.
  if (filters.nearby && parentLocation != null) {
    items.sort((a, b) {
      final ad = a.distanceKm;
      final bd = b.distanceKm;
      if (ad != null && bd != null) {
        final byDist = ad.compareTo(bd);
        if (byDist != 0) return byDist;
      } else if (ad != null) {
        return -1; // a has a distance, b doesn't → a first
      } else if (bd != null) {
        return 1;
      }
      return b.score.compareTo(a.score);
    });
  }
  // else: keep rankTeachersForChild's relevance order.

  // Mark the single best match (the first item under relevance ordering).
  if (items.isNotEmpty && !(filters.nearby && parentLocation != null)) {
    items[0] = items[0]._asBest();
  }

  return items;
}
