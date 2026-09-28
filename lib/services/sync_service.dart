import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../models/walk_models.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'walk_repository.dart';

/// 로컬 기록을 서버로 올린다(업로드 방향만).
///
/// 순서: 서버 삭제 대기열 → 세션 생성·수정 → 포인트 벌크 전송 → finish → 사진 업로드.
/// 모든 단계가 멱등이라 중간에 끊겨도 다음 동기화에서 이어서 보낸다.
class SyncService extends ChangeNotifier {
  SyncService._();

  static final SyncService instance = SyncService._();

  static const _ownerKey = 'sync.owner_user_id';
  static const _lastSyncKey = 'sync.last_synced_at';
  static const _pointChunk = 1000;
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  final WalkRepository _repository = WalkRepository.instance;
  final AuthService _auth = AuthService.instance;

  bool _running = false;
  bool _again = false;
  String? _error;
  int _pending = 0;
  DateTime? _lastSyncedAt;

  bool get isRunning => _running;
  String? get error => _error;
  int get pendingCount => _pending;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  Future<void> refreshStatus() async {
    _pending = await _repository.pendingSyncCount();
    final last = await _repository.readMeta(_lastSyncKey);
    _lastSyncedAt = last == null ? null : DateTime.parse(last).toLocal();
    notifyListeners();
  }

  /// 이미 돌고 있으면 끝난 뒤 한 번 더 돈다(그 사이 생긴 변경을 놓치지 않게).
  Future<void> sync() async {
    if (_auth.state != AuthState.signedIn) {
      return;
    }
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    _error = null;
    notifyListeners();
    try {
      do {
        _again = false;
        await _syncOnce();
      } while (_again);
      await _repository.writeMeta(
        _lastSyncKey,
        DateTime.now().toUtc().toIso8601String(),
      );
    } on ApiException catch (error) {
      _error = error.message;
    } on _SyncBlocked catch (error) {
      _error = error.message;
    } catch (error) {
      _error = '동기화 중 오류가 발생했습니다.';
      debugPrint('sync failed: $error');
    } finally {
      _running = false;
      await refreshStatus();
    }
  }

  Future<void> _syncOnce() async {
    await _checkOwner();

    for (final deletion in await _repository.pendingDeletions()) {
      final path = deletion.kind == 'session'
          ? '/v1/sessions/${deletion.remoteId}'
          : '/v1/photos/${deletion.remoteId}';
      try {
        await _auth.authorized('DELETE', path);
      } on ApiException catch (error) {
        // 서버에 없으면(한 번도 안 올라갔거나 이미 지움) 끝난 것으로 본다.
        if (error.statusCode != 404) {
          rethrow;
        }
      }
      await _repository.clearDeletion(deletion);
    }

    for (final target in await _repository.pendingSyncSessions()) {
      // 목업 기록(walk-001 등)은 서버로 보내지 않는다.
      if (!_uuid.hasMatch(target.sessionId)) {
        await _repository.markSessionSynced(target.sessionId, target.rev);
        continue;
      }
      final session = await _repository.loadSession(target.sessionId);
      if (session == null) {
        continue;
      }
      await _syncSession(session, target);
      await _repository.markSessionSynced(session.id, target.rev);
      _pending = await _repository.pendingSyncCount();
      notifyListeners();
    }
  }

  /// 이 기기의 기록은 처음 동기화한 계정에만 올린다. 다른 계정으로 로그인해서
  /// 앞 사람의 산책 기록이 섞여 올라가는 것을 막는다.
  Future<void> _checkOwner() async {
    final userId = _auth.user!.id;
    final owner = await _repository.readMeta(_ownerKey);
    if (owner == null) {
      await _repository.writeMeta(_ownerKey, userId);
    } else if (owner != userId) {
      throw const _SyncBlocked('이 기기의 기록은 다른 계정에 연결돼 있어 동기화하지 않았습니다.');
    }
  }

  /// 실패하면 예외를 던지고, 세션은 다음 동기화 때 처음부터(멱등하게) 다시 보낸다.
  Future<void> _syncSession(WalkSession session, SyncTarget target) async {
    await _auth.authorized(
      'POST',
      '/v1/sessions',
      json: {
        'id': session.id,
        'title': session.title,
        'note': session.note,
        'started_at': _utc(session.startedAt),
      },
    );
    final featured = session.featuredPhotoId;
    await _auth.authorized(
      'PATCH',
      '/v1/sessions/${session.id}',
      json: {
        'title': session.title,
        'note': session.note,
        'featured_photo_id':
            featured != null && _uuid.hasMatch(featured) ? featured : null,
        'steps': session.steps,
      },
    );

    final lastSeq = session.points.length - 1;
    var acked = await _sendPoints(session, target.syncedPointSeq);
    try {
      await _finish(session, lastSeq);
    } on ApiException catch (error) {
      if (error.statusCode != 409) {
        rethrow;
      }
      // 서버에 빠진 구간이 있다. 서버가 알려 준 지점부터 다시 보낸다.
      final body = error.body;
      final serverAcked = body is Map ? body['last_acked_seq'] as int? : null;
      acked = await _sendPoints(session, serverAcked ?? -1);
      await _finish(session, lastSeq);
    }
    await _repository.setSyncedPointSeq(session.id, acked);

    final uploaded = await _repository.uploadedPhotoIds(session.id);
    for (final photo in session.photos) {
      if (!uploaded.contains(photo.id)) {
        await _uploadPhoto(photo);
      }
    }
  }

  Future<int> _sendPoints(WalkSession session, int fromAcked) async {
    var acked = fromAcked;
    final points = session.points;
    while (acked < points.length - 1) {
      final start = acked + 1;
      final end = (start + _pointChunk).clamp(0, points.length);
      final body = await _auth.authorized(
        'POST',
        '/v1/sessions/${session.id}/points:batch',
        gzipBody: true,
        json: {
          'points': [
            for (var seq = start; seq < end; seq += 1)
              {
                'seq': seq,
                'recorded_at': _utc(points[seq].recordedAt),
                'lat': points[seq].position.latitude,
                'lng': points[seq].position.longitude,
                'elevation': points[seq].elevation,
                'accuracy': points[seq].accuracy,
                'speed': points[seq].speed,
              },
          ],
        },
      );
      final next = (body as Map<String, dynamic>)['last_acked_seq'] as int;
      if (next <= acked) {
        // 진전이 없으면 무한 반복하지 않고 다음 동기화로 넘긴다.
        throw const ApiException(409, 'GPS 기록을 서버에 저장하지 못했습니다.');
      }
      acked = next;
      await _repository.setSyncedPointSeq(session.id, acked);
    }
    return acked;
  }

  Future<void> _finish(WalkSession session, int lastSeq) async {
    await _auth.authorized(
      'POST',
      '/v1/sessions/${session.id}/finish',
      json: {'ended_at': _utc(session.endedAt), 'last_seq': lastSeq},
    );
  }

  /// 목업 사진이나 원본 파일이 사라진 사진은 올리지 않고 넘어간다.
  Future<void> _uploadPhoto(WalkPhoto photo) async {
    if (!_uuid.hasMatch(photo.id) || photo.imageUrl.startsWith('http')) {
      return;
    }
    final file = File(photo.imageUrl);
    if (!await file.exists()) {
      debugPrint('photo file missing, skip: ${photo.imageUrl}');
      return;
    }

    // 표시용(짧은 변 1536px)과 썸네일(짧은 변 320px). EXIF(위치 포함)는 남기지 않는다.
    final display = await FlutterImageCompress.compressWithFile(
      file.path,
      minWidth: 1536,
      minHeight: 1536,
      quality: 85,
    );
    final thumb = await FlutterImageCompress.compressWithFile(
      file.path,
      minWidth: 320,
      minHeight: 320,
      quality: 80,
    );
    if (display == null || thumb == null) {
      debugPrint('photo compress failed, skip: ${photo.imageUrl}');
      return;
    }

    final created = await _auth.authorized(
      'POST',
      '/v1/photos',
      json: {
        'id': photo.id,
        'session_id': photo.sessionId,
        'taken_at': _utc(photo.takenAt),
        'lat': photo.position.latitude,
        'lng': photo.position.longitude,
        'caption': photo.caption,
        'sha256': sha256.convert(display).toString(),
        'size_bytes': display.length,
        'content_type': 'image/jpeg',
      },
    ) as Map<String, dynamic>;

    final uploads = created['uploads'] as Map<String, dynamic>;
    final bytes = {'display': display, 'thumb': thumb};
    for (final entry in uploads.entries) {
      final target = entry.value as Map<String, dynamic>;
      await _auth.api.putBytes(
        target['url'] as String,
        bytes[entry.key]!,
        (target['headers'] as Map<String, dynamic>).cast<String, String>(),
      );
    }
    await _auth.authorized('POST', '/v1/photos/${photo.id}/complete');
    await _repository.markPhotoUploaded(photo.id);
  }

  static String _utc(DateTime value) => value.toUtc().toIso8601String();
}

class _SyncBlocked implements Exception {
  const _SyncBlocked(this.message);

  final String message;
}
