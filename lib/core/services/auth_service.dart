import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/phone_credentials.dart';
import '../models/app_user.dart';
import '../models/user_role.dart';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

sealed class AuthResult {
  const AuthResult();
}

final class AuthSuccess extends AuthResult {
  const AuthSuccess(this.user);
  final AppUser user;
}

/// A recovery code has been requested. Deliberately says nothing about whether
/// the number is registered.
final class PinResetRequested extends AuthResult {
  const PinResetRequested();
}

/// The new PIN is in place; the person can sign in with it.
final class PinResetComplete extends AuthResult {
  const PinResetComplete();
}

final class AuthFailure extends AuthResult {
  const AuthFailure(this.message);
  final String message;
}

/// Sign-up produced a user but no session, which means the Supabase project
/// still has email confirmation switched on. There is no inbox behind a phone
/// account, so this is a configuration problem rather than something the person
/// signing up can fix.
final class AuthNeedsEmailConfirmation extends AuthResult {
  const AuthNeedsEmailConfirmation(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// All authentication operations go through this interface.
/// Screens must never call Supabase directly.
/// People sign in with a phone number and a short PIN. The phone is the
/// identity; the PIN never leaves the device in the clear (see
/// [PhoneCredentials]).
abstract class AuthService {
  Stream<AppUser?> get authStateChanges;
  Future<AppUser?> currentUser();

  /// [phone] may be in any form a person types; it is normalised here.
  Future<AuthResult> signIn({required String phone, required String pin});

  Future<AuthResult> register({required String phone, required String pin});

  /// Starts PIN recovery: a code is sent by SMS to the registered number.
  ///
  /// Always reports success. Telling a caller whether a number has an account
  /// would turn this into a way to discover who is registered.
  Future<AuthResult> requestPinReset(String phone);

  /// Completes recovery with the code from the SMS and a new PIN.
  Future<AuthResult> confirmPinReset({
    required String phone,
    required String code,
    required String newPin,
  });

  Future<void> signOut();
}

// ---------------------------------------------------------------------------
// Real implementation backed by Supabase
// ---------------------------------------------------------------------------

class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._client);

  final SupabaseClient _client;

  @override
  Stream<AppUser?> get authStateChanges {
    return _client.auth.onAuthStateChange.asyncMap((event) async {
      final session = event.session;
      if (session == null) return null;
      return _fetchAppUser(session.user);
    });
  }

  @override
  Future<AppUser?> currentUser() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    return _fetchAppUser(user);
  }

  @override
  Future<AuthResult> signIn({
    required String phone,
    required String pin,
  }) async {
    final number = PhoneCredentials.normalisePhone(phone);
    if (number == null) {
      return const AuthFailure('Enter a valid number, e.g. 670 00 00 00.');
    }
    if (!PhoneCredentials.isValidPin(pin)) {
      return const AuthFailure('Enter your PIN.');
    }

    try {
      final response = await _client.auth.signInWithPassword(
        email: PhoneCredentials.emailFor(number),
        password: PhoneCredentials.secretFor(number, pin),
      );
      final user = response.user;
      if (user == null) {
        return const AuthFailure('Sign in failed. Please try again.');
      }
      return AuthSuccess(await _fetchAppUser(user));
    } on AuthException catch (e) {
      return AuthFailure(_friendlyError(e.message));
    } catch (_) {
      return const AuthFailure(
          'Something went wrong. Please check your connection.');
    }
  }

  @override
  Future<AuthResult> register({
    required String phone,
    required String pin,
  }) async {
    final number = PhoneCredentials.normalisePhone(phone);
    if (number == null) {
      return const AuthFailure('Enter a valid number, e.g. 670 00 00 00.');
    }
    if (!PhoneCredentials.isValidPin(pin)) {
      return const AuthFailure(
        'Your PIN must be ${PhoneCredentials.minPinLength} to '
        '${PhoneCredentials.maxPinLength} digits.',
      );
    }

    final email = PhoneCredentials.emailFor(number);
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: PhoneCredentials.secretFor(number, pin),
        // Kept on the account so the number is available server-side without
        // parsing it back out of the address.
        data: {'phone': number},
      );
      final user = response.user;
      if (user == null) {
        return const AuthFailure('Could not create your account. Try again.');
      }

      if (response.session == null) {
        // Nothing the person can do: there is no inbox behind a phone account.
        return const AuthNeedsEmailConfirmation(
          'Accounts cannot be confirmed yet. Please contact support.',
        );
      }

      return AuthSuccess(AppUser(
        id: user.id,
        email: user.email ?? email,
        name: '',
        activeRole: UserRole.parent,
        profileComplete: false,
      ));
    } on AuthException catch (e) {
      return AuthFailure(_friendlyError(e.message));
    } catch (_) {
      return const AuthFailure(
          'Something went wrong. Please check your connection.');
    }
  }

  @override
  Future<AuthResult> requestPinReset(String phone) async {
    final number = PhoneCredentials.normalisePhone(phone);
    if (number == null) {
      return const AuthFailure('Enter a valid number, e.g. 670 00 00 00.');
    }
    try {
      await _client.functions.invoke(
        'pin-reset-request',
        body: {'phone': number},
      );
      // The reply carries no information about the account, and neither does
      // this: the same answer is given either way.
      return const PinResetRequested();
    } catch (_) {
      return const AuthFailure(
          'Could not send a code. Please check your connection.');
    }
  }

  @override
  Future<AuthResult> confirmPinReset({
    required String phone,
    required String code,
    required String newPin,
  }) async {
    final number = PhoneCredentials.normalisePhone(phone);
    if (number == null) {
      return const AuthFailure('Enter a valid number, e.g. 670 00 00 00.');
    }
    if (!PhoneCredentials.isValidPin(newPin)) {
      return const AuthFailure(
        'Your PIN must be ${PhoneCredentials.minPinLength} to '
        '${PhoneCredentials.maxPinLength} digits.',
      );
    }
    if (code.trim().length != 6) {
      return const AuthFailure('Enter the 6-digit code from the SMS.');
    }

    try {
      final response = await _client.functions.invoke(
        'pin-reset-confirm',
        body: {
          'phone': number,
          'code': code.trim(),
          // Derived here, so the new PIN never leaves the device either.
          'secret': PhoneCredentials.secretFor(number, newPin),
        },
      );
      final data = (response.data as Map?) ?? const {};
      if (data['reset'] == true) return const PinResetComplete();
      return AuthFailure(
        (data['error'] as String?) ?? 'That code is not valid.',
      );
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map ? details['error'] as String? : null;
      return AuthFailure(message ?? 'That code is not valid.');
    } catch (_) {
      return const AuthFailure(
          'Could not reset your PIN. Please check your connection.');
    }
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<AppUser> _fetchAppUser(User user) async {
    final profile = await _client
        .from('user_profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (profile != null) {
      return AppUser.fromMap(
        id: user.id,
        email: user.email ?? '',
        profile: profile,
      );
    }

    // No profile row yet — a freshly registered user who has not completed
    // onboarding. They default to parent until they confirm their role;
    // profile_complete is false so the router sends them to onboarding.
    return AppUser(
      id: user.id,
      email: user.email ?? '',
      name: '',
      activeRole: UserRole.parent,
      profileComplete: false,
    );
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('invalid login') ||
        lower.contains('invalid credentials')) {
      return 'Incorrect number or PIN.';
    }
    if (lower.contains('already registered') ||
        lower.contains('email already') ||
        lower.contains('user already')) {
      return 'An account already exists for this number. Sign in instead.';
    }
    if (lower.contains('rate limit') || lower.contains('too many')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    // The stored secret is a 64-character hash, so a length complaint is a
    // project setting rather than anything the person typed.
    if (lower.contains('password')) {
      return 'Could not sign you in. Please contact support.';
    }
    if (lower.contains('network') || lower.contains('connection')) {
      return 'No connection. Please check your internet.';
    }
    return 'Something went wrong. Please try again.';
  }
}

// ---------------------------------------------------------------------------
// Stub used when Supabase credentials are not configured
// ---------------------------------------------------------------------------

class UnconfiguredAuthService implements AuthService {
  const UnconfiguredAuthService();

  static const _msg =
      'The app is not connected to a backend. Please contact support.';

  @override
  Stream<AppUser?> get authStateChanges => const Stream.empty();

  @override
  Future<AppUser?> currentUser() async => null;

  @override
  Future<AuthResult> signIn({
    required String phone,
    required String pin,
  }) async =>
      const AuthFailure(_msg);

  @override
  Future<AuthResult> register({
    required String phone,
    required String pin,
  }) async =>
      const AuthFailure(_msg);

  @override
  Future<AuthResult> requestPinReset(String phone) async =>
      const AuthFailure(_msg);

  @override
  Future<AuthResult> confirmPinReset({
    required String phone,
    required String code,
    required String newPin,
  }) async =>
      const AuthFailure(_msg);

  @override
  Future<void> signOut() async {}
}

// ---------------------------------------------------------------------------
// Widget tree injection
// ---------------------------------------------------------------------------

/// Makes [AuthService] available to the widget tree.
/// Placed above [MaterialApp] in [app.dart].
class AuthServiceScope extends InheritedWidget {
  const AuthServiceScope({
    super.key,
    required this.authService,
    required super.child,
  });

  final AuthService authService;

  static AuthService of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AuthServiceScope>();
    assert(scope != null, 'No AuthServiceScope found in widget tree.');
    return scope!.authService;
  }

  @override
  bool updateShouldNotify(AuthServiceScope oldWidget) =>
      authService != oldWidget.authService;
}
