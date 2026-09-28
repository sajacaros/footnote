import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import 'package:intl/intl.dart';

import '../models/walk_models.dart';
import 'walk_repository.dart';

/// Health Connect에서 산책 시간대의 걸음 수를 읽는다.
///
/// 만보기 앱(삼성 헬스, 토스 등)이 Health Connect에 쓴 기록을 합산하므로
/// 같은 시간대라면 그 앱들과 같은 숫자가 나온다. 앱마다 Health Connect에
/// 쓰는 시점이 늦을 수 있어, 끝난 지 얼마 안 된 산책은 다시 읽어 갱신한다.
/// 걸음 수 표기(예: 12,345).
String formatSteps(int steps) =>
    NumberFormat.decimalPattern('ko').format(steps);

class StepService {
  StepService._();

  static final StepService instance = StepService._();

  static const _types = [HealthDataType.STEPS];
  static const _askedKey = 'steps.permission_asked';

  /// 이 기간 안에 끝난 산책은 볼 때마다 다시 읽는다.
  static const refreshWindow = Duration(days: 2);

  final Health _health = Health();
  final WalkRepository _repository = WalkRepository.instance;
  bool _configured = false;

  Future<bool> _available() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      if (!_configured) {
        await _health.configure();
        _configured = true;
      }
      return await _health.isHealthConnectAvailable();
    } catch (error) {
      debugPrint('health connect unavailable: $error');
      return false;
    }
  }

  Future<bool> hasPermission() async {
    if (!await _available()) {
      return false;
    }
    try {
      return await _health.hasPermissions(_types) ?? false;
    } catch (error) {
      debugPrint('steps permission check failed: $error');
      return false;
    }
  }

  /// 권한 화면을 띄운다. Health Connect가 없으면 설치 화면으로 보내고 false.
  Future<bool> requestPermission() async {
    await _repository.writeMeta(_askedKey, '1');
    if (!await _available()) {
      await _health.installHealthConnect();
      return false;
    }
    try {
      return await _health.requestAuthorization(_types);
    } catch (error) {
      debugPrint('steps permission request failed: $error');
      return false;
    }
  }

  /// 산책을 처음 시작할 때 한 번만 권한을 묻는다. 거절하면 다시 묻지 않고
  /// 상세 화면의 연결 버튼으로만 켤 수 있다.
  Future<void> askOnce() async {
    if (await _repository.readMeta(_askedKey) != null) {
      return;
    }
    if (!await _available()) {
      return;
    }
    if (await hasPermission()) {
      await _repository.writeMeta(_askedKey, '1');
      return;
    }
    await requestPermission();
  }

  /// 권한이 없거나 읽지 못하면 null.
  Future<int?> stepsBetween(DateTime start, DateTime end) async {
    if (!await hasPermission()) {
      return null;
    }
    try {
      return await _health.getTotalStepsInInterval(start, end);
    } catch (error) {
      debugPrint('steps read failed: $error');
      return null;
    }
  }

  /// 걸음 수를 다시 읽어 바뀌었으면 저장하고, 갱신된 세션을 돌려준다.
  /// 이미 값이 있고 끝난 지 오래된 산책은 읽지 않는다.
  Future<WalkSession> refresh(WalkSession session, {bool force = false}) async {
    final recent = DateTime.now().difference(session.endedAt) < refreshWindow;
    if (!force && session.steps != null && !recent) {
      return session;
    }
    final steps = await stepsBetween(session.startedAt, session.endedAt);
    // 0은 기록이 없다는 뜻에 가깝다(만보기 앱 연동 전이거나, Health Connect가
    // 권한을 받은 날보다 30일 넘게 이전 기록은 주지 않는다). 모르는 값으로 둔다.
    if (steps == null || steps == 0 || steps == session.steps) {
      return session;
    }
    await _repository.updateSteps(session.id, steps);
    return session.copyWith(steps: steps);
  }

  /// 목록을 열 때 최근 산책만 다시 읽는다. 바뀐 게 있으면 새 목록, 없으면 null.
  Future<List<WalkSession>?> refreshRecent(List<WalkSession> sessions) async {
    final now = DateTime.now();
    if (!sessions.any((s) => now.difference(s.endedAt) < refreshWindow)) {
      return null;
    }
    if (!await hasPermission()) {
      return null;
    }
    var changed = false;
    final updated = <WalkSession>[];
    for (final session in sessions) {
      if (now.difference(session.endedAt) >= refreshWindow) {
        updated.add(session);
        continue;
      }
      final refreshed = await refresh(session);
      changed = changed || !identical(refreshed, session);
      updated.add(refreshed);
    }
    return changed ? updated : null;
  }
}
