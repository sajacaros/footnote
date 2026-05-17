import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart' hide LatLng;
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../models/walk_models.dart';
import '../services/session_photo_finder.dart';

class PhotoManageResult {
  const PhotoManageResult({
    required this.toAttach,
    required this.toDetach,
  });

  final List<SessionPhotoCandidate> toAttach;
  final List<String> toDetach;
}

class SessionPhotoManagerSheet extends StatefulWidget {
  const SessionPhotoManagerSheet({
    required this.candidates,
    required this.attachedPhotos,
    super.key,
  });

  final List<SessionPhotoCandidate> candidates;
  final List<WalkPhoto> attachedPhotos;

  @override
  State<SessionPhotoManagerSheet> createState() =>
      _SessionPhotoManagerSheetState();
}

class _SessionPhotoManagerSheetState extends State<SessionPhotoManagerSheet> {
  final Set<String> _selectedPaths = {};
  late final Set<String> _initialPaths =
      widget.attachedPhotos.map((photo) => photo.imageUrl).toSet();

  @override
  void initState() {
    super.initState();
    _selectedPaths.addAll(_initialPaths);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '사진 연결 관리',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(_result),
                    child: const Text('적용'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemBuilder: (context, index) {
                  final candidate = widget.candidates[index];
                  final selected = _selectedPaths.contains(candidate.path);
                  final initiallyAttached =
                      _initialPaths.contains(candidate.path);
                  return _CandidateTile(
                    candidate: candidate,
                    selected: selected,
                    initiallyAttached: initiallyAttached,
                    onTap: () {
                      setState(() {
                        if (selected) {
                          _selectedPaths.remove(candidate.path);
                        } else {
                          _selectedPaths.add(candidate.path);
                        }
                      });
                    },
                  );
                },
                itemCount: widget.candidates.length,
              ),
            ),
          ],
        ),
      ),
    );
  }

  PhotoManageResult get _result {
    final toDetach =
        _initialPaths.where((path) => !_selectedPaths.contains(path)).toList();
    final toAttach = widget.candidates
        .where(
          (candidate) =>
              _selectedPaths.contains(candidate.path) &&
              !_initialPaths.contains(candidate.path),
        )
        .toList();
    return PhotoManageResult(toAttach: toAttach, toDetach: toDetach);
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.selected,
    required this.initiallyAttached,
    required this.onTap,
  });

  final SessionPhotoCandidate candidate;
  final bool selected;
  final bool initiallyAttached;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(
              image: AssetEntityImageProvider(
                candidate.asset,
                isOriginal: false,
                thumbnailSize: const ThumbnailSize.square(240),
              ),
              fit: BoxFit.cover,
            ),
            if (selected)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.34),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                ),
              ),
            if (selected)
              const Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
            if (initiallyAttached)
              Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  margin: const EdgeInsets.all(6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.58),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '첨부됨',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
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
