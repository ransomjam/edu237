import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:edu237/core/models/teacher_profile.dart';
import 'package:edu237/shared/widgets/app_avatar.dart';
import 'package:edu237/shared/widgets/greeting_header.dart';

void main() {
  group('AppAvatar.initialsFor', () {
    test('single name → up to two letters', () {
      expect(AppAvatar.initialsFor('Grace'), 'GR');
      expect(AppAvatar.initialsFor('A'), 'A');
    });
    test('multiple names → first + last initial', () {
      expect(AppAvatar.initialsFor('Jam Ransom'), 'JR');
      expect(AppAvatar.initialsFor('Marie Claire Nkeng'), 'MN');
    });
    test('blank → placeholder', () {
      expect(AppAvatar.initialsFor('   '), '?');
    });
    test('is deterministic', () {
      expect(AppAvatar.initialsFor('Daniel'), AppAvatar.initialsFor('Daniel'));
    });
  });

  group('GreetingHeader.greetingForHour', () {
    test('maps hours to greetings', () {
      expect(GreetingHeader.greetingForHour(8), 'Good morning');
      expect(GreetingHeader.greetingForHour(13), 'Good afternoon');
      expect(GreetingHeader.greetingForHour(20), 'Good evening');
    });
  });

  group('TeacherProfile location', () {
    TeacherProfile make({String? city, String? area}) => TeacherProfile(
          id: 't1',
          userId: 'u1',
          displayName: 'Teacher A',
          city: city,
          area: area,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('locationLabel combines area and city', () {
      expect(make(city: 'Bamenda', area: 'Nkwen').locationLabel,
          'Nkwen, Bamenda');
    });
    test('locationLabel falls back to whichever is present', () {
      expect(make(city: 'Bamenda').locationLabel, 'Bamenda');
      expect(make(area: 'Nkwen').locationLabel, 'Nkwen');
      expect(make().locationLabel, isNull);
    });
    test('fromMap parses city/area and tolerates their absence', () {
      final withLoc = TeacherProfile.fromMap({
        'id': 't1',
        'user_id': 'u1',
        'display_name': 'Teacher A',
        'city': 'Bamenda',
        'area': 'Nkwen',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
      expect(withLoc.city, 'Bamenda');
      expect(withLoc.area, 'Nkwen');

      final legacy = TeacherProfile.fromMap({
        'id': 't2',
        'user_id': 'u2',
        'display_name': 'Teacher B',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
      expect(legacy.city, isNull);
      expect(legacy.area, isNull);
      expect(legacy.locationLabel, isNull);
    });
    test('toWriteFields includes trimmed city/area (or null when blank)', () {
      final fields = make(city: '  Bamenda ', area: '').toWriteFields();
      expect(fields['city'], 'Bamenda');
      expect(fields['area'], isNull);
    });
    test('fromMap parses hourly_rate or defaults to 5000', () {
      final custom = TeacherProfile.fromMap({
        'id': 't1',
        'user_id': 'u1',
        'display_name': 'Teacher A',
        'hourly_rate': 6500,
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
      expect(custom.hourlyRate, 6500);

      final fallback = TeacherProfile.fromMap({
        'id': 't2',
        'user_id': 'u2',
        'display_name': 'Teacher B',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
      expect(fallback.hourlyRate, 5000);
    });
  });

  group('AppAvatar icons', () {
    testWidgets('renders child icon for AvatarKind.child', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: AppAvatar(name: 'Daniel', kind: AvatarKind.child),
        ),
      );
      expect(find.byIcon(Icons.face_6_rounded), findsOneWidget);
    });

    testWidgets('renders parent icon for AvatarKind.parent', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: AppAvatar(name: 'Parent Name', kind: AvatarKind.parent),
        ),
      );
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    });

    testWidgets('renders teacher icon for AvatarKind.teacher', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: AppAvatar(name: 'Teacher Name', kind: AvatarKind.teacher),
        ),
      );
      expect(find.byIcon(Icons.school_rounded), findsOneWidget);
    });
  });
}
