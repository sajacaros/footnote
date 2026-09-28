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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: textTheme.headlineSmall?.copyWith(
            color: onDark ? Colors.white : AppColors.ink,
            fontWeight: FontWeight.w800,
          ),
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
