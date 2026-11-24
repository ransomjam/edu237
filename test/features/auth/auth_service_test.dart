import 'package:edu237/core/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'stub_auth_service.dart';

void main() {
  group('UnconfiguredAuthService', () {
    late AuthService sut;

    setUp(() => sut = const UnconfiguredAuthService());

    test('currentUser returns null', () async {
      expect(await sut.currentUser(), isNull);
    });

    test('authStateChanges emits nothing', () async {
      final events = await sut.authStateChanges.toList();
      expect(events, isEmpty);
    });

    test('signIn returns AuthFailure', () async {
      final result = await sut.signIn(phone: '670000000', pin: '1234');
      expect(result, isA<AuthFailure>());
    });

    test('register returns AuthFailure', () async {
      final result = await sut.register(
        phone: '670000000',
        pin: '1234',
      );
      expect(result, isA<AuthFailure>());
    });

    test('signOut completes without error', () async {
      await expectLater(sut.signOut(), completes);
    });
  });

  group('StubAuthService', () {
    test('returns configured signIn result', () async {
      final sut = StubAuthService(
        signInResult: AuthSuccess(testUser),
      );
      final result = await sut.signIn(phone: '670000000', pin: '1234');
      expect(result, isA<AuthSuccess>());
      expect((result as AuthSuccess).user.email, testUser.email);
    });

    test('returns configured register result', () async {
      final sut = StubAuthService(
        registerResult: const AuthFailure('email taken'),
      );
      final result = await sut.register(
        phone: '670000000',
        pin: '1234',
      );
      expect(result, isA<AuthFailure>());
      expect((result as AuthFailure).message, 'email taken');
    });

    test('signOut sets signOutCalled flag', () async {
      final sut = StubAuthService();
      await sut.signOut();
      expect(sut.signOutCalled, isTrue);
    });
  });
}
