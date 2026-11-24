import '../../core/models/tutoring_agreement.dart';

/// What a teacher has typed into the tutoring form but not yet sent.
///
/// The form used to lose everything the moment the teacher navigated away — to
/// check the child's details, or by pressing back — and they had to start over.
/// Drafts are kept here, keyed by relationship, so coming back restores exactly
/// what they had.
///
/// In memory only, and deliberately so: a draft is not an agreement. It is
/// dropped when the proposal is sent, and it does not survive the app closing —
/// nothing in it has been promised to anyone.
class TutoringDraft {
  const TutoringDraft({
    required this.startDate,
    required this.frequency,
    required this.customLessons,
    required this.lessonMinutes,
    required this.priceText,
    required this.priceUnit,
    required this.mode,
    required this.area,
    required this.paymentMethod,
    required this.paymentFrequency,
  });

  final DateTime startDate;
  final LessonFrequency frequency;
  final int customLessons;
  final int lessonMinutes;
  final String priceText;
  final PriceUnit priceUnit;
  final TeachingModeChoice mode;
  final String area;
  final AgreementPaymentMethod paymentMethod;
  final PaymentFrequency paymentFrequency;
}

/// Holds in-progress tutoring forms for the life of the app session.
abstract final class TutoringDraftStore {
  static final Map<String, TutoringDraft> _drafts = {};

  static TutoringDraft? read(String relationshipId) => _drafts[relationshipId];

  static void save(String relationshipId, TutoringDraft draft) {
    _drafts[relationshipId] = draft;
  }

  /// Called once the proposal is actually sent — the draft has become an
  /// agreement and should not linger.
  static void clear(String relationshipId) => _drafts.remove(relationshipId);

  /// Test helper.
  static void reset() => _drafts.clear();
}
