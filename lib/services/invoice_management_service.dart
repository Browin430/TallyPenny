import '../domain/models/transaction.dart';

enum InvoiceStatusView { waitingInvoice, waitingReimbursement, reimbursed }

/// 发票与报销页的筛选规则。开票和报销互相独立，因此同一账单可同时
/// 出现在“待开票”和“已报销”中。
class InvoiceManagementService {
  const InvoiceManagementService._();

  static bool isManaged(TransactionEntity transaction) =>
      transaction.invoiceRequired ||
      transaction.invoiceIssued ||
      transaction.invoiceWaived ||
      transaction.reimbursed;

  static bool matches(
    TransactionEntity transaction,
    InvoiceStatusView view,
  ) =>
      switch (view) {
        InvoiceStatusView.waitingInvoice => transaction.invoiceRequired &&
            !transaction.invoiceIssued &&
            !transaction.invoiceWaived,
        InvoiceStatusView.waitingReimbursement =>
          isManaged(transaction) && !transaction.reimbursed,
        InvoiceStatusView.reimbursed => transaction.reimbursed,
      };

  /// 金额大的优先；金额相同时，较新的账单优先。
  static List<TransactionEntity> filteredAndSorted(
    Iterable<TransactionEntity> transactions,
    InvoiceStatusView view,
  ) {
    final result = transactions
        .where(isManaged)
        .where((transaction) => matches(transaction, view))
        .toList();
    result.sort((a, b) {
      final byAmount = b.amountCents.compareTo(a.amountCents);
      return byAmount != 0
          ? byAmount
          : b.transactionTime.compareTo(a.transactionTime);
    });
    return result;
  }

  static int count(
    Iterable<TransactionEntity> transactions,
    InvoiceStatusView view,
  ) =>
      transactions
          .where(isManaged)
          .where((transaction) => matches(transaction, view))
          .length;
}
