import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns a Supabase / Edge Function error into something a user can act on,
/// without leaking database or provider detail.
///
/// The important case this handles is a backend that has not been set up yet.
/// A missing table or function used to arrive as the generic "Something went
/// wrong", which is indistinguishable from a network blip and leaves nothing to
/// act on. It now says plainly that payments are not set up, because that is a
/// deployment step, not a user error.
///
/// In debug builds the underlying message is appended so the cause is visible
/// while developing; release builds never show it.
String friendlyPaymentError(Object error) {
  final raw = _rawMessage(error);

  // The user-facing text is deliberately vague, which makes a real failure
  // impossible to diagnose from the app alone. In debug the underlying cause
  // goes to the console instead, where it helps and cannot leak.
  if (kDebugMode) {
    debugPrint('[camiva] payment error: $raw');
  }

  final lower = raw.toLowerCase();
  final code = _code(error);

  // The two halves fail differently and are fixed differently, so they are
  // never reported with the same sentence.
  if (error is FunctionException && error.status == 404) {
    return _withDetail(
      'The payment service is not deployed yet. '
      'Deploy the payment functions to this project.',
      raw,
    );
  }

  if (_isBackendMissing(code, lower)) {
    return _withDetail(
      'Payments are not set up in the database yet. '
      'Apply the payment migrations to this project.',
      raw,
    );
  }

  if (lower.contains('network') ||
      lower.contains('connection') ||
      lower.contains('socket') ||
      lower.contains('failed host lookup')) {
    return 'No connection. Please check your internet.';
  }

  if (code == '42501' ||
      lower.contains('permission denied') ||
      lower.contains('row-level security') ||
      lower.contains('rls') ||
      lower.contains('policy') ||
      lower.contains('jwt')) {
    return _withDetail('Permission denied. Please sign in again.', raw);
  }

  return safePaymentMessage(raw);
}

/// Whether the failure means "this part of the backend does not exist here".
///
///   42P01 undefined_table        42883 undefined_function
///   PGRST202 function not found  PGRST205 table not found (schema cache)
///   404 from a function that has not been deployed
bool _isBackendMissing(String? code, String lowerMessage) {
  const codes = {'42p01', '42883', 'pgrst202', 'pgrst205'};
  if (code != null && codes.contains(code.toLowerCase())) return true;
  return lowerMessage.contains('does not exist') ||
      lowerMessage.contains('schema cache') ||
      lowerMessage.contains('not found in the schema') ||
      lowerMessage.contains('function not found');
}

/// Messages our own backend raises deliberately are safe to show as-is;
/// anything else becomes a single generic line.
String safePaymentMessage(String raw) {
  const safePhrases = [
    // Refusals the server raises on purpose. These tell the user exactly what
    // to do, so hiding them behind "something went wrong" is worse than useless.
    'verification',
    'already',
    'first month',
    'service plan',
    'only the parent',
    'only the teacher',
    'not authorised',
    'not authorized',
    'smallest payment',
    'more than the balance',
    'not configured',
    'not set up',
    'no service fee',
    'not accepted',
    'not required',
    'not active',
    'rate yet',
    'relationship',
    'available earnings',
    'withdrawal in progress',
    'payout number',
    'minimum withdrawal',
    'could not be started',
    'valid amount',
  ];
  final lower = raw.toLowerCase();
  if (safePhrases.any(lower.contains)) return raw;
  return genericPaymentError;
}

const String genericPaymentError = 'Something went wrong. Please try again.';

String _withDetail(String message, String raw) {
  if (!kDebugMode || raw.isEmpty || raw == genericPaymentError) return message;
  return '$message\n\n($raw)';
}

String? _code(Object error) {
  if (error is PostgrestException) return error.code;
  return null;
}

String _rawMessage(Object error) {
  if (error is PostgrestException) {
    return [error.message, error.details, error.hint]
        .whereType<Object>()
        .map((part) => part.toString())
        .where((part) => part.isNotEmpty && part != 'null')
        .join(' · ');
  }
  if (error is FunctionException) {
    final details = error.details;
    if (details is Map && details['error'] != null) {
      return details['error'].toString();
    }
    // A function that was never deployed answers 404.
    if (error.status == 404) {
      return 'Edge Function not found (404)';
    }
    return error.reasonPhrase ?? 'Edge Function error (${error.status})';
  }
  return error.toString();
}
