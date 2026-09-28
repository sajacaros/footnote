import 'package:flutter/material.dart';

/// 앱 전체에서 쓰는 색 토큰. 화면 코드에서 색을 직접 적지 말고 여기서 가져온다.
class AppColors {
  static const paper = Color(0xFFF7F6F1);
  static const surface = Colors.white;
  static const line = Color(0xFFE5E0D6);
  static const ink = Color(0xFF151713);
  static const inkMuted = Color(0xFF6B6D66);
  static const inkSubtle = Color(0xFF8F918A);

  static const brand = Color(0xFF1F8A70);
  static const brandStrong = Color(0xFF0B4F3F);
  static const brandText = Color(0xFF1F6F5B);
  static const brandTint = Color(0xFFEAF6F1);

  static const routeEnd = Color(0xFFDC5F00);
  static const warningTint = Color(0xFFFFF4D8);
  static const danger = Color(0xFFB3261E);

  /// 사진 위에 얹는 라벨 배경.
  static const photoScrim = Color(0xA0000000);
}

class AppTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: Brightness.light,
      surface: AppColors.paper,
    ).copyWith(
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.inkMuted,
      outlineVariant: AppColors.line,
      error: AppColors.danger,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.paper,
      // 위계: 화면 제목(titleLarge) > 섹션 제목(titleMedium) > 본문. 굵기는 w800까지만 쓴다.
      // 크기는 로케일별 기본 타이포그래피에서 합쳐지므로 여기서는 굵기만 지정한다.
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontWeight: FontWeight.w800),
        titleMedium: TextStyle(fontWeight: FontWeight.w800),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.paper,
        foregroundColor: AppColors.ink,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          height: 1.27,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.line, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  /// 되돌릴 수 없는 동작(삭제·버리기) 확인 버튼.
  static ButtonStyle dangerFilledButton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton.styleFrom(
      backgroundColor: scheme.error,
      foregroundColor: scheme.onError,
    );
  }
}
