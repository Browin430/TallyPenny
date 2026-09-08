import '../data/services/rule_based_transaction_parser.dart';
import '../domain/models/enums.dart';
import '../domain/models/transaction.dart';
import '../domain/repositories/transaction_repository.dart';

/// 修复旧识别结果中的明显分类错误，并为平台型商户补充稳定规则。
class ClassificationRepairService {
  const ClassificationRepairService(this._transactions);

  final TransactionRepository _transactions;

  Future<int> repairExisting() async {
    var changed = 0;
    for (final transaction in await _transactions.getAll()) {
      final category = suggestCategory(transaction);
      if (category == null || category == transaction.categoryId) continue;
      await _transactions.update(
        transaction.copyWith(categoryId: category, updatedAt: DateTime.now()),
      );
      changed++;
    }
    return changed;
  }

  static String? suggestCategory(TransactionEntity transaction) {
    if (transaction.type != TransactionType.expense) return null;
    final merchant = transaction.merchant?.trim() ?? '';
    final description = transaction.description?.trim() ?? '';
    final probe = '$merchant $description ${transaction.note ?? ''} '
        '${transaction.subcategory ?? ''}';

    // 高确定性的平台和商品规则必须覆盖模型旧分类。
    if (probe.contains('小遛')) {
      return 'transport';
    }
    if (_hardwareKeywords.any(probe.contains)) {
      return 'shopping';
    }

    // 平台功能优先于模型偶发猜测：滴滴是交通；美团且有订单描述按餐饮处理。
    if (merchant.contains('滴滴') || probe.contains('滴滴出行')) {
      return 'transport';
    }
    if (merchant.contains('美团') &&
        description.isNotEmpty &&
        (transaction.categoryId == null || transaction.categoryId == 'other')) {
      return 'food';
    }

    // 不覆盖用户已有的明确分类，只修复“其他/未分类”。
    if (transaction.categoryId != null && transaction.categoryId != 'other') {
      return null;
    }
    final predicted =
        RuleBasedTransactionParser.classify(probe, isIncome: false)?.$1;
    return const {
      'food',
      'transport',
      'shopping',
      'housing',
      'entertainment',
      'medical',
      'education',
      'travel',
      'pet',
      'telecom',
      'utilities',
      'subscription',
      'insurance',
      'car',
      'gift',
      'social',
      'investment',
    }.contains(predicted)
        ? predicted
        : null;
  }

  static const _hardwareKeywords = [
    '螺丝钉',
    '螺丝刀',
    '螺丝',
    '螺母',
    '垫片',
    '紧固件',
    '五金',
    '扳手',
    '钳子',
    '钻头',
  ];
}
