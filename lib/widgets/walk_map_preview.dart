import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/walk_models.dart';
import 'walk_photo_image.dart';

class WalkMapPreview extends StatefulWidget {
  const WalkMapPreview({
    required this.session,
    this.interactive = false,
    this.height = 132,
    this.onPhotoTap,
    this.showAttribution = true,
    this.showPhotoMarkers = true,
    this.fitRoute = false,
    this.maxAutoFitZoom,
    super.key,
  });

  final WalkSession session;
  final bool interactive;
  final double height;
  final ValueChanged<WalkPhoto>? onPhotoTap;
  final bool showAttribution;
  final bool showPhotoMarkers;
  final bool fitRoute;
  final double? maxAutoFitZoom;

  @override
  State<WalkMapPreview> createState() => _WalkMapPreviewState();
}

class _WalkMapPreviewState extends State<WalkMapPreview> {
  final MapController _mapController = MapController();
  double _rotationDegrees = 0;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.session.route;
    final initialCameraFit = _initialCameraFit(route);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.session.center,
                initialZoom: 15,
                initialCameraFit: initialCameraFit,
                interactionOptions: InteractionOptions(
                  flags: widget.interactive
                      ? InteractiveFlag.all
                      : InteractiveFlag.none,
                ),
                onPositionChanged: _handlePositionChanged,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.footnote.walk',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: route,
                      color: const Color(0x661F8A70),
                      strokeWidth: 2.2,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    ..._directionMarkers(route),
                    if (route.isNotEmpty)
                      _dot(route.first, const Color(0xFF151713)),
                    if (route.length > 1)
                      _dot(route.last, const Color(0xFFDC5F00)),
                    if (widget.showPhotoMarkers)
                      ...widget.session.photos.map(_photoMarker),
                  ],
                ),
                if (widget.showAttribution)
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution(
                        'OpenStreetMap contributors | CARTO',
                        onTap: () {},
                      ),
                    ],
                  ),
              ],
            ),
            if (widget.interactive)
              _CompassButton(
                rotationDegrees: _rotationDegrees,
                onPressed: _resetRotation,
              ),
          ],
        ),
      ),
    );
  }

  CameraFit? _initialCameraFit(List<LatLng> route) {
    if (!widget.fitRoute || route.length < 2) {
      return null;
    }

    return CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(route),
      maxZoom: widget.maxAutoFitZoom,
      padding: EdgeInsets.fromLTRB(
        28,
        28,
        28,
        widget.interactive ? 62 : 28,
      ),
    );
  }

  void _handlePositionChanged(MapCamera camera, bool hasGesture) {
    if (!widget.interactive) {
      return;
    }

    final rotation = _normalizeDegrees(camera.rotation);
    if ((rotation - _rotationDegrees).abs() < 0.25) {
      return;
    }

    setState(() {
      _rotationDegrees = rotation;
    });
  }

  void _resetRotation() {
    _mapController.rotate(0);
    setState(() {
      _rotationDegrees = 0;
    });
  }

  double _normalizeDegrees(double value) {
    final normalized = value % 360;
    if (normalized < 0) {
      return normalized + 360;
    }
    return normalized;
  }

  List<Marker> _directionMarkers(List<LatLng> route) {
    if (route.length < 2) {
      return const [];
    }

    const calculator = Distance();
    final maxArrows = widget.height < 180 ? 8 : 42;
    final preferredSpacingMeters = widget.height < 180 ? 55.0 : 22.0;
    var routeMeters = 0.0;

    for (var index = 1; index < route.length; index += 1) {
      routeMeters += calculator(route[index - 1], route[index]);
    }
    if (routeMeters < 6) {
      return const [];
    }

    final arrowCount = math.min(
      maxArrows,
      math.max(1, (routeMeters / preferredSpacingMeters).floor()),
    );
    final spacingMeters = routeMeters / (arrowCount + 1);
    final markers = <Marker>[];
    var traveledMeters = 0.0;
    var nextTargetMeters = spacingMeters;

    for (var index = 1; index < route.length; index += 1) {
      final start = route[index - 1];
      final end = route[index];
      final segmentMeters = calculator(start, end);
      if (segmentMeters < 1) {
        continue;
      }

      while (traveledMeters + segmentMeters >= nextTargetMeters &&
          markers.length < arrowCount) {
        final progress = (nextTargetMeters - traveledMeters) / segmentMeters;
        final point = LatLng(
          start.latitude + (end.latitude - start.latitude) * progress,
          start.longitude + (end.longitude - start.longitude) * progress,
        );
        markers.add(_directionArrow(point, calculator.bearing(start, end)));
        nextTargetMeters += spacingMeters;
      }

      traveledMeters += segmentMeters;
      if (markers.length >= arrowCount) {
        break;
      }
    }

    return markers;
  }

  Marker _directionArrow(LatLng point, double bearingDegrees) {
    return Marker(
      point: point,
      width: 16,
      height: 16,
      child: Transform.rotate(
        angle: (bearingDegrees - 90) * math.pi / 180,
        child: const Text(
          '>',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF1F8A70),
            fontSize: 15,
            fontWeight: FontWeight.w900,
            height: 1,
            shadows: [
              Shadow(color: Colors.white, blurRadius: 3),
              Shadow(color: Colors.white, blurRadius: 3),
            ],
          ),
        ),
      ),
    );
  }

  Marker _dot(LatLng point, Color color) {
    return Marker(
      point: point,
      width: 18,
      height: 18,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
        ),
      ),
    );
  }

  Marker _photoMarker(WalkPhoto photo) {
    return Marker(
      point: photo.position,
      width: 42,
      height: 42,
      child: GestureDetector(
        onTap:
            widget.onPhotoTap == null ? null : () => widget.onPhotoTap!(photo),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: WalkPhotoImage(imageUrl: photo.imageUrl, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}

class _CompassButton extends StatelessWidget {
  const _CompassButton({
    required this.rotationDegrees,
    required this.onPressed,
  });

  final double rotationDegrees;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 36,
      child: IconButton.filledTonal(
        tooltip: '북쪽으로 정렬',
        style: IconButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF151713),
          minimumSize: const Size(42, 42),
          fixedSize: const Size(42, 42),
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.22),
        ),
        onPressed: onPressed,
        icon: Transform.rotate(
          angle: -rotationDegrees * math.pi / 180,
          child: const Icon(Icons.explore_rounded, size: 23),
        ),
      ),
    );
  }
}
