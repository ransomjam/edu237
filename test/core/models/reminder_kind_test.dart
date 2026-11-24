import 'package:edu237/core/models/payment_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

/// One unrecognised kind used to throw, which failed the whole reminders fetch
/// — so a reader lost every reminder they had because the server sent one value
/// this build had not heard of. These tests exist so that cannot come back.
void main() {
  group('ReminderKind', () {
    test('every kind the server can send is understood', () {
      // Must match the payment_reminders_kind_check constraint.
      const serverKinds = [
        'payment_received',
        'payment_failed',
        'payment_due',
        'service_fee_due',
        'service_fee_overdue',
        'relationship_activated',
        'verification_update',
        'agreement_update',
        'withdrawal_update',
        'request_received',
        'request_answered',
        'lesson_scheduled',
      ];

      for (final kind in serverKinds) {
        final parsed = ReminderKind.fromString(kind);
        expect(parsed, isNot(ReminderKind.other),
            reason: '$kind falls through to "other"');
        expect(parsed.value, kind);
      }
    });

    test('an unknown kind is kept, not thrown away', () {
      // A reminder's title and body are already written for the reader, so an
      // unfamiliar kind is still worth showing.
      expect(ReminderKind.fromString('something_new'), ReminderKind.other);
      expect(ReminderKind.fromString(null), ReminderKind.other);
    });

    test('a list survives one unknown kind', () {
      final rows = [
        {'kind': 'payment_due'},
        {'kind': 'invented_later'},
        {'kind': 'payment_received'},
      ];

      final parsed =
          rows.map((r) => ReminderKind.fromString(r['kind'])).toList();

      expect(parsed, hasLength(3));
      expect(parsed.first, ReminderKind.paymentDue);
      expect(parsed.last, ReminderKind.paymentReceived);
    });
  });
}
