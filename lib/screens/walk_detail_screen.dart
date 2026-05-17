import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/walk_models.dart';
import '../services/gpx_exporter.dart';
import '../services/session_photo_finder.dart';
import '../services/share_card_exporter.dart';
import '../services/walk_repository.dart';
import '../widgets/session_photo_manager_sheet.dart';
import '../widgets/walk_map_preview.dart';
import '../widgets/walk_photo_image.dart';

class WalkDetailScreen extends StatefulWidget {
  const WalkDetailScreen({required this.session, super.key});

  final WalkSession session;

  @override
  State<WalkDetailScreen> createState() => _WalkDetailScreenState();
}

class _WalkDetailScreenState extends State<WalkDetailScreen> {
  late WalkSession _session = widget.session;
  final GlobalKey _mapCaptureKey = GlobalKey();
  bool _addingPhotos = false;
  bool _sharingImage = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 380,
            title: Text(_session.title),
            actions: [
              IconButton(
                tooltip: 'GPX 공유',
                onPressed: () => _shareGpx(context),
                icon: const Icon(Icons.ios_share_rounded),
              ),
              IconButton(
                tooltip: '이미지 공유',
                onPressed: _sharingImage ? null : _shareImage,
                icon: const Icon(Icons.image_outlined),
              ),
              IconButton(
                tooltip: '사진 추가',
                onPressed: _addingPhotos ? null : _addSessionPhotos,
                icon: const Icon(Icons.add_photo_alternate_outlined),
              ),
              IconButton(
                tooltip: '산책 삭제',
                onPressed: () => _confirmDelete(context),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: RepaintBoundary(
                key: _mapCaptureKey,
                child: WalkMapPreview(
                  session: _session,
                  interactive: true,
                  height: 380,
                  onPhotoTap: (photo) => _showPhoto(context, photo),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(
                  children: [
                    Expanded(
                      child: _StatBlock(
                        value:
                            (_session.distanceMeters / 1000).toStringAsFixed(2),
                        label: 'km',
                      ),
                    ),
                    Expanded(
                      child: _StatBlock(
                        value: '${_session.duration.inMinutes}',
                        label: '분',
                      ),
                    ),
                    Expanded(
                      child: _StatBlock(
                        value: '${_session.photos.length}',
                        label: '사진',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  '${DateFormat('yyyy.MM.dd HH:mm').format(_session.startedAt)} - '
                  '${DateFormat('HH:mm').format(_session.endedAt)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.black54,
                      ),
                ),
                if (_session.note != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _session.note!,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  '사진 위치',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 150,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (context, index) {
                      final photo = _session.photos[index];
                      return _PhotoThumb(
                        photo: photo,
                        onTap: () => _showPhoto(context, photo),
                        onRemove: () => _removePhotoLink(photo),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemCount: _session.photos.length,
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareGpx(BuildContext context) async {
    final file = await GpxExporter.writeToDownloads(_session);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: '${_session.title}.gpx',
    );
  }

  Future<void> _shareImage() async {
    setState(() => _sharingImage = true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      final file = await ShareCardExporter.export(
        boundaryKey: _mapCaptureKey,
        sessionId: _session.id,
      );
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '${_session.title}.png',
      );
    } finally {
      if (mounted) {
        setState(() => _sharingImage = false);
      }
    }
  }

  Future<void> _addSessionPhotos() async {
    setState(() => _addingPhotos = true);
    final candidates = await SessionPhotoFinder.findPhotos(
      startedAt: _session.startedAt,
      endedAt: _session.endedAt,
    );
    if (!mounted) {
      return;
    }
    setState(() => _addingPhotos = false);

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이 산책 시간대에 찍힌 사진이 없습니다.')),
      );
      return;
    }

    final result = await showModalBottomSheet<PhotoManageResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SessionPhotoManagerSheet(
        candidates: candidates,
        attachedPhotos: _session.photos,
      ),
    );
    if (result == null) {
      return;
    }

    final currentByPath = {
      for (final photo in _session.photos) photo.imageUrl: photo,
    };
    final photosToAdd = <WalkPhoto>[];
    for (final candidate in result.toAttach) {
      final path = candidate.path;
      if (currentByPath.containsKey(path)) {
        continue;
      }
      photosToAdd.add(
        WalkPhoto(
          id: const Uuid().v4(),
          sessionId: _session.id,
          imageUrl: path,
          position: _positionForCandidate(candidate),
          takenAt: candidate.takenAt,
          caption: '앨범에서 추가',
        ),
      );
    }

    final idsToRemove = result.toDetach
        .map((path) => currentByPath[path]?.id)
        .whereType<String>()
        .toList();

    if (photosToAdd.isEmpty && idsToRemove.isEmpty) {
      return;
    }

    await WalkRepository.instance.addPhotos(_session.id, photosToAdd);
    await WalkRepository.instance.removePhotos(_session.id, idsToRemove);
    if (!mounted) {
      return;
    }
    setState(() {
      final remaining = _session.photos
          .where((photo) => !idsToRemove.contains(photo.id))
          .toList();
      _session = _session.copyWith(
        photos: [...remaining, ...photosToAdd]
          ..sort((a, b) => a.takenAt.compareTo(b.takenAt)),
      );
    });
  }

  LatLng _positionForCandidate(SessionPhotoCandidate candidate) {
    if (_session.points.isEmpty) {
      return _session.center;
    }

    var closest = _session.points.first;
    var smallestGap = candidate.takenAt.difference(closest.recordedAt).abs();
    for (final point in _session.points.skip(1)) {
      final gap = candidate.takenAt.difference(point.recordedAt).abs();
      if (gap < smallestGap) {
        smallestGap = gap;
        closest = point;
      }
    }
    return closest.position;
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('산책 기록을 삭제할까요?'),
        content: const Text(
          '경로와 산책 기록만 삭제합니다. 사진 파일은 삭제하지 않습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (delete != true || !context.mounted) {
      return;
    }

    await WalkRepository.instance.deleteSession(_session.id);

    if (context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _removePhotoLink(WalkPhoto photo) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('사진 연결을 제거할까요?'),
        content: const Text('산책 기록에서만 제거합니다. 원본 사진 파일은 삭제하지 않습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('연결 제거'),
          ),
        ],
      ),
    );

    if (remove != true) {
      return;
    }

    await WalkRepository.instance.removePhotos(_session.id, [photo.id]);
    if (!mounted) {
      return;
    }
    setState(() {
      _session = _session.copyWith(
        photos: _session.photos.where((item) => item.id != photo.id).toList(),
      );
    });
  }

  void _showPhoto(BuildContext context, WalkPhoto photo) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog.fullscreen(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                child: WalkPhotoImage(
                  imageUrl: photo.imageUrl,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: IconButton.filledTonal(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black54,
              ),
        ),
      ],
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({
    required this.photo,
    required this.onTap,
    required this.onRemove,
  });

  final WalkPhoto photo;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          GestureDetector(
            onTap: onTap,
            onLongPress: onRemove,
            child: SizedBox(
              width: 118,
              height: 150,
              child: WalkPhotoImage(
                imageUrl: photo.imageUrl,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: IconButton.filledTonal(
              tooltip: '사진 연결 제거',
              style: IconButton.styleFrom(
                minimumSize: const Size(34, 34),
                fixedSize: const Size(34, 34),
                padding: EdgeInsets.zero,
              ),
              onPressed: onRemove,
              icon: const Icon(Icons.link_off_rounded, size: 18),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.56),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  DateFormat('HH:mm').format(photo.takenAt),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
