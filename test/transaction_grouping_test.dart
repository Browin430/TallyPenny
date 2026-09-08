import 'package:flutter_test/flutter_test.dart';
import 'package:flowmoney/data/repositories/memory_transaction_repository.dart';
import 'package:flowmoney/domain/models/enums.dart';
import 'package:flowmoney/domain/models/transaction.dart';
import 'package:flowmoney/domain/models/transaction_candidate.dart';
import 'package:flowmoney/services/refund_reconciliation_service.dart';
import 'package:flowmoney/services/transaction_grouping_service.dart';

void main() {
  group('流水商户与散单分组', () {
    test('3笔及以上进入商户组，只有1至2笔按分类折叠', () {
      final transactions = <TransactionEntity>[
        _transaction('a1', merchant: '常用商户', cents: 100),
        _transaction('a2', merchant: '常用商户', cents: 500),
        _transaction('a3', merchant: '常用商户', cents: 300),
        _transaction('a4', merchant: '常用商户', cents: 200),
        _transaction('b1', merchant: '偶尔商户', cents: 900),
        _transaction('b2', merchant: '偶尔商户', cents: 800),
        _transaction('d1', merchant: '正好三笔', cents: 1200),
        _transaction('d2', merchant: '正好三笔', cents: 1100),
        _transaction('d3', merchant: '正好三笔', cents: 1000),
        _transaction('c1', merchant: null, cents: 2500, categoryId: 'food'),
        _transaction('c2', merchant: null, cents: 500, categoryId: 'transport'),
      ];

      final result = TransactionGroupingService.group(transactions);

      expect(result.merchants, hasLength(2));
      expect(result.merchants.last.title, '常用商户');
      expect(
        result.merchants.last.transactions.map((item) => item.amountCents),
        [500, 300, 200, 100],
      );
      expect(
        result.scatteredCategories.map((group) => group.categoryId),
        ['food', 'transport'],
      );
      expect(result.scatteredCategories.first.transactions, hasLength(3));
      expect(result.company, isNull);
    });

    test('开票及报销账单从商户和散单中移出并统一放到公司账单', () {
      final transactions = <TransactionEntity>[
        _transaction('personal', merchant: '普通商户', cents: 100),
        _transaction(
          'invoice-required',
          merchant: '普通商户',
          cents: 200,
          invoiceRequired: true,
        ),
        _transaction(
          'invoice-issued',
          merchant: '另一个商户',
          cents: 300,
          invoiceIssued: true,
        ),
        _transaction(
          'invoice-waived',
          merchant: null,
          cents: 400,
          invoiceWaived: true,
        ),
        _transaction(
          'reimbursed',
          merchant: null,
          cents: 500,
          reimbursed: true,
        ),
      ];

      final result = TransactionGroupingService.group(transactions);

      expect(result.merchants, isEmpty);
      expect(
        result.scatteredCategories
            .expand((group) => group.transactions)
            .map((item) => item.id),
        ['personal'],
      );
      expect(result.company?.title, '公司账单');
      expect(
        result.company?.transactions.map((item) => item.id),
        ['reimbursed', 'invoice-waived', 'invoice-issued', 'invoice-required'],
      );
    });

    test('时间模式按日期和具体时间从新到旧排列', () {
      final result = TransactionGroupingService.timeline([
        _transaction(
          'older-day',
          merchant: '甲',
          cents: 100,
          transactionTime: DateTime(2026, 8, 19, 23),
        ),
        _transaction(
          'newer-time',
          merchant: '乙',
          cents: 200,
          transactionTime: DateTime(2026, 8, 20, 18),
        ),
        _transaction(
          'older-time',
          merchant: '丙',
          cents: 300,
          transactionTime: DateTime(2026, 8, 20, 9),
        ),
      ]);

      expect(result.map((group) => group.title), ['8月20日', '8月19日']);
      expect(
        result.first.transactions.map((item) => item.id),
        ['newer-time', 'older-time'],
      );
    });
  });

  group('退款冲销', () {
    test('全额退款原支出与退款收入均忽略，正常订单保留', () {
      final service = RefundReconciliationService(MemoryTransactionRepository());
      final result = service.removePairsWithinBatch([
        TransactionCandidate(
          sourceType: SourceType.screenshot,
          confidence: 0.9,
          type: TransactionType.expense,
          amountCents: 2991,
          merchant: '美团',
          note: '已全额退款',
        ),
        _candidate(TransactionType.income, 2991, '美团'),
        _candidate(TransactionType.expense, 2690, '美团'),
        _candidate(TransactionType.expense, 2991, '美团'),
      ]);
      expect(result.cancelledPairs, 2);
      expect(result.remaining.map((item) => item.amountCents), [2690, 2991]);
    });

    test('同批退款直接忽略且不删除其他支出', () {
      final service = RefundReconciliationService(
        MemoryTransactionRepository(),
      );
      final result = service.removePairsWithinBatch([
        _candidate(TransactionType.expense, 8800, '网购商户'),
        _candidate(TransactionType.income, 8800, '网购商户'),
        _candidate(TransactionType.expense, 8800, '网购商户'),
      ]);

      expect(result.cancelledPairs, 1);
      expect(result.remaining, hasLength(2));
      expect(
        result.remaining.every((item) => item.type == TransactionType.expense),
        isTrue,
      );
    });

    test('退款不写入流水，也不猜测删除已经存在的支出', () async {
      final repository = MemoryTransactionRepository();
      await repository.insert(
        _transaction('order', merchant: '网购商户', cents: 8800),
      );
      final service = RefundReconciliationService(repository);

      final cancelled = await service.cancelAgainstExisting(
        _candidate(TransactionType.income, 8800, '网购商户'),
      );

      expect(cancelled, isTrue);
      expect(await repository.getAll(), hasLength(1));
    });

    test('启动时只清理旧版本留下的退款收入', () async {
      final repository = MemoryTransactionRepository();
      await repository.insert(
        _transaction('expense', merchant: '网购商户', cents: 8800),
      );
      await repository.insert(
        _transaction(
          'refund',
          merchant: '网购商户',
          cents: 8800,
          type: TransactionType.income,
          categoryId: 'refund',
        ),
      );

      final pairs = await RefundReconciliationService(repository)
          .reconcileExistingImportedPairs();

      expect(pairs, 1);
      final remaining = await repository.getAll();
      expect(remaining, hasLength(1));
      expect(remaining.single.type, TransactionType.expense);
    });

    test('原支出已在回收站时继续清理残留的退款收入', () async {
      final repository = MemoryTransactionRepository();
      await repository.insert(
        _transaction('expense', merchant: '网购商户', cents: 8800),
      );
      await repository.softDelete('expense');
      await repository.insert(
        _transaction(
          'refund',
          merchant: '网购商户',
          cents: 8800,
          type: TransactionType.income,
          categoryId: 'refund',
        ),
      );

      final pairs = await RefundReconciliationService(repository)
          .reconcileExistingImportedPairs();

      expect(pairs, 1);
      expect(await repository.getAll(), isEmpty);
      expect(await repository.getDeleted(), hasLength(2));
    });

    test('同商户同金额的普通收入不会被当作退款', () async {
      final repository = MemoryTransactionRepository();
      await repository.insert(
        _transaction('expense', merchant: '往来商户', cents: 8800),
      );
      await repository.insert(
        _transaction(
          'income',
          merchant: '往来商户',
          cents: 8800,
          type: TransactionType.income,
          categoryId: 'other_income',
        ),
      );

      final pairs = await RefundReconciliationService(repository)
          .reconcileExistingImportedPairs();

      expect(pairs, 0);
      expect(await repository.getAll(), hasLength(2));
    });
  });
}

TransactionEntity _transaction(
  String id, {
  required String? merchant,
  required int cents,
  String categoryId = 'food',
  TransactionType type = TransactionType.expense,
  bool invoiceRequired = false,
  bool invoiceIssued = false,
  bool invoiceWaived = false,
  bool reimbursed = false,
  DateTime? transactionTime,
}) {
  final now = transactionTime ?? DateTime(2026, 8, 20, 12);
  return TransactionEntity(
    id: id,
    userId: 'local',
    type: type,
    amountCents: cents,
    currency: 'CNY',
    categoryId: categoryId,
    merchant: merchant,
    transactionTime: now,
    createdAt: now,
    updatedAt: now,
    sourceType: SourceType.screenshot,
    confidence: 0.9,
    status: TxStatus.confirmed,
    invoiceRequired: invoiceRequired,
    invoiceIssued: invoiceIssued,
    invoiceWaived: invoiceWaived,
    reimbursed: reimbursed,
  );
}

TransactionCandidate _candidate(
  TransactionType type,
  int cents,
  String merchant,
) =>
    TransactionCandidate(
      sourceType: SourceType.screenshot,
      confidence: 0.9,
      type: type,
      amountCents: cents,
      categoryId: type == TransactionType.income ? 'refund' : 'shopping',
      merchant: merchant,
      transactionTime: DateTime(2026, 8, 20, 12),
    );
