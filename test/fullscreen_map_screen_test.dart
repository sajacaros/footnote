import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footnote_walk/models/walk_models.dart';
import 'package:footnote_walk/screens/fullscreen_map_screen.dart';
import 'package:latlong2/latlong.dart';

WalkSession _route({required double dLat, required double dLng}) {
  final start = DateTime(2026, 9, 28, 8);
  return WalkSession(
    id: 's',
    title: 'test',
    startedAt: start,
    endedAt: start.add(const Duration(minutes: 20)),
    photos: const [],
    points: [
      for (var i = 0; i < 10; i += 1)
        TrackPoint(
          position: LatLng(37.5665 + i * dLat, 126.9780 + i * dLng),
          recordedAt: start.add(Duration(seconds: 2 * i)),
        ),
    ],
  );
}

/// SystemChrome.setPreferredOrientations 호출을 가로챈다.
List<List<String>> _recordOrientations(WidgetTester tester) {
  final calls = <List<String>>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        calls.add((call.arguments as List).cast<String>());
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return calls;
}

Future<void> _open(WidgetTester tester, WalkSession session) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => FullscreenMapScreen(session: session),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wide route opens in landscape and restores on close',
      (tester) async {
    final calls = _recordOrientations(tester);
    await _open(tester, _route(dLat: 0.0001, dLng: 0.001));
    expect(calls.last, [
      'DeviceOrientation.landscapeLeft',
      'DeviceOrientation.landscapeRight',
    ]);

    await tester.tap(find.byTooltip('지도 작게 보기'));
    await tester.pumpAndSettle();
    expect(find.byType(FullscreenMapScreen), findsNothing);
    expect(calls.last, isEmpty);
  });

  testWidgets('tall route opens in portrait and can be rotated',
      (tester) async {
    final calls = _recordOrientations(tester);
    await _open(tester, _route(dLat: 0.001, dLng: 0.0001));
    expect(calls.last, ['DeviceOrientation.portraitUp']);

    await tester.tap(find.byTooltip('가로로 보기'));
    await tester.pump();
    expect(calls.last, [
      'DeviceOrientation.landscapeLeft',
      'DeviceOrientation.landscapeRight',
    ]);
    expect(find.byTooltip('세로로 보기'), findsOneWidget);
  });
}
