import 'package:flutter/material.dart';

/// 앱 전체에서 쓰는 색 토큰. 화면 코드에서 색을 직접 적지 말고 여기서 가져온다.
class AppColors {
  // 크림색 바탕. 카드는 테두리 없이 흰 면과 옅은 그림자로만 띄운다.
  static const paper = Color(0xFFF8F5EE);
  static const surface = Colors.white;
  static const line = Color(0xFFE5E0D6);
  static const ink = Color(0xFF151713);
  static const inkMuted = Color(0xFF6B6D66);
  static const inkSubtle = Color(0xFF8F918A);

  static const brand = Color(0xFF1F8A70);
  static const brandStrong = Color(0xFF0B4F3F);
  static const brandText = Color(0xFF1F6F5B);
  static const brandTint = Color(0xFFE3F4EE);
  static const brandLight = Color(0xFF2A9D7F);

  // 앱 아이콘의 발바닥 분홍. 산책한 날, 대표 사진, 강조 숫자에 쓴다.
  static const paw = Color(0xFFF29AA3);
  static const pawStrong = Color(0xFFD9707C);
  static const pawTint = Color(0xFFFDE8EA);

  static const routeEnd = Color(0xFFDC5F00);
  static const warningTint = Color(0xFFFFF4D8);
  static const danger = Color(0xFFB3261E);

  /// 사진 위에 얹는 라벨 배경.
  static const photoScrim = Color(0xA0000000);
}

/// 모서리 둥글기. 아이콘처럼 말랑한 모양을 유지하려고 작은 값은 쓰지 않는다.
class AppRadius {
  static const double sm = 14;
  static const double md = 20;
  static const double lg = 26;
}

/// 제목·큰 숫자용 둥근 글꼴(Jua). 본문은 시스템 글꼴을 쓴다.
const kDisplayFont = 'Jua';

/// 흰 카드를 바탕에서 띄우는 그림자.
const kCardShadow = [
  BoxShadow(
    color: Color(0x14000000),
    blurRadius: 18,
    offset: Offset(0, 6),
  ),
];

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
      // 제목은 둥근 글꼴(Jua는 굵기가 하나라 weight를 주지 않는다).
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontFamily: kDisplayFont),
        titleLarge: TextStyle(fontFamily: kDisplayFont),
        titleMedium: TextStyle(fontFamily: kDisplayFont, fontSize: 18),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.paper,
        foregroundColor: AppColors.ink,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontFamily: kDisplayFont,
          fontSize: 24,
          height: 1.27,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 3,
        shadowColor: const Color(0x33000000),
        surfaceTintColor: Colors.transparent,
        color: AppColors.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      // 버튼은 모두 알약 모양.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.line, width: 1.5),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: const StadiumBorder()),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(shape: const CircleBorder()),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
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
