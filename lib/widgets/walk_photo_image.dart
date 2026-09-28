import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class WalkPhotoImage extends StatelessWidget {
  const WalkPhotoImage({
    required this.imageUrl,
    required this.fit,
    this.decodeWidth,
    super.key,
  });

  final String imageUrl;
  final BoxFit fit;

  /// 작게만 보여 줄 때 이 폭(px)으로 줄여 읽어 메모리를 아낀다.
  final int? decodeWidth;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return Image.network(
        imageUrl,
        fit: fit,
        cacheWidth: decodeWidth,
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
      cacheWidth: decodeWidth,
      errorBuilder: (_, __, ___) => const _MissingPhoto(),
    );
  }
}

class _MissingPhoto extends StatelessWidget {
  const _MissingPhoto();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.line,
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: AppColors.inkSubtle,
        ),
      ),
    );
  }
}
