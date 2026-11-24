import 'dart:typed_data';

import 'package:edu237/core/models/teacher_profile.dart';
import 'package:edu237/core/models/teaching_mode.dart';
import 'package:edu237/core/services/teacher_profile_service.dart';

/// A shared in-memory store so multiple scoped [FakeTeacherProfileService]
/// instances (different users) see the same teacher_profiles table.
class FakeTeacherStore {
  final Map<String, TeacherProfile> _byUserId = {};
  int _seq = 0;

  List<TeacherProfile> get all => _byUserId.values.toList(growable: false);

  /// Seed a pre-existing teacher owned by [userId].
  void seed(TeacherProfile profile) => _byUserId[profile.userId] = profile;

  TeacherProfile upsertFor(
    String userId, {
    required String displayName,
    String? title,
    required List<String> subjects,
    required List<String> forms,
    List<String> levelCodes = const <String>[],
    List<String> seriesCodes = const <String>[],
    String? bio,
    String? city,
    String? area,
    double? latitude,
    double? longitude,
    TeachingMode teachingMode = TeachingMode.inPerson,
    String? photoUrl,
    String? coverUrl,
    int hourlyRate = 5000,
  }) {
    final existing = _byUserId[userId];
    final now = DateTime.now();
    final profile = TeacherProfile(
      id: existing?.id ?? 'tp-${++_seq}',
      userId: userId,
      displayName: displayName.trim(),
      title: title ?? existing?.title,
      subjects: List<String>.from(subjects),
      forms: List<String>.from(forms),
      levelCodes: List<String>.from(levelCodes),
      seriesCodes: List<String>.from(seriesCodes),
      bio: (bio?.trim().isEmpty ?? true) ? null : bio!.trim(),
      city: (city?.trim().isEmpty ?? true) ? null : city!.trim(),
      area: (area?.trim().isEmpty ?? true) ? null : area!.trim(),
      latitude: latitude,
      longitude: longitude,
      teachingMode: teachingMode,
      photoUrl: photoUrl ?? existing?.photoUrl,
      coverUrl: coverUrl ?? existing?.coverUrl,
      hourlyRate: hourlyRate,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    _byUserId[userId] = profile;
    return profile;
  }

  TeacherProfile? forUser(String userId) => _byUserId[userId];
}

/// An in-memory [TeacherProfileService] scoped to a single [userId], backed by
/// a shared [FakeTeacherStore]. Mirrors the real contract: a caller can only
/// read/write their OWN profile (there is no method to target another user),
/// while [fetchTeachers] returns everyone (discovery).
class FakeTeacherProfileService implements TeacherProfileService {
  FakeTeacherProfileService({required this.userId, FakeTeacherStore? store})
      : store = store ?? FakeTeacherStore();

  final String userId;
  final FakeTeacherStore store;

  @override
  Future<TeacherProfileResult> fetchMyProfile() async =>
      TeacherProfileSuccess(store.forUser(userId));

  @override
  Future<TeacherProfileResult> upsertMyProfile({
    required String displayName,
    String? title,
    required List<String> subjects,
    required List<String> forms,
    List<String> levelCodes = const <String>[],
    List<String> seriesCodes = const <String>[],
    String? bio,
    String? city,
    String? area,
    double? latitude,
    double? longitude,
    TeachingMode teachingMode = TeachingMode.inPerson,
    String? photoUrl,
    String? coverUrl,
    int hourlyRate = 5000,
  }) async {
    final profile = store.upsertFor(
      userId,
      displayName: displayName,
      title: title,
      subjects: subjects,
      forms: forms,
      levelCodes: levelCodes,
      seriesCodes: seriesCodes,
      bio: bio,
      city: city,
      area: area,
      latitude: latitude,
      longitude: longitude,
      teachingMode: teachingMode,
      photoUrl: photoUrl,
      coverUrl: coverUrl,
      hourlyRate: hourlyRate,
    );
    return TeacherProfileSuccess(profile);
  }

  @override
  Future<TeacherProfileResult> fetchTeachers() async =>
      TeacherProfileListSuccess(store.all);

  @override
  Future<TeacherProfileResult> uploadProfilePhoto({
    required Uint8List bytes,
    required String fileExtension,
  }) async =>
      const TeacherProfileSuccess(null);

  @override
  Future<TeacherProfileResult> deleteProfilePhoto() async =>
      const TeacherProfileSuccess(null);

  @override
  Future<TeacherProfileResult> updatePhotoUrl(String? url) async =>
      const TeacherProfileSuccess(null);

  @override
  Future<TeacherProfileResult> uploadCoverPhoto({
    required Uint8List bytes,
    required String fileExtension,
  }) async =>
      const TeacherProfileSuccess(null);

  @override
  Future<TeacherProfileResult> deleteCoverPhoto() async =>
      const TeacherProfileSuccess(null);

  @override
  Future<TeacherProfileResult> updateCoverUrl(String? url) async =>
      const TeacherProfileSuccess(null);
}
