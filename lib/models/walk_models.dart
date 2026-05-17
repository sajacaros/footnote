import 'package:latlong2/latlong.dart';

class WalkPhoto {
  const WalkPhoto({
    required this.id,
    required this.sessionId,
    required this.imageUrl,
    required this.position,
    required this.takenAt,
    this.caption,
  });

  final String id;
  final String sessionId;
  final String imageUrl;
  final LatLng position;
  final DateTime takenAt;
  final String? caption;
}

class TrackPoint {
  const TrackPoint({
    required this.position,
    required this.recordedAt,
    this.elevation,
    this.accuracy,
    this.speed,
  });

  final LatLng position;
  final DateTime recordedAt;
  final double? elevation;
  final double? accuracy;
  final double? speed;
}

class WalkSession {
  const WalkSession({
    required this.id,
    required this.title,
    required this.startedAt,
    required this.endedAt,
    required this.points,
    required this.photos,
    this.note,
  });

  final String id;
  final String title;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<TrackPoint> points;
  final List<WalkPhoto> photos;
  final String? note;

  Duration get duration => endedAt.difference(startedAt);

  LatLng get center {
    if (points.isEmpty) {
      return const LatLng(37.5665, 126.9780);
    }

    final latitude = points
            .map((point) => point.position.latitude)
            .reduce((sum, value) => sum + value) /
        points.length;
    final longitude = points
            .map((point) => point.position.longitude)
            .reduce((sum, value) => sum + value) /
        points.length;

    return LatLng(latitude, longitude);
  }

  double get distanceMeters {
    if (points.length < 2) {
      return 0;
    }

    const calculator = Distance();
    var total = 0.0;
    for (var index = 1; index < points.length; index += 1) {
      total += calculator(
        points[index - 1].position,
        points[index].position,
      );
    }
    return total;
  }

  List<LatLng> get route => points.map((point) => point.position).toList();

  WalkSession copyWith({
    String? id,
    String? title,
    DateTime? startedAt,
    DateTime? endedAt,
    List<TrackPoint>? points,
    List<WalkPhoto>? photos,
    String? note,
  }) {
    return WalkSession(
      id: id ?? this.id,
      title: title ?? this.title,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      points: points ?? this.points,
      photos: photos ?? this.photos,
      note: note ?? this.note,
    );
  }
}
