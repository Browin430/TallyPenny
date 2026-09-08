import 'package:flutter_test/flutter_test.dart';
import 'package:flowmoney/data/dao/mappers.dart';
import 'package:flowmoney/data/repositories/memory_invoice_repository.dart';
import 'package:flowmoney/domain/models/enums.dart';
import 'package:flowmoney/domain/models/transaction.dart';
import 'package:flowmoney/services/invoice_management_service.dart';

void main() {
  TransactionEntity transaction({
    String id = 'tx-1',
    int amount = 3200,
    bool invoiceRequired = false,
    bool invoiceIssued = false,
    bool invoiceWaived = false,
    bool reimbursed = false,
  }) {
    final now = DateTime(2026, 8, 28, 12);
    return TransactionEntity(
      id: id,
      userId: 'local',
      type: TransactionType.expense,
      amountCents: amount,
      currency: 'CNY',
      transactionTime: now,
      createdAt: now,
      updatedAt: now,
      sourceType: SourceType.manual,
      confidence: 1,
      status: TxStatus.confirmed,
      invoiceRequired: invoiceRequired,
      invoiceIssued: invoiceIssued,
      invoiceWaived: invoiceWaived,
      reimbursed: reimbursed,
    );
  }

  test('账单开票与报销字段可复制并完成数据库映射', () {
    final updated = transaction().copyWith(
      invoiceRequired: true,
      invoiceIssued: true,
      invoiceWaived: false,
      reimbursed: true,
    );
    final mapped = txToMap(updated);
    expect(mapped['invoice_required'], 1);
    expect(mapped['invoice_issued'], 1);
    expect(mapped['invoice_waived'], 0);
    expect(mapped['reimbursed'], 1);

    final restored = txFromMap(mapped);
    expect(restored.invoiceRequired, isTrue);
    expect(restored.invoiceIssued, isTrue);
    expect(restored.invoiceWaived, isFalse);
    expect(restored.reimbursed, isTrue);
  });

  test('旧数据库记录缺少发票字段时默认为关闭', () {
    final mapped = txToMap(transaction())
      ..remove('invoice_required')
      ..remove('invoice_issued')
      ..remove('invoice_waived')
      ..remove('reimbursed');
    final restored = txFromMap(mapped);
    expect(restored.invoiceRequired, isFalse);
    expect(restored.invoiceIssued, isFalse);
    expect(restored.invoiceWaived, isFalse);
    expect(restored.reimbursed, isFalse);
  });

  test('无需开票状态可独立于报销保存', () {
    final updated = transaction().copyWith(
      invoiceWaived: true,
      reimbursed: true,
    );
    final restored = txFromMap(txToMap(updated));
    expect(restored.invoiceWaived, isTrue);
    expect(restored.reimbursed, isTrue);
    expect(restored.invoiceRequired, isFalse);
    expect(restored.invoiceIssued, isFalse);
  });

  test('已报销可以与未开票状态同时保存', () {
    final tx = transaction().copyWith(
      invoiceRequired: true,
      invoiceIssued: false,
      reimbursed: true,
    );
    final restored = txFromMap(txToMap(tx));
    expect(restored.reimbursed, isTrue);
    expect(restored.invoiceRequired, isTrue);
    expect(restored.invoiceIssued, isFalse);
  });

  test('状态筛选相互独立并按金额从大到小排序', () {
    final transactions = [
      transaction(id: 'personal', amount: 99999),
      transaction(
        id: 'issued',
        amount: 10000,
        invoiceIssued: true,
      ),
      transaction(
        id: 'reimbursed-before-invoice',
        amount: 7000,
        invoiceRequired: true,
        reimbursed: true,
      ),
      transaction(
        id: 'waived',
        amount: 5000,
        invoiceWaived: true,
      ),
      transaction(
        id: 'waiting-invoice',
        amount: 3000,
        invoiceRequired: true,
      ),
    ];

    expect(
      InvoiceManagementService.filteredAndSorted(
        transactions,
        InvoiceStatusView.waitingInvoice,
      ).map((item) => item.id),
      ['reimbursed-before-invoice', 'waiting-invoice'],
    );
    expect(
      InvoiceManagementService.filteredAndSorted(
        transactions,
        InvoiceStatusView.waitingReimbursement,
      ).map((item) => item.id),
      ['issued', 'waived', 'waiting-invoice'],
    );
    expect(
      InvoiceManagementService.filteredAndSorted(
        transactions,
        InvoiceStatusView.reimbursed,
      ).map((item) => item.id),
      ['reimbursed-before-invoice'],
    );
  });

  test('发票附件可以保存、关联、解除关联和删除', () async {
    final repository = MemoryInvoiceRepository();
    final document = InvoiceDocument(
      id: 'invoice-1',
      transactionId: 'tx-1',
      storedPath: '/private/invoices/invoice-1.jpg',
      originalName: '发票.jpg',
      fileType: 'image',
      createdAt: DateTime(2026, 8, 28),
    );

    await repository.insert(document);
    expect(await repository.forTransaction('tx-1'), hasLength(1));

    await repository.update(document.copyWith(unlink: true));
    expect(await repository.forTransaction('tx-1'), isEmpty);
    expect((await repository.getAll()).single.transactionId, isNull);

    await repository.delete(document.id);
    expect(await repository.getAll(), isEmpty);
  });
}
