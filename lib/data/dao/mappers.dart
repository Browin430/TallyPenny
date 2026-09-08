import 'dart:convert';

import '../../core/utils/id_gen.dart';
import '../../domain/models/category.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/transaction.dart';
import '../../domain/models/transaction_candidate.dart';

/// 行 ↔ 实体映射（sqflite 与内存实现共用）。

TransactionEntity txFromMap(Map<String, Object?> m) => TransactionEntity(
      id: m['id'] as String,
      userId: m['user_id'] as String,
      type: TransactionType.fromDb(m['type'] as String),
      amountCents: m['amount'] as int,
      currency: (m['currency'] ?? 'CNY') as String,
      categoryId: m['category_id'] as String?,
      subcategory: m['subcategory'] as String?,
      merchant: m['merchant'] as String?,
      description: m['description'] as String?,
      transactionTime:
          DateTime.fromMillisecondsSinceEpoch(m['transaction_time'] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      sourceType: SourceType.fromDb(m['source_type'] as String),
      confidence: (m['confidence'] as num?)?.toDouble() ?? 1.0,
      status: TxStatus.fromDb(m['status'] as String),
      isRecurring: (m['is_recurring'] ?? 0) == 1,
      recurringTransactionId: m['recurring_transaction_id'] as String?,
      paymentMethod: PaymentMethod.fromDb(m['payment_method'] as String?),
      note: m['note'] as String?,
      invoiceRequired: (m['invoice_required'] ?? 0) == 1,
      invoiceIssued: (m['invoice_issued'] ?? 0) == 1,
      invoiceWaived: (m['invoice_waived'] ?? 0) == 1,
      reimbursed: (m['reimbursed'] ?? 0) == 1,
      isDeleted: (m['is_deleted'] ?? 0) == 1,
      deletedAt: m['deleted_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(m['deleted_at'] as int),
    );

Map<String, Object?> txToMap(TransactionEntity t) => {
      'id': t.id,
      'user_id': t.userId,
      'type': t.type.toDb(),
      'amount': t.amountCents,
      'currency': t.currency,
      'category_id': t.categoryId,
      'subcategory': t.subcategory,
      'merchant': t.merchant,
      'description': t.description,
      'transaction_time': t.transactionTime.millisecondsSinceEpoch,
      'created_at': t.createdAt.millisecondsSinceEpoch,
      'updated_at': t.updatedAt.millisecondsSinceEpoch,
      'source_type': t.sourceType.toDb(),
      'confidence': t.confidence,
      'status': t.status.toDb(),
      'is_recurring': t.isRecurring ? 1 : 0,
      'recurring_transaction_id': t.recurringTransactionId,
      'payment_method': t.paymentMethod?.toDb(),
      'note': t.note,
      'invoice_required': t.invoiceRequired ? 1 : 0,
      'invoice_issued': t.invoiceIssued ? 1 : 0,
      'invoice_waived': t.invoiceWaived ? 1 : 0,
      'reimbursed': t.reimbursed ? 1 : 0,
      'is_deleted': t.isDeleted ? 1 : 0,
      'deleted_at': t.deletedAt?.millisecondsSinceEpoch,
    };

InvoiceDocument invoiceFromMap(Map<String, Object?> m) => InvoiceDocument(
      id: m['id'] as String,
      transactionId: m['transaction_id'] as String?,
      storedPath: m['stored_path'] as String,
      originalName: m['original_name'] as String,
      fileType: m['file_type'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    );

Map<String, Object?> invoiceToMap(InvoiceDocument invoice) => {
      'id': invoice.id,
      'transaction_id': invoice.transactionId,
      'stored_path': invoice.storedPath,
      'original_name': invoice.originalName,
      'file_type': invoice.fileType,
      'created_at': invoice.createdAt.millisecondsSinceEpoch,
    };

SourceRecord sourceFromMap(Map<String, Object?> m) => SourceRecord(
      id: m['id'] as String,
      transactionId: m['transaction_id'] as String,
      sourceType: SourceType.fromDb(m['source_type'] as String),
      rawText: m['raw_text'] as String?,
      imageReference: m['image_reference'] as String?,
      ocrResult: m['ocr_result'] as String?,
      aiParseResult: m['ai_parse_result'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    );

Map<String, Object?> sourceToMap(SourceRecordDraft d, String transactionId) => {
      'id': IdGen.newId(),
      'transaction_id': transactionId,
      'source_type': d.sourceType.toDb(),
      'raw_text': d.rawText,
      'image_reference': d.imageReference,
      'ocr_result': d.ocrResultJson,
      'ai_parse_result': d.aiParseResultJson,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    };

Category categoryFromMap(Map<String, Object?> m) => Category(
      id: m['id'] as String,
      name: m['name'] as String,
      iconCode: m['icon'] as String,
      colorValue: m['color'] as int,
      type: TransactionType.fromDb(m['type'] as String),
      sortOrder: (m['sort_order'] ?? 0) as int,
      isSystem: (m['is_system'] ?? 0) == 1,
      isHidden: (m['is_hidden'] ?? 0) == 1,
    );

Map<String, Object?> categoryToMap(Category c) => {
      'id': c.id,
      'name': c.name,
      'icon': c.iconCode,
      'color': c.colorValue,
      'type': c.type.toDb(),
      'sort_order': c.sortOrder,
      'is_system': c.isSystem ? 1 : 0,
      'is_hidden': c.isHidden ? 1 : 0,
    };

String duplicateEventReasonsJson(List<String> reasons) => jsonEncode(reasons);
