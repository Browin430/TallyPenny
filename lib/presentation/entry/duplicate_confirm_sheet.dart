import 'package:flutter/material.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money_utils.dart';
import '../../core/widgets/fm_amount_text.dart';
import '../../core/widgets/fm_category_icon.dart';
import '../../core/widgets/fm_sheets.dart';
import '../../domain/models/category.dart';
import '../../domain/models/duplicate_match.dart';
import '../../domain/models/enums.dart';
import '../detail/transaction_detail_page.dart';

enum DuplicateDecision { merge, keepBoth }

/// 重复账单确认窗口：左右对比 + AI 判定理由 + 两种处理方式。
Future<DuplicateDecision?> showDuplicateConfirmSheet(
  BuildContext context, {
  required DuplicateMatch match,
  required Category? existingCategory,
  required Category? incomingCategory,
}) {
  return showFMSheet<DuplicateDecision>(
    context,
    isScrollControlled: true,
    builder: (_) => _DuplicateConfirmSheet(
      match: match,
      existingCategory: existingCategory,
      incomingCategory: incomingCategory,
    ),
  );
}

class _DuplicateConfirmSheet extends StatelessWidget {
  const _DuplicateConfirmSheet({
    required this.match,
    required this.existingCategory,
    required this.incomingCategory,
  });

  final DuplicateMatch match;
  final Category? existingCategory;
  final Category? incomingCategory;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final existing = match.existing;
    final incoming = match.incoming;
    final scorePct = (match.score * 100).toStringAsFixed(0);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            FMSpacing.l, FMSpacing.s, FMSpacing.l, FMSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '发现一笔可能重复的消费',
              style: AppText.headline(s.ink).copyWith(fontSize: 21),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FMSpacing.xs),
            Text(
              '这两笔记录可能是同一笔 · 重复度 $scorePct%',
              style: AppText.sub(s.inkSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FMSpacing.l),
            Column(
              children: [
                _SideCard(
                  label:
                      existing.sourceType == SourceType.voice ? '语音记录' : '已有账单',
                  labelColor: s.inkSecondary,
                  child: _TxPreview(
                    title: existing.displayTitle,
                    category: existingCategory,
                    cents: existing.amountCents,
                    type: existing.type,
                    time: existing.transactionTime,
                    source: existing.sourceType,
                  ),
                ),
                const SizedBox(height: FMSpacing.m),
                _SideCard(
                  label: incoming.sourceType == SourceType.screenshot
                      ? '支付宝截图'
                      : '本次录入',
                  labelColor: s.accent,
                  child: _TxPreview(
                    title: incoming.merchant?.isNotEmpty == true
                        ? incoming.merchant!
                        : (incoming.description ?? '未命名'),
                    category: incomingCategory,
                    cents: incoming.amountCents ?? 0,
                    type: incoming.type ?? TransactionType.expense,
                    time: incoming.transactionTime,
                    source: incoming.sourceType,
                  ),
                ),
              ],
            ),
            const SizedBox(height: FMSpacing.l),
            Container(
              padding: const EdgeInsets.all(FMSpacing.l),
              decoration: BoxDecoration(
                color: s.warnSoft,
                borderRadius: BorderRadius.circular(FMRadius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(FMIcons.sparkles, size: 14, color: s.warn),
                      const SizedBox(width: FMSpacing.xs),
                      Text('AI 判断依据', style: AppText.caption(s.warn)),
                    ],
                  ),
                  const SizedBox(height: FMSpacing.s),
                  Wrap(
                    spacing: FMSpacing.s,
                    runSpacing: FMSpacing.s,
                    children: [
                      for (final reason in match.reasons)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: FMSpacing.m,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: s.surface.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(reason,
                              style: AppText.caption(s.inkSecondary)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: FMSpacing.xl),
            _ActionButton(
              label: '合并为一笔',
              filled: true,
              onTap: () => Navigator.of(context).pop(DuplicateDecision.merge),
            ),
            const SizedBox(height: FMSpacing.m),
            _ActionButton(
              label: '这是两笔消费',
              onTap: () =>
                  Navigator.of(context).pop(DuplicateDecision.keepBoth),
            ),
            const SizedBox(height: FMSpacing.s),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        TransactionDetailPage(transactionId: existing.id),
                  ),
                );
              },
              child: Text('查看已有账单详情', style: AppText.sub(s.inkSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideCard extends StatelessWidget {
  const _SideCard({
    required this.label,
    required this.labelColor,
    required this.child,
  });

  final String label;
  final Color labelColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FMSpacing.m),
      decoration: BoxDecoration(
        color: s.surfaceAlt,
        borderRadius: BorderRadius.circular(FMRadius.card),
        border: Border.all(color: s.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.micro(labelColor)),
          const SizedBox(height: FMSpacing.s),
          child,
        ],
      ),
    );
  }
}

class _TxPreview extends StatelessWidget {
  const _TxPreview({
    required this.title,
    required this.category,
    required this.cents,
    required this.type,
    required this.time,
    required this.source,
  });

  final String title;
  final Category? category;
  final int cents;
  final TransactionType type;
  final DateTime? time;
  final SourceType source;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            FMCategoryIcon(category: category, size: 38),
            const SizedBox(width: FMSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong(s.ink)),
                  const SizedBox(height: 2),
                  Text(
                    '${category?.name ?? '未分类'} · ${source.label}'
                    '${time == null ? '' : ' · ${AppDate.timeHM(time!)}'}',
                    style: AppText.caption(s.inkSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: FMSpacing.s),
            FMAmountText(cents, type: type, style: AppText.amountM(s.ink)),
          ],
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(
      {required this.label, required this.onTap, this.filled = false});

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Material(
      color: filled ? s.accent : s.ink.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(FMRadius.button),
      child: InkWell(
        borderRadius: BorderRadius.circular(FMRadius.button),
        onTap: onTap,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppText.bodyStrong(
              filled ? Colors.white : s.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// 供确认弹窗展示分类（由调用方查询后传入）。
String moneyLabel(int cents) => Money.centsToText(cents);
