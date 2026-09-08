import 'dart:math' as math;

import '../domain/models/transaction.dart';

/// 一笔「每月只发生一次（或低频）且金额稳定」的固定消费（房租、水电、订阅等）。
class MonthlyFixedExpense {
  const MonthlyFixedExpense({
    required this.key,
    required this.label,
    required this.monthlyCents,
    required this.avgRecentCents,
    required this.paidThisMonth,
  });

  /// 分组键：`rule:<周期规则id>` 或 `m:<归一化商户名>`。
  final String key;

  /// 展示名（优先商户原文名）。
  final String label;

  /// monthKey（年*12+月-1）→ 该月合计（分）。
  final Map<int, int> monthlyCents;

  /// 近几个完整月的均值（分）；无完整月数据时退回锚定月已发生额。
  final int avgRecentCents;

  /// 锚定月是否已发生。
  final bool paidThisMonth;
}

/// 从已结算的个人支出中识别「每月固定一次」的消费。
///
/// 判定条件（窗口 = 锚定月往前 6 个自然月）：
/// A 频次：任一月份出现 ≤ [maxPerMonthCount] 笔（天然排除每日咖啡、周频周期规则）；
/// B 持续性：近 [recentMonths] 个完整月中出现 ≥ [minSeenMonths] 月
///   （周期规则来源放宽为 ≥ 1 月，让本月新建的月度规则立即生效）；
/// C 稳定性：各月金额变异系数 σ/μ ≤ [maxCoefficientOfVariation]。
class MonthlyFixedExpenseDetector {
  const MonthlyFixedExpenseDetector._();

  static const lookbackMonths = 6;
  static const recentMonths = 3;
  static const maxPerMonthCount = 2;
  static const minSeenMonths = 2;
  static const maxCoefficientOfVariation = 0.35;

  /// 即使缺少足够历史数据，也不应纳入「每日消费速度」外推的分类。
  ///
  /// 其他低频支出仍由下面的跨月频次与金额稳定性规则识别，避免把普通的
  /// 住房、教育等消费一刀切地排除。订阅服务的产品语义本身就是周期扣款，
  /// 因此从首次出现起就排除。
  static const alwaysExcludedFromDailyPaceCategoryIds = <String>{
    'subscription',
  };

  /// 只有这些分类中「跨月低频且金额稳定」的账单才可以从日均
  /// 消费速度中排除。餐饮、交通、购物等即使恰好每月出现一次，
  /// 也不能因此被误判为固定支出。
  static const historicalFixedPaceCategoryIds = <String>{
    'housing',
    'utilities',
    'telecom',
    'insurance',
    'subscription',
    'education',
  };

  static bool isAlwaysExcludedFromDailyPace(TransactionEntity transaction) =>
      alwaysExcludedFromDailyPaceCategoryIds.contains(transaction.categoryId);

  static bool canExcludeDetectedItemFromDailyPace(
          TransactionEntity transaction) =>
      historicalFixedPaceCategoryIds.contains(transaction.categoryId);

  static int monthKey(DateTime t) => t.year * 12 + (t.month - 1);

  /// 商户名归一化：去首尾与内部空白、转小写（中文不受影响，"KFC"/"kfc" 归一）。
  static String normalizeMerchant(String raw) =>
      raw.replaceAll(RegExp(r'\s+'), '').toLowerCase().trim();

  /// 交易所属的固定项分组键；无周期来源且无有效商户时返回 null。
  static String? keyOf(TransactionEntity t) {
    final rid = t.recurringTransactionId;
    if (rid != null && rid.isNotEmpty) return 'rule:$rid';
    final m = t.merchant;
    if (m == null) return null;
    final norm = normalizeMerchant(m);
    return norm.isEmpty ? null : 'm:$norm';
  }

  static List<MonthlyFixedExpense> detect({
    required Iterable<TransactionEntity> settledExpenses,
    required DateTime anchorMonth,
  }) {
    final anchorKey = monthKey(anchorMonth);
    final windowStart = anchorKey - lookbackMonths;

    // 分组：key → {monthKey → [金额]}，保留展示名。
    final groups = <String, Map<int, List<int>>>{};
    final labels = <String, String>{};
    for (final t in settledExpenses) {
      if (t.isIncome) continue;
      final key = keyOf(t);
      if (key == null) continue;
      final mk = monthKey(t.transactionTime);
      if (mk < windowStart || mk > anchorKey) continue;
      final months = groups.putIfAbsent(key, () => <int, List<int>>{});
      months.putIfAbsent(mk, () => <int>[]).add(t.amountCents);
      final merchant = t.merchant;
      if (merchant != null && merchant.trim().isNotEmpty) {
        labels[key] = merchant.trim();
      }
    }

    // 近 N 个完整月（不含锚定月）。
    final recentComplete = <int>[
      for (var i = 1; i <= recentMonths; i++) anchorKey - i,
    ];

    final results = <MonthlyFixedExpense>[];
    for (final entry in groups.entries) {
      final key = entry.key;
      final months = entry.value;
      final isRuleBased = key.startsWith('rule:');

      // A 频次：任一月份笔数超限 → 可变。
      final tooFrequent =
          months.values.any((list) => list.length > maxPerMonthCount);
      if (tooFrequent) continue;

      // B 持续性。
      final seenRecentComplete =
          recentComplete.where((mk) => months.containsKey(mk)).length;
      final persistent = isRuleBased
          ? (seenRecentComplete >= 1 || months.containsKey(anchorKey))
          : seenRecentComplete >= minSeenMonths;
      if (!persistent) continue;

      // C 稳定性：完整月的月度合计变异系数。
      final completeTotals = <int>[
        for (final mk in months.keys.toSet().toList()..sort())
          if (mk < anchorKey) months[mk]!.fold(0, (a, b) => a + b),
      ];
      if (completeTotals.length >= 2) {
        final mean =
            completeTotals.reduce((a, b) => a + b) / completeTotals.length;
        if (mean > 0) {
          final variance = completeTotals
                  .map((v) => (v - mean) * (v - mean))
                  .reduce((a, b) => a + b) /
              completeTotals.length;
          final cv = math.sqrt(variance) / mean;
          if (cv > maxCoefficientOfVariation) continue;
        }
      }

      // 均值：近 3 个完整月 → 全部完整月 → 锚定月已发生额。
      final recentTotals = <int>[
        for (final mk in recentComplete)
          if (months.containsKey(mk)) months[mk]!.fold(0, (a, b) => a + b),
      ];
      final anchorTotal = months.containsKey(anchorKey)
          ? months[anchorKey]!.fold(0, (a, b) => a + b)
          : 0;
      final avgSource = recentTotals.isNotEmpty ? recentTotals : completeTotals;
      final avg = avgSource.isNotEmpty
          ? (avgSource.reduce((a, b) => a + b) / avgSource.length).round()
          : anchorTotal;

      results.add(MonthlyFixedExpense(
        key: key,
        label: labels[key] ?? key,
        monthlyCents: {
          for (final mk in months.keys)
            mk: months[mk]!.fold(0, (a, b) => a + b),
        },
        avgRecentCents: avg,
        paidThisMonth: months.containsKey(anchorKey),
      ));
    }
    return results;
  }
}
