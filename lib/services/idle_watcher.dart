import 'package:latlong2/latlong.dart';

import '../models/walk_models.dart';

enum IdleAction { none, prompt, end }

/// 산책 중 한자리에 오래 머무는지 지켜본다. 시간은 밖에서 넣어 주므로 테스트할 수 있다.
///
/// - 포인트가 [movePoints]개 연달아 기준점에서 [radiusMeters] 밖에 있으면 움직인 것으로
///   보고 처음부터 다시 센다. 한 번 튄 위치로는 움직였다고 보지 않는다.
///   GPS가 끊겨 포인트가 안 들어오는 동안은 멈춘 것으로 친다.
/// - 멈춘 지 [promptAfter]가 지나면 묻고, [endAfter]가 지나면 끝낸다.
/// - 사용자가 계속하겠다고 하면 그때부터 다시 센다.
/// - 끝낼 때의 종료 시각은 마지막으로 계속하겠다고 한 시각, 없으면 멈추기 시작한 시각.
class IdleWatcher {
  IdleWatcher({
    this.radiusMeters = 40,
    this.promptAfter = const Duration(minutes: 10),
    this.endAfter = const Duration(minutes: 20),
    this.movePoints = 3,
  });

  final double radiusMeters;
  final int movePoints;
  final Duration promptAfter;
  final Duration endAfter;

  static const _distance = Distance();

  LatLng? _anchor;
  DateTime? _stillSince;
  DateTime? _confirmedAt;
  bool _prompted = false;
  // 기준점 반경 밖에 연달아 찍힌 포인트 수.
  int _outside = 0;

  bool get prompted => _prompted;

  /// 이번 멈춤을 세기 시작한 시각.
  DateTime? get _countFrom {
    final confirmed = _confirmedAt;
    final still = _stillSince;
    if (confirmed != null && (still == null || confirmed.isAfter(still))) {
      return confirmed;
    }
    return still;
  }

  /// 자동 종료할 때 쓸 종료 시각.
  DateTime? get endAt => _confirmedAt ?? _stillSince;

  /// 움직였으면 true.
  bool addPoint(TrackPoint point) {
    final anchor = _anchor;
    if (anchor == null) {
      _reset(point);
      return false;
    }
    // 정확도가 나쁜 포인트는 튄 값일 수 있어 움직임 판단에 쓰지 않는다.
    final accuracy = point.accuracy ?? 0;
    if (accuracy > radiusMeters) {
      return false;
    }
    if (_distance(anchor, point.position) <= radiusMeters) {
      _outside = 0;
      return false;
    }
    _outside += 1;
    if (_outside < movePoints) {
      return false;
    }
    _reset(point);
    return true;
  }

  /// 사용자가 알림에서 계속 기록을 골랐다.
  void confirm(DateTime now) {
    _confirmedAt = now;
    _prompted = false;
  }

  IdleAction evaluate(DateTime now) {
    final since = _countFrom;
    if (since == null) {
      return IdleAction.none;
    }
    final idle = now.difference(since);
    if (idle >= endAfter) {
      return IdleAction.end;
    }
    if (idle >= promptAfter && !_prompted) {
      _prompted = true;
      return IdleAction.prompt;
    }
    return IdleAction.none;
  }

  void _reset(TrackPoint point) {
    _anchor = point.position;
    _stillSince = point.recordedAt;
    _confirmedAt = null;
    _prompted = false;
    _outside = 0;
  }
}
