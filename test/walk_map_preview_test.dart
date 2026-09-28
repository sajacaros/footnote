import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footnote_walk/models/walk_models.dart';
import 'package:footnote_walk/widgets/walk_map_preview.dart';
import 'package:latlong2/latlong.dart';

WalkSession _session() {
  final start = DateTime(2026, 9, 28, 8);
  return WalkSession(
    id: 's',
    title: 'test',
    startedAt: start,
    endedAt: start.add(const Duration(minutes: 20)),
    photos: const [],
    points: [
      for (var i = 0; i < 20; i += 1)
        TrackPoint(
          position: LatLng(37.5665 + i * 0.0004, 126.9780 + i * 0.0002),
          recordedAt: start.add(Duration(seconds: 2 * i)),
        ),
    ],
  );
}

/// 나침반 버튼 안의 바늘 회전각(도).
double _needleDegrees(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byTooltip('북쪽을 위로'),
      matching: find.byType(Transform),
    ),
  );
  final m = transform.transform.storage;
  return math.atan2(m[1], m[0]) * 180 / math.pi;
}

Future<MapCamera Function()> _pumpMap(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WalkMapPreview(
          session: _session(),
          interactive: true,
          height: 380,
          fitRoute: true,
          maxAutoFitZoom: 16,
        ),
      ),
    ),
  );
  await tester.pump();
  // 지도 안쪽 위젯의 context로 카메라와 컨트롤러를 꺼낸다.
  BuildContext inner() => tester.element(find.byType(PolylineLayer));
  return () => MapCamera.of(inner());
}

void main() {
  testWidgets('compass turns the map back to north', (tester) async {
    final camera = await _pumpMap(tester);
    final before = camera();
    MapController.of(tester.element(find.byType(PolylineLayer))).rotate(70);
    await tester.pump();
    expect(camera().rotation, closeTo(70, 0.01));
    // 지도가 돌아간 만큼 바늘은 반대로 돌아 실제 북쪽을 가리킨다.
    expect(_needleDegrees(tester), closeTo(-70, 0.5));

    final rotated = camera();
    await tester.tap(find.byTooltip('북쪽을 위로'));
    await tester.pumpAndSettle();

    expect(camera().rotation % 360, closeTo(0, 0.01));
    expect(_needleDegrees(tester), closeTo(0, 0.5));
    // 방향만 바뀌고 중심과 확대는 그대로다.
    expect(camera().zoom, before.zoom);
    expect(camera().center.latitude, rotated.center.latitude);
    expect(camera().center.longitude, rotated.center.longitude);
  });

  testWidgets('reset returns to the initial view', (tester) async {
    final camera = await _pumpMap(tester);
    final initial = camera();

    final controller =
        MapController.of(tester.element(find.byType(PolylineLayer)));
    controller.moveAndRotate(const LatLng(37.60, 127.05), 12, 200);
    await tester.pump();
    expect(camera().zoom, closeTo(12, 0.01));

    await tester.tap(find.byTooltip('지도 처음 위치로'));
    await tester.pumpAndSettle();

    final after = camera();
    expect(after.rotation % 360, closeTo(0, 0.01));
    expect(after.zoom, closeTo(initial.zoom, 0.01));
    expect(after.center.latitude, closeTo(initial.center.latitude, 1e-6));
    expect(after.center.longitude, closeTo(initial.center.longitude, 1e-6));
  });
}
