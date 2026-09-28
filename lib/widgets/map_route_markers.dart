import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/walk_models.dart';
import '../theme/app_theme.dart';
import 'walk_photo_image.dart';

// 지도 위 경로 화살표와 사진 핀. 둘 다 현재 줌을 보고 다시 그린다.
// - 화살표: 미터가 아니라 화면 간격으로 놓아 줌과 관계없이 밀도가 같다.
// - 사진 핀: 꼬리 끝이 촬영 위치를 가리키고, 줌에 따라 완만하게 커지며, 겹치면 묶는다.

/// 줌 16에서의 핀 크기와, 줌이 한 단계 오를 때 커지는 비율.
const _pinBaseSize = 38.0;
const _pinBaseZoom = 16.0;
const _pinGrowthPerZoom = 1.25;
const _pinMinSize = 24.0;
const _pinMaxSize = 64.0;
const _pinTailHeight = 7.0;

/// 뒤에 겹친 카드와 개수 배지가 들어갈 여백.
const _pinPadding = 8.0;

/// 마커에 쓰는 사진은 이 폭으로 줄여 읽는다. 줌마다 다시 읽지 않도록 고정한다.
const _pinDecodeWidth = 200;

/// 줌에 따라 완만하게 커지는 핀 크기. [maxSize]는 작은 지도에서 핀이 지도를 덮지 않게 한다.
double photoPinSize(double zoom, {double maxSize = _pinMaxSize}) {
  final size = _pinBaseSize * math.pow(_pinGrowthPerZoom, zoom - _pinBaseZoom);
  return size.clamp(_pinMinSize, math.max(_pinMinSize, maxSize)).toDouble();
}

/// 화면에서 서로 [distance] 픽셀 안에 있는 사진을 한 묶음으로 모은다.
///
/// 촬영 순서대로 돌면서 가장 먼저 만든 묶음에 붙이므로, 묶음의 위치(첫 사진)가
/// 줌을 바꿔도 크게 흔들리지 않는다.
List<List<WalkPhoto>> clusterPhotos(
  List<WalkPhoto> photos,
  Offset Function(LatLng point) project,
  double distance,
) {
  final sorted = [...photos]..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  final clusters = <List<WalkPhoto>>[];
  final anchors = <Offset>[];
  for (final photo in sorted) {
    final position = project(photo.position);
    var joined = false;
    for (var index = 0; index < clusters.length; index += 1) {
      if ((anchors[index] - position).distance < distance) {
        clusters[index].add(photo);
        joined = true;
        break;
      }
    }
    if (!joined) {
      clusters.add([photo]);
      anchors.add(position);
    }
  }
  return clusters;
}

/// 화면 좌표로 바꾼 경로 위에 [spacing] 픽셀마다 화살표 자리를 잡는다.
/// 돌려주는 값은 (경로 위치의 선분 번호, 선분 안 비율, 진행 방향 라디안)이다.
List<({int segment, double t, double angle})> arrowPlacements(
  List<Offset> projected,
  double spacing, {
  int maxArrows = 80,
}) {
  final placements = <({int segment, double t, double angle})>[];
  if (projected.length < 2) {
    return placements;
  }
  var total = 0.0;
  for (var index = 1; index < projected.length; index += 1) {
    total += (projected[index] - projected[index - 1]).distance;
  }
  // 경로가 화살표 한 칸보다 짧으면 가운데에 하나만 둔다.
  var next = total < spacing ? total / 2 : spacing * 0.6;
  final end = total < spacing ? total / 2 : total - spacing * 0.4;
  var travelled = 0.0;
  for (var index = 1; index < projected.length; index += 1) {
    final from = projected[index - 1];
    final to = projected[index];
    final length = (to - from).distance;
    if (length < 0.5) {
      continue;
    }
    final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
    while (travelled + length >= next &&
        next <= end &&
        placements.length < maxArrows) {
      placements.add(
        (segment: index - 1, t: (next - travelled) / length, angle: angle),
      );
      next += spacing;
    }
    travelled += length;
    if (next > end || placements.length >= maxArrows) {
      break;
    }
  }
  return placements;
}

/// 경로 진행 방향 화살표.
class RouteArrowLayer extends StatelessWidget {
  const RouteArrowLayer({required this.route, this.spacing = 56, super.key});

  final List<LatLng> route;

  /// 화살표 사이 화면 간격(px).
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    // 회전 전 좌표로 방향을 잡는다. 마커가 지도와 함께 돌기 때문에 그대로 맞는다.
    final projected = [for (final point in route) camera.projectAtZoom(point)];
    final markers = <Marker>[];
    for (final place in arrowPlacements(projected, spacing)) {
      final from = route[place.segment];
      final to = route[place.segment + 1];
      markers.add(
        Marker(
          point: LatLng(
            from.latitude + (to.latitude - from.latitude) * place.t,
            from.longitude + (to.longitude - from.longitude) * place.t,
          ),
          width: 16,
          height: 16,
          child: Transform.rotate(angle: place.angle, child: const _Arrow()),
        ),
      );
    }
    return MarkerLayer(markers: markers);
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '>',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: AppColors.brandStrong,
        fontSize: 15,
        fontWeight: FontWeight.w900,
        height: 1,
        shadows: [
          Shadow(color: Colors.white, blurRadius: 3),
          Shadow(color: Colors.white, blurRadius: 3),
        ],
      ),
    );
  }
}

/// 사진 핀. 꼬리 끝이 촬영 위치이고, 지도를 돌려도 똑바로 선다.
class PhotoPinLayer extends StatelessWidget {
  const PhotoPinLayer({
    required this.photos,
    this.maxSize = _pinMaxSize,
    this.onPhotoTap,
    this.onClusterTap,
    super.key,
  });

  final List<WalkPhoto> photos;
  final double maxSize;
  final ValueChanged<WalkPhoto>? onPhotoTap;

  /// 여러 장이 묶인 핀을 눌렀을 때. 없으면 첫 사진을 [onPhotoTap]으로 연다.
  final ValueChanged<List<WalkPhoto>>? onClusterTap;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final size = photoPinSize(camera.zoom, maxSize: maxSize);
    final clusters = clusterPhotos(
      photos,
      (point) => camera.projectAtZoom(point),
      size * 0.9,
    );
    return MarkerLayer(
      rotate: true,
      alignment: Alignment.topCenter,
      markers: [
        for (final cluster in clusters)
          Marker(
            point: cluster.first.position,
            width: size + _pinPadding * 2,
            height: size + _pinPadding + _pinTailHeight,
            child: _PhotoPin(
              photos: cluster,
              size: size,
              onTap: _tapHandler(cluster),
            ),
          ),
      ],
    );
  }

  VoidCallback? _tapHandler(List<WalkPhoto> cluster) {
    if (cluster.length > 1 && onClusterTap != null) {
      return () => onClusterTap!(cluster);
    }
    final open = onPhotoTap;
    return open == null ? null : () => open(cluster.first);
  }
}

class _PhotoPin extends StatelessWidget {
  const _PhotoPin({required this.photos, required this.size, this.onTap});

  final List<WalkPhoto> photos;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final count = photos.length;
    final radius = BorderRadius.circular(size * 0.2);
    final border = size < 32 ? 2.0 : 2.5;
    final shadow = [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.25),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];

    Widget card({Widget? child}) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: radius,
            boxShadow: shadow,
          ),
          padding: EdgeInsets.all(border),
          child: child == null
              ? null
              : ClipRRect(
                  borderRadius: BorderRadius.circular(size * 0.2 - border),
                  child: child,
                ),
        );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(_pinPadding, _pinPadding, _pinPadding, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                // 여러 장이면 뒤에 카드를 비스듬히 겹쳐 묶음임을 보여 준다.
                if (count > 2)
                  Transform.translate(
                      offset: const Offset(5, -5), child: card()),
                if (count > 1)
                  Transform.translate(
                      offset: const Offset(2.5, -2.5), child: card()),
                card(
                  child: WalkPhotoImage(
                    imageUrl: photos.first.imageUrl,
                    fit: BoxFit.cover,
                    decodeWidth: _pinDecodeWidth,
                  ),
                ),
                if (count > 1)
                  Positioned(
                    top: -_pinPadding + 1,
                    right: -_pinPadding + 1,
                    child: _CountBadge(count: count),
                  ),
              ],
            ),
            const CustomPaint(
              size: Size(12, _pinTailHeight),
              painter: _TailPainter(),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: AppColors.brand,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

/// 카드 아래의 흰 삼각형 꼬리. 끝이 정확히 촬영 위치에 닿는다.
class _TailPainter extends CustomPainter {
  const _TailPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.4), 1.5, false);
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_TailPainter oldDelegate) => false;
}
