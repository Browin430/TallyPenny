import 'package:flutter_test/flutter_test.dart';
import 'package:flowmoney/domain/models/enums.dart';
import 'package:flowmoney/domain/models/transaction.dart';
import 'package:flowmoney/services/monthly_fixed_expense_detector.dart';

TransactionEntity tx(
  DateTime time,
  int amountCents, {
  String? merchant,
  String categoryId = 'other',
  String? recurringId,
}) {
  final created = DateTime(2026, 1, 1);
  return TransactionEntity(
    id: 'tx-${time.hashCode}-$amountCents-${merchant ?? recurringId ?? "x"}',
    userId: 'local',
    type: TransactionType.expense,
    amountCents: amountCents,
    currency: 'CNY',
    transactionTime: time,
    createdAt: created,
    updatedAt: created,
    sourceType: SourceType.manual,
    confidence: 1,
    status: TxStatus.confirmed,
    categoryId: categoryId,
    merchant: merchant,
    recurringTransactionId: recurringId,
    isRecurring: recurringId != null,
  );
}

void main() {
  // 锚定月固定为 2026-09，避免依赖真实时钟。
  final anchor = DateTime(2026, 9, 1);

  test('每月一次且金额稳定的商户 → 固定项', () {
    final expenses = [
      for (final m in [6, 7, 8])
        tx(DateTime(2026, m, 1, 9), 300000, merchant: '嘉恒广场'),
      tx(DateTime(2026, 9, 1, 9), 300000, merchant: '嘉恒广场'),
    ];
    final items = MonthlyFixedExpenseDetector.detect(
      settledExpenses: expenses,
      anchorMonth: anchor,
    );
    expect(items, hasLength(1));
    expect(items.single.key, 'm:嘉恒广场');
    expect(items.single.paidThisMonth, isTrue);
    expect(items.single.avgRecentCents, 300000);
    expect(items.single.monthlyCents[MonthlyFixedExpenseDetector.monthKey(anchor)],
        300000);
  });

  test('每日咖啡（月内 >2 笔）→ 可变', () {
    final expenses = [
      for (var d = 1; d <= 20; d++)
        for (final m in [7, 8])
          tx(DateTime(2026, m, d, 10), 1500, merchant: '瑞幸咖啡'),
    ];
    final items = MonthlyFixedExpenseDetector.detect(
      settledExpenses: expenses,
      anchorMonth: anchor,
    );
    expect(items, isEmpty);
  });

  test('周频周期规则（每月 4+ 笔）→ 可变；月频周期规则 1 个月史 → 固定', () {
    final weekly = [
      for (var w = 0; w < 4; w++)
        for (final m in [7, 8])
          tx(DateTime(2026, m, 1 + w * 7, 9), 300, recurringId: 'metro'),
    ];
    final monthlyRuleOnlyOnce = [
      tx(DateTime(2026, 8, 15, 9), 6800, recurringId: 'netflix'),
    ];
    final items = MonthlyFixedExpenseDetector.detect(
      settledExpenses: [...weekly, ...monthlyRuleOnlyOnce],
      anchorMonth: anchor,
    );
    expect(items.map((i) => i.key), ['rule:netflix']);
    expect(items.single.avgRecentCents, 6800);
    expect(items.single.paidThisMonth, isFalse);
  });

  test('金额波动大（σ/μ > 0.35）→ 可变', () {
    final expenses = [
      tx(DateTime(2026, 6, 5, 9), 10000, merchant: '京东'),
      tx(DateTime(2026, 7, 5, 9), 60000, merchant: '京东'),
      tx(DateTime(2026, 8, 5, 9), 90000, merchant: '京东'),
    ];
    final items = MonthlyFixedExpenseDetector.detect(
      settledExpenses: expenses,
      anchorMonth: anchor,
    );
    expect(items, isEmpty);
  });

  test('商户大小写与空格归一化合并为同一固定项', () {
    final expenses = [
      tx(DateTime(2026, 6, 2, 9), 2500, merchant: 'KFC'),
      tx(DateTime(2026, 7, 2, 9), 2600, merchant: ' kfc '),
      tx(DateTime(2026, 8, 2, 9), 2400, merchant: 'K FC'),
    ];
    final items = MonthlyFixedExpenseDetector.detect(
      settledExpenses: expenses,
      anchorMonth: anchor,
    );
    expect(items, hasLength(1));
    expect(items.single.key, 'm:kfc');
    // 均值 = (2500 + 2600 + 2400) / 3 = 2500
    expect(items.single.avgRecentCents, 2500);
  });

  test('仅出现 1 个完整月的普通商户 → 不算固定（保守）', () {
    final expenses = [
      tx(DateTime(2026, 8, 5, 9), 300000, merchant: '新房东'),
    ];
    final items = MonthlyFixedExpenseDetector.detect(
      settledExpenses: expenses,
      anchorMonth: anchor,
    );
    expect(items, isEmpty);
  });

  test('无商户无周期来源的账单不参与分组', () {
    final expenses = [
      for (final m in [6, 7, 8]) tx(DateTime(2026, m, 1, 9), 300000),
    ];
    final items = MonthlyFixedExpenseDetector.detect(
      settledExpenses: expenses,
      anchorMonth: anchor,
    );
    expect(items, isEmpty);
  });
}
