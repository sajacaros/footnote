import 'package:flutter_test/flutter_test.dart';
import 'package:footnote_walk/models/walk_models.dart';
import 'package:footnote_walk/services/idle_watcher.dart';
import 'package:latlong2/latlong.dart';

final _start = DateTime(2026, 9, 28, 8);

DateTime _at(int minutes) => _start.add(Duration(minutes: minutes));

/// 시작점에서 북쪽으로 [meters]만큼 떨어진 포인트.
TrackPoint _point(int minutes, {double meters = 0, double accuracy = 5}) {
  return TrackPoint(
    position: LatLng(37.5665 + meters / 111320, 126.9780),
    recordedAt: _at(minutes),
    accuracy: accuracy,
  );
}

void main() {
  test('prompts after 10 minutes still and ends after 20 at the stop time', () {
    final watcher = IdleWatcher();
    watcher.addPoint(_point(0));
    for (final meters in [96.0, 98.0, 100.0]) {
      watcher.addPoint(_point(5, meters: meters));
    }
    // GPS 흔들림은 반경 안이라 멈춘 것으로 본다.
    watcher.addPoint(_point(8, meters: 125));

    expect(watcher.evaluate(_at(14)), IdleAction.none);
    expect(watcher.evaluate(_at(15)), IdleAction.prompt);
    expect(watcher.evaluate(_at(16)), IdleAction.none);
    expect(watcher.evaluate(_at(25)), IdleAction.end);
    expect(watcher.endAt, _at(5));
  });

  test('moving again after a prompt resets the count', () {
    final watcher = IdleWatcher();
    watcher.addPoint(_point(0));
    expect(watcher.evaluate(_at(10)), IdleAction.prompt);

    expect(watcher.addPoint(_point(12, meters: 50)), isFalse);
    expect(watcher.addPoint(_point(12, meters: 55)), isFalse);
    expect(watcher.addPoint(_point(12, meters: 60)), isTrue);
    expect(watcher.prompted, isFalse);
    expect(watcher.evaluate(_at(21)), IdleAction.none);
    expect(watcher.evaluate(_at(22)), IdleAction.prompt);
  });

  test('continue restarts the count and the end time is the confirmation', () {
    final watcher = IdleWatcher();
    watcher.addPoint(_point(0));
    expect(watcher.evaluate(_at(10)), IdleAction.prompt);
    watcher.confirm(_at(11));

    expect(watcher.evaluate(_at(20)), IdleAction.none);
    expect(watcher.evaluate(_at(21)), IdleAction.prompt);
    expect(watcher.evaluate(_at(30)), IdleAction.none);
    expect(watcher.evaluate(_at(31)), IdleAction.end);
    expect(watcher.endAt, _at(11));
  });

  test('inaccurate jumps do not count as movement', () {
    final watcher = IdleWatcher();
    watcher.addPoint(_point(0));
    expect(watcher.addPoint(_point(3, meters: 80, accuracy: 60)), isFalse);
    expect(watcher.evaluate(_at(10)), IdleAction.prompt);
  });

  test('a single jump outside the radius is not movement', () {
    final watcher = IdleWatcher();
    watcher.addPoint(_point(0));
    expect(watcher.addPoint(_point(3, meters: 80)), isFalse);
    expect(watcher.addPoint(_point(3, meters: 5)), isFalse);
    // 돌아온 뒤에는 연속 횟수도 처음부터 센다.
    expect(watcher.addPoint(_point(4, meters: 80)), isFalse);
    expect(watcher.addPoint(_point(4, meters: 85)), isFalse);
    expect(watcher.addPoint(_point(4, meters: 3)), isFalse);
    expect(watcher.evaluate(_at(10)), IdleAction.prompt);
  });

  test('no points (GPS lost) counts as still', () {
    final watcher = IdleWatcher();
    watcher.addPoint(_point(0));
    expect(watcher.evaluate(_at(20)), IdleAction.end);
    expect(watcher.endAt, _at(0));
  });
}
