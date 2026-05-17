import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

class ShareCardExporter {
  static Future<File> export({
    required GlobalKey boundaryKey,
    required String sessionId,
  }) async {
    final context = boundaryKey.currentContext;
    if (context == null) {
      throw StateError('Share card is not ready.');
    }

    final boundary = context.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    return _writeFile(sessionId, bytes);
  }

  static Future<File> _writeFile(String sessionId, Uint8List bytes) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/walk_share_$sessionId.png');
    return file.writeAsBytes(bytes, flush: true);
  }
}
