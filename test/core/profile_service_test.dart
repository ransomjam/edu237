import 'package:edu237/core/models/app_user.dart';
import 'package:edu237/core/models/user_role.dart';
import 'package:edu237/core/services/profile_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // AppUser.fromMap — profile parsing
  // ---------------------------------------------------------------------------
  group('AppUser.fromMap', () {
    test('parses a complete parent profile row', () {
      final user = AppUser.fromMap(
        id: 'uid-0',
        email: 'p@b.com',
        profile: {
          'name': 'Pat',
          'active_role': 'parent',
          'profile_complete': true,
        },
      );
      expect(user.activeRole, UserRole.parent);
      expect(user.profileComplete, isTrue);
    });

    test('parses a complete teacher profile row', () {
      final user = AppUser.fromMap(
        id: 'uid-1',
        email: 'a@b.com',
        profile: {
          'name': 'Alice',
          'active_role': 'teacher',
          'profile_complete': true,
        },
      );
      expect(user.id, 'uid-1');
      expect(user.email, 'a@b.com');
      expect(user.name, 'Alice');
      expect(user.activeRole, UserRole.teacher);
      expect(user.profileComplete, isTrue);
    });

    test('throws for unknown role string', () {
      expect(
        () => AppUser.fromMap(
          id: 'uid-2',
          email: 'b@c.com',
          profile: {'name': 'Bob', 'active_role': 'unknown_role'},
        ),
        throwsFormatException,
      );
    });

    test('fails safely (throws) when active_role is null — no silent default',
        () {
      expect(
        () => AppUser.fromMap(
          id: 'uid-3',
          email: 'c@d.com',
          profile: {'name': 'Carol', 'active_role': null},
        ),
        throwsFormatException,
      );
    });

    test('accepts the student role — students can now authenticate', () {
      final user = AppUser.fromMap(
        id: 'uid-5',
        email: 'e@f.com',
        profile: {'name': 'Eve', 'active_role': 'student'},
      );
      expect(user.activeRole, UserRole.student);
      expect(user.activeRole.isStudent, isTrue);
      expect(user.activeRole.isParent, isFalse);
      expect(user.activeRole.isTeacher, isFalse);
    });

    test('defaults profileComplete to false when absent', () {
      final user = AppUser.fromMap(
        id: 'uid-4',
        email: 'd@e.com',
        profile: {'name': 'Dave', 'active_role': 'parent'},
      );
      expect(user.profileComplete, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // AppUser.roleToString / roleFromString round-trip
  // ---------------------------------------------------------------------------
  group('role serialisation', () {
    test('parent round-trips correctly', () {
      expect(
        AppUser.roleFromString(AppUser.roleToString(UserRole.parent)),
        UserRole.parent,
      );
    });

    test('teacher round-trips correctly', () {
      expect(
        AppUser.roleFromString(AppUser.roleToString(UserRole.teacher)),
        UserRole.teacher,
      );
    });

    test('student round-trips correctly', () {
      expect(
        AppUser.roleFromString(AppUser.roleToString(UserRole.student)),
        UserRole.student,
      );
    });

    test('roleFromString rejects null and unknown values', () {
      expect(() => AppUser.roleFromString(null), throwsFormatException);
      expect(() => AppUser.roleFromString('admin'), throwsFormatException);
      expect(() => AppUser.roleFromString(''), throwsFormatException);
    });
  });

  // ---------------------------------------------------------------------------
  // UnconfiguredProfileService
  // ---------------------------------------------------------------------------
  group('UnconfiguredProfileService', () {
    late ProfileService sut;

    setUp(() => sut = const UnconfiguredProfileService());

    test('fetchProfile returns null', () async {
      final result = await sut.fetchProfile(userId: 'x', email: 'x@y.com');
      expect(result, isNull);
    });

    test('upsertProfile returns ProfileFailure', () async {
      final result = await sut.upsertProfile(
        userId: 'x',
        email: 'x@y.com',
        name: 'X',
        activeRole: UserRole.parent,
      );
      expect(result, isA<ProfileFailure>());
    });

    test('completeOnboarding returns ProfileFailure', () async {
      final result = await sut.completeOnboarding(
        userId: 'x',
        email: 'x@y.com',
        name: 'X',
        activeRole: UserRole.parent,
      );
      expect(result, isA<ProfileFailure>());
    });
  });
}
