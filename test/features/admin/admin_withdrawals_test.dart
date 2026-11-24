import 'package:edu237/core/models/withdrawal.dart';
import 'package:edu237/core/services/admin_service.dart';
import 'package:edu237/features/admin/admin_withdrawals_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_admin_service.dart';

Future<void> _pump(WidgetTester tester, AdminService service) async {
  await tester.pumpWidget(
    AdminServiceScope(
      adminService: service,
      child: const MaterialApp(home: AdminWithdrawalsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fillPrompt(WidgetTester tester, String value) async {
  await tester.enterText(find.byKey(const Key('admin_prompt_field')), value);
  await tester.tap(find.byKey(const Key('admin_prompt_confirm')));
  await tester.pumpAndSettle();
}

void main() {
  group('AdminWithdrawalsScreen', () {
    testWidgets('shows what an admin needs in order to send the money',
        (tester) async {
      await _pump(tester, FakeAdminService(pending: [fakePending()]));

      expect(find.text('Jam Ransom'), findsOneWidget);
      expect(find.text('5,000 FCFA'), findsOneWidget);
      // The full number, because sending the money requires it.
      expect(find.text('670123456'), findsOneWidget);
      expect(find.byKey(const Key('mark_sent_w1')), findsOneWidget);
      expect(find.byKey(const Key('reject_w1')), findsOneWidget);
    });

    testWidgets('marking as sent records the reference', (tester) async {
      final service = FakeAdminService(pending: [fakePending()]);
      await _pump(tester, service);

      await tester.tap(find.byKey(const Key('mark_sent_w1')));
      await tester.pumpAndSettle();
      await _fillPrompt(tester, 'MOMO-88213');

      expect(service.sent, hasLength(1));
      expect(service.sent.single.id, 'w1');
      expect(service.sent.single.reference, 'MOMO-88213');
    });

    testWidgets('a settlement without a reference is not recorded',
        (tester) async {
      final service = FakeAdminService(pending: [fakePending()]);
      await _pump(tester, service);

      await tester.tap(find.byKey(const Key('mark_sent_w1')));
      await tester.pumpAndSettle();
      await _fillPrompt(tester, '   ');

      // Nothing is claimed to have been sent.
      expect(service.sent, isEmpty);
      expect(find.byKey(const Key('pending_withdrawal_w1')), findsOneWidget);
    });

    testWidgets('rejecting captures the reason the teacher will see',
        (tester) async {
      final service = FakeAdminService(pending: [fakePending()]);
      await _pump(tester, service);

      await tester.tap(find.byKey(const Key('reject_w1')));
      await tester.pumpAndSettle();
      await _fillPrompt(tester, 'Wrong payout number.');

      expect(service.rejected, hasLength(1));
      expect(service.rejected.single.reason, 'Wrong payout number.');
      expect(service.sent, isEmpty);
    });

    testWidgets('an empty queue says so plainly', (tester) async {
      await _pump(tester, FakeAdminService());
      expect(find.byKey(const Key('admin_no_pending')), findsOneWidget);
    });

    testWidgets('a non-admin reaching the screen is shown nothing',
        (tester) async {
      await _pump(
        tester,
        FakeAdminService(
          isAdmin: false,
          pending: [fakePending()],
          failure: 'Not authorised',
        ),
      );

      // The server refused, so no teacher name, amount or payout number leaks.
      expect(find.text('Jam Ransom'), findsNothing);
      expect(find.text('670123456'), findsNothing);
      expect(find.text('Could not load withdrawals'), findsOneWidget);
    });

    testWidgets('handled withdrawals show how they were settled',
        (tester) async {
      await _pump(
        tester,
        FakeAdminService(recent: [
          SettledWithdrawal(
            id: 'w0',
            teacherName: 'Jam Ransom',
            amount: 5000,
            currency: 'XAF',
            status: WithdrawalStatus.successful,
            settlementMode: SettlementMode.manual,
            reference: 'MOMO-1',
            completedAt: DateTime(2026, 8, 13),
          ),
        ]),
      );

      expect(find.text('Ref MOMO-1'), findsOneWidget);
      expect(find.text('Sent'), findsOneWidget);
    });
  });

  group('UnconfiguredAdminService', () {
    test('never grants admin access when there is no backend', () async {
      final result = await const UnconfiguredAdminService().checkAdminAccess();
      expect(result, isA<AdminAccessSuccess>());
      expect((result as AdminAccessSuccess).isAdmin, isFalse);
    });

    test('every admin action fails closed', () async {
      const sut = UnconfiguredAdminService();
      expect(await sut.fetchPendingWithdrawals(), isA<AdminFailure>());
      expect(await sut.fetchRecentWithdrawals(), isA<AdminFailure>());
      expect(
        await sut.markWithdrawalSent(withdrawalId: 'w1', reference: 'r'),
        isA<AdminFailure>(),
      );
      expect(
        await sut.rejectWithdrawal(withdrawalId: 'w1', reason: 'r'),
        isA<AdminFailure>(),
      );
    });
  });

  group('manual settlement records', () {
    test('a withdrawal says which route settled it', () {
      final row = Withdrawal.fromMap({
        'id': 'w1',
        'teacher_id': 'teacher-1',
        'amount': 5000,
        'currency': 'XAF',
        'status': 'successful',
        'payout_medium': 'mobile money',
        'payout_phone': '670123456',
        'settlement_mode': 'manual',
        'manual_reference': 'MOMO-88213',
        'created_at': '2026-08-13T10:00:00Z',
        'updated_at': '2026-08-13T11:00:00Z',
        'completed_at': '2026-08-13T11:00:00Z',
      });

      expect(row.settlementMode, SettlementMode.manual);
      expect(row.manualReference, 'MOMO-88213');
      // A manual settlement is never dressed up as a provider payout.
      expect(row.providerTransId, isNull);
    });

    test('a requested withdrawal does not claim the provider has it', () {
      expect(WithdrawalStatus.requested.message,
          'Camiva is sending your money.');
      expect(WithdrawalStatus.requested.message.toLowerCase(),
          isNot(contains('provider')));
    });

    test('a rejected withdrawal tells the teacher their money is intact', () {
      expect(WithdrawalStatus.cancelled.message, contains('unchanged'));
    });
  });
}
