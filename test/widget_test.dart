import 'package:edu237/app.dart';
import 'package:flutter_test/flutter_test.dart';

import 'features/auth/stub_auth_service.dart';
import 'features/onboarding/stub_profile_service.dart';

void main() {
  testWidgets('Unauthenticated app shows Login screen', (tester) async {
    await tester.pumpWidget(
      CamivaApp(
        authService: StubAuthService(),
        profileService: StubProfileService(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsWidgets);
  });

  testWidgets('Authenticated parent shows shell with bottom navigation',
      (tester) async {
    await tester.pumpWidget(
      CamivaApp(
        authService: StubAuthService(currentUserResult: testUser),
        profileService: StubProfileService(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Payments'), findsWidgets);
    expect(find.text('Updates'), findsWidgets);
    expect(find.text('Profile'), findsNothing);
    
    // Retired concepts must not appear.
    expect(find.text('Classes'), findsNothing);
    expect(find.text('Assignments'), findsNothing);
  });

  testWidgets('Authenticated teacher shows shell with bottom navigation',
      (tester) async {
    await tester.pumpWidget(
      CamivaApp(
        authService: StubAuthService(currentUserResult: testTeacher),
        profileService: StubProfileService(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Earnings'), findsWidgets);
    expect(find.text('Updates'), findsWidgets);
    expect(find.text('Profile'), findsWidgets);
  });
}
