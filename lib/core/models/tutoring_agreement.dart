import '../utils/money.dart';

/// How often lessons happen.
enum LessonFrequency {
  onceWeekly('once_weekly', 'Once a week', 1),
  twiceWeekly('twice_weekly', 'Twice a week', 2),
  thriceWeekly('thrice_weekly', '3 times a week', 3),
  custom('custom', 'Custom', 1);

  const LessonFrequency(this.value, this.label, this.lessonsPerWeek);

  final String value;
  final String label;

  /// The default lessons per week for this choice. 'custom' carries its own
  /// number on the agreement instead.
  final int lessonsPerWeek;

  static LessonFrequency fromString(String? value) =>
      LessonFrequency.values.firstWhere(
        (f) => f.value == value,
        orElse: () => LessonFrequency.onceWeekly,
      );
}

/// What the agreed price is measured in.
enum PriceUnit {
  perLesson('per_lesson', 'Per lesson'),
  perWeek('per_week', 'Per week'),
  perMonth('per_month', 'Per month');

  const PriceUnit(this.value, this.label);
  final String value;
  final String label;

  /// How the price reads next to an amount: "5,000 FCFA / lesson".
  String get suffix => switch (this) {
        PriceUnit.perLesson => '/ lesson',
        PriceUnit.perWeek => '/ week',
        PriceUnit.perMonth => '/ month',
      };

  static PriceUnit fromString(String? value) => PriceUnit.values.firstWhere(
        (u) => u.value == value,
        orElse: () => PriceUnit.perLesson,
      );
}

enum TeachingModeChoice {
  inPerson('in_person', 'In person'),
  online('online', 'Online');

  const TeachingModeChoice(this.value, this.label);
  final String value;
  final String label;

  static TeachingModeChoice fromString(String? value) =>
      TeachingModeChoice.values.firstWhere(
        (m) => m.value == value,
        orElse: () => TeachingModeChoice.inPerson,
      );
}

/// How the parent pays for the tutoring.
///
/// Camiva-managed is the normal option because it is the one that produces a
/// receipt, a payment history, reminders, teacher earnings history and a record
/// Camiva support can act on. A direct arrangement is a real choice, not a
/// forbidden one — it simply is not recorded as Camiva activity.
enum AgreementPaymentMethod {
  edu237('edu237', 'Camiva-managed'),
  direct('direct', 'Direct to teacher');

  const AgreementPaymentMethod(this.value, this.label);
  final String value;
  final String label;

  bool get isCamiva => this == AgreementPaymentMethod.edu237;

  static AgreementPaymentMethod fromString(String? value) =>
      AgreementPaymentMethod.values.firstWhere(
        (m) => m.value == value,
        orElse: () => AgreementPaymentMethod.edu237,
      );
}

enum PaymentFrequency {
  perLesson('per_lesson', 'Every lesson'),
  perWeek('per_week', 'Every week'),
  perMonth('per_month', 'Every month');

  const PaymentFrequency(this.value, this.label);
  final String value;
  final String label;

  static PaymentFrequency fromString(String? value) =>
      PaymentFrequency.values.firstWhere(
        (f) => f.value == value,
        orElse: () => PaymentFrequency.perMonth,
      );
}

/// Where a tutoring arrangement stands.
enum AgreementStatus {
  proposed,
  confirmed,
  declined,
  active,
  cancelled;

  static AgreementStatus fromString(String? value) => switch (value) {
        'proposed' => AgreementStatus.proposed,
        'confirmed' => AgreementStatus.confirmed,
        'declined' => AgreementStatus.declined,
        'active' => AgreementStatus.active,
        'cancelled' => AgreementStatus.cancelled,
        _ => throw FormatException('Unsupported agreement status: $value'),
      };

  String get value => name;

  /// The parent has agreed, but the relationship is not live until the teacher's
  /// Platform Charge is confirmed.
  bool get awaitingActivation => this == AgreementStatus.confirmed;

  bool get isLive => this == AgreementStatus.active;
}

/// The agreed terms of one tutoring arrangement.
///
/// This is the source of truth for what was agreed — structured fields rather
/// than free text, so both sides see the same thing and the expected payment
/// can be computed from it. Once proposed, the terms are frozen: the database
/// rejects any change to them.
class TutoringAgreement {
  const TutoringAgreement({
    required this.id,
    required this.relationshipId,
    required this.parentId,
    required this.teacherId,
    required this.studentId,
    required this.subject,
    required this.startDate,
    required this.frequency,
    required this.lessonsPerWeek,
    required this.lessonMinutes,
    required this.price,
    required this.priceUnit,
    required this.currency,
    required this.teachingMode,
    required this.paymentMethod,
    required this.paymentFrequency,
    required this.status,
    required this.proposedAt,
    this.locationArea,
    this.parentConfirmedAt,
    this.parentDeclinedAt,
    this.declineReason,
    this.teacherActivatedAt,
  });

  final String id;
  final String relationshipId;
  final String parentId;
  final String teacherId;
  final String studentId;

  final String subject;
  final DateTime startDate;
  final LessonFrequency frequency;
  final int lessonsPerWeek;
  final int lessonMinutes;

  final int price;
  final PriceUnit priceUnit;
  final String currency;

  final TeachingModeChoice teachingMode;

  /// An area, never a street address — Camiva does not ask for exact private
  /// residences.
  final String? locationArea;

  final AgreementPaymentMethod paymentMethod;
  final PaymentFrequency paymentFrequency;
  final AgreementStatus status;

  final DateTime proposedAt;
  final DateTime? parentConfirmedAt;
  final DateTime? parentDeclinedAt;
  final String? declineReason;
  final DateTime? teacherActivatedAt;

  String get formattedPrice => '${formatMoney(price, currency)} '
      '${priceUnit.suffix}';

  /// "2 lessons/week", the way a parent reads it.
  String get frequencyLabel =>
      lessonsPerWeek == 1 ? '1 lesson/week' : '$lessonsPerWeek lessons/week';

  String get durationLabel => switch (lessonMinutes) {
        30 => '30 min',
        45 => '45 min',
        60 => '1 hour',
        90 => '1.5 hours',
        _ => '${lessonMinutes ~/ 60} hours',
      };

  /// "In person · Bastos" or just "Online".
  String get modeLabel {
    final area = (locationArea ?? '').trim();
    if (teachingMode == TeachingModeChoice.online || area.isEmpty) {
      return teachingMode.label;
    }
    return '${teachingMode.label} · $area';
  }

  factory TutoringAgreement.fromMap(Map<String, dynamic> map) {
    DateTime? parse(String key) {
      final value = map[key] as String?;
      return value == null ? null : DateTime.parse(value);
    }

    return TutoringAgreement(
      id: map['id'] as String,
      relationshipId: map['relationship_id'] as String,
      parentId: map['parent_id'] as String,
      teacherId: map['teacher_id'] as String,
      studentId: map['student_id'] as String,
      subject: (map['subject'] as String?) ?? '',
      startDate: parse('start_date') ?? DateTime.now(),
      frequency: LessonFrequency.fromString(map['frequency'] as String?),
      lessonsPerWeek: (map['lessons_per_week'] as num?)?.toInt() ?? 1,
      lessonMinutes: (map['lesson_minutes'] as num?)?.toInt() ?? 60,
      price: (map['price'] as num?)?.toInt() ?? 0,
      priceUnit: PriceUnit.fromString(map['price_unit'] as String?),
      currency: (map['currency'] as String?) ?? 'XAF',
      teachingMode:
          TeachingModeChoice.fromString(map['teaching_mode'] as String?),
      locationArea: map['location_area'] as String?,
      paymentMethod:
          AgreementPaymentMethod.fromString(map['payment_method'] as String?),
      paymentFrequency:
          PaymentFrequency.fromString(map['payment_frequency'] as String?),
      status: AgreementStatus.fromString(map['status'] as String?),
      proposedAt: parse('proposed_at') ?? DateTime.now(),
      parentConfirmedAt: parse('parent_confirmed_at'),
      parentDeclinedAt: parse('parent_declined_at'),
      declineReason: map['decline_reason'] as String?,
      teacherActivatedAt: parse('teacher_activated_at'),
    );
  }
}

/// What the parent is expected to pay, and when.
///
/// Expected is not paid: nothing here means money arrived. Only a
/// provider-confirmed transaction does that.
class ExpectedPayment {
  const ExpectedPayment({
    required this.amount,
    required this.currency,
    required this.dueOn,
    required this.frequency,
    required this.isCamivaManaged,
  });

  final int amount;
  final String currency;
  final DateTime dueOn;
  final PaymentFrequency frequency;
  final bool isCamivaManaged;

  String get formattedAmount => formatMoney(amount, currency);

  factory ExpectedPayment.fromMap(Map<String, dynamic> map) => ExpectedPayment(
        amount: (map['amount'] as num?)?.toInt() ?? 0,
        currency: (map['currency'] as String?) ?? 'XAF',
        dueOn: DateTime.parse(map['due_on'] as String),
        frequency: PaymentFrequency.fromString(map['frequency'] as String?),
        isCamivaManaged: map['is_edu237'] == true,
      );
}
