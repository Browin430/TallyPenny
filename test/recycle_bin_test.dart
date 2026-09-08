import 'package:flutter_test/flutter_test.dart';
import 'package:flowmoney/data/repositories/memory_transaction_repository.dart';
import 'package:flowmoney/domain/models/enums.dart';
import 'package:flowmoney/domain/models/transaction.dart';

void main() {
  test('软删除账单与正常查询隔离并可还原', () async {
    final repository = MemoryTransactionRepository();
    await repository.insert(_transaction('one'));
    await repository.softDelete('one');

    expect(await repository.getAll(), isEmpty);
    expect(await repository.getById('one'), isNull);
    expect(await repository.getDeleted(), hasLength(1));

    await repository.restore('one');
    expect(await repository.getAll(), hasLength(1));
    expect(await repository.getDeleted(), isEmpty);
  });

  test('超过24小时的软删除账单会被永久清除', () async {
    final repository = MemoryTransactionRepository();
    final old = DateTime.now().subtract(const Duration(hours: 25));
    await repository.insert(
      _transaction('old').copyWith(isDeleted: true, deletedAt: old),
    );

    final purged = await repository.purgeDeletedBefore(
      DateTime.now().subtract(const Duration(hours: 24)),
    );
    expect(purged, 1);
    expect(await repository.getDeleted(), isEmpty);
  });
}

TransactionEntity _transaction(String id) {
  final now = DateTime.now();
  return TransactionEntity(
    id: id,
    userId: 'local',
    type: TransactionType.expense,
    amountCents: 1800,
    currency: 'CNY',
    merchant: '鲜榨果汁',
    transactionTime: now,
    createdAt: now,
    updatedAt: now,
    sourceType: SourceType.manual,
    confidence: 1,
    status: TxStatus.confirmed,
  );
}
