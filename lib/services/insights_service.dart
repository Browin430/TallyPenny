import '../core/constants/app_constants.dart';
import '../core/utils/money_utils.dart';
import '../core/utils/settlement_policy.dart';
import '../domain/models/ai_insight.dart';
import '../domain/models/transaction.dart';
import 'monthly_fixed_expense_detector.dart';

/// 一条洞察事实：模板兜底文案 + 供远端 AI 组织文案的事实数字。
class InsightFact {
  const InsightFact({required this.fallback, required this.payload});

  /// 模板文案（离线/降级时直接展示；id、severity、iconCode 以它为准）。
  final AiInsight fallback;

  /// 传服务器的结构化事实（kind + 全部数字，单位分）。
  final Map<String, Object?> payload;
}

/// 规则版财务洞察：数字全部本地确定性计算；远端 AI（qwen-flash）可基于
/// [InsightFact.payload] 重写文案，本服务的模板文案保留为兜底。
class InsightsService {
  const InsightsService();

  /// 生成针对某月的事实列表（最多 4 条，避免打扰）。
  List<InsightFact> factsForMonth({
    required DateTime month,
    required List<TransactionEntity> all,
    required int monthlyBudgetCents,
  }) {
    final facts = <InsightFact>[];
    final now = DateTime.now();
    final settled = SettlementPolicy.personalOccurred(all, now);
    final settledExpenses =
        settled.where((t) => !t.isIncome).toList(growable: false);
    final isCurrentMonth = now.year == month.year && now.month == month.month;

    final monthStart = DateTime(month.year, month.month, 1);
    final nextMonth = DateTime(
      month.month == 12 ? month.year + 1 : month.year,
      month.month == 12 ? 1 : month.month + 1,
      1,
    );
    final prevMonth = DateTime(
      month.month == 1 ? month.year - 1 : month.year,
      month.month == 1 ? 12 : month.month - 1,
      1,
    );

    int expenseIn(DateTime s, DateTime e) => settledExpenses
        .where((t) =>
            !t.transactionTime.isBefore(s) && t.transactionTime.isBefore(e))
        .fold(0, (sum, t) => sum + t.amountCents);

    final monthExpense = expenseIn(monthStart, nextMonth);

    // ---- 固定月度消费（房租/水电等，每月一次、金额稳定）----
    final fixedItems = MonthlyFixedExpenseDetector.detect(
      settledExpenses: settledExpenses,
      anchorMonth: month,
    );
    final fixedKeys = fixedItems.map((f) => f.key).toSet();
    final anchorKey = MonthlyFixedExpenseDetector.monthKey(month);
    final paidFixedCents = fixedItems
        .where((f) => f.paidThisMonth)
        .fold(0, (sum, f) => sum + (f.monthlyCents[anchorKey] ?? 0));
    bool isFixed(TransactionEntity t) =>
        fixedKeys.contains(MonthlyFixedExpenseDetector.keyOf(t));

    // ---- 1. 预算进度 ----
    if (monthlyBudgetCents > 0 && isCurrentMonth) {
      final ratio = monthExpense / monthlyBudgetCents;
      if (ratio >= BudgetAlert.full) {
        facts.add(InsightFact(
          fallback: AiInsight(
            id: 'budget_full',
            severity: InsightSeverity.warning,
            iconCode: 'warning',
            text: '本月预算已用完，支出 ¥${Money.centsToCompact(monthExpense)}。',
          ),
          payload: {
            'kind': 'budget_progress',
            'budgetCents': monthlyBudgetCents,
            'budgetDisplay': Money.centsToCompact(monthlyBudgetCents),
            'spentCents': monthExpense,
            'spentDisplay': Money.centsToCompact(monthExpense),
            'usedPct': (ratio * 100).round(),
            'remainingCents': monthlyBudgetCents - monthExpense,
            'remainingDisplay':
                Money.centsToCompact(monthlyBudgetCents - monthExpense),
          },
        ));
      } else if (ratio >= BudgetAlert.warn) {
        facts.add(InsightFact(
          fallback: AiInsight(
            id: 'budget_warn',
            severity: InsightSeverity.warning,
            iconCode: 'bell',
            text:
                '本月预算已使用 ${(ratio * 100).toStringAsFixed(0)}%，剩余 ¥${Money.centsToCompact(monthlyBudgetCents - monthExpense)}。',
          ),
          payload: {
            'kind': 'budget_progress',
            'budgetCents': monthlyBudgetCents,
            'budgetDisplay': Money.centsToCompact(monthlyBudgetCents),
            'spentCents': monthExpense,
            'spentDisplay': Money.centsToCompact(monthExpense),
            'usedPct': (ratio * 100).round(),
            'remainingCents': monthlyBudgetCents - monthExpense,
            'remainingDisplay':
                Money.centsToCompact(monthlyBudgetCents - monthExpense),
          },
        ));
      }
    }

    // ---- 2. 消费速度预测（仅当月）----
    // 预计 = 已发生支出 + 可变支出日均外推。
    // 固定项（房租等）以及订阅服务不参与日均，避免月初一次扣款被当成
    // 每天都会发生的消费；它们已经发生的金额仍保留在本月预计总支出里。
    // 不再根据历史记录猜测本月「未付固定项」，避免已付房租被重复加入。
    if (isCurrentMonth && monthExpense > 0) {
      final daysInMonth = DateTime(
        month.month == 12 ? month.year + 1 : month.year,
        month.month == 12 ? 1 : month.month + 1,
        0,
      ).day;
      final daysElapsed = now.day;
      final remainingDays = daysInMonth - daysElapsed;
      final paceExcludedCents = settledExpenses
          .where((t) =>
              !t.transactionTime.isBefore(monthStart) &&
              t.transactionTime.isBefore(nextMonth) &&
              ((isFixed(t) &&
                      MonthlyFixedExpenseDetector
                          .canExcludeDetectedItemFromDailyPace(t)) ||
                  MonthlyFixedExpenseDetector.isAlwaysExcludedFromDailyPace(t)))
          .fold(0, (sum, t) => sum + t.amountCents);
      final variableSoFar = monthExpense - paceExcludedCents;
      final variableDailyAvg =
          (variableSoFar / daysElapsed).round(); // daysElapsed ≥ 1
      final projection = monthExpense +
          (remainingDays > 0 ? variableDailyAvg * remainingDays : 0);
      facts.add(InsightFact(
        fallback: AiInsight(
          id: 'projection',
          severity: InsightSeverity.info,
          iconCode: 'chart',
          text: '按目前消费速度，本月预计支出 ¥${Money.centsToCompact(projection)}。',
        ),
        payload: {
          'kind': 'month_projection',
          'projectedCents': projection,
          'projectedDisplay': Money.centsToCompact(projection),
          'spentCents': monthExpense,
          'spentDisplay': Money.centsToCompact(monthExpense),
          'paidFixedCents': paidFixedCents,
          'paceExcludedCents': paceExcludedCents,
          'variableDailyAvgCents': variableDailyAvg,
          'variableDailyAvgDisplay': Money.centsToCompact(variableDailyAvg),
          'daysElapsed': daysElapsed,
          'daysInMonth': daysInMonth,
        },
      ));
    }

    // ---- 3. 环比变化最大的分类（当月与上月同期比；历史月整月比）----
    final momCategory = biggestCategorySwing(
      settledExpenses,
      isFixed,
      monthStart,
      nextMonth,
      prevMonth,
      samePeriodDays: isCurrentMonth ? now.day : null,
    );
    if (momCategory != null) {
      final deltaPct =
          ((momCategory.$3 - momCategory.$4) / momCategory.$4 * 100).round();
      final samePeriod = momCategory.$5;
      if (deltaPct >= 15) {
        facts.add(InsightFact(
          fallback: AiInsight(
            id: 'mom_${momCategory.$1}',
            severity: InsightSeverity.warning,
            iconCode: 'trend_up',
            text: samePeriod
                ? '你本月${momCategory.$2}支出比上月同期增加了 $deltaPct%。'
                : '你本月${momCategory.$2}支出比上月增加了 $deltaPct%。',
          ),
          payload: {
            'kind': 'category_mom',
            'categoryId': momCategory.$1,
            'categoryName': momCategory.$2,
            'currentCents': momCategory.$3,
            'currentDisplay': Money.centsToCompact(momCategory.$3),
            'previousCents': momCategory.$4,
            'previousDisplay': Money.centsToCompact(momCategory.$4),
            'deltaPct': deltaPct,
            'samePeriod': samePeriod,
            'alignedDays': samePeriod ? now.day : null,
          },
        ));
      } else if (deltaPct <= -15) {
        facts.add(InsightFact(
          fallback: AiInsight(
            id: 'mom_${momCategory.$1}',
            severity: InsightSeverity.positive,
            iconCode: 'trend_down',
            text: samePeriod
                ? '你本月${momCategory.$2}支出比上月同期减少了 ${-deltaPct}%，继续保持。'
                : '你本月${momCategory.$2}支出比上月减少了 ${-deltaPct}%，继续保持。',
          ),
          payload: {
            'kind': 'category_mom',
            'categoryId': momCategory.$1,
            'categoryName': momCategory.$2,
            'currentCents': momCategory.$3,
            'currentDisplay': Money.centsToCompact(momCategory.$3),
            'previousCents': momCategory.$4,
            'previousDisplay': Money.centsToCompact(momCategory.$4),
            'deltaPct': deltaPct,
            'samePeriod': samePeriod,
            'alignedDays': samePeriod ? now.day : null,
          },
        ));
      }
    }

    // ---- 4. 连续消费提醒（如连续打车）----
    final streak = _merchantStreak(settled);
    if (streak != null && isCurrentMonth) {
      facts.add(InsightFact(
        fallback: AiInsight(
          id: 'streak_${streak.$1}',
          severity: InsightSeverity.info,
          iconCode: 'repeat',
          text: '你已经连续 ${streak.$2} 天在「${streak.$1}」消费。',
        ),
        payload: {
          'kind': 'merchant_streak',
          'merchant': streak.$1,
          'days': streak.$2,
        },
      ));
    }

    return facts.take(4).toList();
  }

  /// 生成针对某月的洞察列表（模板文案；远端 AI 不可用时即最终展示）。
  List<AiInsight> insightsForMonth({
    required DateTime month,
    required List<TransactionEntity> all,
    required int monthlyBudgetCents,
  }) =>
      factsForMonth(
        month: month,
        all: all,
        monthlyBudgetCents: monthlyBudgetCents,
      ).map((f) => f.fallback).toList();

  /// 返回 (categoryId, categoryName, 本期金额, 上期金额, 是否同期口径)。
  ///
  /// 当月：本期 = 本月 [1 日, 第 N+1 日)、上期 = 上月同期（上月天数不足时
  /// 按上月日均外推到 N 天）；两侧均剔除固定月度消费。
  /// 历史完整月：整月 vs 整月（同样剔固定）。
  static (String, String, int, int, bool)? biggestCategorySwing(
    List<TransactionEntity> all,
    bool Function(TransactionEntity) isFixed,
    DateTime monthStart,
    DateTime nextMonth,
    DateTime prevMonth, {
    required int? samePeriodDays,
  }) {
    int sumVarIn(Set<String> ids, DateTime s, DateTime e) => all
        .where((t) =>
            ids.contains(t.categoryId) &&
            !isFixed(t) &&
            !t.transactionTime.isBefore(s) &&
            t.transactionTime.isBefore(e))
        .fold(0, (sum, t) => sum + t.amountCents);

    final prevDaysInMonth = DateTime(
      prevMonth.year,
      prevMonth.month + 1,
      0,
    ).day;

    (int, double) curAndPrev(Set<String> ids) {
      final int cur;
      final double prev;
      final n = samePeriodDays;
      if (n != null) {
        cur = sumVarIn(ids, monthStart, monthStart.add(Duration(days: n)));
        if (n <= prevDaysInMonth) {
          prev = sumVarIn(ids, prevMonth, prevMonth.add(Duration(days: n)))
              .toDouble();
        } else {
          // 上月没有第 N 天（如 3 月 30 日 vs 2 月 28 天）：按上月日均外推。
          final prevFull = sumVarIn(ids, prevMonth, monthStart);
          prev = prevFull / prevDaysInMonth * n;
        }
      } else {
        cur = sumVarIn(ids, monthStart, nextMonth);
        prev = sumVarIn(ids, prevMonth, monthStart).toDouble();
      }
      return (cur, prev);
    }

    (String, String, int, int, bool)? best;
    for (final entry in const {
      'food': '餐饮',
      'transport': '交通',
      'shopping': '购物',
      'entertainment': '娱乐',
    }.entries) {
      final values = curAndPrev({entry.key});
      final cur = values.$1;
      final prev = values.$2;
      if (prev < 10000) continue; // 上期基数太小，比率无意义
      final swing = (cur - prev).abs() / prev;
      final prevBest =
          best == null ? null : (best.$3 - best.$4).abs() / best.$4;
      if (best == null || swing > prevBest!) {
        best =
            (entry.key, entry.value, cur, prev.round(), samePeriodDays != null);
      }
    }
    return best;
  }

  /// 最近 N 天同一商户连续出现的最长连续天数。
  (String, int)? _merchantStreak(List<TransactionEntity> all,
      {int maxLookback = 14}) {
    final merchants = <String>{};
    for (final t in all) {
      final m = t.merchant;
      if (m != null && m.isNotEmpty) merchants.add(m);
    }
    final now = DateTime.now();
    (String, int)? best;
    for (final merchant in merchants) {
      final days = all
          .where((t) => t.merchant == merchant)
          .map((t) => DateTime(t.transactionTime.year, t.transactionTime.month,
              t.transactionTime.day))
          .toSet();
      var streak = 0;
      var day = now;
      while (days.contains(DateTime(day.year, day.month, day.day))) {
        streak++;
        day = day.subtract(const Duration(days: 1));
        if (streak >= maxLookback) break;
      }
      if (streak >= 3 && (best == null || streak > best.$2)) {
        best = (merchant, streak);
      }
    }
    return best;
  }
}

/// 把洞察 severity 映射为设计系统颜色。
extension InsightSeverityX on InsightSeverity {
  bool get isWarning => this == InsightSeverity.warning;
  bool get isPositive => this == InsightSeverity.positive;

  String get label => switch (this) {
        InsightSeverity.info => '提示',
        InsightSeverity.warning => '注意',
        InsightSeverity.positive => '良好',
      };
}
