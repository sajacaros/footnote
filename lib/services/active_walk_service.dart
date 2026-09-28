import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../models/walk_models.dart';
import 'gpx_exporter.dart';
import 'idle_notifier.dart';
import 'idle_watcher.dart';
import 'location_tracker.dart';
import 'photo_storage.dart';
import 'session_photo_finder.dart';
import 'step_service.dart';
import 'walk_repository.dart';

class ActiveWalkService extends ChangeNotifier {
  ActiveWalkService._();

  static final ActiveWalkService instance = ActiveWalkService._();

  final LocationTracker _tracker = LocationTracker();
  final ImagePicker _picker = ImagePicker();
  final Uuid _uuid = const Uuid();

  String? _sessionId;
  DateTime? _startedAt;
  final List<TrackPoint> _points = [];
  final List<WalkPhoto> _photos = [];
  bool _tracking = false;
  bool _saving = false;
  String? _status;

  // 한자리에 오래 머물면 묻고, 응답이 없으면 기록을 끝낸다(배터리 절약).
  static const _idleCheckInterval = Duration(seconds: 30);
  IdleWatcher _idle = IdleWatcher();
  Timer? _idleTimer;
  late final IdleNotifier _idleNotifier = IdleNotifier(
    onContinue: _continueFromIdle,
    onFinish: () => finish(),
  );

  bool get isActive => _sessionId != null;
  bool get isSaving => _saving;
  String? get status => _status;
  DateTime? get startedAt => _startedAt;
  List<TrackPoint> get points => List.unmodifiable(_points);
  List<WalkPhoto> get photos => List.unmodifiable(_photos);
  int get pointCount => _points.length;
  DateTime? get lastPointAt => _points.isEmpty ? null : _points.last.recordedAt;

  Duration get elapsed {
    final started = _startedAt;
    if (started == null) {
      return Duration.zero;
    }
    return DateTime.now().difference(started);
  }

  double get distanceMeters {
    if (_points.length < 2) {
      return 0;
    }

    const calculator = Distance();
    var meters = 0.0;
    for (var index = 1; index < _points.length; index += 1) {
      meters +=
          calculator(_points[index - 1].position, _points[index].position);
    }
    return meters;
  }

  LatLng? get currentPosition {
    if (_points.isEmpty) {
      return null;
    }
    return _points.last.position;
  }

  Future<void> start() async {
    if (isActive) {
      if (!_tracking) {
        await _startTracking();
      }
      return;
    }

    _sessionId = _uuid.v4();
    _startedAt = DateTime.now();
    _points.clear();
    _photos.clear();
    _status = null;
    _idle = IdleWatcher();
    _idleTimer?.cancel();
    _idleTimer = Timer.periodic(_idleCheckInterval, (_) => _checkIdle());
    notifyListeners();

    await _startTracking();
    await _writeDraft();
  }

  Future<void> addPhoto() async {
    if (!isActive) {
      return;
    }

    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 86,
      maxWidth: 1800,
    );
    if (picked == null) {
      return;
    }

    final sessionId = _sessionId!;
    final path = await PhotoStorage.saveWalkPhoto(
      sessionId: sessionId,
      source: File(picked.path),
    );
    final photo = WalkPhoto(
      id: _uuid.v4(),
      sessionId: sessionId,
      imageUrl: path,
      position: currentPosition ?? const LatLng(37.5665, 126.9780),
      takenAt: DateTime.now(),
      caption: 'Walk photo',
    );

    _photos.add(photo);
    notifyListeners();
    await _writeDraft();
  }

  Future<void> applyGalleryPhotoChanges({
    required List<SessionPhotoCandidate> toAttach,
    required List<String> toDetach,
  }) async {
    if (!isActive) {
      return;
    }

    final currentByPath = {
      for (final photo in _photos) photo.imageUrl: photo,
    };
    final idsToRemove = toDetach
        .map((path) => currentByPath[path]?.id)
        .whereType<String>()
        .toSet();
    _photos.removeWhere((photo) => idsToRemove.contains(photo.id));

    final sessionId = _sessionId!;
    final existingPaths = _photos.map((photo) => photo.imageUrl).toSet();
    for (final candidate in toAttach) {
      if (existingPaths.contains(candidate.path)) {
        continue;
      }
      _photos.add(
        WalkPhoto(
          id: _uuid.v4(),
          sessionId: sessionId,
          imageUrl: candidate.path,
          position: _positionForCandidate(candidate),
          takenAt: candidate.takenAt,
          caption: '앨범에서 추가',
        ),
      );
    }

    _photos.sort((a, b) => a.takenAt.compareTo(b.takenAt));
    notifyListeners();
    await _writeDraft();
  }

  /// [endedAt]을 주면 그 뒤의 포인트는 버린다(멈춰 있던 구간을 빼고 저장).
  Future<WalkSession?> finish({DateTime? endedAt}) async {
    if (!isActive || _points.isEmpty || _saving) {
      return null;
    }

    _saving = true;
    notifyListeners();
    await _stopIdleWatch();
    await _tracker.stop();
    _tracking = false;

    final end = endedAt ?? DateTime.now();
    final firstPoint = _points.first;
    _points.removeWhere((point) => point.recordedAt.isAfter(end));
    if (_points.isEmpty) {
      _points.add(firstPoint);
    }

    var session = _snapshot(endedAt: end);
    // 만보기 앱이 아직 마지막 몇 분을 쓰지 않았을 수 있다. 목록·상세를 열 때 다시 읽는다.
    final steps = await StepService.instance.stepsBetween(
      session.startedAt,
      session.endedAt,
    );
    if (steps != null && steps > 0) {
      session = session.copyWith(steps: steps);
    }
    await WalkRepository.instance.saveSession(session);
    await GpxExporter.writeActiveDraft(session);

    _sessionId = null;
    _startedAt = null;
    _points.clear();
    _photos.clear();
    _saving = false;
    _status = null;
    notifyListeners();

    return session;
  }

  Future<void> discard() async {
    await _stopIdleWatch();
    await _tracker.stop();
    _tracking = false;
    _sessionId = null;
    _startedAt = null;
    _points.clear();
    _photos.clear();
    _saving = false;
    _status = null;
    notifyListeners();
  }

  WalkSession? snapshot() {
    if (!isActive) {
      return null;
    }
    return _snapshot(endedAt: DateTime.now());
  }

  Future<void> _startTracking() async {
    final firstPoint = await _tracker.currentPoint();
    if (firstPoint != null) {
      await _addTrackPoint(firstPoint);
    }

    final started = await _tracker.start(onPoint: (point) {
      _addTrackPoint(point);
    });

    _tracking = started;
    _status = started ? null : '위치 권한을 허용하면 경로가 기록됩니다.';
    notifyListeners();
  }

  Future<void> _addTrackPoint(TrackPoint point) async {
    if (!isActive) {
      return;
    }

    if (_points.isNotEmpty) {
      final elapsed = point.recordedAt.difference(_points.last.recordedAt);
      if (elapsed < LocationTracker.trackingInterval) {
        return;
      }
    }

    _points.add(point);
    final wasPrompted = _idle.prompted;
    if (_idle.addPoint(point) && wasPrompted) {
      // 알림에 답하지 않았어도 다시 걷기 시작했으면 계속 산책 중이다.
      await _idleNotifier.cancelPrompt();
    }
    notifyListeners();
    await _writeDraft();
  }

  Future<void> _checkIdle() async {
    if (!isActive || _saving) {
      return;
    }
    switch (_idle.evaluate(DateTime.now())) {
      case IdleAction.none:
        return;
      case IdleAction.prompt:
        await _idleNotifier.showPrompt();
      case IdleAction.end:
        final session = await finish(endedAt: _idle.endAt);
        if (session != null) {
          await _idleNotifier.showEnded();
        }
    }
  }

  void _continueFromIdle() {
    if (isActive) {
      _idle.confirm(DateTime.now());
    }
  }

  Future<void> _stopIdleWatch() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    await _idleNotifier.cancelPrompt();
  }

  Future<void> _writeDraft() async {
    final session = snapshot();
    if (session == null) {
      return;
    }
    await GpxExporter.writeActiveDraft(session);
  }

  WalkSession _snapshot({required DateTime endedAt}) {
    final startedAt = _startedAt!;
    return WalkSession(
      id: _sessionId!,
      title: '${DateFormat('M월 d일 HH:mm').format(startedAt)} 산책',
      startedAt: startedAt,
      endedAt: endedAt,
      points: List<TrackPoint>.unmodifiable(_points),
      photos: List<WalkPhoto>.unmodifiable(_photos),
    );
  }

  LatLng _positionForCandidate(SessionPhotoCandidate candidate) {
    if (_points.isEmpty) {
      return currentPosition ?? const LatLng(37.5665, 126.9780);
    }

    var closest = _points.first;
    var smallestGap = candidate.takenAt.difference(closest.recordedAt).abs();
    for (final point in _points.skip(1)) {
      final gap = candidate.takenAt.difference(point.recordedAt).abs();
      if (gap < smallestGap) {
        smallestGap = gap;
        closest = point;
      }
    }
    return closest.position;
  }
}
