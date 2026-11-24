import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/service_plan.dart';
import '../models/teacher_verification.dart';
import '../models/tutoring_agreement.dart';
import 'payment_errors.dart';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

sealed class TutoringResult {
  const TutoringResult();
}

final class VerificationSuccess extends TutoringResult {
  const VerificationSuccess(this.verification);
  final TeacherVerification verification;
}

final class AgreementSuccess extends TutoringResult {
  const AgreementSuccess(this.agreement);

  /// Null when no live arrangement exists for the relationship.
  final TutoringAgreement? agreement;
}

final class ExpectedPaymentSuccess extends TutoringResult {
  const ExpectedPaymentSuccess(this.expected);
  final ExpectedPayment? expected;
}

final class ServicePlanSuccess extends TutoringResult {
  const ServicePlanSuccess(this.plan);
  final TeacherServicePlan plan;
}

final class TermsAcceptedSuccess extends TutoringResult {
  const TermsAcceptedSuccess();
}

final class TutoringFailure extends TutoringResult {
  const TutoringFailure(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Verification and tutoring arrangements — the two steps between a teacher
/// accepting a request and the relationship going live.
///
/// The order this interface exists to support:
///   accept → verify → propose → parent confirms → Platform Charge → active
///
/// Two rules are enforced by the server, not here: a teacher cannot propose
/// before being verified, and the Platform Charge cannot be created before the
/// parent confirms.
abstract class TutoringService {
  /// The signed-in teacher's own verification record.
  Future<TutoringResult> fetchMyVerification();

  /// Submits identity and qualification documents for review. This moves the
  /// teacher to "pending" — it never makes them verified.
  Future<TutoringResult> submitVerification({
    required String identityDocPath,
    required IdentityDocType identityDocType,
    required String qualificationDocPath,
    String? qualificationTitle,
  });

  /// Uploads a document to the private verification bucket and returns its
  /// storage path.
  Future<String?> uploadVerificationDoc({
    required String fileName,
    required List<int> bytes,
    required String contentType,
  });

  /// The live arrangement for a relationship, if any.
  Future<TutoringResult> fetchAgreement(String relationshipId);

  /// Teacher proposes the tutoring terms.
  Future<TutoringResult> proposeAgreement({
    required String relationshipId,
    required String subject,
    required DateTime startDate,
    required LessonFrequency frequency,
    required int lessonsPerWeek,
    required int lessonMinutes,
    required int price,
    required PriceUnit priceUnit,
    required TeachingModeChoice teachingMode,
    String? locationArea,
    AgreementPaymentMethod paymentMethod = AgreementPaymentMethod.edu237,
    PaymentFrequency paymentFrequency = PaymentFrequency.perMonth,
  });

  /// Parent confirms the arrangement. This is what makes the teacher's Platform
  /// Charge due — never before.
  Future<TutoringResult> confirmAgreement(String agreementId);

  /// Parent declines, optionally saying why.
  Future<TutoringResult> declineAgreement({
    required String agreementId,
    String? reason,
  });

  /// What the parent is expected to pay, and when.
  Future<TutoringResult> fetchExpectedPayment(String agreementId);

  /// The teacher's Camiva Teacher Service Plan state. Anchored to their first
  /// tutoring earnings — a teacher who has not earned owes nothing.
  Future<TutoringResult> fetchServicePlan();

  /// Records that the teacher agreed to the Camiva terms, with the exact text
  /// they were shown. Called at the moment they accept a request.
  Future<TutoringResult> acceptTerms({
    required String termsText,
    String? requestId,
  });
}

// ---------------------------------------------------------------------------
// Real implementation backed by Supabase
// ---------------------------------------------------------------------------

class SupabaseTutoringService implements TutoringService {
  SupabaseTutoringService(this._client);

  final SupabaseClient _client;

  static const _bucket = 'verification-docs';

  /// Reads the single row a composite-returning function produces.
  ///
  /// Two shapes have to be handled, and both bite:
  ///
  ///   * PostgREST returns a composite as either a JSON object or a
  ///     one-element list, depending on the function.
  ///   * A SQL function returning a composite that matched NOTHING does not
  ///     return null - it returns a row with every field null. Casting that
  ///     row's id to String throws a bare type error, which the UI can only
  ///     report as "something went wrong".
  ///
  /// An all-null row means "no row", and is reported as such.
  static Map<String, dynamic>? _row(dynamic value) {
    Map<String, dynamic>? map;
    if (value is Map) {
      map = Map<String, dynamic>.from(value);
    } else if (value is List && value.isNotEmpty && value.first is Map) {
      map = Map<String, dynamic>.from(value.first as Map);
    }
    if (map == null || map.isEmpty) return null;
    if (map.values.every((v) => v == null)) return null;
    return map;
  }

  @override
  Future<TutoringResult> fetchMyVerification() async {
    final user = _client.auth.currentUser;
    if (user == null) return const TutoringFailure('Please sign in again.');
    try {
      final row = await _client
          .from('teacher_verifications')
          .select()
          .eq('teacher_id', user.id)
          .maybeSingle();
      if (row == null) {
        return const VerificationSuccess(TeacherVerification.none);
      }
      return VerificationSuccess(TeacherVerification.fromMap(row));
    } catch (e) {
      return TutoringFailure(friendlyPaymentError(e));
    }
  }

  @override
  Future<String?> uploadVerificationDoc({
    required String fileName,
    required List<int> bytes,
    required String contentType,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    // The path starts with the teacher's own id, which is what the storage
    // policy checks — nobody can write into another teacher's folder.
    final path = '${user.id}/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    try {
      await _client.storage.from(_bucket).uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
      return path;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<TutoringResult> submitVerification({
    required String identityDocPath,
    required IdentityDocType identityDocType,
    required String qualificationDocPath,
    String? qualificationTitle,
  }) async {
    try {
      final row = await _client.rpc('submit_teacher_verification', params: {
        'p_identity_doc_path': identityDocPath,
        'p_identity_doc_type': identityDocType.value,
        'p_qualification_doc_path': qualificationDocPath,
        'p_qualification_title': qualificationTitle,
      });
      final map = _row(row);
      if (map == null) {
        return const TutoringFailure('Could not send your documents.');
      }
      return VerificationSuccess(TeacherVerification.fromMap(map));
    } catch (e) {
      return TutoringFailure(friendlyPaymentError(e));
    }
  }

  @override
  Future<TutoringResult> fetchAgreement(String relationshipId) async {
    try {
      final row = await _client.rpc(
        'relationship_agreement',
        params: {'p_relationship_id': relationshipId},
      );
      final map = _row(row);
      if (map == null) return const AgreementSuccess(null);
      return AgreementSuccess(TutoringAgreement.fromMap(map));
    } catch (e) {
      return TutoringFailure(friendlyPaymentError(e));
    }
  }

  @override
  Future<TutoringResult> proposeAgreement({
    required String relationshipId,
    required String subject,
    required DateTime startDate,
    required LessonFrequency frequency,
    required int lessonsPerWeek,
    required int lessonMinutes,
    required int price,
    required PriceUnit priceUnit,
    required TeachingModeChoice teachingMode,
    String? locationArea,
    AgreementPaymentMethod paymentMethod = AgreementPaymentMethod.edu237,
    PaymentFrequency paymentFrequency = PaymentFrequency.perMonth,
  }) async {
    try {
      final row = await _client.rpc('propose_tutoring_agreement', params: {
        'p_relationship_id': relationshipId,
        'p_subject': subject,
        'p_start_date': _date(startDate),
        'p_frequency': frequency.value,
        'p_lessons_per_week': lessonsPerWeek,
        'p_lesson_minutes': lessonMinutes,
        'p_price': price,
        'p_price_unit': priceUnit.value,
        'p_teaching_mode': teachingMode.value,
        'p_location_area': locationArea,
        'p_payment_method': paymentMethod.value,
        'p_payment_frequency': paymentFrequency.value,
      });
      final map = _row(row);
      if (map == null) {
        return const TutoringFailure('Could not create the arrangement.');
      }
      return AgreementSuccess(TutoringAgreement.fromMap(map));
    } catch (e) {
      return TutoringFailure(friendlyPaymentError(e));
    }
  }

  @override
  Future<TutoringResult> confirmAgreement(String agreementId) async {
    try {
      final row = await _client.rpc(
        'confirm_tutoring_agreement',
        params: {'p_agreement_id': agreementId},
      );
      final map = _row(row);
      if (map == null) {
        return const TutoringFailure('Could not confirm the arrangement.');
      }
      return AgreementSuccess(TutoringAgreement.fromMap(map));
    } catch (e) {
      return TutoringFailure(friendlyPaymentError(e));
    }
  }

  @override
  Future<TutoringResult> declineAgreement({
    required String agreementId,
    String? reason,
  }) async {
    try {
      final row = await _client.rpc('decline_tutoring_agreement', params: {
        'p_agreement_id': agreementId,
        'p_reason': reason,
      });
      final map = _row(row);
      if (map == null) {
        return const TutoringFailure('Could not decline the arrangement.');
      }
      return AgreementSuccess(TutoringAgreement.fromMap(map));
    } catch (e) {
      return TutoringFailure(friendlyPaymentError(e));
    }
  }

  @override
  Future<TutoringResult> fetchExpectedPayment(String agreementId) async {
    try {
      final rows = await _client.rpc(
        'agreement_expected_payment',
        params: {'p_agreement_id': agreementId},
      );
      final list = (rows as List<dynamic>?) ?? const [];
      if (list.isEmpty) return const ExpectedPaymentSuccess(null);
      return ExpectedPaymentSuccess(
        ExpectedPayment.fromMap(Map<String, dynamic>.from(list.first as Map)),
      );
    } catch (e) {
      return TutoringFailure(friendlyPaymentError(e));
    }
  }

  @override
  Future<TutoringResult> fetchServicePlan() async {
    try {
      final rows = await _client.rpc('teacher_service_status');
      final list = (rows as List<dynamic>?) ?? const [];
      if (list.isEmpty) return const ServicePlanSuccess(TeacherServicePlan.none);
      return ServicePlanSuccess(
        TeacherServicePlan.fromMap(Map<String, dynamic>.from(list.first as Map)),
      );
    } catch (e) {
      return TutoringFailure(friendlyPaymentError(e));
    }
  }

  @override
  Future<TutoringResult> acceptTerms({
    required String termsText,
    String? requestId,
  }) async {
    try {
      await _client.rpc('accept_teacher_terms', params: {
        'p_terms_version': TeacherTerms.version,
        'p_terms_text': termsText,
        'p_request_id': requestId,
      });
      return const TermsAcceptedSuccess();
    } catch (e) {
      return TutoringFailure(friendlyPaymentError(e));
    }
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Stub used when Supabase credentials are not configured
// ---------------------------------------------------------------------------

class UnconfiguredTutoringService implements TutoringService {
  const UnconfiguredTutoringService();

  static const _message =
      'The app is not connected to a backend. Please contact support.';

  /// Without a backend there is no way to establish verification, so the answer
  /// is "not verified".
  @override
  Future<TutoringResult> fetchMyVerification() async =>
      const VerificationSuccess(TeacherVerification.none);

  @override
  Future<String?> uploadVerificationDoc({
    required String fileName,
    required List<int> bytes,
    required String contentType,
  }) async =>
      null;

  @override
  Future<TutoringResult> submitVerification({
    required String identityDocPath,
    required IdentityDocType identityDocType,
    required String qualificationDocPath,
    String? qualificationTitle,
  }) async =>
      const TutoringFailure(_message);

  @override
  Future<TutoringResult> fetchAgreement(String relationshipId) async =>
      const AgreementSuccess(null);

  @override
  Future<TutoringResult> proposeAgreement({
    required String relationshipId,
    required String subject,
    required DateTime startDate,
    required LessonFrequency frequency,
    required int lessonsPerWeek,
    required int lessonMinutes,
    required int price,
    required PriceUnit priceUnit,
    required TeachingModeChoice teachingMode,
    String? locationArea,
    AgreementPaymentMethod paymentMethod = AgreementPaymentMethod.edu237,
    PaymentFrequency paymentFrequency = PaymentFrequency.perMonth,
  }) async =>
      const TutoringFailure(_message);

  @override
  Future<TutoringResult> confirmAgreement(String agreementId) async =>
      const TutoringFailure(_message);

  @override
  Future<TutoringResult> declineAgreement({
    required String agreementId,
    String? reason,
  }) async =>
      const TutoringFailure(_message);

  @override
  Future<TutoringResult> fetchExpectedPayment(String agreementId) async =>
      const ExpectedPaymentSuccess(null);

  @override
  Future<TutoringResult> fetchServicePlan() async =>
      const ServicePlanSuccess(TeacherServicePlan.none);

  @override
  Future<TutoringResult> acceptTerms({
    required String termsText,
    String? requestId,
  }) async =>
      const TutoringFailure(_message);
}

// ---------------------------------------------------------------------------
// Widget tree injection
// ---------------------------------------------------------------------------

class TutoringServiceScope extends InheritedWidget {
  const TutoringServiceScope({
    super.key,
    required this.tutoringService,
    required super.child,
  });

  final TutoringService tutoringService;

  static TutoringService of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<TutoringServiceScope>();
    assert(scope != null, 'No TutoringServiceScope found in widget tree.');
    return scope!.tutoringService;
  }

  static TutoringService? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TutoringServiceScope>()
      ?.tutoringService;

  @override
  bool updateShouldNotify(TutoringServiceScope oldWidget) =>
      tutoringService != oldWidget.tutoringService;
}
