import 'package:flutter/widgets.dart';
import '../constants/cameroon_locations.dart';
import '../models/app_user.dart';
import '../models/user_role.dart';
import '../services/geo.dart';

/// Application-level state.
///
/// It holds the authenticated [AppUser].
///
/// [activeRole] derives from [currentUser.activeRole] when authenticated.
/// When signed out there is no role; the getter falls back to
/// [UserRole.parent] purely as a non-null default and callers must not treat
/// a signed-out session as a real parent.
///
/// The router listens to [authStateChanges] on [AuthService] directly.
/// [AppState] is the widget-tree source of truth for the current user.
class AppState extends ChangeNotifier {
  AppUser? _currentUser;
  bool _hasResolvedInitialAuth = false;
  String? _startupError;
  final ValueNotifier<int> _routingRevision = ValueNotifier<int>(0);

  /// A listenable that only fires when auth or onboarding states change,
  /// preventing GoRouter from re-evaluating routes on badge/notification count
  /// or filter updates.
  Listenable get routingListenable => _routingRevision;

  void _notifyRouting() {
    _routingRevision.value++;
  }

  GeoPoint? _parentLocation;
  String? _parentCity;
  String? _parentArea;

  GeoPoint? get parentLocation => _parentLocation;
  String? get parentCity => _parentCity;
  String? get parentArea => _parentArea;

  int _unreadUpdatesCount = 0;
  int _pendingRequestsCount = 0;

  int get unreadUpdatesCount => _unreadUpdatesCount;
  int get pendingRequestsCount => _pendingRequestsCount;
  int get totalNotificationCount => _unreadUpdatesCount + _pendingRequestsCount;

  void setNotificationCounts({int? unreadUpdates, int? pendingRequests}) {
    bool changed = false;
    if (unreadUpdates != null && unreadUpdates != _unreadUpdatesCount) {
      _unreadUpdatesCount = unreadUpdates;
      changed = true;
    }
    if (pendingRequests != null && pendingRequests != _pendingRequestsCount) {
      _pendingRequestsCount = pendingRequests;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  void setParentLocation({GeoPoint? point, String? city, String? area}) {
    _parentLocation = point ?? (city != null ? CameroonLocations.cityCoordinates[city] : null);
    _parentCity = city;
    _parentArea = area;
    notifyListeners();
  }

  AppUser? get currentUser => _currentUser;
  bool get hasResolvedInitialAuth => _hasResolvedInitialAuth;
  String? get startupError => _startupError;

  UserRole? _pendingRole;

  /// The role the user picked on the Register screen, carried into onboarding
  /// so they are not asked the same question twice.
  ///
  /// In-memory only: when email confirmation is on, the user signs in in a
  /// fresh session and onboarding simply asks again rather than assuming.
  UserRole? get pendingRole => _pendingRole;

  void setPendingRole(UserRole? role) {
    if (_pendingRole == role) return;
    _pendingRole = role;
    notifyListeners();
    _notifyRouting();
  }

  UserRole get activeRole => _currentUser?.activeRole ?? UserRole.parent;

  bool get isAuthenticated => _currentUser != null;

  /// True when the user has completed onboarding.
  /// False for newly registered users who still need to confirm name + role.
  bool get profileComplete => _currentUser?.profileComplete ?? false;

  void setUser(AppUser? user) {
    _currentUser = user;
    _startupError = null;
    _hasResolvedInitialAuth = true;
    notifyListeners();
    _notifyRouting();
  }

  void setStartupError(String message) {
    _currentUser = null;
    _startupError = message;
    _hasResolvedInitialAuth = true;
    notifyListeners();
    _notifyRouting();
  }

  @override
  void dispose() {
    _routingRevision.dispose();
    super.dispose();
  }

  /// Convenience accessor — requires [AppStateScope] in the widget tree.
  /// Subscribes the calling [BuildContext] to updates.
  static AppState of(BuildContext context) => AppStateScope.of(context);

  /// Convenience accessor that returns [AppState] WITHOUT subscribing the
  /// calling [BuildContext] to updates. Use in callbacks, services, and
  /// lifecycle methods where rebuilds on state change are not wanted.
  static AppState read(BuildContext context) => AppStateScope.read(context);
}

/// Makes [AppState] available to the widget tree via [InheritedNotifier].
class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({
    super.key,
    required AppState state,
    required super.child,
  }) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'No AppStateScope found in widget tree.');
    return scope!.notifier!;
  }

  static AppState read(BuildContext context) {
    final scope =
        context.getInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'No AppStateScope found in widget tree.');
    return scope!.notifier!;
  }
}
