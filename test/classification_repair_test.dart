import 'package:flutter_test/flutter_test.dart';
import 'package:flowmoney/domain/models/enums.dart';
import 'package:flowmoney/domain/models/transaction.dart';
import 'package:flowmoney/services/classification_repair_service.dart';

void main() {
  test('鲜榨果汁从其他修复为餐饮', () {
    expect(
      ClassificationRepairService.suggestCategory(
        _transaction(merchant: '鲜榨果汁', categoryId: 'other'),
      ),
      'food',
    );
  });

  test('商户名称中的重庆小面等餐饮品类可以修复分类', () {
    for (final merchant in ['老街重庆小面', '兰州牛肉面馆', '阿姨麻辣烫', '巷口粥铺']) {
      expect(
        ClassificationRepairService.suggestCategory(
          _transaction(merchant: merchant, categoryId: 'other'),
        ),
        'food',
        reason: merchant,
      );
    }
  });

  test('滴滴始终修复为交通，美团有订单描述时识别为餐饮', () {
    expect(
      ClassificationRepairService.suggestCategory(
        _transaction(merchant: '滴滴出行', categoryId: 'other'),
      ),
      'transport',
    );
    expect(
      ClassificationRepairService.suggestCategory(
        _transaction(
          merchant: '美团',
          description: '某某餐厅订单',
          categoryId: 'other',
        ),
      ),
      'food',
    );
  });

  test('小遛固定为交通且可以覆盖旧分类', () {
    expect(
      ClassificationRepairService.suggestCategory(
        _transaction(merchant: '小遛共享电动车', categoryId: 'other'),
      ),
      'transport',
    );
  });

  test('购买螺丝钉固定为购物而不是住房', () {
    expect(
      ClassificationRepairService.suggestCategory(
        _transaction(
          merchant: '五金店',
          description: '购买螺丝钉',
          categoryId: 'housing',
        ),
      ),
      'shopping',
    );
  });
}

TransactionEntity _transaction({
  required String merchant,
  required String categoryId,
  String? description,
}) {
  final now = DateTime.now();
  return TransactionEntity(
    id: merchant,
    userId: 'local',
    type: TransactionType.expense,
    amountCents: 1200,
    currency: 'CNY',
    categoryId: categoryId,
    merchant: merchant,
    description: description,
    transactionTime: now,
    createdAt: now,
    updatedAt: now,
    sourceType: SourceType.screenshot,
    confidence: 0.8,
    status: TxStatus.confirmed,
  );
}
