import 'dart:async';

import 'package:flutter/material.dart';

import '../models/walk_models.dart';
import '../services/active_walk_service.dart';
import '../services/session_photo_finder.dart';
import '../widgets/session_photo_manager_sheet.dart';
import '../widgets/walk_map_preview.dart';
import '../widgets/walk_photo_image.dart';

class RecordWalkScreen extends StatefulWidget {
  const RecordWalkScreen({super.key});

  @override
  State<RecordWalkScreen> createState() => _RecordWalkScreenState();
}

class _RecordWalkScreenState extends State<RecordWalkScreen> {
  final ActiveWalkService _activeWalk = ActiveWalkService.instance;
  Timer? _ticker;
  bool _showMap = false;

  @override
  void initState() {
    super.initState();
    _activeWalk.addListener(_refresh);
    _activeWalk.start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _activeWalk.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _activeWalk.snapshot();

    return Scaffold(
      appBar: AppBar(
        title: const Text('진행 중인 산책'),
        leading: IconButton(
          tooltip: '뒤로',
          onPressed: () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            tooltip: _showMap ? '경로 숨기기' : '경로 보기',
            onPressed: () => setState(() => _showMap = !_showMap),
            icon: Icon(_showMap ? Icons.map_rounded : Icons.route_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            _StatusPanel(activeWalk: _activeWalk),
            if (_activeWalk.status != null) ...[
              const SizedBox(height: 12),
              _Notice(text: _activeWalk.status!),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _activeWalk.addPhoto,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('사진 찍기'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: '앨범에서 추가',
                  onPressed: _manageAlbumPhotos,
                  icon: const Icon(Icons.photo_library_outlined),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_showMap && snapshot != null) ...[
              WalkMapPreview(session: snapshot, interactive: true, height: 280),
              const SizedBox(height: 20),
            ],
            _PhotoSection(photos: _activeWalk.photos),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _activeWalk.isSaving ? null : _finishWalk,
              icon: _activeWalk.isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.stop_rounded),
              label: const Text('산책 종료하고 저장'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _confirmDiscard,
              child: const Text('이 산책 버리기'),
            ),
          ],
        ),
      ),
    );
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _finishWalk() async {
    final session = await _activeWalk.finish();
    if (!mounted) {
      return;
    }

    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('아직 기록된 위치가 없습니다.')),
      );
      return;
    }

    Navigator.of(context).pop(true);
  }

  Future<void> _manageAlbumPhotos() async {
    final startedAt = _activeWalk.startedAt;
    if (startedAt == null) {
      return;
    }

    final candidates = await SessionPhotoFinder.findPhotos(
      startedAt: startedAt,
      endedAt: DateTime.now(),
    );
    if (!mounted) {
      return;
    }

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
        attachedPhotos: _activeWalk.photos,
      ),
    );
    if (result == null) {
      return;
    }

    await _activeWalk.applyGalleryPhotoChanges(
      toAttach: result.toAttach,
      toDetach: result.toDetach,
    );
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('산책을 버릴까요?'),
        content: const Text('기록을 중단하고 진행 중인 세션을 삭제합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('계속 기록'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('버리기'),
          ),
        ],
      ),
    );

    if (discard != true) {
      return;
    }

    await _activeWalk.discard();
    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.activeWalk});

  final ActiveWalkService activeWalk;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF151713),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.directions_walk_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                '기록 중',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  value: _formatDuration(activeWalk.elapsed),
                  label: '시간',
                ),
              ),
              Expanded(
                child: _Metric(
                  value: (activeWalk.distanceMeters / 1000).toStringAsFixed(2),
                  label: 'km',
                ),
              ),
              Expanded(
                child: _Metric(
                  value: '${activeWalk.photos.length}',
                  label: '사진',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '이 화면을 나가도 산책을 종료하기 전까지 경로와 GPX 임시 저장이 계속됩니다.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

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
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white70,
              ),
        ),
      ],
    );
  }
}

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({required this.photos});

  final List<WalkPhoto> photos;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E0D6)),
        ),
        child: const Text('아직 찍은 사진이 없습니다.'),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final photo = photos[index];
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: WalkPhotoImage(imageUrl: photo.imageUrl, fit: BoxFit.cover),
        );
      },
      itemCount: photos.length,
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text),
    );
  }
}
