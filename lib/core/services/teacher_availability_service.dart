import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/teacher_availability.dart';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

sealed class AvailabilityResult {
  const AvailabilityResult();
}

final class AvailabilitySuccess extends AvailabilityResult {
  const AvailabilitySuccess(this.availability);
  final WeeklyAvailability availability;
}

final class AvailabilityFailure extends AvailabilityResult {
  const AvailabilityFailure(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// All `teacher_availability` table operations go through this interface.
/// Screens must never call Supabase directly.
///
/// A teacher may read and replace their OWN weekly availability. Any
/// authenticated user may read a teacher's availability (it is part of the
/// public profile), enforced here and by row-level security.
abstract class TeacherAvailabilityService {
  /// The signed-in teacher's own weekly availability.
  Future<AvailabilityResult> fetchMyAvailability();

  /// Any teacher's public weekly availability, by their auth user id.
  Future<AvailabilityResult> fetchAvailabilityFor(String teacherId);

  /// Replaces the signed-in teacher's whole weekly availability with [slots].
  /// Days omitted from [slots] become "Unavailable".
  Future<AvailabilityResult> saveMyAvailability(List<AvailabilitySlot> slots);
}

// ---------------------------------------------------------------------------
// Supabase implementation
// ---------------------------------------------------------------------------

class SupabaseTeacherAvailabilityService implements TeacherAvailabilityService {
  SupabaseTeacherAvailabilityService(this._client);

  final SupabaseClient _client;

  @override
  Future<AvailabilityResult> fetchMyAvailability() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const AvailabilityFailure('Please sign in again.');
    }
    return fetchAvailabilityFor(user.id);
  }

  @override
  Future<AvailabilityResult> fetchAvailabilityFor(String teacherId) async {
    try {
      final rows = await _client
          .from('teacher_availability')
          .select()
          .eq('teacher_id', teacherId)
          .order('weekday', ascending: true);
      final list = (rows as List<dynamic>)
          .map((r) => AvailabilitySlot.fromMap(r as Map<String, dynamic>))
          .toList();
      return AvailabilitySuccess(WeeklyAvailability(list));
    } catch (e) {
      return AvailabilityFailure(_friendlyError(e));
    }
  }

  @override
  Future<AvailabilityResult> saveMyAvailability(
      List<AvailabilitySlot> slots) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const AvailabilityFailure('Please sign in again.');
    }

    // Validate windows before touching the database (defence-in-depth; the DB
    // enforces the same via CHECK constraints).
    for (final s in slots) {
      if (s.endMinute <= s.startMinute) {
        return const AvailabilityFailure(
            'Each day\'s end time must be after its start time.');
      }
    }

    try {
      // MVP replace-all: clear the teacher's rows, then insert the current set.
      // Postgres has no client transaction here, but the delete + insert is
      // scoped to the teacher's own rows and re-runnable.
      await _client
          .from('teacher_availability')
          .delete()
          .eq('teacher_id', user.id);

      if (slots.isNotEmpty) {
        await _client.from('teacher_availability').insert(
              slots.map((s) => s.toInsertMap(teacherId: user.id)).toList(),
            );
      }
      return AvailabilitySuccess(WeeklyAvailability(slots));
    } catch (e) {
      return AvailabilityFailure(_friendlyError(e));
    }
  }

  String _friendlyError(Object e) {
    debugPrint('TeacherAvailabilityService error: $e');
    if (e is PostgrestException) {
      if (e.code == '42P01' || e.message.contains('does not exist')) {
        return 'Table "teacher_availability" not found. Please run the SQL migration in Supabase.';
      }
      if (e.message.isNotEmpty) return e.message;
    }
    final message = e.toString().toLowerCase();
    if (message.contains('network') || message.contains('connection')) {
      return 'No connection. Please check your internet.';
    }
    if (message.contains('permission') ||
        message.contains('rls') ||
        message.contains('policy') ||
        message.contains('denied')) {
      return 'Permission denied. Please sign in again.';
    }
    return e.toString();
  }
}

// ---------------------------------------------------------------------------
// Unconfigured fallback
// ---------------------------------------------------------------------------

class UnconfiguredTeacherAvailabilityService
    implements TeacherAvailabilityService {
  const UnconfiguredTeacherAvailabilityService();

  static const _message =
      'The app is not connected to a backend. Please contact support.';

  @override
  Future<AvailabilityResult> fetchMyAvailability() async =>
      const AvailabilityFailure(_message);

  @override
  Future<AvailabilityResult> fetchAvailabilityFor(String teacherId) async =>
      const AvailabilityFailure(_message);

  @override
  Future<AvailabilityResult> saveMyAvailability(
          List<AvailabilitySlot> slots) async =>
      const AvailabilityFailure(_message);
}

// ---------------------------------------------------------------------------
// Widget tree injection
// ---------------------------------------------------------------------------

class TeacherAvailabilityServiceScope extends InheritedWidget {
  const TeacherAvailabilityServiceScope({
    super.key,
    required this.service,
    required super.child,
  });

  final TeacherAvailabilityService service;

  static TeacherAvailabilityService of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<TeacherAvailabilityServiceScope>();
    assert(scope != null,
        'No TeacherAvailabilityServiceScope found in widget tree.');
    return scope!.service;
  }

  @override
  bool updateShouldNotify(TeacherAvailabilityServiceScope oldWidget) =>
      service != oldWidget.service;
}
