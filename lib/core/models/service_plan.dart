import '../utils/money.dart';

/// Where the teacher stands with the Camiva Teacher Service Plan.
///
/// The plan is anchored to the teacher's FIRST tutoring earnings, never to
/// signup: a teacher who has not earned owes nothing, and the state says so.
enum ServicePlanState {
  /// No tutoring earnings yet. Nothing is owed.
  notStarted('not_started'),

  /// Inside the first month of tutoring earnings. Nothing is owed yet.
  firstMonth('first_month'),

  /// The first month is complete and the plan is payable.
  due('due'),

  /// A plan payment is with the provider.
  pending('pending'),

  /// Paid, and the current period is covered.
  active('active'),

  /// Past due, still inside the grace period.
  overdue('overdue'),

  /// Past due beyond grace — no new Camiva relationships.
  suspended('suspended');

  const ServicePlanState(this.value);
  final String value;

  static ServicePlanState fromString(String? value) =>
      ServicePlanState.values.firstWhere(
        (s) => s.value == value,
        orElse: () => ServicePlanState.notStarted,
      );

  bool get isPayable =>
      this == ServicePlanState.due ||
      this == ServicePlanState.overdue ||
      this == ServicePlanState.suspended;

  /// Whether the teacher may take on new Camiva relationships. Teaching already
  /// underway is never stopped by the plan.
  bool get canAcceptNewWork => this != ServicePlanState.suspended;

  String get label => switch (this) {
        ServicePlanState.notStarted => 'Not started',
        ServicePlanState.firstMonth => 'First month in progress',
        ServicePlanState.due => 'Service plan due',
        ServicePlanState.pending => 'Payment processing',
        ServicePlanState.active => 'Active',
        ServicePlanState.overdue => 'Service plan overdue',
        ServicePlanState.suspended => 'Suspended',
      };
}

/// The teacher's service plan, derived server-side from the ledger.
class TeacherServicePlan {
  const TeacherServicePlan({
    required this.state,
    required this.amount,
    required this.currency,
    this.firstEarnedAt,
    this.dueOn,
    this.graceEndsOn,
    this.paidUntil,
  });

  final ServicePlanState state;

  /// The flat monthly amount. Configurable server-side; currently 3,000 FCFA.
  final int? amount;
  final String currency;

  /// When the teacher first received tutoring money — the anchor for the plan.
  final DateTime? firstEarnedAt;

  final DateTime? dueOn;
  final DateTime? graceEndsOn;
  final DateTime? paidUntil;

  static const none = TeacherServicePlan(
    state: ServicePlanState.notStarted,
    amount: null,
    currency: 'XAF',
  );

  String get formattedAmount =>
      amount == null ? '—' : formatMoney(amount!, currency);

  /// What the teacher should read on the plan card. Never says "free": the
  /// first month is fully paid tutoring — Camiva simply does not charge the
  /// plan yet.
  String get message => switch (state) {
        ServicePlanState.notStarted =>
          'Your service plan starts after your first month of tutoring.',
        ServicePlanState.firstMonth =>
          'Your first month of tutoring is in progress. Your service plan '
              'starts after it.',
        ServicePlanState.due =>
          'Your first month of tutoring is complete. Keep your account active '
              'with your Camiva Teacher Service Plan.',
        ServicePlanState.pending =>
          'We are confirming your payment. This updates by itself.',
        ServicePlanState.active =>
          'Your Camiva Teacher Service Plan is active.',
        ServicePlanState.overdue =>
          'Your service plan is overdue. Pay to keep your account active.',
        ServicePlanState.suspended =>
          'Your account is suspended for new students. Your current students '
              'are not affected — pay to become active again.',
      };

  factory TeacherServicePlan.fromMap(Map<String, dynamic> map) {
    DateTime? parse(String key) {
      final value = map[key] as String?;
      return value == null ? null : DateTime.parse(value);
    }

    return TeacherServicePlan(
      state: ServicePlanState.fromString(map['state'] as String?),
      amount: (map['amount'] as num?)?.toInt(),
      currency: (map['currency'] as String?) ?? 'XAF',
      firstEarnedAt: parse('first_earned_at'),
      dueOn: parse('due_on'),
      graceEndsOn: parse('grace_ends_on'),
      paidUntil: parse('paid_until'),
    );
  }
}

/// The commercial terms a teacher agrees to before accepting a request.
///
/// The text is stored with the acceptance, so a later wording change cannot
/// rewrite what someone actually agreed to.
abstract final class TeacherTerms {
  static const String version = '2026-08-19';

  /// [amount] is the plan price quoted at the time, in FCFA.
  static List<String> points(String amount) => [
        'Tutoring payments for this Camiva relationship are managed through '
            'Camiva.',
        'You receive your tutoring earnings through the agreed Camiva process.',
        'Your first month has no Teacher Service Plan charge.',
        'After your first month of tutoring earnings, an Camiva Teacher '
            'Service Plan of $amount/month is required to remain an active '
            'teacher on the platform.',
        'Camiva provides payment records, reminders and relationship support '
            'as part of the service.',
      ];

  static String text(String amount) =>
      'Camiva Teacher Terms\n\nBy accepting this tutoring request:\n'
      '${points(amount).map((p) => '- $p').join('\n')}';
}
