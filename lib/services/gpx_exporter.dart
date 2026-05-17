import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/walk_models.dart';

class GpxExporter {
  static final DateFormat _fileDate = DateFormat('yyyyMMdd_HHmm');

  static String build(WalkSession session) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<gpx version="1.1" creator="Footnote Walk" xmlns="http://www.topografix.com/GPX/1/1">',
      )
      ..writeln('  <metadata>')
      ..writeln('    <name>${_escape(session.title)}</name>')
      ..writeln('    <time>${_iso(session.startedAt)}</time>')
      ..writeln('  </metadata>');

    for (final photo in session.photos) {
      buffer
        ..writeln(
          '  <wpt lat="${photo.position.latitude}" lon="${photo.position.longitude}">',
        )
        ..writeln('    <time>${_iso(photo.takenAt)}</time>')
        ..writeln('    <name>${_escape(photo.caption ?? 'Walk photo')}</name>')
        ..writeln('    <link href="${_escape(photo.imageUrl)}" />')
        ..writeln('  </wpt>');
    }

    buffer
      ..writeln('  <trk>')
      ..writeln('    <name>${_escape(session.title)}</name>')
      ..writeln('    <trkseg>');

    for (final point in session.points) {
      buffer.writeln(
        '      <trkpt lat="${point.position.latitude}" lon="${point.position.longitude}">',
      );
      if (point.elevation != null) {
        buffer.writeln('        <ele>${point.elevation}</ele>');
      }
      buffer
        ..writeln('        <time>${_iso(point.recordedAt)}</time>')
        ..writeln('      </trkpt>');
    }

    buffer
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');

    return buffer.toString();
  }

  static Future<File> writeToDownloads(WalkSession session) async {
    final directory = await getApplicationDocumentsDirectory();
    final fileName = 'walk_${_fileDate.format(session.startedAt)}.gpx';
    final file = File('${directory.path}/$fileName');
    return file.writeAsString(build(session));
  }

  static Future<File> writeActiveDraft(WalkSession session) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/active_walk_${session.id}.gpx');
    return file.writeAsString(build(session));
  }

  static String _iso(DateTime value) => value.toUtc().toIso8601String();

  static String _escape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
