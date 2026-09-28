import 'dart:io';

import 'package:photo_manager/photo_manager.dart';

class SessionPhotoCandidate {
  const SessionPhotoCandidate({
    required this.asset,
    required this.takenAt,
    required this.path,
  });

  final AssetEntity asset;
  final DateTime takenAt;
  final String path;
}

class SessionPhotoFinder {
  static Future<List<SessionPhotoCandidate>> findPhotos({
    required DateTime startedAt,
    required DateTime endedAt,
  }) async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) {
      await PhotoManager.openSetting();
      return [];
    }

    final count = await PhotoManager.getAssetCount(type: RequestType.image);
    if (count == 0) {
      return [];
    }

    final assets = await PhotoManager.getAssetListRange(
      start: 0,
      end: count > 1000 ? 1000 : count,
      type: RequestType.image,
      filterOption: FilterOptionGroup(
        orders: const [
          OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );

    final candidates = <SessionPhotoCandidate>[];
    final queryStart = startedAt.subtract(const Duration(minutes: 10));
    final queryEnd = endedAt.add(const Duration(minutes: 10));
    for (final asset in assets) {
      final file = await asset.file;
      if (file == null) {
        continue;
      }
      final takenAt = await _bestTakenAt(asset, file);
      if (takenAt.isBefore(queryStart) || takenAt.isAfter(queryEnd)) {
        continue;
      }
      candidates.add(
        SessionPhotoCandidate(
          asset: asset,
          takenAt: takenAt,
          path: file.path,
        ),
      );
    }
    return candidates;
  }

  static Future<String?> filePath(SessionPhotoCandidate candidate) async =>
      candidate.path;

  static Future<DateTime> _bestTakenAt(AssetEntity asset, File file) async {
    final createDate = asset.createDateTime;
    if (createDate.year > 1971) {
      return createDate;
    }

    final modifiedDate = asset.modifiedDateTime;
    if (modifiedDate.year > 1971) {
      return modifiedDate;
    }

    final stat = await file.stat();
    return stat.modified;
  }
}
