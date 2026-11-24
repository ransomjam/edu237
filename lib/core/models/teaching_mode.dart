/// How a teacher can teach a student.
///
/// Kept deliberately small and parent-legible: a parent should immediately
/// understand whether a teacher can come to them physically, teach remotely,
/// or both. Stored verbatim in `teacher_profiles.teaching_mode`.
enum TeachingMode {
  /// Remote lessons only (video / phone).
  online,

  /// Face-to-face lessons only.
  inPerson,

  /// Either online or in person.
  both;

  /// The value stored in the database. Snake-cased so it reads cleanly in SQL.
  String get value => switch (this) {
        TeachingMode.online => 'online',
        TeachingMode.inPerson => 'in_person',
        TeachingMode.both => 'both',
      };

  /// A short, human label for chips/badges.
  String get label => switch (this) {
        TeachingMode.online => 'Online',
        TeachingMode.inPerson => 'In person',
        TeachingMode.both => 'Online + In person',
      };

  /// True when this teacher can teach remotely.
  bool get supportsOnline =>
      this == TeachingMode.online || this == TeachingMode.both;

  /// True when this teacher can teach face-to-face.
  bool get supportsInPerson =>
      this == TeachingMode.inPerson || this == TeachingMode.both;

  /// Parses a stored value. Unknown / null values fall back to [inPerson],
  /// which is the safest assumption for a Cameroon MVP (most tutoring is
  /// face-to-face) and keeps older rows meaningful.
  static TeachingMode fromString(String? value) {
    return switch (value) {
      'online' => TeachingMode.online,
      'in_person' => TeachingMode.inPerson,
      'both' => TeachingMode.both,
      _ => TeachingMode.inPerson,
    };
  }
}
