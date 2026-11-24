import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';
import '../models/user_role.dart';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

sealed class ProfileResult {
  const ProfileResult();
}

final class ProfileSuccess extends ProfileResult {
  const ProfileSuccess(this.user);
  final AppUser user;
}

final class ProfileFailure extends ProfileResult {
  const ProfileFailure(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// All user_profiles table operations go through this interface.
/// Screens must never call Supabase directly.
abstract class ProfileService {
  /// Fetches the profile for [userId]. Returns null if no row exists yet.
  Future<AppUser?> fetchProfile({
    required String userId,
    required String email,
  });

  /// Creates or replaces the profile row for [userId].
  Future<ProfileResult> upsertProfile({
    required String userId,
    required String email,
    required String name,
    required UserRole activeRole,
  });

  /// Marks the profile as complete (onboarding finished).
  Future<ProfileResult> completeOnboarding({
    required String userId,
    required String email,
    required String name,
    required UserRole activeRole,
  });
}

// ---------------------------------------------------------------------------
// Real implementation backed by Supabase
// ---------------------------------------------------------------------------

class SupabaseProfileService implements ProfileService {
  SupabaseProfileService(this._client);

  final SupabaseClient _client;

  @override
  Future<AppUser?> fetchProfile({
    required String userId,
    required String email,
  }) async {
    try {
      final row = await _client
          .from('user_profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (row == null) return null;
      return AppUser.fromMap(id: userId, email: email, profile: row);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ProfileResult> upsertProfile({
    required String userId,
    required String email,
    required String name,
    required UserRole activeRole,
  }) async {
    try {
      final row = await _client
          .from('user_profiles')
          .upsert({
            'id': userId,
            'email': email,
            'name': name.trim(),
            'active_role': AppUser.roleToString(activeRole),
          })
          .select()
          .single();
      return ProfileSuccess(
        AppUser.fromMap(id: userId, email: email, profile: row),
      );
    } catch (e) {
      return ProfileFailure(_friendlyError(e));
    }
  }

  @override
  Future<ProfileResult> completeOnboarding({
    required String userId,
    required String email,
    required String name,
    required UserRole activeRole,
  }) async {
    try {
      final row = await _client
          .from('user_profiles')
          .upsert({
            'id': userId,
            'email': email,
            'name': name.trim(),
            'active_role': AppUser.roleToString(activeRole),
            'profile_complete': true,
          })
          .select()
          .single();
      return ProfileSuccess(
        AppUser.fromMap(id: userId, email: email, profile: row),
      );
    } catch (e) {
      return ProfileFailure(_friendlyError(e));
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('network') || msg.contains('connection')) {
      return 'No connection. Please check your internet.';
    }
    if (msg.contains('permission') || msg.contains('rls') ||
        msg.contains('policy')) {
      return 'Permission denied. Please sign in again.';
    }
    return 'Something went wrong. Please try again.';
  }
}

// ---------------------------------------------------------------------------
// Stub used when Supabase credentials are not configured
// ---------------------------------------------------------------------------

class UnconfiguredProfileService implements ProfileService {
  const UnconfiguredProfileService();

  @override
  Future<AppUser?> fetchProfile({
    required String userId,
    required String email,
  }) async =>
      null;

  @override
  Future<ProfileResult> upsertProfile({
    required String userId,
    required String email,
    required String name,
    required UserRole activeRole,
  }) async =>
      const ProfileFailure(
          'The app is not connected to a backend. Please contact support.');

  @override
  Future<ProfileResult> completeOnboarding({
    required String userId,
    required String email,
    required String name,
    required UserRole activeRole,
  }) async =>
      const ProfileFailure(
          'The app is not connected to a backend. Please contact support.');
}

// ---------------------------------------------------------------------------
// Widget tree injection
// ---------------------------------------------------------------------------

class ProfileServiceScope extends InheritedWidget {
  const ProfileServiceScope({
    super.key,
    required this.profileService,
    required super.child,
  });

  final ProfileService profileService;

  static ProfileService of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ProfileServiceScope>();
    assert(scope != null, 'No ProfileServiceScope found in widget tree.');
    return scope!.profileService;
  }

  @override
  bool updateShouldNotify(ProfileServiceScope oldWidget) =>
      profileService != oldWidget.profileService;
}
