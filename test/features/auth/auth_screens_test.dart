import 'package:edu237/app.dart';
import 'package:edu237/core/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'stub_auth_service.dart';
import '../onboarding/stub_profile_service.dart';

/// Pumps [CamivaApp] with a [StubAuthService] and settles routing.
Future<void> pumpApp(
  WidgetTester tester, {
  required AuthService authService,
}) async {
  await tester.pumpWidget(
    CamivaApp(
      authService: authService,
      profileService: StubProfileService(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // ---------------------------------------------------------------------------
  // Unauthenticated routing
  // ---------------------------------------------------------------------------
  group('Unauthenticated routing', () {
    testWidgets('shows Login screen when no session exists', (tester) async {
      await pumpApp(tester, authService: StubAuthService());
      expect(find.text('Sign in'), findsWidgets);
      // Shell nav must NOT be visible
      expect(find.text('Home'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Authenticated routing
  // ---------------------------------------------------------------------------
  group('Authenticated routing', () {
    testWidgets('shows app shell when session exists', (tester) async {
      await pumpApp(
        tester,
        authService: StubAuthService(currentUserResult: testUser),
      );
      // Bottom nav is visible
      expect(find.text('Home'), findsWidgets);
      expect(find.text('Payments'), findsWidgets);
      expect(find.text('Profile'), findsNothing);
      // The retired Classes tab must not exist.
      expect(find.text('Classes'), findsNothing);
      // Login screen is NOT visible
      expect(find.text('Sign in'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Login screen
  // ---------------------------------------------------------------------------
  group('LoginScreen', () {
    testWidgets('renders email, password fields and sign-in button',
        (tester) async {
      await pumpApp(tester, authService: StubAuthService());
      expect(find.text('Phone number'), findsOneWidget);
      expect(find.text('PIN'), findsOneWidget);
      expect(find.text('Sign in'), findsWidgets);
    });

    testWidgets('shows validation errors when submitted empty', (tester) async {
      await pumpApp(tester, authService: StubAuthService());
      // Tap the Sign in button without filling fields
      final signInBtn = find.widgetWithText(ElevatedButton, 'Sign in');
      await tester.tap(signInBtn);
      await tester.pumpAndSettle();
      expect(find.text('This field is required.'), findsWidgets);
    });

    testWidgets('shows error banner on auth failure', (tester) async {
      await pumpApp(
        tester,
        authService: StubAuthService(
          signInResult: const AuthFailure('Incorrect email or password.'),
        ),
      );
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Phone number'), '670000000');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'PIN'), '9999');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Incorrect email or password.'), findsOneWidget);
    });

    testWidgets('navigates to Register when link tapped', (tester) async {
      await pumpApp(tester, authService: StubAuthService());
      await tester.tap(find.text('Register'));
      await tester.pumpAndSettle();
      expect(find.text('Create account'), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------
  // Register screen
  // ---------------------------------------------------------------------------
  group('RegisterScreen', () {
    Future<void> goToRegister(WidgetTester tester) async {
      await pumpApp(tester, authService: StubAuthService());
      await tester.tap(find.text('Register'));
      await tester.pumpAndSettle();
    }

    /// Registration starts with "who are you?", so every submit path has to
    /// answer it first.
    Future<void> chooseRole(WidgetTester tester, String label) async {
      final option = find.text(label);
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
    }

    testWidgets('offers three human-worded roles, never raw enum names',
        (tester) async {
      await goToRegister(tester);
      expect(find.text('I am a Parent'), findsOneWidget);
      expect(find.text('I am a Teacher'), findsOneWidget);
      expect(find.text('I am a Student'), findsOneWidget);
      expect(find.text('PARENT'), findsNothing);
      expect(find.text('TEACHER'), findsNothing);
      expect(find.text('STUDENT'), findsNothing);
    });

    testWidgets('renders account fields', (tester) async {
      await goToRegister(tester);
      expect(find.text('Phone number'), findsOneWidget);
      expect(find.text('PIN'), findsOneWidget);
      expect(find.text('Confirm PIN'), findsOneWidget);
    });

    testWidgets('a role must be chosen before an account is created',
        (tester) async {
      await goToRegister(tester);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Phone number'), '670000000');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'PIN'), '1234');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm PIN'), '1234');

      final createBtn = find.widgetWithText(ElevatedButton, 'Create account');
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pumpAndSettle();

      expect(
        find.text('Please choose how you will use Camiva.'),
        findsOneWidget,
      );
    });

    testWidgets('shows PIN mismatch error', (tester) async {
      await goToRegister(tester);
      await chooseRole(tester, 'I am a Parent');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Phone number'), '670000000');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'PIN'), '1234');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm PIN'), '5678');
      await tester.ensureVisible(
          find.widgetWithText(ElevatedButton, 'Create account'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(find.text('The two PINs do not match.'), findsOneWidget);
    });

    testWidgets('navigates to onboarding on successful registration',
        (tester) async {
      // Start unauthenticated so we land on Login, then navigate to Register.
      // Use a stub that returns success on register but starts with no session.
      final stub = StubAuthService(
        registerResult: const AuthSuccess(testUserIncomplete),
      );
      await pumpApp(tester, authService: stub);
      await tester.tap(find.text('Register'));
      await tester.pumpAndSettle();
      await chooseRole(tester, 'I am a Parent');

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Phone number'), '670000000');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'PIN'), '1234');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm PIN'), '1234');
      await tester.ensureVisible(
          find.widgetWithText(ElevatedButton, 'Create account'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await tester.pumpAndSettle();

      expect(find.text('How will you use Camiva?'), findsOneWidget);
    });

    testWidgets('shows email confirmation message when no session is returned',
        (tester) async {
      final stub = StubAuthService(
        registerResult: const AuthNeedsEmailConfirmation(
          'Check your email to confirm your account, then sign in.',
        ),
      );
      await pumpApp(tester, authService: stub);
      await tester.tap(find.text('Register'));
      await tester.pumpAndSettle();
      await chooseRole(tester, 'I am a Parent');

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Phone number'), '670000000');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'PIN'), '1234');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm PIN'), '1234');
      await tester.ensureVisible(
          find.widgetWithText(ElevatedButton, 'Create account'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await tester.pumpAndSettle();

      expect(
        find.text('Check your email to confirm your account, then sign in.'),
        findsOneWidget,
      );
    });
  });
}
