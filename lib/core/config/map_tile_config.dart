/// Abstract description of a raster tile source for the discovery map.
///
/// The map layer is kept behind this small config so the tile provider can be
/// swapped later (e.g. to a keyed provider such as MapTiler / Stadia, or a
/// self-hosted style) WITHOUT touching any screen. No secrets are hardcoded;
/// the MVP uses a keyless OSM-compatible source.
///
/// ── Provider decision (MVP) ───────────────────────────────────────────────
/// We use the standard OpenStreetMap raster tiles:
///   https://tile.openstreetmap.org/{z}/{x}/{y}.png
///
/// Why: it needs no API key or secret, works immediately, and is fine for a
/// low-traffic MVP being tested on a device. OSM's tile usage policy asks for a
/// valid identifying User-Agent (set via [userAgentPackageName] on the tile
/// layer) and discourages heavy/bulk use. When Camiva grows we should move to a
/// keyed provider — because the map is isolated behind this config and the
/// [DiscoveryMap] widget, that is a one-line change here.
class MapTileConfig {
  const MapTileConfig({
    required this.urlTemplate,
    required this.attribution,
    this.userAgentPackageName = 'com.edu237.app',
    this.maxZoom = 19,
    this.minZoom = 3,
    this.fallbackUrlTemplate,
  });

  /// Tile URL template, using {x}/{y}/{z} placeholders.
  final String urlTemplate;

  /// Optional secondary template used if a tile fails to load.
  final String? fallbackUrlTemplate;

  /// Short attribution text shown on the map (required by OSM's licence).
  final String attribution;

  /// Identifies the app to the tile server (OSM policy). Not a secret.
  final String userAgentPackageName;

  final double maxZoom;
  final double minZoom;

  /// The default MVP provider: standard OpenStreetMap tiles.
  static const MapTileConfig osm = MapTileConfig(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap contributors',
  );
}
