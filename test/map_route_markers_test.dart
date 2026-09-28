import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footnote_walk/models/walk_models.dart';
import 'package:footnote_walk/widgets/map_route_markers.dart';
import 'package:footnote_walk/widgets/walk_map_preview.dart';
import 'package:latlong2/latlong.dart';

WalkPhoto _photo(String id, double lat, double lng, int minute) => WalkPhoto(
      id: id,
      sessionId: 's',
      imageUrl: '/missing/$id.jpg',
      position: LatLng(lat, lng),
      takenAt: DateTime(2026, 9, 28, 8, minute),
    );

void main() {
  group('photoPinSize', () {
    test('grows gently with zoom and is clamped', () {
      expect(photoPinSize(16), closeTo(38, 0.01));
      expect(photoPinSize(17), closeTo(47.5, 0.01));
      expect(photoPinSize(10), 24);
      expect(photoPinSize(21), 64);
      expect(photoPinSize(21, maxSize: 40), 40);
    });
  });

  group('clusterPhotos', () {
    test('merges photos closer than the distance, in taken order', () {
      final photos = [
        _photo('b', 0, 10, 2),
        _photo('a', 0, 0, 1),
        _photo('c', 0, 100, 3),
      ];
      // 경도를 그대로 x 픽셀로 쓰는 가짜 투영.
      Offset project(LatLng p) => Offset(p.longitude, p.latitude);

      final near = clusterPhotos(photos, project, 20);
      expect(near.map((c) => c.map((p) => p.id).toList()).toList(), [
        ['a', 'b'],
        ['c'],
      ]);

      final far = clusterPhotos(photos, project, 5);
      expect(far.length, 3);
    });
  });

  group('arrowPlacements', () {
    test('spacing follows screen pixels, not meters', () {
      const short = [Offset.zero, Offset(560, 0)];
      const long = [Offset.zero, Offset(1120, 0)];
      // 같은 경로라도 두 배로 확대되면 화면 길이가 두 배라 화살표도 두 배가 된다.
      expect(arrowPlacements(short, 56).length, 10);
      expect(arrowPlacements(long, 56).length, 20);
    });

    test('a route shorter than one spacing gets one arrow in the middle', () {
      final places = arrowPlacements(const [Offset.zero, Offset(30, 0)], 56);
      expect(places.length, 1);
      expect(places.single.t, closeTo(0.5, 1e-9));
    });
  });

  testWidgets('photos merge when zoomed out and split when zoomed in',
      (tester) async {
    final start = DateTime(2026, 9, 28, 8);
    final session = WalkSession(
      id: 's',
      title: 't',
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 30)),
      points: [
        for (var i = 0; i < 10; i += 1)
          TrackPoint(
            position: LatLng(37.5665 + i * 0.0003, 126.978),
            recordedAt: start.add(Duration(minutes: i)),
          ),
      ],
      // 약 30m 떨어진 사진 두 장
      photos: [
        _photo('p1', 37.5665, 126.978, 1),
        _photo('p2', 37.5668, 126.978, 2),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body:
              WalkMapPreview(session: session, interactive: true, height: 500),
        ),
      ),
    );
    await tester.pump();
    final controller =
        MapController.of(tester.element(find.byType(PhotoPinLayer)));

    controller.move(const LatLng(37.5667, 126.978), 14);
    await tester.pump();
    expect(find.text('2'), findsOneWidget,
        reason: '줌을 줄이면 한 핀으로 묶이고 개수를 보여 준다');

    controller.move(const LatLng(37.5667, 126.978), 19);
    await tester.pump();
    expect(find.text('2'), findsNothing, reason: '줌을 키우면 다시 두 핀으로 나뉜다');
  });
}
