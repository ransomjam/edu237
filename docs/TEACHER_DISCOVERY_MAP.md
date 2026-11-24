# Teacher Discovery + Map

A parent goes **Child → Find a Teacher** and lands on a discovery experience that
ranks real teacher profiles by relevance to the child (Form + subjects), shows an
approximate location on a map, and lets them switch **Map | List**. Location is
optional — everything works without it.

## Architecture (Screen → Service → Supabase)

Logic is kept out of the screens:

- `core/services/teacher_matching.dart` — transparent relevance scoring (unchanged).
- `core/services/teacher_discovery.dart` — `buildDiscovery(...)`: attaches an
  approximate location + distance, applies the small filters, and orders results.
  `DiscoveryTeacher` is the view model both Map and List render.
- `core/services/geo.dart` — `GeoPoint`, Haversine `distanceKm`, friendly
  `formatDistance` (rounded so it's never falsely precise).
- `core/constants/cameroon_places.dart` — a tiny gazetteer (town/area centroids)
  so a teacher with only a coarse city still gets a map pin.
- `core/services/location_service.dart` — device location behind an interface
  (`GeolocatorLocationService` / `UnavailableLocationService` / fakes). Permission
  is requested **lazily** (only when the parent taps *Nearby*, or a teacher pins
  their area), never on launch. Any non-success result degrades gracefully.
- `features/teacher/discovery_map.dart` — the `flutter_map` widget.
- `features/teacher/discovery_widgets.dart` — cards, badges, markers.

## Map / tile provider decision

Map layer: **`flutter_map`** (OSM-compatible; no Google Maps).

Tiles are described entirely by `core/config/map_tile_config.dart` so the provider
can be swapped without touching any screen. The MVP uses the keyless standard
OpenStreetMap raster tiles:

```
https://tile.openstreetmap.org/{z}/{x}/{y}.png
```

- **Why:** no API key/secret, works immediately, fine for a low-traffic MVP.
- **Policy:** OSM asks for an identifying `User-Agent` (set via
  `userAgentPackageName` on the tile layer) and discourages bulk use. When traffic
  grows, switch to a keyed provider (MapTiler / Stadia / self-hosted) by editing
  **only** `MapTileConfig.osm`.
- **No secrets are hardcoded.** Attribution ("© OpenStreetMap") is shown on the map.

The map is never a single point of failure: the **List** view is always one tap
away, teachers without coordinates still appear in the list, and tile-load failures
surface a small banner pointing to the list.

## Location data model (teacher-owned)

`teacher_profiles` (migration `20260813000000_teacher_map_fields.sql`, additive):

| Column          | Meaning                                                        |
|-----------------|----------------------------------------------------------------|
| `city`, `area`  | Coarse location (pre-existing).                                |
| `latitude`      | **Approximate** service-area latitude (optional, nullable).    |
| `longitude`     | **Approximate** service-area longitude (optional, nullable).   |
| `teaching_mode` | `online` \| `in_person` \| `both` (default `in_person`).       |
| `photo_url`     | Optional avatar; discovery falls back to initials.             |

Coordinates describe a **teaching/service area, never a home address**. When a
teacher pins their area from the device, we round to 2 decimals (~1 km) so a
precise home is never stored. The UI states "Teaching area — not a home address."

## Security / RLS

**No RLS changes.** The new columns are teacher-owned profile fields covered by the
existing `teacher_profiles` policies:

- any authenticated user may **read** (discovery);
- only the owner (`auth.uid() = user_id`) may **insert/update**.

Parents read the coarse location for discovery but can never write it. No precise
residential location is stored or exposed. A `check` constraint keeps
`teaching_mode` to the known set.

## Deliberately out of scope

Turn-by-turn / routing, live tracking, exact house locations, chat, payments,
ratings/reviews, push notifications, map analytics. This is simply: find a suitable
teacher near me → understand them → request them.
