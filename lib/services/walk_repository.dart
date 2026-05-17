import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/walk_models.dart';
import 'mock_walk_repository.dart';

class WalkRepository {
  WalkRepository._();

  static final WalkRepository instance = WalkRepository._();

  Database? _database;

  Future<List<WalkSession>> loadSessions() async {
    final db = await _open();
    await _seedIfEmpty(db);

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
          startedAt: DateTime.parse(row['started_at'] as String),
          endedAt: DateTime.parse(row['ended_at'] as String),
          note: row['note'] as String?,
          points: pointRows.map(_pointFromRow).toList(),
          photos: photoRows.map(_photoFromRow).toList(),
        ),
      );
    }

    return sessions;
  }

  Future<void> saveSession(WalkSession session) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.insert(
        'walk_sessions',
        {
          'id': session.id,
          'title': session.title,
          'started_at': session.startedAt.toIso8601String(),
          'ended_at': session.endedAt.toIso8601String(),
          'note': session.note,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        'track_points',
        where: 'session_id = ?',
        whereArgs: [session.id],
      );
      await txn.delete(
        'walk_photos',
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
          'recorded_at': point.recordedAt.toIso8601String(),
        });
      }

      for (final photo in session.photos) {
        await txn.insert('walk_photos', {
          'id': photo.id,
          'session_id': photo.sessionId,
          'image_url': photo.imageUrl,
          'latitude': photo.position.latitude,
          'longitude': photo.position.longitude,
          'taken_at': photo.takenAt.toIso8601String(),
          'caption': photo.caption,
        });
      }
    });
  }

  Future<void> deleteSession(String sessionId) async {
    final db = await _open();
    await db.transaction((txn) async {
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
            'taken_at': photo.takenAt.toIso8601String(),
            'caption': photo.caption,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<void> removePhotos(String sessionId, List<String> photoIds) async {
    if (photoIds.isEmpty) {
      return;
    }

    final db = await _open();
    final placeholders = List.filled(photoIds.length, '?').join(',');
    await db.delete(
      'walk_photos',
      where: 'session_id = ? AND id IN ($placeholders)',
      whereArgs: [sessionId, ...photoIds],
    );
  }

  Future<Database> _open() async {
    if (_database != null) {
      return _database!;
    }

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'footnote_walk.db');
    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE walk_sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            started_at TEXT NOT NULL,
            ended_at TEXT NOT NULL,
            note TEXT
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
      },
    );

    return _database!;
  }

  Future<void> _seedIfEmpty(Database db) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM walk_sessions');
    final count = Sqflite.firstIntValue(rows) ?? 0;
    if (count > 0) {
      return;
    }

    for (final session in MockWalkRepository.loadSessions()) {
      await saveSession(session);
    }
  }

  TrackPoint _pointFromRow(Map<String, Object?> row) {
    return TrackPoint(
      position: LatLng(
        (row['latitude'] as num).toDouble(),
        (row['longitude'] as num).toDouble(),
      ),
      recordedAt: DateTime.parse(row['recorded_at'] as String),
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
      takenAt: DateTime.parse(row['taken_at'] as String),
      caption: row['caption'] as String?,
    );
  }
}
