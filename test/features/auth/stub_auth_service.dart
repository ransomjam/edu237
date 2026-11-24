import 'package:edu237/core/models/app_user.dart';
import 'package:edu237/core/models/user_role.dart';
import 'package:edu237/core/services/auth_service.dart';

/// A controllable stub [AuthService] for widget tests.
/// No network calls are made.
class StubAuthService implements AuthService {
  StubAuthService({
    this.currentUserResult,
    AuthResult? signInResult,
    AuthResult? registerResult,
  })  : _signInResult = signInResult ??
            const AuthFailure('stub: no sign-in result configured'),
        _registerResult = registerResult ??
            const AuthFailure('stub: no register result configured');

  final AppUser? currentUserResult;
  final AuthResult _signInResult;
  final AuthResult _registerResult;

  bool signOutCalled = false;

  /// Recovery calls, recorded so a test can check what the screen asked for.
  final List<String> resetRequests = [];
  final List<({String phone, String code, String pin})> resetConfirms = [];

  /// What confirmPinReset returns. Defaults to success.
  AuthResult confirmResult = const PinResetComplete();

  @override
  Stream<AppUser?> get authStateChanges => Stream.value(currentUserResult);

  @override
  Future<AppUser?> currentUser() async => currentUserResult;

  @override
  Future<AuthResult> signIn({
    required String phone,
    required String pin,
  }) async =>
      _signInResult;

  @override
  Future<AuthResult> register({
    required String phone,
    required String pin,
  }) async =>
      _registerResult;

  @override
  Future<AuthResult> requestPinReset(String phone) async {
    resetRequests.add(phone);
    return const PinResetRequested();
  }

  @override
  Future<AuthResult> confirmPinReset({
    required String phone,
    required String code,
    required String newPin,
  }) async {
    resetConfirms.add((phone: phone, code: code, pin: newPin));
    return confirmResult;
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
  }
}

/// A pre-built authenticated user for tests — profile complete, goes to shell.
/// Authenticated users are parents or teachers; this one is a parent.
const testUser = AppUser(
  id: 'test-id-123',
  email: 'test@edu237.cm',
  name: 'Test User',
  activeRole: UserRole.parent,
  profileComplete: true,
);

/// A pre-built teacher user for tests — profile complete.
const testTeacher = AppUser(
  id: 'teacher-id-456',
  email: 'teacher@edu237.cm',
  name: 'Test Teacher',
  activeRole: UserRole.teacher,
  profileComplete: true,
);

/// A pre-built student user for tests — profile complete. A student account is
/// a login attached to an existing `students` row, never a second learner.
const testStudent = AppUser(
  id: 'student-id-789',
  email: 'student@edu237.cm',
  name: 'Ngwa Divine',
  activeRole: UserRole.student,
  profileComplete: true,
);

/// A newly registered user whose profile is not yet complete.
/// New users default to parent until they confirm their role at onboarding.
const testUserIncomplete = AppUser(
  id: 'new-id-789',
  email: 'new@edu237.cm',
  name: '',
  activeRole: UserRole.parent,
  profileComplete: false,
);
