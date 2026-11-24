import 'package:edu237/core/models/teacher_availability.dart';
import 'package:edu237/core/services/teacher_availability_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/schedule/fake_schedule_services.dart';

AvailabilitySlot _slot(int weekday, int startH, int endH) => AvailabilitySlot(
      weekday: weekday,
      startMinute: startH * 60,
      endMinute: endH * 60,
    );

void main() {
  group('AvailabilitySlot / WeeklyAvailability', () {
    test('containsMinute treats the window as half-open', () {
      final s = _slot(DateTime.monday, 16, 20); // 4pm–8pm
      expect(s.containsMinute(16 * 60), isTrue);
      expect(s.containsMinute(19 * 60 + 59), isTrue);
      expect(s.containsMinute(20 * 60), isFalse); // end excluded
      expect(s.containsMinute(15 * 60), isFalse);
    });

    test('isAvailableAt / canFit respect weekday and window', () {
      final avail = WeeklyAvailability([_slot(DateTime.monday, 16, 20)]);
      // A Monday at 17:00.
      final mon17 = DateTime(2026, 8, 17, 17); // 2026-08-17 is a Monday
      expect(mon17.weekday, DateTime.monday);
      expect(avail.isAvailableAt(mon17), isTrue);
      expect(avail.canFit(mon17, 60), isTrue); // ends 18:00, inside 20:00
      expect(avail.canFit(DateTime(2026, 8, 17, 19, 30), 60), isFalse); // 20:30 > 20:00
      // Tuesday has no window.
      expect(avail.isAvailableAt(DateTime(2026, 8, 18, 17)), isFalse);
    });

    test('summary groups consecutive identical days', () {
      final avail = WeeklyAvailability([
        _slot(DateTime.monday, 16, 20),
        _slot(DateTime.tuesday, 16, 20),
        _slot(DateTime.wednesday, 16, 20),
        _slot(DateTime.thursday, 16, 20),
        _slot(DateTime.friday, 16, 20),
        _slot(DateTime.saturday, 9, 14),
      ]);
      final lines = availabilitySummaryLines(avail);
      expect(lines, [
        'Mon–Fri · 4:00 PM–8:00 PM',
        'Sat · 9:00 AM–2:00 PM',
      ]);
    });

    test('summary does not merge days with different windows', () {
      final avail = WeeklyAvailability([
        _slot(DateTime.monday, 16, 20),
        _slot(DateTime.tuesday, 15, 20),
      ]);
      final lines = availabilitySummaryLines(avail);
      expect(lines.length, 2);
    });

    test('formatMinuteOfDay renders a 12-hour clock', () {
      expect(formatMinuteOfDay(0), '12:00 AM');
      expect(formatMinuteOfDay(960), '4:00 PM');
      expect(formatMinuteOfDay(9 * 60 + 30), '9:30 AM');
      expect(formatMinuteOfDay(12 * 60), '12:00 PM');
    });
  });

  group('TeacherAvailabilityService contract (fake)', () {
    test('save then read returns the same windows', () async {
      final store = <String, List<AvailabilitySlot>>{};
      final teacher =
          FakeTeacherAvailabilityService(userId: 'teacher-A', store: store);

      final saved = await teacher.saveMyAvailability([
        _slot(DateTime.monday, 16, 20),
        _slot(DateTime.saturday, 9, 14),
      ]);
      expect(saved, isA<AvailabilitySuccess>());

      final read = await teacher.fetchMyAvailability() as AvailabilitySuccess;
      expect(read.availability.slots.length, 2);
      expect(read.availability.forWeekday(DateTime.monday)!.startMinute, 960);
    });

    test('save replaces the whole week (removed days become unavailable)',
        () async {
      final store = <String, List<AvailabilitySlot>>{};
      final teacher =
          FakeTeacherAvailabilityService(userId: 'teacher-A', store: store);

      await teacher.saveMyAvailability([
        _slot(DateTime.monday, 16, 20),
        _slot(DateTime.tuesday, 16, 20),
      ]);
      await teacher.saveMyAvailability([_slot(DateTime.monday, 16, 20)]);

      final read = await teacher.fetchMyAvailability() as AvailabilitySuccess;
      expect(read.availability.slots.length, 1);
      expect(read.availability.forWeekday(DateTime.tuesday), isNull);
    });

    test('an invalid window (end <= start) is rejected', () async {
      final teacher = FakeTeacherAvailabilityService(userId: 'teacher-A');
      final result = await teacher.saveMyAvailability([
        const AvailabilitySlot(
            weekday: DateTime.monday, startMinute: 1200, endMinute: 1200),
      ]);
      expect(result, isA<AvailabilityFailure>());
    });

    test('one teacher cannot see another\'s availability as their own',
        () async {
      final store = <String, List<AvailabilitySlot>>{};
      final a = FakeTeacherAvailabilityService(userId: 'teacher-A', store: store);
      final b = FakeTeacherAvailabilityService(userId: 'teacher-B', store: store);

      await a.saveMyAvailability([_slot(DateTime.monday, 16, 20)]);

      final bMine = await b.fetchMyAvailability() as AvailabilitySuccess;
      expect(bMine.availability.isEmpty, isTrue);

      // But B (like any authenticated user) can READ A's public availability.
      final aPublic =
          await b.fetchAvailabilityFor('teacher-A') as AvailabilitySuccess;
      expect(aPublic.availability.slots.length, 1);
    });
  });
}
