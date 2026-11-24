import 'package:edu237/core/models/tutoring_agreement.dart';
import 'package:edu237/core/services/payment_service.dart';
import 'package:edu237/core/services/tutoring_service.dart';
import 'package:edu237/features/tutoring/contract_view.dart';
import 'package:edu237/features/tutoring/setup_tutoring_screen.dart';
import 'package:edu237/features/tutoring/tutoring_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../payments/fake_payment_services.dart';
import 'fake_tutoring_service.dart';

Future<void> _pumpSetup(
  WidgetTester tester,
  FakeTutoringService service,
) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    TutoringServiceScope(
      tutoringService: service,
      child: PaymentServiceScope(
        paymentService: FakePaymentService(),
        child: const MaterialApp(
          home: SetupTutoringScreen(
            args: SetupTutoringArgs(
              relationshipId: 'rel-1',
              childName: 'Daniel',
              subject: 'Mathematics',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(TutoringDraftStore.reset);
  tearDown(TutoringDraftStore.reset);

  group('Tutoring form draft', () {
    testWidgets('what was typed survives leaving and coming back',
        (tester) async {
      final service = FakeTutoringService();
      await _pumpSetup(tester, service);

      await tester.enterText(find.byKey(const Key('price_field')), '7500');
      await tester.tap(find.byKey(const Key('duration_90')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('price_unit_per_week')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('area_field')), 'Bastos');
      await tester.pump();

      // Leave the screen entirely, then come back to a fresh instance.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await _pumpSetup(tester, service);

      final price = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('price_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(price.controller?.text, '7500');

      final area = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('area_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(area.controller?.text, 'Bastos');
    });

    testWidgets('sending clears the draft — it is an agreement now',
        (tester) async {
      final service = FakeTutoringService(
        verification: fakeAgreementVerification(),
      );
      await _pumpSetup(tester, service);

      await tester.enterText(find.byKey(const Key('price_field')), '5000');
      await tester.ensureVisible(find.byKey(const Key('send_proposal_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send_proposal_button')));
      await tester.pumpAndSettle();

      expect(service.proposals, hasLength(1));
      expect(TutoringDraftStore.read('rel-1'), isNull);
    });

    test('drafts are kept per relationship', () {
      final draft = TutoringDraft(
        startDate: DateTime(2026, 9, 1),
        frequency: LessonFrequency.thriceWeekly,
        customLessons: 3,
        lessonMinutes: 45,
        priceText: '3000',
        priceUnit: PriceUnit.perLesson,
        mode: TeachingModeChoice.online,
        area: '',
        paymentMethod: AgreementPaymentMethod.edu237,
        paymentFrequency: PaymentFrequency.perWeek,
      );
      TutoringDraftStore.save('rel-1', draft);

      expect(TutoringDraftStore.read('rel-1')?.priceText, '3000');
      // Another arrangement is untouched.
      expect(TutoringDraftStore.read('rel-2'), isNull);
    });
  });

  group('ContractView', () {
    testWidgets('reads back every agreed term', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContractView(
              agreement: fakeAgreement(),
              childName: 'Daniel',
              teacherName: 'Jam Ransom',
              parentName: 'Mrs Ayuk',
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('contract_view')), findsOneWidget);
      expect(find.text('Daniel'), findsOneWidget);
      expect(find.text('Jam Ransom'), findsOneWidget);
      expect(find.text('2 lessons/week'), findsOneWidget);
      expect(find.text('5,000 FCFA / lesson'), findsOneWidget);
      expect(find.text('In person · Bastos'), findsOneWidget);
      expect(find.text('Camiva-managed'), findsOneWidget);
      expect(find.byKey(const Key('copy_contract_button')), findsOneWidget);
    });

    testWidgets('shows where the arrangement stands', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContractView(
              agreement: fakeAgreement(status: AgreementStatus.confirmed),
              childName: 'Daniel',
              teacherName: 'Jam Ransom',
              parentName: 'Mrs Ayuk',
            ),
          ),
        ),
      );

      // Confirmed is "Agreed", not "Active" - activation still has to happen.
      expect(find.text('Agreed'), findsOneWidget);
      expect(find.text('Active'), findsNothing);
    });

    test('the copyable text carries the whole arrangement', () {
      final view = ContractView(
        agreement: fakeAgreement(),
        childName: 'Daniel',
        teacherName: 'Jam Ransom',
        parentName: 'Mrs Ayuk',
      );

      expect(view.asText, contains('Student: Daniel'));
      expect(view.asText, contains('Teacher: Jam Ransom'));
      expect(view.asText, contains('Parent: Mrs Ayuk'));
      expect(view.asText, contains('5,000 FCFA / lesson'));
      expect(view.asText, contains('Payment: Camiva-managed'));
    });
  });

  group('ContactActions', () {
    testWidgets('renders nothing without a number', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ContactActions(phone: null, name: 'Jam Ransom'),
          ),
        ),
      );

      // Contact rules decide whether a number exists; this widget cannot be
      // used to work around them.
      expect(find.byKey(const Key('contact_actions')), findsNothing);
      expect(find.byKey(const Key('call_button')), findsNothing);
      expect(find.byKey(const Key('whatsapp_button')), findsNothing);
    });

    testWidgets('offers call and WhatsApp once a number is available',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ContactActions(phone: '670123456', name: 'Jam Ransom'),
          ),
        ),
      );

      expect(find.byKey(const Key('call_button')), findsOneWidget);
      expect(find.byKey(const Key('whatsapp_button')), findsOneWidget);
    });
  });
}
