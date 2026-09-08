import 'package:flutter/material.dart';

import '../icons/app_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../utils/app_date_utils.dart';

/// 月份切换器：‹ 2026年8月 ›，未来月份禁用前进。
class FMMonthSwitcher extends StatelessWidget {
  const FMMonthSwitcher({
    super.key,
    required this.month,
    required this.onChanged,
  });

  /// 任意月份内日期（内部取 1 号）。
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final now = DateTime.now();
    final canGoNext = AppDate.isSameMonth(month, now) ? false : true;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NavButton(
          icon: FMIcons.chevronLeft,
          onTap: () => onChanged(AppDate.addMonths(month, -1)),
        ),
        const SizedBox(width: FMSpacing.s),
        Text(
          AppDate.monthTitle(month),
          style: AppText.title(s.ink).copyWith(fontSize: 18),
        ),
        const SizedBox(width: FMSpacing.s),
        _NavButton(
          icon: FMIcons.chevronRight,
          enabled: canGoNext,
          onTap:
              canGoNext ? () => onChanged(AppDate.addMonths(month, 1)) : null,
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, this.onTap, this.enabled = true});

  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Opacity(
      opacity: enabled ? 1 : 0.3,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: s.ink.withValues(alpha: 0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 15, color: s.ink),
        ),
      ),
    );
  }
}
