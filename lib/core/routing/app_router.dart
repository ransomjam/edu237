import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:edu237/l10n/app_localizations.dart';
import '../shell/app_shell.dart';
import '../constants/app_constants.dart';
import '../state/app_state.dart';
import '../theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/forgot_pin_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/children/add_child_screen.dart';
import '../../features/children/edit_child_screen.dart';
import '../services/student_service.dart';
import '../../features/teacher/teacher_discovery_screen.dart';
import '../../features/teacher/teacher_profile_screen.dart';
import '../../features/teacher/edit_teacher_profile_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/student/student_learning_screen.dart';
import '../../features/student/student_profile_screen.dart';
import '../../features/requests/parent_requests_screen.dart';
import '../../features/requests/teacher_requests_screen.dart';
import '../../features/teacher/teacher_student_detail_screen.dart';
import '../models/student.dart';
import '../models/teacher_profile.dart';
import '../models/learning_activity.dart';
import '../../features/learning/create_activity_screen.dart';
import '../../features/learning/teacher_activity_list_screen.dart';
import '../../features/learning/teacher_activity_detail_screen.dart';
import '../../features/learning/student_learning_feed_screen.dart';
import '../../features/schedule/edit_availability_screen.dart';
import '../../features/schedule/schedule_lesson_screen.dart';
import '../../features/schedule/teacher_schedule_screen.dart';
import '../../features/admin/admin_billing_screen.dart';
import '../../features/admin/admin_verifications_screen.dart';
import '../../features/tutoring/review_agreement_screen.dart';
import '../../features/tutoring/service_plan_screen.dart';
import '../../features/tutoring/setup_tutoring_screen.dart';
import '../../features/tutoring/teacher_agreement_screen.dart';
import '../../features/tutoring/teacher_verification_screen.dart';
import '../../features/admin/admin_home_screen.dart';
import '../../features/admin/admin_payments_screen.dart';
import '../../features/admin/admin_users_screen.dart';
import '../../features/admin/admin_user_detail_screen.dart';
import '../../features/admin/admin_withdrawals_screen.dart';
import '../models/admin_user_detail.dart';
import '../../features/payments/activate_relationship_screen.dart';
import '../../features/payments/parent_payment_screen.dart';
import '../../features/payments/payment_history_screen.dart';
import '../../features/payments/teacher_earnings_screen.dart';

abstract final class AppRoutes {
  // Auth
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPin = '/forgot-pin';
  static const String loading = '/loading';
  static const String profileError = '/profile-error';

  // Onboarding
  static const String onboarding = '/onboarding';

  // Shell branches
  static const String home = '/';
  static const String children = '/children'; // kept for deep-links into child detail
  static const String paymentsDash = '/payments-tab'; // parent tab 1
  static const String earningsDash = '/earnings-tab'; // teacher tab 1
  static const String profile = '/profile';

  // Full-screen flows (pushed over the shell)
  static const String addChild = '/add-child';

  static String childDetailPath(String id) => '/child/$id';
  static String childEditPath(String id) => '/child/$id/edit';
  static String childTeachersPath(String id) => '/child/$id/teachers';

  // Teacher profile flows
  static const String teacherProfileEdit = '/teacher/profile/edit';
  static const String teacherProfile = '/teacher/view';

  // Requests
  static const String parentRequests = '/requests';
  static const String teacherRequests = '/teacher/requests';
  static const String myStudents = '/teacher/students';
  
  // Teacher view of a student
  static const String teacherStudentDetail = '/teacher/student/view';

  // Verification, tutoring proposal and parent review
  static const String teacherVerification = '/teacher/verification';
  static const String setupTutoring = '/teacher/setup-tutoring';
  static const String reviewAgreement = '/tutoring/review';
  static const String teacherAgreement = '/teacher/arrangement';
  static const String servicePlan = '/teacher/service-plan';

  // Camiva admin (shown only to platform admins)
  static const String adminHome = '/admin';
  static const String adminUsers = '/admin/users';
  static const String adminUserDetail = '/admin/users/:id';
  static String adminUserDetailPath(String id) => '/admin/users/$id';
  static const String adminWithdrawals = '/admin/withdrawals';
  static const String adminPayments = '/admin/payments';
  static const String adminBilling = '/admin/billing';
  static const String adminVerifications = '/admin/verifications';

  // Scheduling & availability
  static const String teacherAvailability = '/teacher/availability';
  static const String teacherSchedule = '/teacher/schedule';
  static const String scheduleLesson = '/teacher/schedule-lesson';

  // Payments (commercial layer)
  static const String activateRelationship = '/payments/activate';
  static const String payForTutoring = '/payments/tutoring';
  static const String paymentHistory = '/payments';
  static const String teacherEarnings = '/teacher/earnings';

  // Learning Activities
  static const String createActivity = '/learning/create';
  static const String teacherActivityList = '/learning/teacher/list';
  static const String teacherActivityDetail = '/learning/teacher/detail';
  static const String studentLearningFeed = '/learning/student/feed';

  // Legacy Lessons (Teacher) - Pending Migration
  @Deprecated('Pending migration to new learning module') static const String teacherLessons = '/teacher/lessons';
  @Deprecated('Pending migration to new learning module') static const String editLesson = '/teacher/lessons/edit';
  @Deprecated('Pending migration to new learning module') static const String teacherLessonDetail = '/teacher/lessons/view';

  // Legacy Lessons (Parent/Student) - Pending Migration
  @Deprecated('Pending migration to new learning module') static const String studentLessons = '/student/lessons';
  @Deprecated('Pending migration to new learning module') static const String parentLessonDetail = '/student/lessons/view';

  // Legacy Assignments (Teacher) - Pending Migration
  @Deprecated('Pending migration to new assignments module') static const String teacherAssignments = '/teacher/assignments';
  @Deprecated('Pending migration to new assignments module') static const String createAssignment = '/teacher/assignments/create';
  @Deprecated('Pending migration to new assignments module') static const String teacherAssignmentDetail = '/teacher/assignments/view';
  @Deprecated('Pending migration to new assignments module') static const String teacherSubmissionView = '/teacher/assignments/submission';

  // Legacy Assignments (Parent/Student) - Pending Migration
  @Deprecated('Pending migration to new assignments module') static const String studentAssignments = '/student/assignments';
  @Deprecated('Pending migration to new assignments module') static const String parentAssignmentDetail = '/student/assignments/view';
  @Deprecated('Pending migration to new assignments module') static const String submitWork = '/student/assignments/submit';
}

/// Creates the router. Requires [appState] so the redirect guard can read
/// authentication and profile-completeness reactively.
///
/// Redirect logic:
///   Unauthenticated                    → /login
///   Authenticated + profile incomplete → /onboarding
///   Authenticated + profile complete   → / (shell)
///   Authenticated on auth route        → /
///   Authenticated + complete on /onboarding → /
GoRouter createRouter(AppState appState) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: false,
    refreshListenable: appState.routingListenable,
    redirect: (BuildContext context, GoRouterState state) {
      final isAuthenticated = appState.isAuthenticated;
      final isProfileComplete = appState.profileComplete;
      final hasResolvedInitialAuth = appState.hasResolvedInitialAuth;
      final hasStartupError = appState.startupError != null;
      final location = state.matchedLocation;

      final isOnAuthRoute = location == AppRoutes.login ||
          location == AppRoutes.register ||
          // Recovery is for people who cannot sign in, so it has to be
          // reachable without a session.
          location == AppRoutes.forgotPin;
      final isOnAdminRoute = location == AppRoutes.adminHome ||
          location.startsWith('${AppRoutes.adminHome}/');
      final isOnOnboarding = location == AppRoutes.onboarding;
      final isOnLoading = location == AppRoutes.loading;
      final isOnProfileError = location == AppRoutes.profileError;

      // Admin routes are directly accessible on the web.
      if (isOnAdminRoute) {
        return null;
      }

      if (!hasResolvedInitialAuth) {
        return isOnLoading ? null : AppRoutes.loading;
      }

      if (hasStartupError) {
        return isOnProfileError ? null : AppRoutes.profileError;
      }

      if (isOnLoading || isOnProfileError) {
        return isAuthenticated ? AppRoutes.home : AppRoutes.login;
      }

      if (!isAuthenticated) {
        // Unauthenticated users may only be on auth routes.
        return isOnAuthRoute ? null : AppRoutes.login;
      }

      // Authenticated from here down.
      if (!isProfileComplete) {
        // Must complete onboarding before accessing the shell.
        return isOnOnboarding ? null : AppRoutes.onboarding;
      }

      // Profile is complete — bounce away from auth/onboarding routes.
      if (isOnAuthRoute || isOnOnboarding) {
        return AppRoutes.home;
      }

      return null;
    },
    routes: [
      // Auth routes — outside the shell
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPin,
        builder: (context, state) => const ForgotPinScreen(),
      ),
      GoRoute(
        path: AppRoutes.loading,
        builder: (context, state) => const _ProfileLoadingScreen(),
      ),
      GoRoute(
        path: AppRoutes.profileError,
        builder: (context, state) => _ProfileErrorScreen(appState: appState),
      ),

      // Onboarding — outside the shell
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),

      // Add child — a full-screen flow pushed over the shell.
      GoRoute(
        path: AppRoutes.addChild,
        builder: (context, state) => const AddChildScreen(),
      ),

      // Child detail — pushed over the shell. The tapped child is passed via
      // `extra`; if absent (e.g. a cold deep link) the screen fetches by id.
      GoRoute(
        path: '/child/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final extra = state.extra;
          return EditChildScreen(
            studentId: id,
            student: extra is Student ? extra : null,
          );
        },
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              final extra = state.extra;
              return EditChildScreen(
                studentId: id,
                student: extra is Student ? extra : null,
              );
            },
          ),
          GoRoute(
            path: 'teachers',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              final extra = state.extra;
              if (extra is TeacherDiscoveryArgs) {
                return TeacherDiscoveryScreen(
                  child: extra.child,
                  initialSubject: extra.initialSubject,
                );
              }
              if (extra is Student) {
                return TeacherDiscoveryScreen(child: extra);
              }
              return _LoadStudentAndThenDiscovery(
                studentId: id,
              );
            },
          ),
        ],
      ),

      // Teacher profile: edit own, and view another (from discovery).
      GoRoute(
        path: AppRoutes.teacherProfileEdit,
        builder: (context, state) => EditTeacherProfileScreen(
          existing: state.extra is TeacherProfile
              ? state.extra as TeacherProfile
              : null,
        ),
      ),
      GoRoute(
        path: AppRoutes.teacherProfile,
        builder: (context, state) {
          final args = state.extra;
          if (args is TeacherProfileArgs) {
            return TeacherProfileScreen(
              teacher: args.teacher,
              student: args.student,
            );
          }
          // Should always be reached with args; guard defensively.
          return const Scaffold(
            body: Center(child: Text('Teacher not found.')),
          );
        },
      ),

      // Teacher view of a student (passed via extra)
      GoRoute(
        path: AppRoutes.teacherStudentDetail,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is TeacherStudentDetailArgs) {
            return ScheduleLessonScreen(student: extra.student);
          }
          if (extra is Student) {
            return ScheduleLessonScreen(student: extra);
          }
          return const Scaffold(
            body: Center(child: Text('Student not found.')),
          );
        },
      ),

      // Camiva admin. The screen and every action behind it are re-checked
      // server-side, so reaching this route without admin rights shows nothing.
      GoRoute(
        path: AppRoutes.teacherVerification,
        builder: (context, state) => const TeacherVerificationScreen(),
      ),
      GoRoute(
        path: AppRoutes.setupTutoring,
        builder: (context, state) {
          final args = state.extra;
          if (args is SetupTutoringArgs) {
            return SetupTutoringScreen(args: args);
          }
          return const Scaffold(
            body: Center(child: Text('Tutoring details not found.')),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.servicePlan,
        builder: (context, state) => const ServicePlanScreen(),
      ),
      GoRoute(
        path: AppRoutes.teacherAgreement,
        builder: (context, state) {
          final args = state.extra;
          if (args is TeacherAgreementArgs) {
            return TeacherAgreementScreen(args: args);
          }
          return const Scaffold(
            body: Center(child: Text('Tutoring arrangement not found.')),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.reviewAgreement,
        builder: (context, state) {
          final args = state.extra;
          if (args is ReviewAgreementArgs) {
            return ReviewAgreementScreen(
              agreement: args.agreement,
              childName: args.childName,
              teacherName: args.teacherName,
            );
          }
          return const Scaffold(
            body: Center(child: Text('Tutoring arrangement not found.')),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.adminHome,
        builder: (context, state) => const AdminHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminUsers,
        builder: (context, state) => const AdminUsersScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminUserDetail,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final extra = state.extra;
          return AdminUserDetailScreen(
            userId: id,
            initialSummary: extra is AdminUserSummary ? extra : null,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.adminWithdrawals,
        builder: (context, state) => const AdminWithdrawalsScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminPayments,
        builder: (context, state) => const AdminPaymentsScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminBilling,
        builder: (context, state) => const AdminBillingScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminVerifications,
        builder: (context, state) => const AdminVerificationsScreen(),
      ),

      // Scheduling & availability
      GoRoute(
        path: AppRoutes.teacherAvailability,
        builder: (context, state) => const EditAvailabilityScreen(),
      ),
      GoRoute(
        path: AppRoutes.teacherSchedule,
        builder: (context, state) => const TeacherScheduleScreen(),
      ),
      GoRoute(
        path: AppRoutes.scheduleLesson,
        builder: (context, state) {
          final student = state.extra;
          if (student is Student) {
            return ScheduleLessonScreen(student: student);
          }
          return const Scaffold(
            body: Center(child: Text('Student not found.')),
          );
        },
      ),

      // Payments — the commercial layer. Each is a full-screen flow pushed
      // over the shell; the payment screens always resolve their own amount
      // and state from the server.
      GoRoute(
        path: AppRoutes.activateRelationship,
        builder: (context, state) {
          final args = state.extra;
          if (args is ActivateRelationshipArgs) {
            return ActivateRelationshipScreen(args: args);
          }
          return const Scaffold(
            body: Center(child: Text('Relationship not found.')),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.payForTutoring,
        builder: (context, state) {
          final args = state.extra;
          if (args is ParentPaymentArgs) {
            return ParentPaymentScreen(args: args);
          }
          return const Scaffold(
            body: Center(child: Text('Tutoring arrangement not found.')),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.paymentHistory,
        builder: (context, state) => const PaymentHistoryScreen(),
      ),
      GoRoute(
        path: AppRoutes.teacherEarnings,
        builder: (context, state) => const TeacherEarningsScreen(),
      ),

      // Learning Activities
      GoRoute(
        path: AppRoutes.createActivity,
        builder: (context, state) {
          final student = state.extra;
          return CreateActivityScreen(
            preselectedStudent: student is Student ? student : null,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.teacherActivityList,
        builder: (context, state) {
          final student = state.extra;
          if (student is Student) {
            return TeacherActivityListScreen(student: student);
          }
          return const Scaffold(body: Center(child: Text('Student not found.')));
        },
      ),
      GoRoute(
        path: AppRoutes.teacherActivityDetail,
        builder: (context, state) {
          final activity = state.extra;
          if (activity is LearningActivity) {
            return TeacherActivityDetailScreen(activity: activity);
          }
          return const Scaffold(body: Center(child: Text('Activity not found.')));
        },
      ),
      GoRoute(
        path: AppRoutes.studentLearningFeed,
        builder: (context, state) {
          final student = state.extra;
          if (student is Student) {
            return StudentLearningFeedScreen(student: student);
          }
          return const Scaffold(body: Center(child: Text('Student not found.')));
        },
      ),

      // Main app shell
      StatefulShellRoute.indexedStack(
        builder: (BuildContext context, GoRouterState state,
            StatefulNavigationShell navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                // Tab 1: static path; builder switches screen by role.
                // Students get Learning here — never a money screen.
                path: AppRoutes.paymentsDash,
                builder: (context, state) {
                  final role = AppState.of(context).activeRole;
                  if (role.isStudent) return const StudentLearningScreen();
                  if (role.isTeacher) return const TeacherEarningsScreen();
                  return const PaymentHistoryScreen();
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                // For teachers, this is the Requests tab.
                // For parents, we just mount the ParentRequestsScreen here to keep it available
                // even though it's not shown in the bottom nav.
                path: AppRoutes.teacherRequests,
                builder: (context, state) =>
                    AppState.of(context).activeRole.isTeacher
                        ? const TeacherRequestsScreen()
                        : const ParentRequestsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (context, state) =>
                    AppState.of(context).activeRole.isStudent
                        ? const StudentProfileScreen()
                        : const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class _ProfileLoadingScreen extends StatelessWidget {
  const _ProfileLoadingScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppConstants.space16),
              Text(l10n.loadingProfile, style: AppTextStyles.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileErrorScreen extends StatelessWidget {
  const _ProfileErrorScreen({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                appState.startupError ?? l10n.errorProfileLoad,
                style: AppTextStyles.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppConstants.space16),
              AppButton(
                label: l10n.retryButton,
                onPressed: () {
                  appState.setUser(null);
                  context.go(AppRoutes.login);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadStudentAndThenDiscovery extends StatefulWidget {
  const _LoadStudentAndThenDiscovery({required this.studentId, this.initialSubject});
  final String studentId;
  final String? initialSubject;

  @override
  State<_LoadStudentAndThenDiscovery> createState() => _LoadStudentAndThenDiscoveryState();
}

class _LoadStudentAndThenDiscoveryState extends State<_LoadStudentAndThenDiscovery> {
  Student? _student;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await StudentServiceScope.of(context).fetchStudent(widget.studentId);
    if (!mounted) return;
    switch (result) {
      case StudentSuccess(:final student):
        setState(() {
          _student = student;
          _isLoading = false;
        });
      case StudentFailure(:final message):
        setState(() {
          _errorMessage = message;
          _isLoading = false;
        });
      case StudentListSuccess():
      case StudentNotFound():
        setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_student == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(_errorMessage ?? 'Student not found.')),
      );
    }
    return TeacherDiscoveryScreen(
      child: _student!,
      initialSubject: widget.initialSubject,
    );
  }
}
