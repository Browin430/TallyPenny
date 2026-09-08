import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// iOS 风格分段控件（带滑动动画的选中指示）。
class FMSegmented<T> extends StatelessWidget {
  const FMSegmented({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.height = 36,
  });

  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final index =
        items.indexWhere((e) => e.$1 == value).clamp(0, items.length - 1);

    return Container(
      height: height,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: s.ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment(index * 2 / (items.length - 1) - 1, 0),
            child: FractionallySizedBox(
              widthFactor: 1 / items.length,
              child: Container(
                decoration: BoxDecoration(
                  color: s.surface,
                  borderRadius: BorderRadius.circular(height / 2),
                  boxShadow: [
                    BoxShadow(
                      color: s.ink.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final (i, item) in items.indexed)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(item.$1),
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: AppText.bodyStrong(
                          i == index ? s.ink : s.inkSecondary,
                        ).copyWith(fontSize: 14),
                        child: Text(item.$2, maxLines: 1),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 圆角横向进度条，数值变化带动画。
class FMProgressBar extends StatelessWidget {
  const FMProgressBar({
    super.key,
    required this.value,
    this.height = 8,
    this.color,
    this.trackColor,
  });

  /// 0.0 ~ 1.0（超过 1 视作 1）。
  final double value;
  final double height;
  final Color? color;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final clamped = value.clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: clamped),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Container(
        height: height,
        decoration: BoxDecoration(
          color: trackColor ?? s.ink.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(height / 2),
        ),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: v,
          child: Container(
            decoration: BoxDecoration(
              color: color ?? s.accent,
              borderRadius: BorderRadius.circular(height / 2),
            ),
          ),
        ),
      ),
    );
  }
}
