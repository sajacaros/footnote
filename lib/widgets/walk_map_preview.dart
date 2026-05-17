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
                  points: session.route,
                  color: const Color(0xFF1F8A70),
                  strokeWidth: 5,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                if (session.route.isNotEmpty)
                  _dot(session.route.first, const Color(0xFF151713)),
                if (session.route.length > 1)
                  _dot(session.route.last, const Color(0xFFDC5F00)),
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
