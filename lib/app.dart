import 'package:edu237/l10n/app_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'core/routing/app_router.dart';
import 'core/services/admin_service.dart';
import 'core/services/tutoring_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/learning_activity_service.dart';
import 'core/services/lesson_session_service.dart';
import 'core/services/location_service.dart';
import 'core/services/earnings_service.dart';
import 'core/services/parent_teacher_relationship_service.dart';
import 'core/services/payment_service.dart';
import 'core/services/profile_service.dart';
import 'core/services/push_service.dart';
import 'core/services/student_service.dart';
import 'core/services/teacher_availability_service.dart';
import 'core/services/teacher_profile_service.dart';
import 'core/services/teacher_request_service.dart';
import 'core/state/app_state.dart';
import 'core/state/refresh_bus.dart';
import 'core/theme/app_theme.dart';

class CamivaApp extends StatefulWidget {
  const CamivaApp({
    super.key,
    this.authService,
    this.profileService,
    this.studentService,
    this.relationshipService,
    this.teacherProfileService,
    this.teacherRequestService,
    this.learningActivityService,
    this.locationService,
    this.teacherAvailabilityService,
    this.lessonSessionService,
    this.paymentService,
    this.earningsService,
    this.adminService,
    this.tutoringService,
  });

  final AuthService? authService;
  final ProfileService? profileService;
  final StudentService? studentService;
  final ParentTeacherRelationshipService? relationshipService;
  final TeacherProfileService? teacherProfileService;
  final TeacherRequestService? teacherRequestService;
  final LearningActivityService? learningActivityService;
  final LocationService? locationService;
  final TeacherAvailabilityService? teacherAvailabilityService;
  final LessonSessionService? lessonSessionService;
  final PaymentService? paymentService;
  final EarningsService? earningsService;
  final AdminService? adminService;
  final TutoringService? tutoringService;

  @override
  State<CamivaApp> createState() => _CamivaAppState();
}

class _CamivaAppState extends State<CamivaApp> {
  late final AppState _appState;
  late final AuthService _authService;
  late final ProfileService _profileService;
  late final StudentService _studentService;
  late final ParentTeacherRelationshipService _relationshipService;
  late final TeacherProfileService _teacherProfileService;
  late final TeacherRequestService _teacherRequestService;
  late final LearningActivityService _learningActivityService;
  late final LocationService _locationService;
  late final TeacherAvailabilityService _teacherAvailabilityService;
  late final LessonSessionService _lessonSessionService;
  late final PaymentService _paymentService;
  late final EarningsService _earningsService;
  late final AdminService _adminService;
  late final TutoringService _tutoringService;
  final RefreshBus _refreshBus = RefreshBus();
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _appState = AppState();
    _authService = widget.authService ??
        (AppConfig.isConfigured
            ? SupabaseAuthService(Supabase.instance.client)
            : const UnconfiguredAuthService());
    _profileService = widget.profileService ??
        (AppConfig.isConfigured
            ? SupabaseProfileService(Supabase.instance.client)
            : const UnconfiguredProfileService());
    _studentService = widget.studentService ??
        (AppConfig.isConfigured
            ? SupabaseStudentService(Supabase.instance.client)
            : const UnconfiguredStudentService());
    _relationshipService = widget.relationshipService ??
        (AppConfig.isConfigured
            ? SupabaseParentTeacherRelationshipService(
                Supabase.instance.client)
            : const UnconfiguredParentTeacherRelationshipService());
    _teacherProfileService = widget.teacherProfileService ??
        (AppConfig.isConfigured
            ? SupabaseTeacherProfileService(Supabase.instance.client)
            : const UnconfiguredTeacherProfileService());
    _teacherRequestService = widget.teacherRequestService ??
        (AppConfig.isConfigured
            ? SupabaseTeacherRequestService(Supabase.instance.client)
            : const UnconfiguredTeacherRequestService());
    _learningActivityService = widget.learningActivityService ??
        (AppConfig.isConfigured
            ? SupabaseLearningActivityService(Supabase.instance.client)
            : const UnconfiguredLearningActivityService());
    _locationService = widget.locationService ??
        (AppConfig.isConfigured
            ? const GeolocatorLocationService()
            : const UnavailableLocationService());
    _teacherAvailabilityService = widget.teacherAvailabilityService ??
        (AppConfig.isConfigured
            ? SupabaseTeacherAvailabilityService(Supabase.instance.client)
            : const UnconfiguredTeacherAvailabilityService());
    _lessonSessionService = widget.lessonSessionService ??
        (AppConfig.isConfigured
            ? SupabaseLessonSessionService(Supabase.instance.client)
            : const UnconfiguredLessonSessionService());
    _paymentService = widget.paymentService ??
        (AppConfig.isConfigured
            ? SupabasePaymentService(Supabase.instance.client)
            : const UnconfiguredPaymentService());
    _earningsService = widget.earningsService ??
        (AppConfig.isConfigured
            ? SupabaseEarningsService(Supabase.instance.client)
            : const UnconfiguredEarningsService());
    _adminService = widget.adminService ??
        (AppConfig.isConfigured
            ? SupabaseAdminService(Supabase.instance.client)
            : const UnconfiguredAdminService());
    _tutoringService = widget.tutoringService ??
        (AppConfig.isConfigured
            ? SupabaseTutoringService(Supabase.instance.client)
            : const UnconfiguredTutoringService());
    _router = createRouter(_appState);

    _authService.currentUser().then((user) {
      if (mounted) _appState.setUser(user);
    }).catchError((_) {
      if (mounted) {
        _appState.setStartupError(
          'Could not load your profile. Please check your connection.',
        );
      }
    });

    _authService.authStateChanges.listen(
      (user) {
        if (mounted) _appState.setUser(user);

        // Follow the session: register this device when someone signs in, and
        // drop the token when they leave so the next person on this phone does
        // not receive their reminders.
        if (AppConfig.isConfigured) {
          final client = Supabase.instance.client;
          if (user != null) {
            PushService.registerDevice(client);
          } else {
            PushService.unregisterDevice(client);
          }
        }
      },
      onError: (_) {
        if (mounted) {
          _appState.setStartupError(
            'Could not load your profile. Please check your connection.',
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _appState.dispose();
    _refreshBus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshBusScope(
      bus: _refreshBus,
      child: AppStateScope(
      state: _appState,
      child: AuthServiceScope(
        authService: _authService,
        child: ProfileServiceScope(
          profileService: _profileService,
          child: StudentServiceScope(
            studentService: _studentService,
            child: ParentTeacherRelationshipServiceScope(
              relationshipService: _relationshipService,
              child: TeacherProfileServiceScope(
                teacherProfileService: _teacherProfileService,
                child: TeacherRequestServiceScope(
                  requestService: _teacherRequestService,
                  child: LearningActivityServiceScope(
                    service: _learningActivityService,
                    child: LocationServiceScope(
                    locationService: _locationService,
                    child: TeacherAvailabilityServiceScope(
                    service: _teacherAvailabilityService,
                    child: LessonSessionServiceScope(
                    service: _lessonSessionService,
                    child: PaymentServiceScope(
                    paymentService: _paymentService,
                    child: TutoringServiceScope(
                    tutoringService: _tutoringService,
                    child: AdminServiceScope(
                    adminService: _adminService,
                    child: EarningsServiceScope(
                    earningsService: _earningsService,
                    child: MaterialApp.router(
                      title: 'Camiva',
                      debugShowCheckedModeBanner: false,
                      theme: AppTheme.light,
                      routerConfig: _router,
                      scrollBehavior: const MaterialScrollBehavior().copyWith(
                        dragDevices: {
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.touch,
                          PointerDeviceKind.trackpad,
                          PointerDeviceKind.stylus,
                        },
                      ),
                      localizationsDelegates: const [
                        AppLocalizations.delegate,
                        GlobalMaterialLocalizations.delegate,
                        GlobalWidgetsLocalizations.delegate,
                        GlobalCupertinoLocalizations.delegate,
                      ],
                      supportedLocales: const [
                        Locale('en'),
                      ],
                    ),
                  ),
                  ),
                  ),
                  ),
                  ),
                  ),
                  ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}
