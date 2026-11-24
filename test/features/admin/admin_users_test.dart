import 'package:edu237/core/models/admin_user_detail.dart';
import 'package:edu237/core/models/user_role.dart';
import 'package:edu237/core/routing/app_router.dart';
import 'package:edu237/core/services/admin_service.dart';
import 'package:edu237/core/state/app_state.dart';
import 'package:edu237/features/admin/admin_home_screen.dart';
import 'package:edu237/features/admin/admin_user_detail_screen.dart';
import 'package:edu237/features/admin/admin_users_screen.dart';
import 'package:edu237/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_admin_service.dart';

void main() {
  final sampleTeacherSummary = AdminUserSummary(
    id: 'tea-1',
    email: 'ransom.jam@camiva.cm',
    name: 'Jam Ransom',
    phone: '+237 670 12 34 56',
    role: UserRole.teacher,
    profileComplete: true,
    createdAt: DateTime(2026, 8, 1),
    teacherVerificationStatus: 'approved',
    studentsCount: 2,
    subjects: const ['Mathematics', 'Physics'],
    town: 'Douala',
    totalEarnings: 180000,
    balance: 45000,
  );

  final sampleParentSummary = AdminUserSummary(
    id: 'par-1',
    email: 'grace.ayuk@camiva.cm',
    name: 'Mrs. Grace Ayuk',
    phone: '+237 677 33 22 11',
    role: UserRole.parent,
    profileComplete: true,
    createdAt: DateTime(2026, 8, 2),
    childrenCount: 2,
    town: 'Douala',
  );

  final sampleStudentSummary = AdminUserSummary(
    id: 'stu-1',
    email: 'brenda.bessong@camiva.cm',
    name: 'Brenda Bessong',
    phone: '+237 675 88 99 00',
    role: UserRole.student,
    profileComplete: true,
    createdAt: DateTime(2026, 8, 3),
    subjects: const ['Further Mathematics'],
    town: 'Douala',
  );

  final sampleTeacherDetail = AdminUserDetail(
    id: 'tea-1',
    email: 'ransom.jam@camiva.cm',
    name: 'Jam Ransom',
    phone: '+237 670 12 34 56',
    role: UserRole.teacher,
    profileComplete: true,
    createdAt: DateTime(2026, 8, 1),
    teacherProfile: const AdminTeacherDetails(
      displayName: 'Jam Ransom, MSc',
      bio: 'Mathematics and Physics teacher.',
      subjects: ['Mathematics', 'Physics'],
      forms: ['Form 5', 'Upper Sixth'],
      hourlyRate: 4500,
      teachingMode: 'both',
      town: 'Douala',
      neighbourhood: 'Akwa',
      verificationStatus: 'approved',
      qualificationTitle: 'BSc Mathematics',
      payoutPhone: '+237 670 12 34 56',
      payoutMedium: 'MTN Mobile Money',
      totalEarnings: 180000,
      availableBalance: 45000,
      activeAgreementsCount: 2,
      students: [
        AdminLinkedStudent(
          id: 's-1',
          name: 'Prince Nkwenti',
          level: 'Form 5',
          subsystem: 'English',
          subjects: ['Mathematics', 'Physics'],
        ),
      ],
    ),
  );

  final sampleParentDetail = AdminUserDetail(
    id: 'par-1',
    email: 'grace.ayuk@camiva.cm',
    name: 'Mrs. Grace Ayuk',
    phone: '+237 677 33 22 11',
    role: UserRole.parent,
    profileComplete: true,
    createdAt: DateTime(2026, 8, 2),
    parentProfile: const AdminParentDetails(
      children: [
        AdminLinkedStudent(
          id: 's-1',
          name: 'Prince Nkwenti',
          level: 'Form 5',
          subsystem: 'English',
          subjects: ['Mathematics'],
        ),
      ],
      activeTeachers: ['Jam Ransom'],
      activeAgreementsCount: 1,
      totalPaid: 120000,
      outstandingBalance: 0,
    ),
  );

  final sampleStudentDetail = AdminUserDetail(
    id: 'stu-1',
    email: 'brenda.bessong@camiva.cm',
    name: 'Brenda Bessong',
    phone: '+237 675 88 99 00',
    role: UserRole.student,
    profileComplete: true,
    createdAt: DateTime(2026, 8, 3),
    studentProfile: const AdminStudentDetails(
      studentId: 'stu-1',
      isSelfManaged: true,
      subsystem: 'English',
      level: 'Upper Sixth',
      series: 'Science S1',
      subjects: ['Further Mathematics', 'Physics'],
      assignedTeachers: ['Jam Ransom'],
      totalSessions: 12,
    ),
  );

  Widget createTestWidget({
    required Widget child,
    required AdminService service,
  }) {
    return AdminServiceScope(
      adminService: service,
      child: MaterialApp(home: child),
    );
  }

  group('AdminUsersScreen', () {
    testWidgets('lists users with their name, role badge, and details',
        (tester) async {
      final service = FakeAdminService(
        users: [sampleTeacherSummary, sampleParentSummary, sampleStudentSummary],
      );

      await tester.pumpWidget(
        createTestWidget(child: const AdminUsersScreen(), service: service),
      );
      await tester.pumpAndSettle();

      expect(find.text('Jam Ransom'), findsOneWidget);
      expect(find.text('Mrs. Grace Ayuk'), findsOneWidget);
      expect(find.text('Brenda Bessong'), findsOneWidget);

      expect(find.text('Teacher'), findsOneWidget);
      expect(find.text('Parent'), findsOneWidget);
      expect(find.text('Student'), findsOneWidget);

      expect(find.text('ransom.jam@camiva.cm'), findsOneWidget);
      expect(find.text('+237 670 12 34 56'), findsOneWidget);
    });

    testWidgets('filtering by role narrows down the users list',
        (tester) async {
      final service = FakeAdminService(
        users: [sampleTeacherSummary, sampleParentSummary, sampleStudentSummary],
      );

      await tester.pumpWidget(
        createTestWidget(child: const AdminUsersScreen(), service: service),
      );
      await tester.pumpAndSettle();

      // Tap Teachers filter chip
      await tester.tap(find.byKey(const Key('filter_role_teacher')));
      await tester.pumpAndSettle();

      expect(find.text('Jam Ransom'), findsOneWidget);
      expect(find.text('Mrs. Grace Ayuk'), findsNothing);
      expect(find.text('Brenda Bessong'), findsNothing);
    });

    testWidgets('search filters users by name or query', (tester) async {
      final service = FakeAdminService(
        users: [sampleTeacherSummary, sampleParentSummary, sampleStudentSummary],
      );

      await tester.pumpWidget(
        createTestWidget(child: const AdminUsersScreen(), service: service),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('admin_user_search_field')), 'Grace');
      await tester.pumpAndSettle();

      expect(find.text('Mrs. Grace Ayuk'), findsOneWidget);
      expect(find.text('Jam Ransom'), findsNothing);
    });
  });

  group('AdminUserDetailScreen', () {
    testWidgets('renders all details for a Teacher', (tester) async {
      final service = FakeAdminService(
        userDetails: {'tea-1': sampleTeacherDetail},
      );

      await tester.pumpWidget(
        createTestWidget(
          child: const AdminUserDetailScreen(userId: 'tea-1'),
          service: service,
        ),
      );
      await tester.pumpAndSettle();

      // Identity
      expect(find.text('Jam Ransom'), findsWidgets);
      expect(find.text('ransom.jam@camiva.cm'), findsOneWidget);
      expect(find.text('+237 670 12 34 56'), findsWidgets);

      // Teaching Details
      expect(find.text('TEACHER TEACHING PROFILE'), findsOneWidget);
      expect(find.text('Mathematics and Physics teacher.'), findsOneWidget);
      expect(find.text('BSc Mathematics'), findsOneWidget);
      expect(find.text('Akwa, Douala'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);

      // Payout & Earnings
      expect(find.text('Lifetime Earnings'), findsOneWidget);
      expect(find.text('Available Balance'), findsOneWidget);
      expect(find.text('MTN Mobile Money'), findsOneWidget);

      // Linked Students
      expect(find.text('Prince Nkwenti'), findsOneWidget);
    });

    testWidgets('renders all details for a Parent', (tester) async {
      final service = FakeAdminService(
        userDetails: {'par-1': sampleParentDetail},
      );

      await tester.pumpWidget(
        createTestWidget(
          child: const AdminUserDetailScreen(userId: 'par-1'),
          service: service,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mrs. Grace Ayuk'), findsWidgets);
      expect(find.text('grace.ayuk@camiva.cm'), findsOneWidget);

      // Parent specific sections
      expect(find.text('CHILDREN / REGISTERED LEARNERS (1)'), findsOneWidget);
      expect(find.text('Prince Nkwenti'), findsOneWidget);
      expect(find.text('PARENT COMMERCIAL OVERVIEW'), findsOneWidget);
      expect(find.text('Tutors Hired: '), findsOneWidget);
      expect(find.text('Jam Ransom'), findsOneWidget);
    });

    testWidgets('renders all details for a Student', (tester) async {
      final service = FakeAdminService(
        userDetails: {'stu-1': sampleStudentDetail},
      );

      await tester.pumpWidget(
        createTestWidget(
          child: const AdminUserDetailScreen(userId: 'stu-1'),
          service: service,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Brenda Bessong'), findsWidgets);
      expect(find.text('LEARNER ACADEMIC PROFILE'), findsOneWidget);
      expect(find.text('Upper Sixth'), findsOneWidget);
      expect(find.text('Science S1'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Self-managed Student account'), findsOneWidget);
      expect(find.text('12 sessions'), findsOneWidget);
    });
  });

  group('AdminHomeScreen Users Integration', () {
    testWidgets('displays Community metric card and Users tile in manage',
        (tester) async {
      final service = FakeAdminService(
        users: [sampleTeacherSummary, sampleParentSummary, sampleStudentSummary],
      );

      await tester.pumpWidget(
        createTestWidget(
          child: const AdminHomeScreen(),
          service: service,
        ),
      );
      await tester.pumpAndSettle();

      // Metrics
      expect(find.byKey(const Key('admin_users_metric_card')), findsOneWidget);
      expect(find.text('3 Registered Users'), findsOneWidget);
      expect(find.text('Teachers'), findsOneWidget);
      expect(find.text('Parents'), findsOneWidget);
      expect(find.text('Students'), findsOneWidget);

      // Manage ListTile
      expect(find.byKey(const Key('admin_open_users')), findsOneWidget);
      expect(find.text('Users & Profiles'), findsOneWidget);
    });
  });

  group('Admin Web Routing (/admin)', () {
    testWidgets('web access by typing /admin opens AdminHomeScreen',
        (tester) async {
      final appState = AppState();
      final router = createRouter(appState);
      final service = FakeAdminService(
        users: [sampleTeacherSummary],
      );

      await tester.pumpWidget(
        AppStateScope(
          state: appState,
          child: AdminServiceScope(
            adminService: service,
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en')],
            ),
          ),
        ),
      );
      router.go(AppRoutes.adminHome);
      await tester.pumpAndSettle();

      expect(find.byType(AdminHomeScreen), findsOneWidget);
      expect(find.text('Camiva Admin'), findsOneWidget);
    });

    testWidgets('web access by typing /admin/users opens AdminUsersScreen',
        (tester) async {
      final appState = AppState();
      final router = createRouter(appState);
      final service = FakeAdminService(
        users: [sampleTeacherSummary],
      );

      await tester.pumpWidget(
        AppStateScope(
          state: appState,
          child: AdminServiceScope(
            adminService: service,
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en')],
            ),
          ),
        ),
      );
      router.go(AppRoutes.adminUsers);
      await tester.pumpAndSettle();

      expect(find.byType(AdminUsersScreen), findsOneWidget);
      expect(find.text('Platform Users'), findsOneWidget);
      expect(find.text('Jam Ransom'), findsOneWidget);
    });
  });
}
