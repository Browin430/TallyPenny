// 核心纯逻辑冒烟测试（金额工具 + 规则解析器）。
// Widget 冒烟测试需要完整 Provider 覆盖与 SharedPreferences mock，
// 在 Phase 2 引入集成测试时补充。

import 'package:flutter_test/flutter_test.dart';
import 'package:flowmoney/core/utils/money_utils.dart';
import 'package:flowmoney/data/services/rule_based_transaction_parser.dart';
import 'package:flowmoney/domain/models/enums.dart';

void main() {
  group('Money', () {
    test('分 → 展示文本', () {
      expect(Money.centsToText(812300), '8,123.00');
      expect(Money.centsToCompact(812300), '8,123');
      expect(Money.centsToCompact(1250), '12.50');
    });

    test('用户输入 → 分', () {
      expect(Money.parseToCents('28.5'), 2850);
      expect(Money.parseToCents('1,234.56'), 123456);
      expect(Money.parseToCents('0'), isNull);
      expect(Money.parseToCents('-3'), isNull);
      expect(Money.parseToCents('abc'), isNull);
    });

    test('带符号展示', () {
      expect(Money.signed(3200, isIncome: false), '-¥32.00');
      expect(Money.signed(1500000, isIncome: true), '+¥15,000.00');
    });
  });

  group('RuleBasedTransactionParser', () {
    final parser = RuleBasedTransactionParser();

    test('解析口语金额与商户', () async {
      final c = await parser.parseFromText('昨天中午在麦当劳吃了三十二块');
      expect(c.hasAmount, isTrue);
      expect(c.amountCents, 3200);
    });

    test('数字金额 + 时间', () async {
      final c = await parser.parseFromText('打车28块5');
      expect(c.amountCents, 2850);
      expect(c.type, TransactionType.expense);
    });

    test('收入方向', () async {
      final c = await parser.parseFromText('收到工资15000');
      expect(c.type, TransactionType.income);
      expect(c.amountCents, 1500000);
    });

    test('没有金额 → hasAmount false（绝不静默生成 ¥0 账单）', () async {
      final c = await parser.parseFromText('买咖啡');
      expect(c.hasAmount, isFalse);
    });
  });
}
