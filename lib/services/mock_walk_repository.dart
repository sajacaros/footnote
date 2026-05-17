import 'package:latlong2/latlong.dart';

import '../models/walk_models.dart';

class MockWalkRepository {
  static List<WalkSession> loadSessions() {
    final now = DateTime.now();

    return [
      _session(
        id: 'walk-001',
        title: '점심 햇살 산책',
        startedAt: DateTime(now.year, now.month, now.day, 12, 7),
        minutes: 54,
        note: '카페 골목을 지나 공원 한 바퀴. 사진을 많이 남긴 날.',
        base: const LatLng(37.5664, 126.9785),
        offsets: const [
          [0.0000, 0.0000],
          [0.0012, 0.0005],
          [0.0020, 0.0016],
          [0.0014, 0.0025],
          [0.0003, 0.0022],
          [-0.0004, 0.0010],
        ],
      ),
      _session(
        id: 'walk-002',
        title: '퇴근 후 골목길',
        startedAt: now.subtract(const Duration(days: 1, hours: 3)),
        minutes: 38,
        note: '짧지만 냄새 맡는 시간이 길었던 산책.',
        base: const LatLng(37.5648, 126.9810),
        offsets: const [
          [0.0000, 0.0000],
          [0.0008, -0.0006],
          [0.0015, -0.0012],
          [0.0022, -0.0004],
          [0.0016, 0.0008],
        ],
      ),
      _session(
        id: 'walk-003',
        title: '주말 공원 루프',
        startedAt: now.subtract(const Duration(days: 4, hours: 1)),
        minutes: 72,
        note: '긴 산책. 중간에 벤치에서 쉬었다.',
        base: const LatLng(37.5701, 126.9768),
        offsets: const [
          [0.0000, 0.0000],
          [0.0008, 0.0010],
          [0.0022, 0.0014],
          [0.0031, 0.0003],
          [0.0025, -0.0010],
          [0.0009, -0.0012],
          [-0.0001, -0.0002],
        ],
      ),
    ];
  }

  static WalkSession _session({
    required String id,
    required String title,
    required DateTime startedAt,
    required int minutes,
    required String note,
    required LatLng base,
    required List<List<double>> offsets,
  }) {
    final points = <TrackPoint>[];
    for (var index = 0; index < offsets.length; index += 1) {
      final offset = offsets[index];
      points.add(
        TrackPoint(
          position: LatLng(
            base.latitude + offset[0],
            base.longitude + offset[1],
          ),
          recordedAt: startedAt.add(Duration(minutes: index * 9)),
          elevation: 32 + index.toDouble(),
          accuracy: 8,
        ),
      );
    }

    final endedAt = startedAt.add(Duration(minutes: minutes));
    final photos = [
      WalkPhoto(
        id: '$id-photo-1',
        sessionId: id,
        imageUrl: 'https://picsum.photos/seed/$id-a/480/640',
        position: points[1].position,
        takenAt: startedAt.add(const Duration(minutes: 12)),
        caption: '첫 번째 쉬는 지점',
      ),
      WalkPhoto(
        id: '$id-photo-2',
        sessionId: id,
        imageUrl: 'https://picsum.photos/seed/$id-b/480/640',
        position: points[points.length - 2].position,
        takenAt: startedAt.add(Duration(minutes: minutes - 10)),
        caption: '돌아오는 길',
      ),
    ];

    return WalkSession(
      id: id,
      title: title,
      startedAt: startedAt,
      endedAt: endedAt,
      points: points,
      photos: photos,
      note: note,
    );
  }
}
