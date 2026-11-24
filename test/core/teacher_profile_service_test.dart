import 'package:edu237/core/services/teacher_profile_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/teacher/fake_teacher_profile_service.dart';

/// These tests document the ownership contract the real
/// SupabaseTeacherProfileService + RLS must uphold (RLS itself is verified
/// against the hosted database during backend verification).
void main() {
  group('TeacherProfileService ownership contract', () {
    test('a teacher creates and reads their own profile', () async {
      final store = FakeTeacherStore();
      final teacher =
          FakeTeacherProfileService(userId: 'teacher-A', store: store);

      final created = await teacher.upsertMyProfile(
        displayName: 'Alice',
        subjects: const ['Mathematics'],
        forms: const ['Form 4'],
        bio: 'Maths tutor',
      );
      expect(created, isA<TeacherProfileSuccess>());

      final mine = await teacher.fetchMyProfile() as TeacherProfileSuccess;
      expect(mine.profile, isNotNull);
      expect(mine.profile!.userId, 'teacher-A');
      expect(mine.profile!.displayName, 'Alice');
      expect(mine.profile!.subjects, ['Mathematics']);
      expect(mine.profile!.forms, ['Form 4']);
    });

    test('updating writes to the same row (no duplicate)', () async {
      final store = FakeTeacherStore();
      final teacher =
          FakeTeacherProfileService(userId: 'teacher-A', store: store);

      final first = (await teacher.upsertMyProfile(
        displayName: 'Alice',
        subjects: const ['Mathematics'],
        forms: const ['Form 4'],
      )) as TeacherProfileSuccess;

      final updated = (await teacher.upsertMyProfile(
        displayName: 'Alice B.',
        subjects: const ['Mathematics', 'Physics'],
        forms: const ['Form 4', 'Form 5'],
      )) as TeacherProfileSuccess;

      expect(updated.profile!.id, first.profile!.id);
      expect(store.all.length, 1);
      expect(updated.profile!.subjects.toSet(), {'Mathematics', 'Physics'});
    });

    test('a teacher only sees their OWN profile via fetchMyProfile', () async {
      final store = FakeTeacherStore();
      final a = FakeTeacherProfileService(userId: 'teacher-A', store: store);
      final b = FakeTeacherProfileService(userId: 'teacher-B', store: store);

      await a.upsertMyProfile(
          displayName: 'Alice', subjects: const [], forms: const []);

      // B has no profile yet — cannot retrieve A's as "mine".
      final bMine = await b.fetchMyProfile() as TeacherProfileSuccess;
      expect(bMine.profile, isNull);
    });

    test('a teacher cannot target another teacher (no such method exists)',
        () async {
      // The interface only exposes upsertMyProfile, which always writes the
      // caller's own row — there is no API to modify another teacher.
      final store = FakeTeacherStore();
      final a = FakeTeacherProfileService(userId: 'teacher-A', store: store);
      final b = FakeTeacherProfileService(userId: 'teacher-B', store: store);

      await a.upsertMyProfile(
          displayName: 'Alice', subjects: const ['Mathematics'], forms: const ['Form 4']);
      await b.upsertMyProfile(
          displayName: 'Bob', subjects: const ['Biology'], forms: const ['Form 1']);

      expect((store.forUser('teacher-A'))!.displayName, 'Alice');
      expect((store.forUser('teacher-B'))!.displayName, 'Bob');
      expect(store.all.length, 2);
    });

    test('a parent can read teacher profiles (discovery)', () async {
      final store = FakeTeacherStore();
      final teacher =
          FakeTeacherProfileService(userId: 'teacher-A', store: store);
      await teacher.upsertMyProfile(
          displayName: 'Alice', subjects: const ['Mathematics'], forms: const ['Form 4']);

      // A parent is just another authenticated user with no own profile.
      final parent = FakeTeacherProfileService(userId: 'parent-1', store: store);
      final list = await parent.fetchTeachers() as TeacherProfileListSuccess;
      expect(list.profiles.length, 1);
      expect(list.profiles.single.displayName, 'Alice');

      // The parent has no teacher profile of their own.
      final parentMine =
          await parent.fetchMyProfile() as TeacherProfileSuccess;
      expect(parentMine.profile, isNull);
    });

    test('UnconfiguredTeacherProfileService fails safely', () async {
      const sut = UnconfiguredTeacherProfileService();
      expect(await sut.fetchMyProfile(), isA<TeacherProfileFailure>());
      expect(await sut.fetchTeachers(), isA<TeacherProfileFailure>());
      expect(
        await sut.upsertMyProfile(
            displayName: 'X', subjects: const [], forms: const []),
        isA<TeacherProfileFailure>(),
      );
    });
  });
}
