import 'package:flutter_test/flutter_test.dart';
import 'package:flowmoney/data/repositories/memory_merchant_rule_repository.dart';
import 'package:flowmoney/data/repositories/memory_transaction_repository.dart';
import 'package:flowmoney/domain/models/enums.dart';
import 'package:flowmoney/domain/models/merchant_rule.dart';
import 'package:flowmoney/domain/models/transaction_candidate.dart';
import 'package:flowmoney/domain/pipeline/transaction_pipeline.dart';
import 'package:flowmoney/services/duplicate_detection_service.dart';
import 'package:flowmoney/services/merchant_rule_matcher.dart';

MerchantRule _rule(
  String pattern,
  String category, {
  String id = 'r1',
  String? note,
  int hitCount = 0,
}) {
  final now = DateTime(2026, 9, 1);
  return MerchantRule(
    id: id,
    userId: 'local',
    merchantPattern: pattern,
    preferredCategory: category,
    note: note,
    hitCount: hitCount,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('MerchantRuleMatcher', () {
    test('归一化精确匹配（大小写/空格）', () {
      final rules = [_rule('C.L', 'food')];
      expect(MerchantRuleMatcher.match(rules, 'C.L')!.preferredCategory, 'food');
      expect(MerchantRuleMatcher.match(rules, ' c.l ')!.preferredCategory,
          'food');
    });

    test('互为包含匹配（截图商户常带前后缀）', () {
      final rules = [_rule('黄焖鸡', 'food')];
      expect(
        MerchantRuleMatcher.match(rules, '公司楼下黄焖鸡(米饭店)')!.preferredCategory,
        'food',
      );
      // 反向：规则长、商户短（账单只写简名）同样命中。
      final long = [_rule('嘉恒广场物业费', 'housing')];
      expect(
        MerchantRuleMatcher.match(long, '嘉恒广场')!.preferredCategory,
        'housing',
      );
    });

    test('单字包含不匹配（防误中）', () {
      final rules = [_rule('肯', 'food')];
      expect(MerchantRuleMatcher.match(rules, '肯德基'), isNull);
    });

    test('多命中取最长 pattern', () {
      final rules = [
        _rule('咖啡', 'food', id: 'a'),
        _rule('瑞幸咖啡', 'food', id: 'b'),
      ];
      expect(MerchantRuleMatcher.match(rules, '瑞幸咖啡(旗舰店)')!.id, 'b');
    });

    test('空商户返回 null', () {
      final rules = [_rule('C.L', 'food')];
      expect(MerchantRuleMatcher.match(rules, null), isNull);
      expect(MerchantRuleMatcher.match(rules, '  '), isNull);
    });

    test('toWireJson 含备注并截断到 50 条', () {
      final rules = [
        for (var i = 0; i < 60; i++)
          _rule('C.L-$i', 'food', note: '公司楼下黄焖鸡', id: 'x$i'),
      ];
      final wire = MerchantRuleMatcher.toWireJson(rules);
      expect(wire.length, 50);
      expect(wire.first, containsPair('note', '公司楼下黄焖鸡'));
    });
  });

  group('TransactionPipeline 商户规则覆盖', () {
    late MemoryMerchantRuleRepository merchantRules;
    late MemoryTransactionRepository transactions;

    TransactionPipeline buildPipeline() => TransactionPipeline(
          transactionRepository: transactions,
          duplicateDetection: DuplicateDetectionService(transactions),
          merchantRules: merchantRules,
        );

    setUp(() {
      merchantRules = MemoryMerchantRuleRepository();
      transactions = MemoryTransactionRepository();
    });

    test('命中规则覆盖分类（含覆盖 AI 猜测的非 other 分类）', () async {
      await merchantRules.upsert(_rule('C.L', 'food', hitCount: 3));
      final pipeline = buildPipeline();

      // AI 本来猜成购物。
      final result = await pipeline.process(const TransactionCandidate(
        type: TransactionType.expense,
        amountCents: 2000,
        merchant: 'C.L',
        categoryId: 'shopping',
        sourceType: SourceType.voice,
        confidence: 0.9,
      ));
      expect(result, isA<PipelineSaved>());
      final saved = (result as PipelineSaved).transaction;
      expect(saved.categoryId, 'food');
      expect(saved.merchant, 'C.L');

      // hitCount 异步递增（best-effort）。
      await Future<void>.delayed(Duration.zero);
      expect((await merchantRules.getAll()).single.hitCount, 4);
    });

    test('未命中走原分类 / other 兜底', () async {
      await merchantRules.upsert(_rule('C.L', 'food'));
      final pipeline = buildPipeline();

      final withCategory = await pipeline.process(const TransactionCandidate(
        type: TransactionType.expense,
        amountCents: 1500,
        merchant: '瑞幸咖啡',
        categoryId: 'food',
        sourceType: SourceType.manual,
        confidence: 1,
      ));
      expect((withCategory as PipelineSaved).transaction.categoryId, 'food');

      final noCategory = await pipeline.process(const TransactionCandidate(
        type: TransactionType.income,
        amountCents: 1500000,
        merchant: '公司',
        sourceType: SourceType.manual,
        confidence: 1,
      ));
      expect((noCategory as PipelineSaved).transaction.categoryId,
          'other_income');
    });

    test('无商户规则的管线行为不变', () async {
      final pipeline = TransactionPipeline(
        transactionRepository: transactions,
        duplicateDetection: DuplicateDetectionService(transactions),
      );
      final result = await pipeline.process(const TransactionCandidate(
        type: TransactionType.expense,
        amountCents: 3000,
        merchant: 'C.L',
        sourceType: SourceType.manual,
        confidence: 1,
      ));
      expect((result as PipelineSaved).transaction.categoryId, 'other');
    });
  });
}
