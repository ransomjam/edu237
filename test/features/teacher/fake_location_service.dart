import 'package:edu237/core/services/geo.dart';
import 'package:edu237/core/services/location_service.dart';

/// A deterministic [LocationService] for tests. Defaults to "denied" (matching
/// the safe production default) but can be primed to return a fixed point.
class FakeLocationService implements LocationService {
  FakeLocationService({this.result = LocationResult.denied});

  LocationResult result;

  /// Convenience: a service that reports a known position.
  factory FakeLocationService.at(double lat, double lng) => FakeLocationService(
        result: LocationResult(LocationStatus.success, GeoPoint(lat, lng)),
      );

  int calls = 0;

  @override
  Future<LocationResult> currentPosition() async {
    calls++;
    return result;
  }
}
