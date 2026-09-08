import 'package:flutter_test/flutter_test.dart';
import 'package:flowmoney/domain/models/enums.dart';
import 'package:flowmoney/domain/models/transaction.dart';
import 'package:flowmoney/services/insights_service.dart';

int _seq = 0;

TransactionEntity tx(
  DateTime time,
  int amountCents, {
  String? merchant,
  String? categoryId,
  String? recurringTransactionId,
}) {
  final created = DateTime(2020, 1, 1);
  _seq++;
  return TransactionEntity(
    id: 'tx-$_seq',
    userId: 'local',
    type: TransactionType.expense,
    amountCents: amountCents,
    currency: 'CNY',
    transactionTime: time,
    createdAt: created,
    updatedAt: created,
    sourceType: recurringTransactionId == null
        ? SourceType.manual
        : SourceType.recurring,
    confidence: 1,
    status: TxStatus.confirmed,
    categoryId: categoryId,
    merchant: merchant,
    isRecurring: recurringTransactionId != null,
    recurringTransactionId: recurringTransactionId,
  );
}

void main() {
  final service = const InsightsService();
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;

  /// 上月第 [day] 天（自动处理跨年）。
  DateTime prevMonthDay(int day) => DateTime(
        now.month == 1 ? now.year - 1 : now.year,
        now.month == 1 ? 12 : now.month - 1,
        day,
        9,
      );

  /// 前第 [back] 个月的第 1 天。
  DateTime monthAgo(int back) => DateTime(
        now.year,
        now.month - back,
        1,
        9,
      );

  test('月初大额房租不参与日均外推：预测 = 房租 + 可变日均 × 全月天数', () {
    final all = <TransactionEntity>[
      // 近 3 个月 + 本月，每月 1 号付房租 3000。
      for (final m in [monthAgo(3), monthAgo(2), monthAgo(1)])
        tx(m, 300000, merchant: '嘉恒广场', categoryId: 'housing'),
      tx(DateTime(now.year, now.month, 1, 0, 1), 300000,
          merchant: '嘉恒广场', categoryId: 'housing'),
      // 每天 10 元咖啡（1 号到今天）。
      for (var d = 1; d <= now.day; d++)
        tx(DateTime(now.year, now.month, d, 0, 1), 1000, merchant: '瑞幸咖啡'),
    ];
    final facts = service.factsForMonth(
      month: monthStart,
      all: all,
      monthlyBudgetCents: 0,
    );
    final projection = facts.firstWhere((f) => f.fallback.id == 'projection');
    expect(projection.payload['paidFixedCents'], 300000);
    expect(projection.payload['variableDailyAvgCents'], 1000);
    expect(projection.payload['projectedCents'], 300000 + 1000 * daysInMonth);
  });

  test('历史低频项目本月未付时不额外猜测', () {
    final all = <TransactionEntity>[
      // 房租只在近 3 个月出现（每月 5 号），本月未到账单日。
      for (final m in [monthAgo(3), monthAgo(2), monthAgo(1)])
        tx(DateTime(m.year, m.month, 5, 9), 300000, merchant: '嘉恒广场'),
      for (var d = 1; d <= now.day; d++)
        tx(DateTime(now.year, now.month, d, 0, 1), 1000, merchant: '瑞幸咖啡'),
    ];
    final facts = service.factsForMonth(
      month: monthStart,
      all: all,
      monthlyBudgetCents: 0,
    );
    final projection = facts.firstWhere((f) => f.fallback.id == 'projection');
    expect(projection.payload['paidFixedCents'], 0);
    expect(
      projection.payload['projectedCents'],
      1000 * daysInMonth,
    );
  });

  test('首次出现的订阅服务不纳入每日消费速度外推', () {
    final all = <TransactionEntity>[
      // 本月首次出现，没有历史样本，仍应依据订阅分类排除。
      tx(DateTime(now.year, now.month, 1, 0, 1), 6800,
          merchant: 'Netflix', categoryId: 'subscription'),
      for (var d = 1; d <= now.day; d++)
        tx(DateTime(now.year, now.month, d, 0, 2), 1000,
            merchant: '瑞幸咖啡', categoryId: 'food'),
    ];

    final facts = service.factsForMonth(
      month: monthStart,
      all: all,
      monthlyBudgetCents: 0,
    );
    final projection = facts.firstWhere((f) => f.fallback.id == 'projection');

    expect(projection.payload['paceExcludedCents'], 6800);
    expect(projection.payload['variableDailyAvgCents'], 1000);
    expect(projection.payload['projectedCents'], 6800 + 1000 * daysInMonth);
  });

  test('已支付房租和白条只保留实际金额，不再追加未付固定项', () {
    final all = <TransactionEntity>[
      tx(DateTime(now.year, now.month, 1, 9), 300000,
          merchant: '嘉恒广场',
          categoryId: 'housing',
          recurringTransactionId: 'rent-rule'),
      tx(DateTime(now.year, now.month, 1, 9), 44100,
          merchant: '京东',
          categoryId: 'subscription',
          recurringTransactionId: 'jd-rule'),
      // 即使这家面馆在历史上恰好每月只出现一次，餐饮仍是日常消费。
      tx(monthAgo(2), 1300, merchant: '包扁担重庆小面', categoryId: 'food'),
      tx(monthAgo(1), 1300, merchant: '包扁担重庆小面', categoryId: 'food'),
      tx(DateTime(now.year, now.month, now.day, 11, 40), 1300,
          merchant: '包扁担重庆小面', categoryId: 'food'),
      tx(DateTime(now.year, now.month, 2, 9), 17731, categoryId: 'food'),
    ];

    final facts = service.factsForMonth(
      month: monthStart,
      all: all,
      monthlyBudgetCents: 0,
    );
    final projection = facts.firstWhere((f) => f.fallback.id == 'projection');
    final daily = (19031 / now.day).round();

    expect(projection.payload['paceExcludedCents'], 344100);
    expect(projection.payload['variableDailyAvgCents'], daily);
    expect(
      projection.payload['projectedCents'],
      363131 + daily * (daysInMonth - now.day),
    );
  });

  test('分类环比与上月同期对齐（两侧均 1 号发生）', () {
    final all = <TransactionEntity>[
      tx(DateTime(now.year, now.month, 1, 0, 1), 30000, categoryId: 'food'),
      tx(prevMonthDay(1), 20000, categoryId: 'food'),
    ];
    final facts = service.factsForMonth(
      month: monthStart,
      all: all,
      monthlyBudgetCents: 0,
    );
    final mom = facts.firstWhere((f) => f.fallback.id.startsWith('mom_food'));
    expect(mom.payload['samePeriod'], isTrue);
    expect(mom.payload['currentCents'], 30000);
    expect(mom.payload['previousCents'], 20000);
    expect(mom.payload['deltaPct'], 50);
    expect(mom.fallback.text, contains('同期'));
  });

  test('固定月度消费（如计入餐饮的房租）从环比两侧剔除', () {
    final all = <TransactionEntity>[
      for (final m in [monthAgo(3), monthAgo(2)])
        tx(DateTime(m.year, m.month, 1, 9), 300000,
            merchant: '嘉恒广场', categoryId: 'food'),
      // 上月房租 + 上月可变餐饮 200。
      tx(monthAgo(1), 300000, merchant: '嘉恒广场', categoryId: 'food'),
      tx(monthAgo(1), 20000, categoryId: 'food'),
      // 本月房租 + 本月可变餐饮 250。
      tx(DateTime(now.year, now.month, 1, 0, 1), 300000,
          merchant: '嘉恒广场', categoryId: 'food'),
      tx(DateTime(now.year, now.month, 1, 0, 2), 25000, categoryId: 'food'),
    ];
    final facts = service.factsForMonth(
      month: monthStart,
      all: all,
      monthlyBudgetCents: 0,
    );
    final mom = facts.firstWhere((f) => f.fallback.id.startsWith('mom_food'));
    // 若未剔固定：325000 vs 323000 → +0.6% 不触发；剔固定后 25000 vs 20000 → +25%。
    expect(mom.payload['currentCents'], 25000);
    expect(mom.payload['previousCents'], 20000);
    expect(mom.payload['deltaPct'], 25);
  });

  test('上月同期天数不足时按上月日均外推（30 天 vs 2 月 28 天）', () {
    final all = <TransactionEntity>[
      // 2026-02 每天 10 元（28 天共 280 元）。
      for (var d = 1; d <= 28; d++)
        tx(DateTime(2026, 2, d, 12), 1000, categoryId: 'food'),
      tx(DateTime(2026, 3, 1, 12), 30000, categoryId: 'food'),
    ];
    final swing = InsightsService.biggestCategorySwing(
      all,
      (_) => false,
      DateTime(2026, 3, 1),
      DateTime(2026, 4, 1),
      DateTime(2026, 2, 1),
      samePeriodDays: 30,
    );
    expect(swing, isNotNull);
    expect(swing!.$1, 'food');
    expect(swing.$3, 30000); // 本期
    expect(swing.$4, 30000); // 28000 / 28 × 30
    expect(swing.$5, isTrue);

    // 对齐 15 天：上月同期 = 15000。
    final aligned = InsightsService.biggestCategorySwing(
      all,
      (_) => false,
      DateTime(2026, 3, 1),
      DateTime(2026, 4, 1),
      DateTime(2026, 2, 1),
      samePeriodDays: 15,
    );
    expect(aligned!.$4, 15000);
  });

  test('历史完整月保持整月 vs 整月口径', () {
    final all = <TransactionEntity>[
      tx(DateTime(2020, 1, 5, 9), 30000, categoryId: 'food'),
      tx(DateTime(2019, 12, 5, 9), 20000, categoryId: 'food'),
    ];
    final facts = service.factsForMonth(
      month: DateTime(2020, 1, 1),
      all: all,
      monthlyBudgetCents: 0,
    );
    final mom = facts.firstWhere((f) => f.fallback.id.startsWith('mom_food'));
    expect(mom.payload['samePeriod'], isFalse);
    expect(mom.payload['currentCents'], 30000);
    expect(mom.payload['previousCents'], 20000);
    expect(mom.fallback.text, isNot(contains('同期')));
  });

  test('预算进度事实与模板兜底一致', () {
    final all = <TransactionEntity>[
      tx(DateTime(now.year, now.month, 1, 0, 1), 8000),
    ];
    final facts = service.factsForMonth(
      month: monthStart,
      all: all,
      monthlyBudgetCents: 10000,
    );
    final budget = facts.firstWhere((f) => f.fallback.id == 'budget_warn');
    expect(budget.payload['usedPct'], 80);
    expect(budget.payload['remainingCents'], 2000);

    final insights = service.insightsForMonth(
      month: monthStart,
      all: all,
      monthlyBudgetCents: 10000,
    );
    expect(
      insights.map((i) => i.text).toSet(),
      facts.map((f) => f.fallback.text).toSet(),
    );
  });
}
