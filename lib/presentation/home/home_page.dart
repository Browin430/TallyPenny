import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money_utils.dart';
import '../../core/widgets/fm_amount_text.dart';
import '../../core/widgets/fm_card.dart';
import '../../core/widgets/fm_segmented.dart';
import '../../core/widgets/fm_transaction_tile.dart';
import '../../domain/models/ai_insight.dart';
import '../../domain/models/enums.dart';
import '../../state/app_providers.dart';
import '../detail/transaction_detail_page.dart';
import '../navigation/app_shell.dart';
import '../privacy/analysis_pin_dialog.dart';

/// 首页 Dashboard：本月结余 / 预算 / 今日支出 / AI 财务提示。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.colors;
    final home = ref.watch(homeDataProvider);
    final profile = ref.watch(profileProvider).valueOrNull;

    return Scaffold(
      backgroundColor: s.bg,
      body: SafeArea(
        bottom: false,
        child: home.when(
          loading: () => const _HomeSkeleton(),
          error: (e, _) => Center(
            child: Text('加载失败，请重启应用重试', style: AppText.body(s.inkSecondary)),
          ),
          data: (d) => ListView(
            padding: const EdgeInsets.fromLTRB(
              FMSpacing.l,
              FMSpacing.s,
              FMSpacing.l,
              120,
            ),
            children: [
              // ---- 问候区 ----
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: FMSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AppDate.greeting(DateTime.now()),
                              style: AppText.sub(s.inkSecondary)),
                          Text(profile?.name ?? '你好',
                              style: AppText.headline(s.ink)),
                        ],
                      ),
                    ),
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: s.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: s.border, width: 0.5),
                      ),
                      child: Text(
                        (profile?.name ?? '张').characters.first,
                        style: AppText.bodyStrong(s.accent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FMSpacing.m),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: FMSpacing.xs),
                child: Text(
                  AppDate.monthTitle(d.month),
                  style: AppText.bodyStrong(s.inkSecondary),
                ),
              ),
              const SizedBox(height: FMSpacing.l),

              // ---- 本月结余 ----
              const _BalanceCard(),
              const SizedBox(height: FMSpacing.m),

              // ---- 本月预算 ----
              if (d.budgetCents > 0) ...[
                _BudgetCard(data: d),
                const SizedBox(height: FMSpacing.m),
              ],

              // ---- 今日支出 ----
              _TodaySection(data: d),

              // ---- AI 财务提示 ----
              if (d.insights.isNotEmpty) ...[
                const SizedBox(height: FMSpacing.xs),
                FMSectionHeader(title: 'AI 财务提示'),
                for (final insight in d.insights)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FMSpacing.s),
                    child: _InsightCard(insight: insight),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.colors;
    final data = ref.watch(homeDataProvider).valueOrNull;
    if (data == null) return const SizedBox(height: 160);

    return Container(
      padding: const EdgeInsets.all(FMSpacing.xl),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(FMRadius.card),
        border: s.brightness == Brightness.dark
            ? Border.all(color: s.border, width: 0.5)
            : null,
        boxShadow: s.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('本月结余', style: AppText.sub(s.inkSecondary)),
          const SizedBox(height: 2),
          Text(
            '个人收支 · 已排除开票与报销账单',
            style: AppText.caption(s.inkTertiary),
          ),
          const SizedBox(height: FMSpacing.xs),
          TweenAnimationBuilder<double>(
            tween: Tween(end: data.balanceCents.toDouble()),
            duration: const Duration(milliseconds: 550),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              final cents = value.round();
              final color = cents >= 0 ? s.ink : s.danger;
              return Text(
                '¥${Money.centsToText(cents.abs())}',
                style: AppText.amountXL(color),
              );
            },
          ),
          const SizedBox(height: FMSpacing.l),
          Row(
            children: [
              Expanded(
                child: _FlowBadge(
                  label: '收入',
                  cents: data.incomeCents,
                  previousCents: data.prevIncomeCents,
                  color: s.income,
                  samePeriod: true,
                ),
              ),
              Container(width: 0.5, height: 44, color: s.separator),
              const SizedBox(width: FMSpacing.l),
              Expanded(
                child: _FlowBadge(
                  label: '支出',
                  cents: data.expenseCents,
                  previousCents: data.prevVariableSamePeriodCents,
                  compareCents: data.variableExpenseCents,
                  color: s.inkSecondary,
                  samePeriod: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: FMSpacing.xl),
          SizedBox(
            height: 42,
            width: double.infinity,
            child: CustomPaint(
              painter: _MiniTrendPainter(
                lineColor: s.accent,
                fillColor: s.accentSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowBadge extends StatelessWidget {
  const _FlowBadge({
    required this.label,
    required this.cents,
    required this.previousCents,
    required this.color,
    this.compareCents,
    this.samePeriod = false,
  });

  final String label;

  /// 展示金额（本月至今全额）。
  final int cents;

  /// 环比基数（上月同期口径）。
  final int previousCents;
  final Color color;

  /// 参与环比比较的金额；为 null 时用 [cents]（支出侧传剔除固定月度消费后的可变部分）。
  final int? compareCents;

  /// 是否与上月同期（对齐到本月第 N 天）比较。
  final bool samePeriod;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final isIncome = label == '收入';
    final base = compareCents ?? cents;
    final change = previousCents == 0
        ? null
        : (base - previousCents) / previousCents * 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.caption(s.inkSecondary)),
        const SizedBox(height: 2),
        FMAmountText(
          cents,
          type: isIncome ? TransactionType.income : TransactionType.expense,
          style: AppText.amountM(s.ink),
          showSign: false,
        ),
        if (change != null) ...[
          const SizedBox(height: 4),
          Text(
            '${samePeriod ? '较上月同期' : '较上月'} ${change >= 0 ? '+' : '−'}${change.abs().toStringAsFixed(1)}%',
            style: AppText.micro(
              isIncome
                  ? (change >= 0 ? s.income : s.inkTertiary)
                  : (change <= 0 ? s.income : s.warn),
            ),
          ),
        ],
      ],
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final ratio = data.budgetRatio;
    final remaining = data.budgetCents - data.expenseCents;
    final over = remaining < 0;

    return Container(
      padding: const EdgeInsets.all(FMSpacing.l),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(FMRadius.card),
        border: s.brightness == Brightness.dark
            ? Border.all(color: s.border, width: 0.5)
            : null,
        boxShadow: s.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('本月预算 · 收入减储蓄', style: AppText.bodyStrong(s.ink)),
              const Spacer(),
              Text(
                '${(ratio * 100).floor()}%',
                style: AppText.amountM(ratio >= 0.8 ? s.warn : s.ink),
              ),
            ],
          ),
          const SizedBox(height: FMSpacing.xs),
          Text(
            '¥${Money.centsToCompact(data.expenseCents)} / ¥${Money.centsToCompact(data.budgetCents)}',
            style: AppText.sub(s.inkSecondary),
          ),
          const SizedBox(height: FMSpacing.m),
          FMProgressBar(
            value: ratio,
            color: ratio >= 1
                ? s.danger
                : ratio >= 0.8
                    ? s.warn
                    : s.accent,
          ),
          const SizedBox(height: FMSpacing.s),
          Text(
            over
                ? '本月已超出预算 ¥${Money.centsToCompact(-remaining)}'
                : '本月剩余预算 ¥${Money.centsToCompact(remaining)}',
            style: AppText.caption(over ? s.danger : s.inkTertiary),
          ),
        ],
      ),
    );
  }
}

class _TodaySection extends ConsumerWidget {
  const _TodaySection({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.colors;
    final categories = ref.watch(categoryMapProvider).valueOrNull ?? const {};

    return Column(
      children: [
        FMSectionHeader(
          title: '今日流水',
          actionText: '查看全部',
          onAction: () async {
            final allowed = await requestFinancialDataAccess(context, ref);
            if (allowed && context.mounted) {
              ref.read(shellTabIndexProvider.notifier).state = 1;
            }
          },
        ),
        if (data.today.isEmpty)
          const FMEmptyState(
            icon: FMIcons.sparkles,
            title: '今天还没有账单',
            subtitle: '说一句话或传一张截图，自动帮你记',
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: FMSpacing.l,
              vertical: FMSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: s.surface,
              borderRadius: BorderRadius.circular(FMRadius.card),
              border: s.brightness == Brightness.dark
                  ? Border.all(color: s.border, width: 0.5)
                  : null,
              boxShadow: s.cardShadow,
            ),
            child: Column(
              children: [
                for (final (i, tx) in data.today.indexed) ...[
                  FMTransactionTile(
                    transaction: tx,
                    category: tx.categoryId == null
                        ? null
                        : categories[tx.categoryId],
                    showTime: true,
                    showInvoiceStatus:
                        ref.watch(invoiceManagementProvider).valueOrNull ??
                            false,
                    onTap: () => _openDetail(context, tx.id),
                  ),
                  if (i != data.today.length - 1)
                    Divider(height: 0.5, thickness: 0.5, color: s.separator),
                ],
              ],
            ),
          ),
      ],
    );
  }

  void _openDetail(BuildContext context, String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransactionDetailPage(transactionId: id),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});

  final AiInsight insight;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final color = insight.severity.isWarning
        ? s.warn
        : insight.severity.isPositive
            ? s.income
            : s.accent;
    return Container(
      padding: const EdgeInsets.all(FMSpacing.l),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(FMRadius.card),
        border: s.brightness == Brightness.dark
            ? Border.all(color: s.border, width: 0.5)
            : null,
        boxShadow: s.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(FMIcons.insightIcon(insight.iconCode),
                    size: 16, color: color),
              ),
              const SizedBox(width: FMSpacing.m),
              Text('AI 财务洞察', style: AppText.caption(s.inkSecondary)),
            ],
          ),
          const SizedBox(height: FMSpacing.m),
          Text(insight.text, style: AppText.bodyStrong(s.ink)),
          const SizedBox(height: FMSpacing.s),
          Text('基于本月流水与预算自动生成', style: AppText.caption(s.inkTertiary)),
        ],
      ),
    );
  }
}

class _MiniTrendPainter extends CustomPainter {
  const _MiniTrendPainter({required this.lineColor, required this.fillColor});

  final Color lineColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    const values = [0.62, 0.52, 0.58, 0.34, 0.42, 0.24, 0.30, 0.14];
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final point = Offset(
        size.width * i / (values.length - 1),
        size.height * values[i],
      );
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = fillColor);
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_MiniTrendPainter oldDelegate) =>
      oldDelegate.lineColor != lineColor || oldDelegate.fillColor != fillColor;
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    Widget block(double height, {double? width}) => Container(
          width: width ?? double.infinity,
          height: height,
          decoration: BoxDecoration(
            color: s.ink.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(FMRadius.card),
          ),
        );
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(FMSpacing.l, FMSpacing.l, FMSpacing.l, 120),
      children: [
        block(48, width: 180),
        const SizedBox(height: FMSpacing.xl),
        block(238),
        const SizedBox(height: FMSpacing.m),
        block(142),
        const SizedBox(height: FMSpacing.xl),
        block(220),
      ],
    );
  }
}
