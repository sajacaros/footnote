import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/walk_models.dart';
import '../models/walk_reminder.dart';

class WalkRepository {
  WalkRepository._();

  static final WalkRepository instance = WalkRepository._();

  Database? _database;

  Future<List<WalkSession>> loadSessions() async {
    final db = await _open();

    final sessionRows = await db.query(
      'walk_sessions',
      orderBy: 'started_at DESC',
    );

    final sessions = <WalkSession>[];
    for (final row in sessionRows) {
      final id = row['id'] as String;
      final pointRows = await db.query(
        'track_points',
        where: 'session_id = ?',
        whereArgs: [id],
        orderBy: 'sequence ASC',
      );
      final photoRows = await db.query(
        'walk_photos',
        where: 'session_id = ?',
        whereArgs: [id],
        orderBy: 'taken_at ASC',
      );

      sessions.add(
        WalkSession(
          id: id,
          title: row['title'] as String,
          startedAt: _parseTs(row['started_at'] as String),
          endedAt: _parseTs(row['ended_at'] as String),
          note: row['note'] as String?,
          featuredPhotoId: row['featured_photo_id'] as String?,
          steps: row['steps'] as int?,
          points: pointRows.map(_pointFromRow).toList(),
          photos: photoRows.map(_photoFromRow).toList(),
        ),
      );
    }

    return sessions;
  }

  /// 세션을 저장한다. 행을 지웠다 다시 넣지 않아 사진의 업로드 상태가 유지된다.
  Future<void> saveSession(WalkSession session) async {
    final db = await _open();
    await db.transaction((txn) async {
      final values = {
        'title': session.title,
        'started_at': _ts(session.startedAt),
        'ended_at': _ts(session.endedAt),
        'note': session.note,
        'featured_photo_id': session.featuredPhotoId,
        'steps': session.steps,
      };
      final updated = await txn.update(
        'walk_sessions',
        values,
        where: 'id = ?',
        whereArgs: [session.id],
      );
      if (updated == 0) {
        await txn.insert('walk_sessions', {'id': session.id, ...values});
      }
      await _touch(txn, session.id);

      // 포인트는 기록이 끝날 때 한 번에 저장되고 seq가 고정이라 다시 써도 된다.
      await txn.delete(
        'track_points',
        where: 'session_id = ?',
        whereArgs: [session.id],
      );
      for (var index = 0; index < session.points.length; index += 1) {
        final point = session.points[index];
        await txn.insert('track_points', {
          'session_id': session.id,
          'sequence': index,
          'latitude': point.position.latitude,
          'longitude': point.position.longitude,
          'elevation': point.elevation,
          'accuracy': point.accuracy,
          'speed': point.speed,
          'recorded_at': _ts(point.recordedAt),
        });
      }

      final keepIds = session.photos.map((photo) => photo.id).toList();
      final existing = await txn.query(
        'walk_photos',
        columns: ['id'],
        where: 'session_id = ?',
        whereArgs: [session.id],
      );
      final removed = existing
          .map((row) => row['id'] as String)
          .where((id) => !keepIds.contains(id))
          .toList();
      await _deletePhotoRows(txn, removed);

      for (final photo in session.photos) {
        final photoValues = {
          'session_id': session.id,
          'image_url': photo.imageUrl,
          'latitude': photo.position.latitude,
          'longitude': photo.position.longitude,
          'taken_at': _ts(photo.takenAt),
          'caption': photo.caption,
        };
        final changed = await txn.update(
          'walk_photos',
          photoValues,
          where: 'id = ?',
          whereArgs: [photo.id],
        );
        if (changed == 0) {
          await txn.insert('walk_photos', {'id': photo.id, ...photoValues});
        }
      }
    });
  }

  Future<void> deleteSession(String sessionId) async {
    final db = await _open();
    await db.transaction((txn) async {
      await _queueDeletion(txn, 'session', sessionId);
      await txn.delete(
        'track_points',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      await txn.delete(
        'walk_photos',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      await txn.delete(
        'walk_sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    });
  }

  Future<void> addPhotos(String sessionId, List<WalkPhoto> photos) async {
    if (photos.isEmpty) {
      return;
    }

    final db = await _open();
    await db.transaction((txn) async {
      for (final photo in photos) {
        await txn.insert(
          'walk_photos',
          {
            'id': photo.id,
            'session_id': sessionId,
            'image_url': photo.imageUrl,
            'latitude': photo.position.latitude,
            'longitude': photo.position.longitude,
            'taken_at': _ts(photo.takenAt),
            'caption': photo.caption,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await _touch(txn, sessionId);
    });
  }

  Future<void> removePhotos(String sessionId, List<String> photoIds) async {
    if (photoIds.isEmpty) {
      return;
    }

    final db = await _open();
    await db.transaction((txn) async {
      final placeholders = List.filled(photoIds.length, '?').join(',');
      await _deletePhotoRows(txn, photoIds);
      await _touch(txn, sessionId);
      await txn.update(
        'walk_sessions',
        {'featured_photo_id': null},
        where: 'id = ? AND featured_photo_id IN ($placeholders)',
        whereArgs: [sessionId, ...photoIds],
      );
    });
  }

  Future<void> setFeaturedPhoto(String sessionId, String? photoId) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.update(
        'walk_sessions',
        {'featured_photo_id': photoId},
        where: 'id = ?',
        whereArgs: [sessionId],
      );
      await _touch(txn, sessionId);
    });
  }

  Future<void> updateSessionDetails({
    required String sessionId,
    required String title,
    required String? note,
  }) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.update(
        'walk_sessions',
        {
          'title': title,
          'note': note,
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );
      await _touch(txn, sessionId);
    });
  }

  Future<void> updateSteps(String sessionId, int steps) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.update(
        'walk_sessions',
        {'steps': steps},
        where: 'id = ?',
        whereArgs: [sessionId],
      );
      await _touch(txn, sessionId);
    });
  }

  Future<List<WalkReminder>> loadReminders() async {
    final db = await _open();
    final rows = await db.query(
      'walk_reminders',
      orderBy: 'hour ASC, minute ASC',
    );
    return rows.map(_reminderFromRow).toList();
  }

  /// 새 알림이면 insert하고, 저장된 id가 채워진 값을 돌려준다.
  Future<WalkReminder> saveReminder(WalkReminder reminder) async {
    final db = await _open();
    final values = {
      'label': reminder.label,
      'hour': reminder.hour,
      'minute': reminder.minute,
      'weekdays': (reminder.weekdays.toList()..sort()).join(','),
      'enabled': reminder.enabled ? 1 : 0,
    };
    if (reminder.id == null) {
      final id = await db.insert('walk_reminders', values);
      return reminder.copyWith(id: id);
    }
    await db.update(
      'walk_reminders',
      values,
      where: 'id = ?',
      whereArgs: [reminder.id],
    );
    return reminder;
  }

  Future<void> deleteReminder(int id) async {
    final db = await _open();
    await db.delete('walk_reminders', where: 'id = ?', whereArgs: [id]);
  }

  Future<Database> _open() async {
    if (_database != null) {
      return _database!;
    }

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'footnote_walk.db');
    _database = await openDatabase(
      path,
      version: 6,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE walk_sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            started_at TEXT NOT NULL,
            ended_at TEXT NOT NULL,
            note TEXT,
            featured_photo_id TEXT,
            steps INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE track_points (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            sequence INTEGER NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            elevation REAL,
            accuracy REAL,
            speed REAL,
            recorded_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE walk_photos (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            image_url TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            taken_at TEXT NOT NULL,
            caption TEXT
          )
        ''');
        await _createRemindersTable(db);
        await _addSyncSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE walk_sessions ADD COLUMN featured_photo_id TEXT',
          );
        }
        if (oldVersion < 3) {
          await _createRemindersTable(db);
        }
        if (oldVersion < 4) {
          await _addSyncSchema(db);
        }
        if (oldVersion < 5) {
          await db
              .execute('ALTER TABLE walk_sessions ADD COLUMN steps INTEGER');
        }
        if (oldVersion < 6) {
          await _removeSampleSessions(db);
        }
      },
    );

    return _database!;
  }

  /// 서버 동기화 상태.
  /// - 세션: 바뀔 때마다 sync_rev를 올리고, 서버에 반영한 rev를 synced_rev에 적는다.
  ///   동기화 중에 또 바뀌면 두 값이 달라서 다음 동기화 때 다시 보낸다.
  /// - synced_point_seq: 서버가 받았다고 확인한 마지막 포인트 seq.
  /// - 사진: 한 번 올리면 바이너리는 바뀌지 않으므로 pending → uploaded 한 방향만 있다.
  static Future<void> _addSyncSchema(Database db) async {
    await db.execute(
      'ALTER TABLE walk_sessions ADD COLUMN sync_rev INTEGER NOT NULL DEFAULT 1',
    );
    await db.execute(
      'ALTER TABLE walk_sessions ADD COLUMN synced_rev INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE walk_sessions ADD COLUMN synced_point_seq INTEGER NOT NULL DEFAULT -1',
    );
    await db.execute(
      "ALTER TABLE walk_photos ADD COLUMN sync_state TEXT NOT NULL DEFAULT 'pending'",
    );
    await db.execute('''
      CREATE TABLE sync_deletions (
        kind TEXT NOT NULL,
        remote_id TEXT NOT NULL,
        PRIMARY KEY (kind, remote_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE app_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  /// 예전 버전이 빈 DB에 넣던 예시 산책(walk-001~003)을 지운다.
  /// 서버로 올라간 적이 없으므로 삭제 대기열에 넣지 않는다.
  static Future<void> _removeSampleSessions(Database db) async {
    const where = "session_id IN ('walk-001', 'walk-002', 'walk-003')";
    await db.delete('track_points', where: where);
    await db.delete('walk_photos', where: where);
    await db.delete(
      'walk_sessions',
      where: "id IN ('walk-001', 'walk-002', 'walk-003')",
    );
  }

  static Future<void> _touch(DatabaseExecutor txn, String sessionId) async {
    await txn.rawUpdate(
      'UPDATE walk_sessions SET sync_rev = sync_rev + 1 WHERE id = ?',
      [sessionId],
    );
  }

  static Future<void> _queueDeletion(
    DatabaseExecutor txn,
    String kind,
    String remoteId,
  ) async {
    await txn.insert(
      'sync_deletions',
      {'kind': kind, 'remote_id': remoteId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 사진 행을 지우고, 서버에 올라간 사진이면 서버 삭제 대기열에 넣는다.
  static Future<void> _deletePhotoRows(
    DatabaseExecutor txn,
    List<String> photoIds,
  ) async {
    for (final id in photoIds) {
      final rows = await txn.query(
        'walk_photos',
        columns: ['sync_state'],
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isNotEmpty && rows.first['sync_state'] == 'uploaded') {
        await _queueDeletion(txn, 'photo', id);
      }
      await txn.delete('walk_photos', where: 'id = ?', whereArgs: [id]);
    }
  }

  static String _ts(DateTime value) => value.toUtc().toIso8601String();

  /// 예전 행은 시간대 없는 로컬 시각, 새 행은 UTC다. 둘 다 로컬 시각으로 돌려준다.
  static DateTime _parseTs(String value) => DateTime.parse(value).toLocal();

  // ---- 동기화 ----

  Future<List<SyncTarget>> pendingSyncSessions() async {
    final db = await _open();
    final rows = await db.query(
      'walk_sessions',
      columns: ['id', 'sync_rev', 'synced_point_seq'],
      where: 'sync_rev <> synced_rev',
      orderBy: 'started_at ASC',
    );
    return rows
        .map(
          (row) => SyncTarget(
            sessionId: row['id'] as String,
            rev: row['sync_rev'] as int,
            syncedPointSeq: row['synced_point_seq'] as int,
          ),
        )
        .toList();
  }

  Future<WalkSession?> loadSession(String sessionId) async {
    final sessions = await loadSessions();
    for (final session in sessions) {
      if (session.id == sessionId) {
        return session;
      }
    }
    return null;
  }

  Future<Set<String>> uploadedPhotoIds(String sessionId) async {
    final db = await _open();
    final rows = await db.query(
      'walk_photos',
      columns: ['id'],
      where: "session_id = ? AND sync_state = 'uploaded'",
      whereArgs: [sessionId],
    );
    return rows.map((row) => row['id'] as String).toSet();
  }

  Future<void> setSyncedPointSeq(String sessionId, int seq) async {
    final db = await _open();
    await db.update(
      'walk_sessions',
      {'synced_point_seq': seq},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> markPhotoUploaded(String photoId) async {
    final db = await _open();
    await db.update(
      'walk_photos',
      {'sync_state': 'uploaded'},
      where: 'id = ?',
      whereArgs: [photoId],
    );
  }

  /// 동기화를 시작할 때 읽은 rev까지만 반영됐다고 표시한다.
  Future<void> markSessionSynced(String sessionId, int rev) async {
    final db = await _open();
    await db.update(
      'walk_sessions',
      {'synced_rev': rev},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<List<SyncDeletion>> pendingDeletions() async {
    final db = await _open();
    final rows = await db.query('sync_deletions');
    return rows
        .map(
          (row) => SyncDeletion(
            kind: row['kind'] as String,
            remoteId: row['remote_id'] as String,
          ),
        )
        .toList();
  }

  Future<void> clearDeletion(SyncDeletion deletion) async {
    final db = await _open();
    await db.delete(
      'sync_deletions',
      where: 'kind = ? AND remote_id = ?',
      whereArgs: [deletion.kind, deletion.remoteId],
    );
  }

  /// 서버로 보낼 세션 수와 삭제 대기 수.
  Future<int> pendingSyncCount() async {
    final db = await _open();
    final sessions = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM walk_sessions WHERE sync_rev <> synced_rev',
          ),
        ) ??
        0;
    final deletions = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM sync_deletions'),
        ) ??
        0;
    return sessions + deletions;
  }

  Future<String?> readMeta(String key) async {
    final db = await _open();
    final rows = await db.query(
      'app_meta',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> writeMeta(String key, String? value) async {
    final db = await _open();
    await db.insert(
      'app_meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> _createRemindersTable(Database db) async {
    await db.execute('''
      CREATE TABLE walk_reminders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        label TEXT NOT NULL,
        hour INTEGER NOT NULL,
        minute INTEGER NOT NULL,
        weekdays TEXT NOT NULL,
        enabled INTEGER NOT NULL
      )
    ''');
  }

  TrackPoint _pointFromRow(Map<String, Object?> row) {
    return TrackPoint(
      position: LatLng(
        (row['latitude'] as num).toDouble(),
        (row['longitude'] as num).toDouble(),
      ),
      recordedAt: _parseTs(row['recorded_at'] as String),
      elevation: (row['elevation'] as num?)?.toDouble(),
      accuracy: (row['accuracy'] as num?)?.toDouble(),
      speed: (row['speed'] as num?)?.toDouble(),
    );
  }

  WalkPhoto _photoFromRow(Map<String, Object?> row) {
    return WalkPhoto(
      id: row['id'] as String,
      sessionId: row['session_id'] as String,
      imageUrl: row['image_url'] as String,
      position: LatLng(
        (row['latitude'] as num).toDouble(),
        (row['longitude'] as num).toDouble(),
      ),
      takenAt: _parseTs(row['taken_at'] as String),
      caption: row['caption'] as String?,
    );
  }

  WalkReminder _reminderFromRow(Map<String, Object?> row) {
    final weekdays = (row['weekdays'] as String)
        .split(',')
        .where((value) => value.isNotEmpty)
        .map(int.parse)
        .toSet();
    return WalkReminder(
      id: row['id'] as int,
      label: row['label'] as String,
      hour: row['hour'] as int,
      minute: row['minute'] as int,
      weekdays: weekdays,
      enabled: (row['enabled'] as int) == 1,
    );
  }
}

/// 서버로 보낼 세션.
class SyncTarget {
  const SyncTarget({
    required this.sessionId,
    required this.rev,
    required this.syncedPointSeq,
  });

  final String sessionId;
  final int rev;
  final int syncedPointSeq;
}

/// 서버에서도 지워야 하는 항목.
class SyncDeletion {
  const SyncDeletion({required this.kind, required this.remoteId});

  /// 'session' 또는 'photo'
  final String kind;
  final String remoteId;
}
