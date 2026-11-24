import 'package:edu237/core/models/payment_transaction.dart';
import 'package:edu237/core/services/admin_service.dart';
import 'package:edu237/features/admin/admin_home_screen.dart';
import 'package:edu237/features/admin/admin_payments_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_admin_service.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Widget screen,
  required AdminService service,
}) async {
  await tester.pumpWidget(
    AdminServiceScope(
      adminService: service,
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('AdminPaymentsScreen', () {
    testWidgets('states plainly which parent paid which teacher, for whom',
        (tester) async {
      await _pump(
        tester,
        screen: const AdminPaymentsScreen(),
        service: FakeAdminService(payments: [fakeAdminPayment()]),
      );

      expect(find.text('Tutoring payment'), findsOneWidget);
      expect(find.text('Mrs Ayuk → Jam Ransom'), findsOneWidget);
      expect(find.text('For Favour'), findsOneWidget);
      expect(find.text('5,000 FCFA'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('FAPSHI-123'), findsOneWidget);
    });

    testWidgets('a platform fee reads as teacher paying Camiva, not a parent',
        (tester) async {
      await _pump(
        tester,
        screen: const AdminPaymentsScreen(),
        service: FakeAdminService(payments: [
          fakeAdminPayment(
            id: 'fee-1',
            purpose: PaymentPurpose.matchActivation,
            amount: 1000,
            parentName: 'Mrs Ayuk',
          ),
        ]),
      );

      // The parent is a party to the relationship but not to this payment.
      expect(find.text('Jam Ransom → Camiva'), findsOneWidget);
      expect(find.text('Mrs Ayuk → Jam Ransom'), findsNothing);
    });

    testWidgets('a failed payment shows its status and reason', (tester) async {
      await _pump(
        tester,
        screen: const AdminPaymentsScreen(),
        service: FakeAdminService(payments: [
          AdminPayment(
            id: 'pay-9',
            purpose: PaymentPurpose.tutoringPayment,
            amount: 5000,
            currency: 'XAF',
            status: PaymentStatus.failed,
            parentName: 'Mrs Ayuk',
            teacherName: 'Jam Ransom',
            childName: 'Favour',
            failureReason: 'Insufficient balance',
            createdAt: DateTime(2026, 8, 13),
          ),
        ]),
      );

      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Insufficient balance'), findsOneWidget);
    });

    testWidgets('no contact details are ever shown here', (tester) async {
      await _pump(
        tester,
        screen: const AdminPaymentsScreen(),
        service: FakeAdminService(payments: [fakeAdminPayment()]),
      );

      // Reconciling money needs identity, not phone numbers or emails.
      expect(find.textContaining('67'), findsNothing);
      expect(find.textContaining('@'), findsNothing);
    });

    testWidgets('a non-admin reaching the screen sees no payment data',
        (tester) async {
      await _pump(
        tester,
        screen: const AdminPaymentsScreen(),
        service: FakeAdminService(
          isAdmin: false,
          payments: [fakeAdminPayment()],
          failure: 'Not authorised',
        ),
      );

      expect(find.text('Mrs Ayuk → Jam Ransom'), findsNothing);
      expect(find.text('5,000 FCFA'), findsNothing);
      expect(find.text('Could not load payments'), findsOneWidget);
    });

    testWidgets('an empty ledger says so', (tester) async {
      await _pump(
        tester,
        screen: const AdminPaymentsScreen(),
        service: FakeAdminService(),
      );
      expect(find.byKey(const Key('admin_no_payments')), findsOneWidget);
    });
  });

  group('AdminHomeScreen', () {
    testWidgets('shows platform money derived from the ledger', (tester) async {
      await _pump(
        tester,
        screen: const AdminHomeScreen(),
        service: FakeAdminService(
          totals: const AdminTotals(
            collected: 45000,
            successfulCount: 9,
            pendingCount: 1,
            failedCount: 2,
            owedToTeachers: 20000,
            awaitingWithdrawal: 2,
            currency: 'XAF',
          ),
        ),
      );

      expect(find.text('45,000 FCFA'), findsOneWidget);
      expect(find.text('20,000 FCFA'), findsOneWidget);
      expect(find.text('9 paid · 1 pending'), findsOneWidget);
      expect(find.text('2 waiting to be sent'), findsOneWidget);
    });

    testWidgets('says when nothing is waiting', (tester) async {
      await _pump(
        tester,
        screen: const AdminHomeScreen(),
        service: FakeAdminService(),
      );
      // Withdrawals and verifications each report an empty queue.
      expect(find.text('Nothing waiting'), findsNWidgets(2));
    });
  });
}
