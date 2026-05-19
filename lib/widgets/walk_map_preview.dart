import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/walk_models.dart';
import 'walk_photo_image.dart';

class WalkMapPreview extends StatelessWidget {
  const WalkMapPreview({
    required this.session,
    this.interactive = false,
    this.height = 132,
    this.onPhotoTap,
    this.showAttribution = true,
    super.key,
  });

  final WalkSession session;
  final bool interactive;
  final double height;
  final ValueChanged<WalkPhoto>? onPhotoTap;
  final bool showAttribution;

  @override
  Widget build(BuildContext context) {
    final route = session.route;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: session.center,
            initialZoom: 15,
            interactionOptions: InteractionOptions(
              flags: interactive ? InteractiveFlag.all : InteractiveFlag.none,
            ),
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
                  color: const Color(0xFF1F8A70),
                  strokeWidth: 5,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                ..._directionMarkers(route),
                if (route.isNotEmpty)
                  _dot(route.first, const Color(0xFF151713)),
                if (route.length > 1) _dot(route.last, const Color(0xFFDC5F00)),
                ...session.photos.map(_photoMarker),
              ],
            ),
            if (showAttribution)
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
      ),
    );
  }

  List<Marker> _directionMarkers(List<LatLng> route) {
    if (route.length < 2) {
      return const [];
    }

    const calculator = Distance();
    final maxArrows = height < 180 ? 4 : 18;
    final preferredSpacingMeters = height < 180 ? 90.0 : 45.0;
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
      width: 26,
      height: 26,
      child: Transform.rotate(
        angle: bearingDegrees * math.pi / 180,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1F8A70),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: const Icon(
            Icons.navigation_rounded,
            color: Colors.white,
            size: 15,
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
        onTap: onPhotoTap == null ? null : () => onPhotoTap!(photo),
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
