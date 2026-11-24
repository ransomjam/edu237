import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import 'geo.dart';

/// Outcome of asking for the device's current location.
enum LocationStatus {
  /// We have a position.
  success,

  /// The user declined the permission. Discovery must still work.
  denied,

  /// Location services are switched off on the device.
  servicesDisabled,

  /// Something else went wrong (timeout, platform error).
  error,
}

/// Result of a location request: a status plus an optional point.
class LocationResult {
  const LocationResult(this.status, [this.point]);

  final LocationStatus status;
  final GeoPoint? point;

  bool get isSuccess => status == LocationStatus.success && point != null;

  static const LocationResult denied = LocationResult(LocationStatus.denied);
  static const LocationResult servicesDisabled =
      LocationResult(LocationStatus.servicesDisabled);
  static const LocationResult error = LocationResult(LocationStatus.error);
}

/// Device-location access, behind an interface so screens never touch the
/// geolocator plugin directly and tests can inject a deterministic fake.
///
/// Permission is requested lazily — only when the user opts into something that
/// needs it (tapping "Nearby", or a teacher pinning their area) — never on app
/// launch. Callers must treat any non-success result as "no location" and keep
/// working.
abstract class LocationService {
  Future<LocationResult> currentPosition();
}

/// Real implementation backed by the `geolocator` plugin.
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationResult> currentPosition() async {
    try {
      final servicesOn = await Geolocator.isLocationServiceEnabled();
      if (!servicesOn) return LocationResult.servicesDisabled;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return LocationResult.denied;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return LocationResult(
        LocationStatus.success,
        GeoPoint(position.latitude, position.longitude),
      );
    } catch (_) {
      return LocationResult.error;
    }
  }
}

/// A no-op implementation used when the backend isn't configured or in tests
/// that don't care about location — always reports "denied" so discovery falls
/// back to the coarse-city experience.
class UnavailableLocationService implements LocationService {
  const UnavailableLocationService();

  @override
  Future<LocationResult> currentPosition() async => LocationResult.denied;
}

/// Injects a [LocationService] into the widget tree, mirroring the other
/// service scopes.
class LocationServiceScope extends InheritedWidget {
  const LocationServiceScope({
    super.key,
    required this.locationService,
    required super.child,
  });

  final LocationService locationService;

  static LocationService of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<LocationServiceScope>();
    assert(scope != null, 'No LocationServiceScope found in widget tree.');
    return scope!.locationService;
  }

  @override
  bool updateShouldNotify(LocationServiceScope oldWidget) =>
      locationService != oldWidget.locationService;
}
