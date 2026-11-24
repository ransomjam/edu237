import 'package:edu237/core/models/student.dart';
import 'package:edu237/core/models/teacher_profile.dart';
import 'package:edu237/core/models/teaching_mode.dart';
import 'package:edu237/core/services/geo.dart';
import 'package:edu237/core/services/teacher_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

TeacherProfile _teacher(
  String name, {
  List<String> forms = const ['Form 4'],
  List<String> subjects = const ['Mathematics'],
  String? city,
  String? area,
  double? lat,
  double? lng,
  TeachingMode mode = TeachingMode.inPerson,
}) =>
    TeacherProfile(
      id: name,
      userId: 'u-$name',
      displayName: name,
      subjects: subjects,
      forms: forms,
      city: city,
      area: area,
      latitude: lat,
      longitude: lng,
      teachingMode: mode,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Student _daniel({
  String? form = 'Form 4',
  List<String> subjects = const ['Mathematics', 'Physics'],
}) =>
    Student(
      id: 'daniel',
      parentId: 'p1',
      name: 'Daniel',
      schoolLevel: form,
      subjects: subjects,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  group('buildDiscovery', () {
    test('teacher with stored coordinates gets a map location', () {
      final t = _teacher('Coord',
          subjects: ['Mathematics'], lat: 3.87, lng: 11.52);
      final items = buildDiscovery(child: _daniel(), teachers: [t]);
      expect(items.single.hasLocation, isTrue);
      expect(items.single.location, const GeoPoint(3.87, 11.52));
    });

    test('teacher with only a known city is placed via the gazetteer', () {
      final t = _teacher('Gaz', subjects: ['Mathematics'], city: 'Yaoundé');
      final items = buildDiscovery(child: _daniel(), teachers: [t]);
      expect(items.single.hasLocation, isTrue);
    });

    test('teacher with an unknown area still appears (no location) — list-safe',
        () {
      final t = _teacher('NoLoc',
          subjects: ['Mathematics'], city: 'Nowhereville');
      final items = buildDiscovery(child: _daniel(), teachers: [t]);
      expect(items, hasLength(1));
      expect(items.single.hasLocation, isFalse);
    });

    test('online-only filter keeps online + both, drops in-person', () {
      final online = _teacher('Online', mode: TeachingMode.online);
      final both = _teacher('Both', mode: TeachingMode.both);
      final inPerson = _teacher('InPerson', mode: TeachingMode.inPerson);
      final items = buildDiscovery(
        child: _daniel(),
        teachers: [online, both, inPerson],
        filters: const DiscoveryFilters(onlineOnly: true),
      );
      final names = items.map((d) => d.teacher.displayName).toSet();
      expect(names, containsAll(<String>['Online', 'Both']));
      expect(names, isNot(contains('InPerson')));
    });

    test('in-person teacher is included by default (no online filter)', () {
      final inPerson = _teacher('InPerson', mode: TeachingMode.inPerson);
      final items = buildDiscovery(child: _daniel(), teachers: [inPerson]);
      expect(items.single.teacher.teachingMode, TeachingMode.inPerson);
    });

    test('matching by form: teacher of the child form is relevant', () {
      final t = _teacher('FormOnly',
          forms: ['Form 4'], subjects: ['History']); // form match, no subject
      final items = buildDiscovery(child: _daniel(), teachers: [t]);
      expect(items.single.formMatches, isTrue);
      expect(items.single.matchedSubjects, isEmpty);
    });

    test('matching by subject is surfaced as matchedSubjects', () {
      final t = _teacher('Subj',
          forms: ['Form 4'], subjects: ['Mathematics', 'Physics', 'French']);
      final items = buildDiscovery(child: _daniel(), teachers: [t]);
      expect(items.single.matchedSubjects.toSet(),
          {'Mathematics', 'Physics'});
    });

    test('the single strongest match is flagged isBestMatch', () {
      final strong = _teacher('Strong',
          forms: ['Form 4'], subjects: ['Mathematics', 'Physics']);
      final weak =
          _teacher('Weak', forms: ['Form 4'], subjects: ['History']);
      final items = buildDiscovery(child: _daniel(), teachers: [weak, strong]);
      expect(items.first.teacher.displayName, 'Strong');
      expect(items.first.isBestMatch, isTrue);
      expect(items.where((d) => d.isBestMatch), hasLength(1));
    });

    test('nearby ordering sorts located teachers by distance', () {
      // Parent in Yaoundé centre.
      const parent = GeoPoint(3.8480, 11.5021);
      final near = _teacher('Near',
          subjects: ['Mathematics'], lat: 3.85, lng: 11.51); // ~a few hundred m
      final far = _teacher('Far',
          subjects: ['Mathematics'], lat: 4.05, lng: 9.77); // Douala, ~200 km
      final items = buildDiscovery(
        child: _daniel(),
        teachers: [far, near],
        parentLocation: parent,
        filters: const DiscoveryFilters(nearby: true),
      );
      expect(items.map((d) => d.teacher.displayName).toList(),
          ['Near', 'Far']);
      expect(items.first.distanceKm, lessThan(items.last.distanceKm!));
    });

    test('nearby: teachers without a location sort last, never dropped', () {
      const parent = GeoPoint(3.8480, 11.5021);
      final placed =
          _teacher('Placed', subjects: ['Mathematics'], lat: 3.85, lng: 11.51);
      final unplaced = _teacher('Unplaced',
          subjects: ['Mathematics'], city: 'Nowhereville');
      final items = buildDiscovery(
        child: _daniel(),
        teachers: [unplaced, placed],
        parentLocation: parent,
        filters: const DiscoveryFilters(nearby: true),
      );
      expect(items.map((d) => d.teacher.displayName).toList(),
          ['Placed', 'Unplaced']);
      expect(items.last.distanceKm, isNull);
    });

    test('no parent location: nearby filter degrades to relevance order', () {
      final a = _teacher('A',
          forms: ['Form 4'], subjects: ['Mathematics', 'Physics']);
      final b = _teacher('B', forms: ['Form 4'], subjects: ['Mathematics']);
      final items = buildDiscovery(
        child: _daniel(),
        teachers: [b, a],
        filters: const DiscoveryFilters(nearby: true),
      );
      // Still returns everyone relevant; distances are null.
      expect(items.map((d) => d.teacher.displayName).toSet(), {'A', 'B'});
      expect(items.every((d) => d.distanceKm == null), isTrue);
    });

    test('irrelevant teachers are excluded (Form 1 / unrelated subject)', () {
      final relevant = _teacher('Rel', forms: ['Form 4'], subjects: ['Mathematics']);
      final irrelevant = _teacher('Irr', forms: ['Form 1'], subjects: ['Biology']);
      final items =
          buildDiscovery(child: _daniel(), teachers: [relevant, irrelevant]);
      expect(items.map((d) => d.teacher.displayName), ['Rel']);
    });

    test('subject filter narrows to teachers of that subject', () {
      final maths = _teacher('Maths', subjects: ['Mathematics']);
      final physics = _teacher('Physics', subjects: ['Physics']);
      final items = buildDiscovery(
        child: _daniel(),
        teachers: [maths, physics],
        filters: const DiscoveryFilters(subject: 'Physics'),
      );
      expect(items.map((d) => d.teacher.displayName), ['Physics']);
    });
  });

  group('structured filters', () {
    TeacherProfile structured(
      String name, {
      required List<String> levelCodes,
      List<String> subjects = const ['Mathematics'],
    }) =>
        TeacherProfile(
          id: name,
          userId: 'u-$name',
          displayName: name,
          subjects: subjects,
          levelCodes: levelCodes,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    Student learner(String levelCode) => Student(
          id: 'daniel',
          parentId: 'p1',
          name: 'Daniel',
          levelCode: levelCode,
          subjects: const ['Mathematics'],
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('the class filter is a level code, so it is subsystem-specific', () {
      final form4 = structured('Form4', levelCodes: ['en.sec.ol.form4']);
      final form5 = structured('Form5', levelCodes: ['en.sec.ol.form5']);

      final items = buildDiscovery(
        child: learner('en.sec.ol.form4'),
        teachers: [form4, form5],
        filters: const DiscoveryFilters(levelCode: 'en.sec.ol.form5'),
      );

      expect(items.map((d) => d.teacher.displayName), ['Form5']);
    });

    test('a legacy teacher is still matched by the class filter', () {
      final legacy = _teacher('Legacy', forms: ['Form 4']);
      final items = buildDiscovery(
        child: learner('en.sec.ol.form4'),
        teachers: [legacy],
        filters: const DiscoveryFilters(levelCode: 'en.sec.ol.form4'),
      );
      expect(items, hasLength(1));
    });

    test('availability narrows results to the teachers supplied', () {
      final available = structured('Available',
          levelCodes: ['en.sec.ol.form4']);
      final busy = structured('Busy', levelCodes: ['en.sec.ol.form4']);

      final items = buildDiscovery(
        child: learner('en.sec.ol.form4'),
        teachers: [available, busy],
        filters: DiscoveryFilters(
          availableTeacherUserIds: {available.userId},
        ),
      );

      expect(items.map((d) => d.teacher.displayName), ['Available']);
    });

    test('a French learner never sees English-subsystem teachers', () {
      final english = structured('English Form 4',
          levelCodes: ['en.sec.ol.form4'], subjects: ['Mathematics']);
      final french = structured('French 4eme',
          levelCodes: ['fr.sec.c1.4e'], subjects: ['Mathematics']);

      final items = buildDiscovery(
        child: Student(
          id: 'ngwa',
          parentId: 'p1',
          name: 'Ngwa',
          levelCode: 'fr.sec.c1.4e',
          subjects: const ['Mathematics'],
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
        teachers: [english, french],
      );

      expect(items.map((d) => d.teacher.displayName), ['French 4eme']);
    });
  });
}
