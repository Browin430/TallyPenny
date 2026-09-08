import 'package:flutter/material.dart';

import '../../domain/models/enums.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../utils/money_utils.dart';

/// 金额文本：符号 + 货币符号小一号弱化，数字部分 tabular 对齐。
/// 收入柔和绿，支出用墨色（避免满屏红色）。
class FMAmountText extends StatelessWidget {
  const FMAmountText(
    this.cents, {
    super.key,
    required this.type,
    this.style,
    this.showSign = true,
    this.color,
    this.symbol = '¥',
  });

  final int cents;
  final TransactionType type;
  final TextStyle? style;
  final bool showSign;
  final Color? color;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final mainColor =
        color ?? (type == TransactionType.income ? s.income : s.ink);
    final base = style ?? AppText.amountM(mainColor);
    final isIncome = type == TransactionType.income;
    final sign = !showSign ? '' : (isIncome ? '+' : '-');
    final number = Money.centsToText(cents);

    return Text.rich(
      TextSpan(
        children: [
          if (sign.isNotEmpty)
            TextSpan(
              text: sign,
              style: base.copyWith(
                fontSize: base.fontSize != null ? base.fontSize! * 0.86 : null,
                color: mainColor.withValues(alpha: 0.75),
              ),
            ),
          TextSpan(
            text: symbol,
            style: base.copyWith(
              fontSize: base.fontSize != null ? base.fontSize! * 0.78 : null,
              fontWeight: FontWeight.w500,
              color: mainColor.withValues(alpha: 0.6),
            ),
          ),
          TextSpan(text: number, style: base),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// 通用小徽章。
class FMBadge extends StatelessWidget {
  const FMBadge({
    super.key,
    required this.label,
    this.color,
    this.textColor,
    this.icon,
  });

  final String label;
  final Color? color;
  final Color? textColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final c = color ?? s.inkTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FMSpacing.s,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(FMRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: textColor ?? c),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: AppText.micro(textColor ?? c).copyWith(
              color: textColor ?? c,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
