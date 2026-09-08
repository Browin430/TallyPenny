import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/money_utils.dart';
import '../../core/widgets/fm_category_icon.dart';
import '../../core/widgets/fm_month_switcher.dart';
import '../../domain/models/ai_insight.dart';
import '../../state/app_providers.dart';
import 'charts.dart';

final _analysisMonthProvider = StateProvider<DateTime>((ref) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, 1);
});

final _analysisSelectedProvider = StateProvider<int?>((ref) => null);

final _analysisInsightsProvider =
    FutureProvider.family<List<AiInsight>, DateTime>((ref, month) async {
  ref.watch(dataVersionProvider);
  final all = await ref.watch(transactionRepositoryProvider).getAll();
  final profile = await ref.watch(profileProvider.future);
  return ref.watch(insightsProvider).insightsForMonth(
      month: month, all: all, monthlyBudgetCents: profile.monthlyBudgetCents);
});

/// 财务分析页：消费结构 / 月度趋势 / 消费排名 / AI 洞察。
class AnalysisPage extends ConsumerWidget {
  const AnalysisPage({super.key, this.active = true});

  /// IndexedStack 会长期保留页面；由外层显式告知是否刚进入分析页，
  /// 以便每次打开时重新播放环形图与内容的入场动画。
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.colors;
    final month = ref.watch(_analysisMonthProvider);
    final data = ref.watch(analysisDataProvider(month));
    final insights = ref.watch(_analysisInsightsProvider(month)).valueOrNull;

    return Scaffold(
      backgroundColor: s.bg,
      body: SafeArea(
        bottom: false,
        child: data.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, _) =>
              Center(child: Text('加载失败', style: AppText.body(s.inkSecondary))),
          data: (d) => ListView(
            padding: const EdgeInsets.fromLTRB(
                FMSpacing.l, FMSpacing.s, FMSpacing.l, 130),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: FMSpacing.xs),
                child: Text('分析', style: AppText.headline(s.ink)),
              ),
              const SizedBox(height: FMSpacing.m),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: FMSpacing.xs),
                child: FMMonthSwitcher(
                  month: month,
                  onChanged: (m) {
                    ref.read(_analysisMonthProvider.notifier).state = m;
                    ref.read(_analysisSelectedProvider.notifier).state = null;
                  },
                ),
              ),
              const SizedBox(height: FMSpacing.l),

              // ---- 消费结构（环形图）----
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('本月支出', style: AppText.title(s.ink)),
                        const Spacer(),
                        Text(
                          '¥${Money.centsToCompact(d.expenseTotal)}',
                          style: AppText.amountL(s.ink),
                        ),
                      ],
                    ),
                    const SizedBox(height: FMSpacing.xs),
                    Text(
                      '个人支出 · 已排除开票与报销账单',
                      style: AppText.caption(s.inkTertiary),
                    ),
                    const SizedBox(height: FMSpacing.xl),
                    _AnalysisReveal(
                      key: ValueKey(
                        'spending-$active-${month.year}-${month.month}',
                      ),
                      animate: active,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final chartSize =
                              constraints.maxWidth >= 350 ? 174.0 : 158.0;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: chartSize,
                                child: DonutChart(
                                  key: ValueKey(
                                    'donut-$active-${month.year}-${month.month}',
                                  ),
                                  size: chartSize,
                                  slices: d.slices,
                                  totalCents: d.expenseTotal,
                                  selectedIndex:
                                      ref.watch(_analysisSelectedProvider),
                                  onSelect: (i) => ref
                                      .read(_analysisSelectedProvider.notifier)
                                      .state = i,
                                  centerTitle: '个人支出',
                                  centerValue:
                                      '¥${Money.centsToCompact(d.expenseTotal)}',
                                  centerValueColor: s.ink,
                                ),
                              ),
                              const SizedBox(width: FMSpacing.xl),
                              Expanded(
                                child: _Legend(
                                  slices: d.slices,
                                  selected:
                                      ref.watch(_analysisSelectedProvider),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    _SelectedDetail(data: d),
                  ],
                ),
              ),
              const SizedBox(height: FMSpacing.m),

              // ---- 月度趋势 ----
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('月度趋势', style: AppText.title(s.ink)),
                    const SizedBox(height: FMSpacing.s),
                    Row(
                      children: [
                        _LegendDot(color: s.income, label: '收入'),
                        const SizedBox(width: FMSpacing.l),
                        _LegendDot(color: s.accent, label: '支出'),
                      ],
                    ),
                    const SizedBox(height: FMSpacing.m),
                    TrendChart(
                      trend: d.trend,
                      incomeColor: s.income,
                      expenseColor: s.accent,
                      gridColor: s.separator,
                      labelColor: s.inkTertiary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FMSpacing.m),

              // ---- 消费排名 ----
              if (d.slices.isNotEmpty) _Ranking(data: d),

              // ---- AI 洞察 ----
              if (insights != null && insights.isNotEmpty) ...[
                const SizedBox(height: FMSpacing.xs),
                Padding(
                  padding: const EdgeInsets.all(FMSpacing.xs),
                  child: Text('AI 财务洞察', style: AppText.title(s.ink)),
                ),
                for (final insight in insights)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FMSpacing.s),
                    child: _InsightRow(insight: insight),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FMSpacing.l),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(FMRadius.card),
        border: s.brightness == Brightness.dark
            ? Border.all(color: s.border, width: 0.5)
            : null,
        boxShadow: s.cardShadow,
      ),
      child: child,
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.slices, required this.selected});

  final List<CategorySlice> slices;
  final int? selected;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final total = slices.fold(0, (sum, e) => sum + e.cents);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, slice) in slices.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: slice.category.color.withValues(
                      alpha: selected == null || selected == i ? 1 : 0.35,
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: FMSpacing.s),
                Expanded(
                  child: Text(
                    slice.category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.sub(
                      selected == null || selected == i ? s.ink : s.inkTertiary,
                    ),
                  ),
                ),
                const SizedBox(width: FMSpacing.s),
                Text(
                  '${(slice.cents / (total == 0 ? 1 : total) * 100).toStringAsFixed(0)}%',
                  style: AppText.bodyStrong(
                    selected == null || selected == i
                        ? slice.category.color
                        : s.inkTertiary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AnalysisReveal extends StatelessWidget {
  const _AnalysisReveal({
    super.key,
    required this.animate,
    required this.child,
  });

  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: animate ? 0 : 1, end: 1),
      duration: animate ? const Duration(milliseconds: 430) : Duration.zero,
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}

/// 点击扇区后的分类明细。
class _SelectedDetail extends ConsumerWidget {
  const _SelectedDetail({required this.data});

  final AnalysisData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.colors;
    final index = ref.watch(_analysisSelectedProvider);
    if (index == null || index >= data.slices.length) {
      return const SizedBox.shrink();
    }
    final slice = data.slices[index];
    final txs = data.monthTransactions
        .where((t) => !t.isIncome && t.categoryId == slice.category.id)
        .toList();
    final merchants = <String, int>{};
    for (final t in txs) {
      final key = t.displayTitle;
      merchants[key] = (merchants[key] ?? 0) + t.amountCents;
    }
    final top = merchants.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: FMSpacing.l),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(FMSpacing.l),
          decoration: BoxDecoration(
            color: s.surfaceAlt,
            borderRadius: BorderRadius.circular(FMRadius.field),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FMCategoryIcon(category: slice.category, size: 30),
                  const SizedBox(width: FMSpacing.s),
                  Expanded(
                    child: Text(
                      '${slice.category.name} · ${txs.length} 笔',
                      style: AppText.bodyStrong(s.ink),
                    ),
                  ),
                  Text(
                    '¥${Money.centsToCompact(slice.cents)}',
                    style: AppText.amountM(s.ink),
                  ),
                ],
              ),
              if (top.isNotEmpty) ...[
                const SizedBox(height: FMSpacing.m),
                for (final e in top.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child:
                              Text(e.key, style: AppText.sub(s.inkSecondary)),
                        ),
                        Text(
                          '¥${Money.centsToCompact(e.value)}',
                          style: AppText.caption(s.inkTertiary),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 分类排名（横向条）。
class _Ranking extends StatelessWidget {
  const _Ranking({required this.data});

  final AnalysisData data;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final maxSlice = data.slices.first.cents;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('消费排名', style: AppText.title(s.ink)),
          const SizedBox(height: FMSpacing.l),
          for (final slice in data.slices.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: FMSpacing.m),
              child: Row(
                children: [
                  FMCategoryIcon(category: slice.category, size: 32),
                  const SizedBox(width: FMSpacing.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(slice.category.name,
                                style: AppText.sub(s.ink)),
                            const Spacer(),
                            Text(
                              '¥${Money.centsToCompact(slice.cents)}'
                              ' · ${(slice.cents / (data.expenseTotal == 0 ? 1 : data.expenseTotal) * 100).toStringAsFixed(0)}%',
                              style: AppText.caption(s.inkSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        TweenAnimationBuilder<double>(
                          tween: Tween(
                            end: slice.cents / (maxSlice == 0 ? 1 : maxSlice),
                          ),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          builder: (context, v, _) => FractionallySizedBox(
                            widthFactor: v.clamp(0.02, 1.0),
                            child: Container(
                              height: 5,
                              decoration: BoxDecoration(
                                color: slice.category.color
                                    .withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: AppText.caption(s.inkSecondary)),
      ],
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.insight});

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
      child: Row(
        children: [
          Icon(FMIcons.insightIcon(insight.iconCode), size: 16, color: color),
          const SizedBox(width: FMSpacing.m),
          Expanded(child: Text(insight.text, style: AppText.body(s.ink))),
        ],
      ),
    );
  }
}
