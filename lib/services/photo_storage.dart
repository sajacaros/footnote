import 'dart:io';

import 'package:media_store_plus/media_store_plus.dart';
import 'package:path/path.dart' as p;

class PhotoStorage {
  static Future<String> saveWalkPhoto({
    required String sessionId,
    required File source,
  }) async {
    final extension =
        p.extension(source.path).isEmpty ? '.jpg' : p.extension(source.path);
    final fileName =
        '${sessionId}_${DateTime.now().microsecondsSinceEpoch}$extension';
    final tempSource = await _ensureNamedTempFile(source, fileName);
    final mediaStore = MediaStore();
    final saved = await mediaStore.saveFile(
      tempFilePath: tempSource.path,
      dirType: DirType.photo,
      dirName: DirName.pictures,
      relativePath: 'Footnote Walk',
    );

    if (saved == null) {
      return source.path;
    }

    return await mediaStore.getFilePathFromUri(
          uriString: saved.uri.toString(),
        ) ??
        source.path;
  }

  static Future<File> _ensureNamedTempFile(File source, String fileName) async {
    final currentName = p.basename(source.path);
    if (currentName == fileName) {
      return source;
    }

    final tempFile = File(p.join(p.dirname(source.path), fileName));
    return source.copy(tempFile.path);
  }
}
