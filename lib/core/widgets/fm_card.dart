import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// 基础卡片：圆角 20、柔和阴影（浅色）/ 描边（深色）。
class FMCard extends StatelessWidget {
  const FMCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(FMSpacing.l),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.color,
    this.radius = FMRadius.card,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final isDark = s.brightness == Brightness.dark;
    final border = (isDark || borderColor != null)
        ? Border.all(color: borderColor ?? s.border, width: 0.5)
        : null;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? s.surface,
        borderRadius: BorderRadius.circular(radius),
        border: border,
        boxShadow: s.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// 区块标题：左侧标题 + 右侧可选动作。
class FMSectionHeader extends StatelessWidget {
  const FMSectionHeader({
    super.key,
    required this.title,
    this.actionText,
    this.onAction,
  });

  final String title;
  final String? actionText;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Padding(
      padding: const EdgeInsets.only(
        left: FMSpacing.xs,
        right: FMSpacing.xs,
        top: FMSpacing.s,
        bottom: FMSpacing.m,
      ),
      child: Row(
        children: [
          Expanded(child: Text(title, style: AppText.title(s.ink))),
          if (actionText != null)
            GestureDetector(
              // 热区扩到文字周围的内边距区域，避免在滚动列表里点空。
              behavior: HitTestBehavior.opaque,
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: FMSpacing.xs,
                  vertical: FMSpacing.s,
                ),
                child: Text(
                  actionText!,
                  style: AppText.sub(s.accent),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 空状态占位。
class FMEmptyState extends StatelessWidget {
  const FMEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: FMSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: s.inkTertiary),
            const SizedBox(height: FMSpacing.m),
            Text(title, style: AppText.bodyStrong(s.inkSecondary)),
            if (subtitle != null) ...[
              const SizedBox(height: FMSpacing.xs),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppText.sub(s.inkTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
