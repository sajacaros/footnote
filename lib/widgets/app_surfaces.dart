import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 테마의 카드 스타일을 쓰는 전체 폭 박스.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox(
        width: double.infinity,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColors.inkMuted),
      ),
    );
  }
}

/// 숫자 + 단위 표기. 모든 화면에서 값 위, 단위 아래, 왼쪽 정렬로 통일한다.
///
/// 값이 숫자(예: 0.63, 54, 1,234)면 처음 보일 때 0부터, 바뀔 때는 이전 값에서
/// 새 값까지 짧게 올라간다. 시각(03:12)이나 '-' 같은 값은 그대로 보여 준다.
class MetricValue extends StatelessWidget {
  const MetricValue({
    required this.value,
    required this.label,
    this.onDark = false,
    super.key,
  });

  final String value;
  final String label;
  final bool onDark;

  static final _number = RegExp(r'^\d{1,3}(,\d{3})*(\.\d+)?$|^\d+(\.\d+)?$');

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = textTheme.headlineSmall?.copyWith(
      color: onDark ? Colors.white : AppColors.ink,
      fontFamily: kDisplayFont,
      fontSize: 28,
    );
    final Widget text;
    if (_number.hasMatch(value)) {
      final target = double.parse(value.replaceAll(',', ''));
      final dot = value.indexOf('.');
      final decimals = dot < 0 ? 0 : value.length - dot - 1;
      final grouped = value.contains(',');
      text = TweenAnimationBuilder<double>(
        tween: Tween(end: target),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, current, _) => Text(
          _format(current, decimals, grouped),
          maxLines: 1,
          style: style,
        ),
      );
    } else {
      text = Text(value, maxLines: 1, style: style);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 칸이 좁아도 줄바꿈하지 않고 글자를 줄인다(예: 걸음 수 12,345).
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: text,
        ),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            color: onDark ? Colors.white70 : AppColors.inkMuted,
          ),
        ),
      ],
    );
  }

  static String _format(double value, int decimals, bool grouped) {
    final fixed = value.toStringAsFixed(decimals);
    if (!grouped) {
      return fixed;
    }
    final parts = fixed.split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return parts.length > 1 ? '$whole.${parts[1]}' : whole;
  }
}

class MetricRow extends StatelessWidget {
  const MetricRow({required this.metrics, super.key});

  final List<MetricValue> metrics;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final metric in metrics) Expanded(child: metric)],
    );
  }
}
