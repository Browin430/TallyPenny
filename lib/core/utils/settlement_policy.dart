import '../../domain/models/transaction.dart';

/// 结算只统计已经发生的账单；未来账单仍保存在流水中等待到期。
class SettlementPolicy {
  const SettlementPolicy._();

  static bool hasOccurred(TransactionEntity transaction, DateTime at) =>
      !transaction.transactionTime.isAfter(at);

  /// 开票/报销账单属于公司费用：保留在流水中，但不进入个人结余和收支分析。
  static bool isPersonal(TransactionEntity transaction) =>
      !transaction.invoiceRequired &&
      !transaction.invoiceIssued &&
      !transaction.invoiceWaived &&
      !transaction.reimbursed;

  /// 开票、无需开票或报销状态中的账单都归入公司账单。
  static bool isCompany(TransactionEntity transaction) =>
      !isPersonal(transaction);

  static bool countsTowardPersonalFinance(
    TransactionEntity transaction,
    DateTime at,
  ) =>
      hasOccurred(transaction, at) && isPersonal(transaction);

  static List<TransactionEntity> occurred(
    Iterable<TransactionEntity> transactions,
    DateTime at,
  ) =>
      transactions.where((item) => hasOccurred(item, at)).toList();

  static List<TransactionEntity> personalOccurred(
    Iterable<TransactionEntity> transactions,
    DateTime at,
  ) =>
      transactions
          .where((item) => countsTowardPersonalFinance(item, at))
          .toList();
}
