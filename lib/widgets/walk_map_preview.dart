import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:latlong2/latlong.dart';

import '../models/walk_models.dart';
import '../services/basemap.dart';
import '../theme/app_theme.dart';
import 'map_route_markers.dart';

class WalkMapPreview extends StatefulWidget {
  const WalkMapPreview({
    required this.session,
    this.interactive = false,
    this.height = 132,
    this.onPhotoTap,
    this.compactAttribution = false,
    this.showPhotoMarkers = true,
    this.fitRoute = false,
    this.maxAutoFitZoom,
    this.onToggleFullscreen,
    this.isFullscreen = false,
    this.rounded = true,
    this.controlsTop = 10,
    this.extraControls = const [],
    super.key,
  });

  final WalkSession session;
  final bool interactive;
  final double height;
  final ValueChanged<WalkPhoto>? onPhotoTap;

  /// 목록 썸네일처럼 작은 지도에서는 접히는 버튼 대신 작은 고정 표기를 쓴다.
  final bool compactAttribution;
  final bool showPhotoMarkers;
  final bool fitRoute;
  final double? maxAutoFitZoom;

  /// 있으면 최대화(또는 최대화 화면에서는 닫기) 버튼을 보여 준다.
  final VoidCallback? onToggleFullscreen;
  final bool isFullscreen;
  final bool rounded;

  /// 오른쪽 위 버튼 묶음의 위쪽 여백. 지도 위에 상단바가 겹치는 화면에서 그만큼 내린다.
  final double controlsTop;

  /// 버튼 묶음 맨 위에 더 넣을 버튼(예: 최대화 화면의 화면 돌리기).
  final List<Widget> extraControls;

  @override
  State<WalkMapPreview> createState() => _WalkMapPreviewState();
}

class _WalkMapPreviewState extends State<WalkMapPreview>
    with SingleTickerProviderStateMixin {
  static const _initialZoom = 15.0;
  static const _gestureSources = {
    MapEventSource.dragStart,
    MapEventSource.onDrag,
    MapEventSource.multiFingerGestureStart,
    MapEventSource.onMultiFinger,
    MapEventSource.doubleTap,
    MapEventSource.doubleTapHold,
    MapEventSource.scrollWheel,
  };

  final MapController _mapController = MapController();
  late final AnimationController _cameraAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  double _rotationDegrees = 0;

  @override
  void dispose() {
    _cameraAnimation.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.session.route;
    final initialCameraFit = _initialCameraFit(route);
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.rounded ? 8 : 0),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.session.center,
                initialZoom: _initialZoom,
                initialCameraFit: initialCameraFit,
                interactionOptions: InteractionOptions(
                  flags: widget.interactive
                      ? InteractiveFlag.all
                      : InteractiveFlag.none,
                ),
                // 회전은 onPositionChanged로 오지 않아서(코드로 돌릴 때 포함) 모든 이벤트를 받는다.
                onMapEvent: _handleMapEvent,
              ),
              children: [
                ValueListenableBuilder<vt.Style?>(
                  valueListenable: Basemap.instance.style,
                  builder: (context, style, _) => style == null
                      // 스타일을 못 불러왔을 때만 쓰는 대체 지도.
                      ? TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.footnote.walk',
                          tileBuilder: _mutedTileBuilder,
                        )
                      : vt.VectorTileLayer(
                          theme: style.theme,
                          tileProviders: style.providers,
                          rasterSources: style.rasterSources,
                          sprites: style.sprites,
                        ),
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: route,
                      color: AppColors.brand.withValues(alpha: 0.7),
                      strokeWidth: 3.5,
                      borderColor: Colors.white,
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),
                RouteArrowLayer(
                  route: route,
                  spacing: widget.height < 180 ? 44 : 56,
                ),
                MarkerLayer(
                  markers: [
                    if (route.isNotEmpty) _dot(route.first, AppColors.ink),
                    if (route.length > 1) _dot(route.last, AppColors.routeEnd),
                  ],
                ),
                if (widget.showPhotoMarkers)
                  PhotoPinLayer(
                    photos: widget.session.photos,
                    // 목록 썸네일처럼 작은 지도에서는 핀이 지도를 덮지 않게 줄인다.
                    maxSize: math.min(64, widget.height * 0.3),
                    onPhotoTap: widget.onPhotoTap,
                    onClusterTap: widget.interactive ? _zoomToPhotos : null,
                  ),
                if (widget.compactAttribution)
                  const _CompactAttribution()
                else
                  // 스타일이 늦게 준비돼도 출처 표기가 따라 바뀌게 한다.
                  ValueListenableBuilder<vt.Style?>(
                    valueListenable: Basemap.instance.style,
                    builder: (context, style, _) => RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution(
                          style == null
                              ? 'OpenStreetMap contributors'
                              : Basemap.attribution,
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (widget.interactive)
              Positioned(
                top: widget.controlsTop,
                right: 10 + MediaQuery.paddingOf(context).right,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final control in widget.extraControls) ...[
                      control,
                      const SizedBox(height: 6),
                    ],
                    if (widget.onToggleFullscreen != null) ...[
                      MapControlButton(
                        tooltip: widget.isFullscreen ? '지도 작게 보기' : '지도 크게 보기',
                        onPressed: widget.onToggleFullscreen!,
                        child: Icon(
                          widget.isFullscreen
                              ? Icons.close_fullscreen_rounded
                              : Icons.open_in_full_rounded,
                          size: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    MapControlButton(
                      tooltip: '지도 처음 위치로',
                      onPressed: _resetView,
                      child: const SizedBox.square(
                        dimension: 20,
                        child: CustomPaint(painter: _TargetIconPainter()),
                      ),
                    ),
                    const SizedBox(height: 6),
                    MapControlButton(
                      tooltip: '북쪽을 위로',
                      onPressed: _resetRotation,
                      child: _CompassNeedle(rotationDegrees: _rotationDegrees),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 대체 지도(OSM 기본 타일)는 채도가 높아 경로가 묻히므로 채도를 낮추고 밝게 누른다.
  static Widget _mutedTileBuilder(
    BuildContext context,
    Widget tileWidget,
    TileImage tile,
  ) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(_mutedTileMatrix),
      child: tileWidget,
    );
  }

  CameraFit? _initialCameraFit(List<LatLng> route) {
    if (!widget.fitRoute || route.length < 2) {
      return null;
    }

    return CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(route),
      maxZoom: widget.maxAutoFitZoom,
      padding: const EdgeInsets.all(28),
    );
  }

  void _handleMapEvent(MapEvent event) {
    if (!widget.interactive) {
      return;
    }
    // 되돌아가는 중에 사용자가 지도를 만지면 손동작을 우선한다.
    if (_gestureSources.contains(event.source) &&
        _cameraAnimation.isAnimating) {
      _cameraAnimation.stop();
    }

    final rotation = _normalizeDegrees(event.camera.rotation);
    if ((rotation - _rotationDegrees).abs() < 0.25) {
      return;
    }

    setState(() {
      _rotationDegrees = rotation;
    });
  }

  /// 방향만 북쪽으로 돌린다. 중심과 확대는 건드리지 않는다.
  void _resetRotation() {
    var from = _normalizeDegrees(_mapController.camera.rotation);
    if (from > 180) {
      from -= 360;
    }
    final rotationTween = Tween(begin: from, end: 0.0);
    _runAnimation(
      (t) => _mapController.rotate(rotationTween.transform(t)),
    );
  }

  /// 묶인 사진들이 펼쳐지도록 확대한다. 거의 같은 곳이라 더 펼칠 수 없으면 첫 사진을 연다.
  void _zoomToPhotos(List<WalkPhoto> photos) {
    final camera = _mapController.camera;
    final bounds = LatLngBounds.fromPoints(
      photos.map((photo) => photo.position).toList(),
    );
    final target = CameraFit.bounds(
      bounds: bounds,
      maxZoom: 19,
      padding: const EdgeInsets.all(72),
    ).fit(camera);
    if (target.zoom - camera.zoom < 0.5) {
      widget.onPhotoTap?.call(photos.first);
      return;
    }
    _animateCamera(target.center, target.zoom, camera.rotation);
  }

  /// 처음 열었을 때의 화면(경로 전체, 북쪽 위)으로 돌아간다.
  void _resetView() {
    final route = widget.session.route;
    final fit = _initialCameraFit(route) ??
        (route.length >= 2
            // 기록 중 지도처럼 fitRoute가 꺼져 있어도 경로가 있으면 경로 전체를 보여 준다.
            ? CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(route),
                maxZoom: widget.maxAutoFitZoom ?? 17,
                padding: const EdgeInsets.all(28),
              )
            : null);
    if (fit == null) {
      _animateCamera(widget.session.center, _initialZoom, 0);
      return;
    }
    // 회전이 없는 상태를 기준으로 맞춰야 경로가 화면에 딱 들어온다.
    final target = fit.fit(_mapController.camera.withRotation(0));
    _animateCamera(target.center, target.zoom, 0);
  }

  void _animateCamera(LatLng center, double zoom, double rotation) {
    final start = _mapController.camera;
    final latTween = Tween(begin: start.center.latitude, end: center.latitude);
    final lngTween =
        Tween(begin: start.center.longitude, end: center.longitude);
    final zoomTween = Tween(begin: start.zoom, end: zoom);
    // 350°→0°를 거꾸로 한 바퀴 돌지 않도록 가까운 쪽으로 돈다.
    var fromRotation = _normalizeDegrees(start.rotation);
    if (fromRotation - rotation > 180) {
      fromRotation -= 360;
    }
    final rotationTween = Tween(begin: fromRotation, end: rotation);
    _runAnimation(
      (t) => _mapController.moveAndRotate(
        LatLng(latTween.transform(t), lngTween.transform(t)),
        zoomTween.transform(t),
        rotationTween.transform(t),
      ),
    );
  }

  /// [apply]에 0→1로 부드럽게 변하는 값을 넘겨 준다.
  void _runAnimation(void Function(double t) apply) {
    final curve = CurvedAnimation(
      parent: _cameraAnimation,
      curve: Curves.easeInOutCubic,
    );
    void tick() => apply(curve.value);

    _cameraAnimation
      ..stop()
      ..reset();
    curve.addListener(tick);
    _cameraAnimation.forward().whenCompleteOrCancel(() {
      curve.removeListener(tick);
      curve.dispose();
    });
  }

  double _normalizeDegrees(double value) {
    final normalized = value % 360;
    if (normalized < 0) {
      return normalized + 360;
    }
    return normalized;
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
}

// 채도를 25%로 낮추고 대비를 0.8배로 줄인 뒤 흰색 쪽으로 20% 끌어올린다.
const List<double> _mutedTileMatrix = [
  0.327, 0.429, 0.043, 0, 51, //
  0.127, 0.629, 0.043, 0, 51, //
  0.127, 0.429, 0.243, 0, 51, //
  0, 0, 0, 1, 0, //
];

class _CompactAttribution extends StatelessWidget {
  const _CompactAttribution();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.8),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(4)),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: Text(
            '© OpenFreeMap © OpenStreetMap',
            style: TextStyle(fontSize: 8, color: AppColors.inkMuted),
          ),
        ),
      ),
    );
  }
}

/// 지도 위에 얹는 작은 흰 버튼. 지도 화면들이 같은 모양을 쓰도록 공개한다.
class MapControlButton extends StatelessWidget {
  const MapControlButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
    super.key,
  });

  static const size = 34.0;

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        minimumSize: const Size.square(size),
        fixedSize: const Size.square(size),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.22),
      ),
      onPressed: onPressed,
      icon: child,
    );
  }
}

/// 처음 위치로 버튼 아이콘: 가는 원, 사방의 짧은 눈금, 가운데 작은 점.
class _TargetIconPainter extends CustomPainter {
  const _TargetIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width * 0.3;
    final stroke = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, stroke);
    final tick = size.width * 0.14;
    for (final direction in const [
      Offset(0, -1),
      Offset(0, 1),
      Offset(-1, 0),
      Offset(1, 0),
    ]) {
      canvas.drawLine(
        center + direction * radius,
        center + direction * (radius + tick),
        stroke,
      );
    }
    canvas.drawCircle(center, 1.6, Paint()..color = AppColors.ink);
  }

  @override
  bool shouldRepaint(_TargetIconPainter oldDelegate) => false;
}

/// 빨간 끝이 실제 북쪽을 가리키는 나침반 바늘. 지도가 돌아간 만큼 반대로 돈다.
class _CompassNeedle extends StatelessWidget {
  const _CompassNeedle({required this.rotationDegrees});

  final double rotationDegrees;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -rotationDegrees * math.pi / 180,
      child: const SizedBox(
        width: 21,
        height: 21,
        child: CustomPaint(painter: _NeedlePainter()),
      ),
    );
  }
}

class _NeedlePainter extends CustomPainter {
  const _NeedlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const halfWidth = 3.6;
    final tip = size.height * 0.46;

    final north = ui.Path()
      ..moveTo(cx, cy - tip)
      ..lineTo(cx + halfWidth, cy)
      ..lineTo(cx - halfWidth, cy)
      ..close();
    final south = ui.Path()
      ..moveTo(cx, cy + tip)
      ..lineTo(cx + halfWidth, cy)
      ..lineTo(cx - halfWidth, cy)
      ..close();

    canvas.drawPath(north, Paint()..color = AppColors.danger);
    canvas.drawPath(south, Paint()..color = AppColors.inkSubtle);
    canvas.drawCircle(Offset(cx, cy), 2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_NeedlePainter oldDelegate) => false;
}
