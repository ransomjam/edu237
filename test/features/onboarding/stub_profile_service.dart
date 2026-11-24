import 'package:edu237/core/models/app_user.dart';
import 'package:edu237/core/models/user_role.dart';
import 'package:edu237/core/services/profile_service.dart';

class StubProfileService implements ProfileService {
  StubProfileService({
    this.fetchResult,
    ProfileResult? upsertResult,
    ProfileResult? completeOnboardingResult,
  })  : _upsertResult = upsertResult ??
            const ProfileFailure('stub: no upsert result configured'),
        _completeOnboardingResult = completeOnboardingResult ??
            const ProfileFailure('stub: no completeOnboarding result configured');

  final AppUser? fetchResult;
  final ProfileResult _upsertResult;
  final ProfileResult _completeOnboardingResult;

  @override
  Future<AppUser?> fetchProfile({
    required String userId,
    required String email,
  }) async =>
      fetchResult;

  @override
  Future<ProfileResult> upsertProfile({
    required String userId,
    required String email,
    required String name,
    required UserRole activeRole,
  }) async =>
      _upsertResult;

  @override
  Future<ProfileResult> completeOnboarding({
    required String userId,
    required String email,
    required String name,
    required UserRole activeRole,
  }) async =>
      _completeOnboardingResult;
}
