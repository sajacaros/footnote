import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

class PhotoStorage {
  static const _relativePath = 'Pictures/Footnote Walk';

  static Future<String> saveWalkPhoto({
    required String sessionId,
    required File source,
  }) async {
    final extension =
        p.extension(source.path).isEmpty ? '.jpg' : p.extension(source.path);
    final fileName =
        '${sessionId}_${DateTime.now().microsecondsSinceEpoch}$extension';

    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) {
      return source.path;
    }

    try {
      final saved = await PhotoManager.editor.saveImageWithPath(
        source.path,
        title: fileName,
        relativePath: _relativePath,
      );
      final file = await saved.file;
      return file?.path ?? source.path;
    } catch (_) {
      return source.path;
    }
  }
}
