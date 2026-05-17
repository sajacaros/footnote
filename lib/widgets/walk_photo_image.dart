import 'dart:io';

import 'package:flutter/material.dart';

class WalkPhotoImage extends StatelessWidget {
  const WalkPhotoImage({
    required this.imageUrl,
    required this.fit,
    super.key,
  });

  final String imageUrl;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return Image.network(
        imageUrl,
        fit: fit,
        errorBuilder: (_, __, ___) => const _MissingPhoto(),
      );
    }

    final file = File(imageUrl);
    if (!file.existsSync()) {
      return const _MissingPhoto();
    }

    return Image.file(
      file,
      fit: fit,
      errorBuilder: (_, __, ___) => const _MissingPhoto(),
    );
  }
}

class _MissingPhoto extends StatelessWidget {
  const _MissingPhoto();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE5E0D6),
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Colors.black.withValues(alpha: 0.48),
        ),
      ),
    );
  }
}
