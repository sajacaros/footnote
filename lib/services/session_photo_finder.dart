import 'dart:io';

import 'package:photo_manager/photo_manager.dart';

/// 사진(이미지)만 요청한다. 기본값(RequestType.common)은 영상 권한까지 요구하는데
/// 매니페스트에 READ_MEDIA_VIDEO가 없어서 Android 13에서는 늘 거부로 판정된다.
const photoPermissionOption = PermissionRequestOption(
  androidPermission: AndroidPermission(
    type: RequestType.image,
    mediaLocation: false,
  ),
);

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

enum PhotoAccess { full, limited, denied }

class SessionPhotoSearch {
  const SessionPhotoSearch(this.access, this.candidates);

  final PhotoAccess access;
  final List<SessionPhotoCandidate> candidates;
}

class SessionPhotoFinder {
  static Future<SessionPhotoSearch> findPhotos({
    required DateTime startedAt,
    required DateTime endedAt,
  }) async {
    final permission = await PhotoManager.requestPermissionExtend(
      requestOption: photoPermissionOption,
    );
    if (!permission.hasAccess) {
      return const SessionPhotoSearch(PhotoAccess.denied, []);
    }
    final access =
        permission.isAuth ? PhotoAccess.full : PhotoAccess.limited;

    // 시간대 조건을 쿼리에 넣는다. 예전처럼 최근 1000장의 파일을 하나씩 열어
    // 보면 사진이 많은 폰에서 한참 걸리고, 1000장보다 오래된 산책은 못 찾는다.
    // 기준은 찍은 시각(datetaken, ms)이고, 없으면 추가된 시각(date_added, 초)을 쓴다.
    // createTimeCond는 date_added만 보므로 나중에 폰에 저장된 사진을 놓친다.
    // 자동 종료는 멈춘 뒤 최대 20분을 잘라 내므로 끝 쪽 여유를 넉넉히 둔다.
    final queryStart = startedAt.subtract(const Duration(minutes: 10));
    final queryEnd = endedAt.add(const Duration(minutes: 30));
    final minMs = queryStart.millisecondsSinceEpoch;
    final maxMs = queryEnd.millisecondsSinceEpoch;
    final filter = CustomFilter.sql(
      where: 'COALESCE(NULLIF(datetaken, 0), date_added * 1000) '
          'BETWEEN $minMs AND $maxMs',
      orderBy: const [OrderByItem.desc('datetaken')],
    );

    final count = await PhotoManager.getAssetCount(
      type: RequestType.image,
      filterOption: filter,
    );
    if (count == 0) {
      return SessionPhotoSearch(access, const []);
    }

    final assets = await PhotoManager.getAssetListRange(
      start: 0,
      end: count,
      type: RequestType.image,
      filterOption: filter,
    );

    final candidates = <SessionPhotoCandidate>[];
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
    return SessionPhotoSearch(access, candidates);
  }

  /// 일부 사진만 허용한 상태에서 사진을 더 고르게 한다.
  static Future<void> selectMorePhotos() =>
      PhotoManager.presentLimited(type: RequestType.image);

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
