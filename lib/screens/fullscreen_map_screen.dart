import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/walk_models.dart';
import '../theme/app_theme.dart';
import '../widgets/walk_map_preview.dart';

/// 지도를 화면 전체로 보여 준다.
///
/// 처음 방향은 경로 모양으로 정한다(가로로 넓으면 가로 모드, 세로로 길면 세로 모드).
/// 닫으면 상태바와 화면 방향 제한을 원래대로 돌려놓는다.
class FullscreenMapScreen extends StatefulWidget {
  const FullscreenMapScreen({
    required this.session,
    this.onPhotoTap,
    super.key,
  });

  final WalkSession session;
  final void Function(BuildContext context, WalkPhoto photo)? onPhotoTap;

  @override
  State<FullscreenMapScreen> createState() => _FullscreenMapScreenState();
}

class _FullscreenMapScreenState extends State<FullscreenMapScreen> {
  late bool _landscape = _routeIsWide(widget.session);

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _applyOrientation();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // 앱은 원래 방향 제한이 없다.
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              WalkMapPreview(
                // 화면 방향이 바뀌면 새 크기에 맞춰 경로를 다시 맞춘다.
                key: ValueKey(
                  '${constraints.maxWidth > constraints.maxHeight}',
                ),
                session: widget.session,
                interactive: true,
                height: constraints.maxHeight,
                fitRoute: true,
                maxAutoFitZoom: 17,
                rounded: false,
                isFullscreen: true,
                onToggleFullscreen: () => Navigator.of(context).pop(),
                controlsTop: 10 + MediaQuery.paddingOf(context).top,
                extraControls: [
                  MapControlButton(
                    tooltip: _landscape ? '세로로 보기' : '가로로 보기',
                    onPressed: () {
                      setState(() => _landscape = !_landscape);
                      _applyOrientation();
                    },
                    child: const Icon(Icons.screen_rotation_rounded, size: 17),
                  ),
                ],
                onPhotoTap: widget.onPhotoTap == null
                    ? null
                    : (photo) => widget.onPhotoTap!(context, photo),
              ),
            ],
          );
        },
      ),
    );
  }

  void _applyOrientation() {
    SystemChrome.setPreferredOrientations(
      _landscape
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight
            ]
          : const [DeviceOrientation.portraitUp],
    );
  }

  /// 경로의 동서 폭이 남북 길이보다 길면 가로 모드가 낫다.
  static bool _routeIsWide(WalkSession session) {
    final route = session.route;
    if (route.length < 2) {
      return true;
    }
    final lats = route.map((point) => point.latitude);
    final lngs = route.map((point) => point.longitude);
    final latSpan = lats.reduce(math.max) - lats.reduce(math.min);
    // 경도 1도의 거리는 위도에 따라 줄어든다.
    final lngSpan = (lngs.reduce(math.max) - lngs.reduce(math.min)) *
        math.cos(session.center.latitude * math.pi / 180);
    return lngSpan >= latSpan;
  }
}
