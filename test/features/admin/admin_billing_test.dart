import 'package:edu237/core/services/admin_service.dart';
import 'package:edu237/features/admin/admin_billing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_admin_service.dart';

Future<void> _pump(WidgetTester tester, AdminService service) async {
  await tester.pumpWidget(
    AdminServiceScope(
      adminService: service,
      child: const MaterialApp(home: AdminBillingScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('AdminBillingScreen', () {
    testWidgets('shows what is owed, by whom, and by when', (tester) async {
      await _pump(tester, FakeAdminService(billing: [fakeBillingRow()]));

      expect(find.text('Favour'), findsOneWidget);
      expect(find.text('Mrs Ayuk → Jam Ransom'), findsOneWidget);
      // Balance, not the monthly fee, is the headline figure.
      expect(find.text('15,000 FCFA'), findsOneWidget);
      expect(find.text('20,000 FCFA'), findsOneWidget);
      expect(find.text('5,000 FCFA'), findsOneWidget);
      expect(find.text('1 Sep 2026'), findsOneWidget);
    });

    testWidgets('separates outstanding from fully paid', (tester) async {
      await _pump(
        tester,
        FakeAdminService(billing: [
          fakeBillingRow(),
          fakeBillingRow(
            relationshipId: 'rel-2',
            childName: 'Joel',
            paidThisPeriod: 20000,
          ),
        ]),
      );

      expect(find.text('OUTSTANDING THIS MONTH'), findsOneWidget);
      expect(find.text('FULLY PAID THIS MONTH'), findsOneWidget);
      // A settled arrangement offers no reminder to send.
      expect(find.byKey(const Key('remind_rel-2')), findsNothing);
      expect(find.byKey(const Key('remind_rel-1')), findsOneWidget);
    });

    testWidgets('a reminder with push configured says both happened',
        (tester) async {
      final service = FakeAdminService(
        billing: [fakeBillingRow()],
        push: PushOutcome.sent,
      );
      await _pump(tester, service);

      await tester.tap(find.byKey(const Key('remind_rel-1')));
      await tester.pumpAndSettle();

      expect(service.reminded, ['rel-1']);
      expect(find.text('Reminder sent in the app and to their phone.'),
          findsOneWidget);
    });

    testWidgets('without push set up, it does not claim a notification',
        (tester) async {
      final service = FakeAdminService(
        billing: [fakeBillingRow()],
        push: PushOutcome.notConfigured,
      );
      await _pump(tester, service);

      await tester.tap(find.byKey(const Key('remind_rel-1')));
      await tester.pumpAndSettle();

      // The in-app reminder is real; the push is not claimed.
      expect(
        find.text(
            'Reminder sent in the app. Push notifications are not set up yet.'),
        findsOneWidget,
      );
    });

    testWidgets('with no registered device, it says so', (tester) async {
      final service = FakeAdminService(
        billing: [fakeBillingRow()],
        push: PushOutcome.noDevice,
      );
      await _pump(tester, service);

      await tester.tap(find.byKey(const Key('remind_rel-1')));
      await tester.pumpAndSettle();

      expect(
        find.text(
            'Reminder sent in the app. No phone registered for notifications.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed push is reported as failed, not as sent',
        (tester) async {
      final service = FakeAdminService(
        billing: [fakeBillingRow()],
        push: PushOutcome.failed,
      );
      await _pump(tester, service);

      await tester.tap(find.byKey(const Key('remind_rel-1')));
      await tester.pumpAndSettle();

      expect(
        find.text('Reminder sent in the app. The push notification did not '
            'go through.'),
        findsOneWidget,
      );
    });

    testWidgets('a non-admin sees no balances', (tester) async {
      await _pump(
        tester,
        FakeAdminService(
          isAdmin: false,
          billing: [fakeBillingRow()],
          failure: 'Not authorised',
        ),
      );

      expect(find.text('Mrs Ayuk → Jam Ransom'), findsNothing);
      expect(find.text('15,000 FCFA'), findsNothing);
    });

    testWidgets('says plainly when no monthly arrangements exist',
        (tester) async {
      await _pump(tester, FakeAdminService());
      expect(find.byKey(const Key('admin_no_billing')), findsOneWidget);
    });
  });

  group('PushOutcome', () {
    test('every outcome states the in-app delivery and nothing more', () {
      for (final outcome in PushOutcome.values) {
        expect(outcome.message, contains('in the app'));
      }
      // Only 'sent' may mention the phone.
      expect(PushOutcome.sent.message, contains('phone'));
      expect(PushOutcome.notConfigured.message, isNot(contains('to their')));
    });

    test('an unknown status is treated as not configured, never as sent', () {
      expect(PushOutcome.fromString(null), PushOutcome.notConfigured);
      expect(PushOutcome.fromString('something-else'),
          PushOutcome.notConfigured);
    });
  });
}
