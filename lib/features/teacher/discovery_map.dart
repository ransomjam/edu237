import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:edu237/l10n/app_localizations.dart';

import '../../core/config/map_tile_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/geo.dart';
import '../../core/services/teacher_discovery.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'discovery_widgets.dart';

/// The discovery map. Renders clean avatar markers for teachers that could be
/// placed, highlights the selected teacher, and animates a gentle pan when the
/// selection changes.
///
/// The tile layer is described entirely by [MapTileConfig] so the provider can
/// be swapped without touching this widget. If tiles fail to load, a small
/// banner points the parent to the List view — the map is never a single point
/// of failure.
class DiscoveryMap extends StatefulWidget {
  const DiscoveryMap({
    super.key,
    required this.teachers,
    required this.selectedTeacherId,
    required this.onSelect,
    this.parentLocation,
    this.tileConfig = MapTileConfig.osm,
  });

  final List<DiscoveryTeacher> teachers;
  final String? selectedTeacherId;
  final ValueChanged<String> onSelect;
  final GeoPoint? parentLocation;
  final MapTileConfig tileConfig;

  @override
  State<DiscoveryMap> createState() => _DiscoveryMapState();
}

class _DiscoveryMapState extends State<DiscoveryMap>
    with TickerProviderStateMixin {
  final MapController _controller = MapController();
  AnimationController? _animController;
  bool _tilesFailed = false;
  bool _ready = false;

  Iterable<DiscoveryTeacher> get _located =>
      widget.teachers.where((t) => t.hasLocation);

  @override
  void didUpdateWidget(DiscoveryMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedTeacherId != oldWidget.selectedTeacherId &&
        widget.selectedTeacherId != null) {
      final target = _located.firstWhere(
        (t) => t.teacher.userId == widget.selectedTeacherId,
        orElse: () => widget.teachers.first,
      );
      final loc = target.location;
      if (loc != null && _ready) {
        _animatedMove(LatLng(loc.latitude, loc.longitude), 14.5);
      }
    }
  }

  /// A gentle, natural pan/zoom to [dest] (flutter_map's [MapController.move]
  /// is instant, so we interpolate ourselves).
  void _animatedMove(LatLng dest, double destZoom) {
    _animController?.dispose();
    final startCenter = _controller.camera.center;
    final startZoom = _controller.camera.zoom;
    final latTween =
        Tween<double>(begin: startCenter.latitude, end: dest.latitude);
    final lngTween =
        Tween<double>(begin: startCenter.longitude, end: dest.longitude);
    final zoomTween = Tween<double>(begin: startZoom, end: destZoom);

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    final curved = CurvedAnimation(parent: controller, curve: Curves.easeInOut);
    controller.addListener(() {
      _controller.move(
        LatLng(latTween.evaluate(curved), lngTween.evaluate(curved)),
        zoomTween.evaluate(curved),
      );
    });
    controller.forward();
    _animController = controller;
  }

  LatLng _initialCenter() {
    if (widget.selectedTeacherId != null) {
      final sel = _located.where(
          (t) => t.teacher.userId == widget.selectedTeacherId);
      if (sel.isNotEmpty) {
        final l = sel.first.location!;
        return LatLng(l.latitude, l.longitude);
      }
    }
    if (widget.parentLocation != null) {
      return LatLng(
          widget.parentLocation!.latitude, widget.parentLocation!.longitude);
    }
    final located = _located.toList();
    if (located.isNotEmpty) {
      final avgLat = located
              .map((t) => t.location!.latitude)
              .reduce((a, b) => a + b) /
          located.length;
      final avgLng = located
              .map((t) => t.location!.longitude)
              .reduce((a, b) => a + b) /
          located.length;
      return LatLng(avgLat, avgLng);
    }
    // Default: Yaoundé.
    return const LatLng(3.8480, 11.5021);
  }

  @override
  void dispose() {
    _animController?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cfg = widget.tileConfig;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: _initialCenter(),
              initialZoom: widget.selectedTeacherId != null ? 14.0 : 12.0,
              minZoom: cfg.minZoom,
              maxZoom: cfg.maxZoom,
              backgroundColor: AppColors.grey100,
              onMapReady: () {
                if (mounted) setState(() => _ready = true);
              },
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom |
                    InteractiveFlag.drag |
                    InteractiveFlag.doubleTapZoom |
                    InteractiveFlag.flingAnimation,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: cfg.urlTemplate,
                userAgentPackageName: cfg.userAgentPackageName,
                maxZoom: cfg.maxZoom,
                errorTileCallback: (tile, error, stackTrace) {
                  if (!_tilesFailed && mounted) {
                    // Defer to avoid setState during build/layout.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _tilesFailed = true);
                    });
                  }
                },
              ),
              if (widget.parentLocation != null)
                MarkerLayer(markers: [_parentMarker(widget.parentLocation!)]),
              MarkerLayer(markers: _teacherMarkers()),
            ],
          ),

          // Attribution (required by OSM licence).
          Positioned(
            right: 6,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
              ),
              child: Text(l10n.discoveryMapAttributionOsm,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.grey700, fontSize: 9)),
            ),
          ),

          if (_tilesFailed)
            Positioned(
              left: AppConstants.space12,
              right: AppConstants.space12,
              top: AppConstants.space12,
              child: _MapBanner(
                title: l10n.discoveryMapUnavailableTitle,
                body: l10n.discoveryMapUnavailableBody,
              ),
            ),
        ],
      ),
    );
  }

  List<Marker> _teacherMarkers() {
    return _located.map((t) {
      final selected = t.teacher.userId == widget.selectedTeacherId;
      final loc = t.location!;
      return Marker(
        point: LatLng(loc.latitude, loc.longitude),
        width: 64,
        height: 64,
        alignment: Alignment.center,
        // Selected marker paints last (on top).
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onSelect(t.teacher.userId),
          child: TeacherMapMarker(
            name: t.teacher.fullNameWithTitle,
            imageUrl: t.teacher.photoUrl,
            selected: selected,
            isBest: t.isBestMatch,
          ),
        ),
      );
    }).toList()
      // Ensure the selected marker is drawn on top.
      ..sort((a, b) {
        final aSel = _isSelectedMarker(a);
        final bSel = _isSelectedMarker(b);
        if (aSel == bSel) return 0;
        return aSel ? 1 : -1;
      });
  }

  bool _isSelectedMarker(Marker m) {
    final child = m.child;
    return child is GestureDetector &&
        child.child is TeacherMapMarker &&
        (child.child as TeacherMapMarker).selected;
  }

  Marker _parentMarker(GeoPoint p) {
    return Marker(
      point: LatLng(p.latitude, p.longitude),
      width: 26,
      height: 26,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.25),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.white, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapBanner extends StatelessWidget {
  const _MapBanner({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.space12),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.map_outlined, color: AppColors.warning, size: 18),
          const SizedBox(width: AppConstants.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTextStyles.label
                        .copyWith(color: AppColors.warning)),
                Text(body, style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
