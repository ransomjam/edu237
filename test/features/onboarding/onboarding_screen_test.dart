import 'dart:async';

import 'package:edu237/app.dart';
import 'package:edu237/core/models/app_user.dart';
import 'package:edu237/core/models/user_role.dart';
import 'package:edu237/core/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:edu237/shared/widgets/role_choice_selector.dart';

import '../auth/stub_auth_service.dart';
import 'stub_profile_service.dart';

/// Pumps the app with an incomplete-profile user so the router lands on
/// OnboardingScreen, using the given [profileService].
Future<void> pumpOnboarding(
  WidgetTester tester, {
  required ProfileService profileService,
  AppUser user = testUserIncomplete,
}) async {
  await tester.pumpWidget(
    CamivaApp(
      authService: StubAuthService(currentUserResult: user),
      profileService: profileService,
    ),
  );
  await tester.pumpAndSettle();
}

/// Reads the role the [RoleChoiceSelector] is currently showing as selected.
UserRole selectedRole(WidgetTester tester) {
  final selector =
      tester.widget<RoleChoiceSelector>(find.byType(RoleChoiceSelector));
  return selector.selected!;
}

void main() {
  // ---------------------------------------------------------------------------
  // Routing
  // ---------------------------------------------------------------------------
  group('Routing', () {
    testWidgets('unauthenticated → Login', (tester) async {
      await tester.pumpWidget(
        CamivaApp(
          authService: StubAuthService(),
          profileService: StubProfileService(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sign in'), findsWidgets);
      expect(find.text('How will you use Camiva?'), findsNothing);
    });

    testWidgets('authenticated + incomplete profile → Onboarding',
        (tester) async {
      await pumpOnboarding(
        tester,
        profileService: StubProfileService(),
      );
      expect(find.text('How will you use Camiva?'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);
    });

    testWidgets('authenticated + complete profile → App Shell', (tester) async {
      await tester.pumpWidget(
        CamivaApp(
          authService: StubAuthService(currentUserResult: testUser),
          profileService: StubProfileService(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsWidgets);
      expect(find.text('How will you use Camiva?'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // OnboardingScreen rendering
  // ---------------------------------------------------------------------------
  group('OnboardingScreen', () {
    testWidgets('renders title, subtitle, name field, role selector, button',
        (tester) async {
      await pumpOnboarding(tester, profileService: StubProfileService());
      expect(find.text('How will you use Camiva?'), findsOneWidget);
      expect(
          find.text('Choose your role. You can update this later.'),
          findsOneWidget);
      expect(find.text('Your name'), findsOneWidget);
      // Three human-worded choices, never raw enum names.
      expect(find.text('I am a Parent'), findsOneWidget);
      expect(find.text('I am a Teacher'), findsOneWidget);
      expect(find.text('I am a Student'), findsOneWidget);
      expect(find.text('PARENT'), findsNothing);
      expect(find.text('TEACHER'), findsNothing);
      expect(find.text('STUDENT'), findsNothing);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('Parent is selected by default', (tester) async {
      await pumpOnboarding(tester, profileService: StubProfileService());
      expect(selectedRole(tester), UserRole.parent);
    });

    testWidgets('Teacher can be selected', (tester) async {
      await pumpOnboarding(tester, profileService: StubProfileService());
      await tester.tap(find.text('I am a Teacher'));
      await tester.pumpAndSettle();
      expect(selectedRole(tester), UserRole.teacher);
    });

    testWidgets('choosing Student reveals the school questions and nothing '
        'else', (tester) async {
      await pumpOnboarding(tester, profileService: StubProfileService());
      await tester.tap(find.text('I am a Student'));
      await tester.pumpAndSettle();

      expect(selectedRole(tester), UserRole.student);
      expect(find.text('Your school details'), findsOneWidget);
      expect(find.text('Which education system?'), findsOneWidget);

      // Minimal signup: no address, no date of birth, no parent details.
      expect(find.textContaining('Neighbourhood'), findsNothing);
      expect(find.textContaining('City / Town'), findsNothing);
      expect(find.textContaining('Date of birth'), findsNothing);
      expect(find.textContaining("Parent's"), findsNothing);
    });

    testWidgets('a student cannot finish signup without a class',
        (tester) async {
      await pumpOnboarding(tester, profileService: StubProfileService());
      await tester.tap(find.text('I am a Student'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Your name'), 'Ngwa');

      final continueBtn = find.text('Continue');
      await tester.ensureVisible(continueBtn);
      await tester.tap(continueBtn);
      await tester.pumpAndSettle();

      expect(find.text('Please choose a class to continue.'), findsOneWidget);
    });

    testWidgets('shows validation error when name is empty', (tester) async {
      await pumpOnboarding(tester, profileService: StubProfileService());
      final continueBtn = find.text('Continue');
      await tester.ensureVisible(continueBtn);
      await tester.tap(continueBtn);
      await tester.pumpAndSettle();
      expect(find.text('This field is required.'), findsOneWidget);
    });

    testWidgets('shows loading state while submitting', (tester) async {
      // Use a service that never completes to observe the loading state.
      final neverCompletes = _NeverCompleteProfileService();
      await pumpOnboarding(tester, profileService: neverCompletes);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Your name'), 'Alice');
      final continueBtn = find.text('Continue');
      await tester.ensureVisible(continueBtn);
      await tester.tap(continueBtn);
      await tester.pump(); // one frame — loading starts
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('navigates to shell on successful onboarding', (tester) async {
      final completedUser = testUserIncomplete.copyWith(
        name: 'Alice',
        activeRole: UserRole.parent,
        profileComplete: true,
      );
      await pumpOnboarding(
        tester,
        profileService: StubProfileService(
          completeOnboardingResult: ProfileSuccess(completedUser),
        ),
      );
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Your name'), 'Alice');
      final continueBtn = find.text('Continue');
      await tester.ensureVisible(continueBtn);
      await tester.tap(continueBtn);
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsWidgets);
      expect(find.text('How will you use Camiva?'), findsNothing);
    });

    testWidgets('shows error banner on submission failure', (tester) async {
      await pumpOnboarding(
        tester,
        profileService: StubProfileService(
          completeOnboardingResult:
              const ProfileFailure('No connection. Please check your internet and try again.'),
        ),
      );
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Your name'), 'Alice');
      final continueBtn = find.text('Continue');
      await tester.ensureVisible(continueBtn);
      await tester.tap(continueBtn);
      await tester.pumpAndSettle();
      expect(
        find.text('No connection. Please check your internet and try again.'),
        findsOneWidget,
      );
    });
  });
}

/// A [ProfileService] whose [completeOnboarding] never resolves,
/// used to observe the loading state mid-submission.
class _NeverCompleteProfileService implements ProfileService {
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
      const ProfileFailure('stub');

  @override
  Future<ProfileResult> completeOnboarding({
    required String userId,
    required String email,
    required String name,
    required UserRole activeRole,
  }) =>
      Completer<ProfileResult>().future; // never completes
}
