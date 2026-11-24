import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/teacher_profile.dart';
import '../models/teaching_mode.dart';

sealed class TeacherProfileResult {
  const TeacherProfileResult();
}

final class TeacherProfileSuccess extends TeacherProfileResult {
  const TeacherProfileSuccess(this.profile);
  final TeacherProfile? profile;
}

final class TeacherProfileListSuccess extends TeacherProfileResult {
  const TeacherProfileListSuccess(this.profiles);
  final List<TeacherProfile> profiles;
}

final class TeacherProfileFailure extends TeacherProfileResult {
  const TeacherProfileFailure(this.message);
  final String message;
}

abstract class TeacherProfileService {
  Future<TeacherProfileResult> fetchMyProfile();

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
  });

  Future<TeacherProfileResult> fetchTeachers();

  Future<TeacherProfileResult> uploadProfilePhoto({required Uint8List bytes, required String fileExtension});
  Future<TeacherProfileResult> deleteProfilePhoto();
  Future<TeacherProfileResult> updatePhotoUrl(String? url);

  Future<TeacherProfileResult> uploadCoverPhoto({required Uint8List bytes, required String fileExtension});
  Future<TeacherProfileResult> deleteCoverPhoto();
  Future<TeacherProfileResult> updateCoverUrl(String? url);
}

class SupabaseTeacherProfileService implements TeacherProfileService {
  SupabaseTeacherProfileService(this._client);
  final SupabaseClient _client;

  @override
  Future<TeacherProfileResult> fetchMyProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return const TeacherProfileFailure('Please sign in again.');
    try {
      final row = await _client.from('teacher_profiles').select().eq('user_id', user.id).maybeSingle();
      return TeacherProfileSuccess(row == null ? null : TeacherProfile.fromMap(row));
    } catch (e) {
      return TeacherProfileFailure(_friendlyError(e));
    }
  }

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
    final user = _client.auth.currentUser;
    if (user == null) return const TeacherProfileFailure('Please sign in again.');
    final profile = TeacherProfile(
      id: '',
      userId: user.id,
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
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    try {
      final row = await _client.from('teacher_profiles')
          .upsert(profile.toUpsertMap(userId: user.id), onConflict: 'user_id').select().single();
      return TeacherProfileSuccess(TeacherProfile.fromMap(row));
    } on PostgrestException {
      // A missing column (e.g. cover_photo_url not yet migrated) causes
      // PostgreSQL error 42703 or PostgREST PGRST204.  Try a fallback
      // WITHOUT the newest column so the rest of the profile still saves.
      final payload = profile.toUpsertMap(userId: user.id);
      payload.remove('cover_photo_url');
      try {
        final row = await _client.from('teacher_profiles')
            .upsert(payload, onConflict: 'user_id')
            .select()
            .single();
        return TeacherProfileSuccess(TeacherProfile.fromMap(row));
      } on PostgrestException {
        // Even that failed — strip all optional columns as a last resort.
        try {
          final row = await _client.from('teacher_profiles')
              .upsert(profile.toUpsertMap(userId: user.id, includeOptionalColumns: false), onConflict: 'user_id')
              .select()
              .single();
          return TeacherProfileSuccess(TeacherProfile.fromMap(row));
        } catch (fallbackError) {
          return TeacherProfileFailure(_friendlyError(fallbackError));
        }
      }
    } catch (e) {
      return TeacherProfileFailure(_friendlyError(e));
    }
  }

  @override
  Future<TeacherProfileResult> fetchTeachers() async {
    final user = _client.auth.currentUser;
    if (user == null) return const TeacherProfileFailure('Please sign in again.');
    try {
      final rows = await _client.from('teacher_profiles').select().order('display_name', ascending: true);
      final profiles = (rows as List<dynamic>)
          .map((row) => TeacherProfile.fromMap(row as Map<String, dynamic>)).toList();
      return TeacherProfileListSuccess(profiles);
    } catch (e) {
      return TeacherProfileFailure(_friendlyError(e));
    }
  }

  @override
  Future<TeacherProfileResult> uploadProfilePhoto({required Uint8List bytes, required String fileExtension}) async {
    final user = _client.auth.currentUser;
    if (user == null) return const TeacherProfileFailure('Please sign in again.');
    try {
      final path = '${user.id}/profile.$fileExtension';
      await _client.storage.from('profile-photos').uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(upsert: true),
      );
      final baseUrl = _client.storage.from('profile-photos').getPublicUrl(path);
      final url = '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      return await updatePhotoUrl(url);
    } on StorageException catch (e) {
      debugPrint('StorageException: $e');
      if (e.statusCode == '404' || e.message.toLowerCase().contains('not found')) {
        return const TeacherProfileFailure(
          'Storage bucket "profile-photos" not found. Please create the bucket in your Supabase dashboard or run the migration SQL.',
        );
      }
      return TeacherProfileFailure(e.message);
    } catch (e) {
      return TeacherProfileFailure(_friendlyError(e));
    }
  }

  @override
  Future<TeacherProfileResult> deleteProfilePhoto() async {
    final user = _client.auth.currentUser;
    if (user == null) return const TeacherProfileFailure('Please sign in again.');
    try {
      try {
        final files = await _client.storage.from('profile-photos').list(path: user.id);
        if (files.isNotEmpty) {
          final paths = files.map((f) => '${user.id}/${f.name}').toList();
          await _client.storage.from('profile-photos').remove(paths);
        }
      } catch (_) {
        // Ignore storage cleanup failure if bucket or files do not exist
      }
      return await updatePhotoUrl(null);
    } catch (e) {
      return TeacherProfileFailure(_friendlyError(e));
    }
  }

  @override
  Future<TeacherProfileResult> updatePhotoUrl(String? url) async {
    final user = _client.auth.currentUser;
    if (user == null) return const TeacherProfileFailure('Please sign in again.');
    try {
      final existing = await _client
          .from('teacher_profiles')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (existing == null) {
        final name = (user.userMetadata?['name'] as String?) ??
            (user.email?.split('@').first ?? 'Teacher');
        final row = await _client
            .from('teacher_profiles')
            .upsert({
              'user_id': user.id,
              'display_name': name,
              'photo_url': url,
            }, onConflict: 'user_id')
            .select()
            .single();
        return TeacherProfileSuccess(TeacherProfile.fromMap(row));
      } else {
        final row = await _client
            .from('teacher_profiles')
            .update({'photo_url': url})
            .eq('user_id', user.id)
            .select()
            .single();
        return TeacherProfileSuccess(TeacherProfile.fromMap(row));
      }
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST204') {
        return const TeacherProfileFailure(
          'Column "photo_url" does not exist in teacher_profiles. Please run the SQL migration in Supabase.',
        );
      }
      return TeacherProfileFailure(_friendlyError(e));
    } catch (e) {
      return TeacherProfileFailure(_friendlyError(e));
    }
  }

  @override
  Future<TeacherProfileResult> uploadCoverPhoto({required Uint8List bytes, required String fileExtension}) async {
    final user = _client.auth.currentUser;
    if (user == null) return const TeacherProfileFailure('Please sign in again.');
    try {
      final path = '${user.id}/cover.$fileExtension';
      await _client.storage.from('profile-photos').uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(upsert: true),
      );
      final baseUrl = _client.storage.from('profile-photos').getPublicUrl(path);
      final url = '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      return await updateCoverUrl(url);
    } on StorageException catch (e) {
      debugPrint('StorageException (cover): $e');
      if (e.statusCode == '404' || e.message.toLowerCase().contains('not found')) {
        return const TeacherProfileFailure(
          'Storage bucket "profile-photos" not found. Please create the bucket in your Supabase dashboard or run the migration SQL.',
        );
      }
      return TeacherProfileFailure(e.message);
    } catch (e) {
      return TeacherProfileFailure(_friendlyError(e));
    }
  }

  @override
  Future<TeacherProfileResult> deleteCoverPhoto() async {
    final user = _client.auth.currentUser;
    if (user == null) return const TeacherProfileFailure('Please sign in again.');
    try {
      try {
        final files = await _client.storage.from('profile-photos').list(path: user.id);
        final coverFiles = files.where((f) => f.name.startsWith('cover.')).map((f) => '${user.id}/${f.name}').toList();
        if (coverFiles.isNotEmpty) {
          await _client.storage.from('profile-photos').remove(coverFiles);
        }
      } catch (_) {}
      return await updateCoverUrl(null);
    } catch (e) {
      return TeacherProfileFailure(_friendlyError(e));
    }
  }

  @override
  Future<TeacherProfileResult> updateCoverUrl(String? url) async {
    final user = _client.auth.currentUser;
    if (user == null) return const TeacherProfileFailure('Please sign in again.');
    try {
      final existing = await _client
          .from('teacher_profiles')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (existing == null) {
        final name = (user.userMetadata?['name'] as String?) ??
            (user.email?.split('@').first ?? 'Teacher');
        final row = await _client
            .from('teacher_profiles')
            .upsert({
              'user_id': user.id,
              'display_name': name,
              'cover_photo_url': url,
            }, onConflict: 'user_id')
            .select()
            .single();
        return TeacherProfileSuccess(TeacherProfile.fromMap(row));
      } else {
        final row = await _client
            .from('teacher_profiles')
            .update({'cover_photo_url': url})
            .eq('user_id', user.id)
            .select()
            .single();
        return TeacherProfileSuccess(TeacherProfile.fromMap(row));
      }
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST204') {
        return const TeacherProfileFailure(
          'Column "cover_photo_url" does not exist in teacher_profiles. Please run the SQL migration in Supabase.',
        );
      }
      return TeacherProfileFailure(_friendlyError(e));
    } catch (e) {
      return TeacherProfileFailure(_friendlyError(e));
    }
  }

  String _friendlyError(Object e) {
    debugPrint('TeacherProfileService error: $e');
    if (e is PostgrestException) {
      if (e.message.isNotEmpty) return e.message;
    }
    final message = e.toString().toLowerCase();
    if (message.contains('network') || message.contains('connection')) {
      return 'No connection. Please check your internet.';
    }
    if (message.contains('permission') ||
        message.contains('rls') ||
        message.contains('policy') ||
        message.contains('denied')) {
      return 'Permission denied. Please sign in again.';
    }
    return e.toString();
  }
}

class UnconfiguredTeacherProfileService implements TeacherProfileService {
  const UnconfiguredTeacherProfileService();
  static const _message = 'The app is not connected to a backend. Please contact support.';
  @override
  Future<TeacherProfileResult> fetchMyProfile() async => const TeacherProfileFailure(_message);
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
  }) async => const TeacherProfileFailure(_message);
  @override
  Future<TeacherProfileResult> fetchTeachers() async => const TeacherProfileFailure(_message);
  @override
  Future<TeacherProfileResult> uploadProfilePhoto({required Uint8List bytes, required String fileExtension}) async => const TeacherProfileFailure(_message);
  @override
  Future<TeacherProfileResult> deleteProfilePhoto() async => const TeacherProfileFailure(_message);
  @override
  Future<TeacherProfileResult> updatePhotoUrl(String? url) async => const TeacherProfileFailure(_message);
  @override
  Future<TeacherProfileResult> uploadCoverPhoto({required Uint8List bytes, required String fileExtension}) async => const TeacherProfileFailure(_message);
  @override
  Future<TeacherProfileResult> deleteCoverPhoto() async => const TeacherProfileFailure(_message);
  @override
  Future<TeacherProfileResult> updateCoverUrl(String? url) async => const TeacherProfileFailure(_message);
}

class TeacherProfileServiceScope extends InheritedWidget {
  const TeacherProfileServiceScope({super.key, required this.teacherProfileService, required super.child});
  final TeacherProfileService teacherProfileService;
  static TeacherProfileService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TeacherProfileServiceScope>();
    assert(scope != null, 'No TeacherProfileServiceScope found in widget tree.');
    return scope!.teacherProfileService;
  }
  @override
  bool updateShouldNotify(TeacherProfileServiceScope oldWidget) => teacherProfileService != oldWidget.teacherProfileService;
}
