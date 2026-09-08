import 'package:flutter/material.dart';

import '../../domain/models/category.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/transaction.dart';
import '../icons/app_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../utils/app_date_utils.dart';
import 'fm_amount_text.dart';
import 'fm_category_icon.dart';

/// 账单行：分类图标 + 标题（商户/描述）+ 分类名 + 金额。
/// 首页"今日支出"与流水页共用。
class FMTransactionTile extends StatelessWidget {
  const FMTransactionTile({
    super.key,
    required this.transaction,
    required this.category,
    this.onTap,
    this.showTime = false,
    this.showInvoiceStatus = false,
    this.subtitle,
    this.title,
    this.onCategoryTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  final TransactionEntity transaction;
  final Category? category;
  final VoidCallback? onTap;
  final bool showTime;
  final bool showInvoiceStatus;
  final String? subtitle;
  final String? title;
  final VoidCallback? onCategoryTap;
  final VoidCallback? onLongPress;
  final bool selectionMode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final sub = subtitle ??
        [
          category?.name ?? '未分类',
          if (showTime) AppDate.timeHM(transaction.transactionTime),
          if (transaction.status == TxStatus.needsReview) '待确认',
          if (transaction.transactionTime.isAfter(DateTime.now())) '待发生',
          if (showInvoiceStatus && transaction.reimbursed)
            '已报销'
          else if (showInvoiceStatus && transaction.invoiceIssued)
            '已开票'
          else if (showInvoiceStatus && transaction.invoiceRequired)
            '需开票',
        ].join(' · ');

    return Material(
      color: selected ? s.accentSoft : Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(FMRadius.cardSmall),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FMSpacing.xs,
            vertical: FMSpacing.m,
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Semantics(
                    button: onCategoryTap != null,
                    label: onCategoryTap == null ? null : '修改分类',
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onCategoryTap,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: FMCategoryIcon(category: category),
                      ),
                    ),
                  ),
                  if (selectionMode)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: selected ? s.accent : s.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? s.accent : s.inkTertiary,
                            width: 1.5,
                          ),
                        ),
                        child: selected
                            ? const Icon(
                                FMIcons.check,
                                color: Colors.white,
                                size: 11,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: FMSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title ?? transaction.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong(s.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption(s.inkSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: FMSpacing.m),
              FMAmountText(
                transaction.amountCents,
                type: transaction.type,
                style: AppText.amountM(s.ink),
              ),
              const SizedBox(width: FMSpacing.xs),
            ],
          ),
        ),
      ),
    );
  }
}
