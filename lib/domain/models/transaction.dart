import 'enums.dart';

/// 一笔账单。金额一律为正数（分），方向由 [type] 决定。
class TransactionEntity {
  const TransactionEntity({
    required this.id,
    required this.userId,
    required this.type,
    required this.amountCents,
    required this.currency,
    required this.transactionTime,
    required this.createdAt,
    required this.updatedAt,
    required this.sourceType,
    required this.confidence,
    required this.status,
    this.categoryId,
    this.subcategory,
    this.merchant,
    this.description,
    this.isRecurring = false,
    this.recurringTransactionId,
    this.paymentMethod,
    this.note,
    this.invoiceRequired = false,
    this.invoiceIssued = false,
    this.invoiceWaived = false,
    this.reimbursed = false,
    this.isDeleted = false,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final TransactionType type;
  final int amountCents;
  final String currency;
  final String? categoryId;
  final String? subcategory;
  final String? merchant;
  final String? description;
  final DateTime transactionTime;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SourceType sourceType;
  final double confidence;
  final TxStatus status;
  final bool isRecurring;
  final String? recurringTransactionId;
  final PaymentMethod? paymentMethod;
  final String? note;
  final bool invoiceRequired;
  final bool invoiceIssued;

  /// 无需开票也可报销（例如无需发票的差旅补贴）。
  final bool invoiceWaived;
  final bool reimbursed;
  final bool isDeleted;
  final DateTime? deletedAt;

  bool get isIncome => type == TransactionType.income;

  /// 正负号金额（收入 +，支出 -）。
  int get signedAmountCents => isIncome ? amountCents : -amountCents;

  /// 展示标题：优先商户，其次描述，最后分类名由 UI 层解析。
  String get displayTitle {
    final t = (merchant != null && merchant!.trim().isNotEmpty)
        ? merchant!.trim()
        : (description ?? '').trim();
    return t.isEmpty ? '未命名' : t;
  }

  TransactionEntity copyWith({
    TransactionType? type,
    int? amountCents,
    String? currency,
    String? categoryId,
    String? subcategory,
    String? merchant,
    String? description,
    DateTime? transactionTime,
    DateTime? updatedAt,
    SourceType? sourceType,
    double? confidence,
    TxStatus? status,
    PaymentMethod? paymentMethod,
    String? note,
    bool? invoiceRequired,
    bool? invoiceIssued,
    bool? invoiceWaived,
    bool? reimbursed,
    bool? isDeleted,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    bool clearSubcategory = false,
    bool clearRecurringId = false,
  }) =>
      TransactionEntity(
        id: id,
        userId: userId,
        type: type ?? this.type,
        amountCents: amountCents ?? this.amountCents,
        currency: currency ?? this.currency,
        categoryId: categoryId ?? this.categoryId,
        subcategory:
            clearSubcategory ? null : (subcategory ?? this.subcategory),
        merchant: merchant ?? this.merchant,
        description: description ?? this.description,
        transactionTime: transactionTime ?? this.transactionTime,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        sourceType: sourceType ?? this.sourceType,
        confidence: confidence ?? this.confidence,
        status: status ?? this.status,
        isRecurring: isRecurring,
        recurringTransactionId:
            clearRecurringId ? null : recurringTransactionId,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        note: note ?? this.note,
        invoiceRequired: invoiceRequired ?? this.invoiceRequired,
        invoiceIssued: invoiceIssued ?? this.invoiceIssued,
        invoiceWaived: invoiceWaived ?? this.invoiceWaived,
        reimbursed: reimbursed ?? this.reimbursed,
        isDeleted: isDeleted ?? this.isDeleted,
        deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      );
}

/// 保存在 App 私有目录中的发票附件，可关联一笔账单，也可暂不关联。
class InvoiceDocument {
  const InvoiceDocument({
    required this.id,
    required this.storedPath,
    required this.originalName,
    required this.fileType,
    required this.createdAt,
    this.transactionId,
  });

  final String id;
  final String? transactionId;
  final String storedPath;
  final String originalName;

  /// `image` 或 `pdf`。
  final String fileType;
  final DateTime createdAt;

  bool get isPdf => fileType == 'pdf';

  InvoiceDocument copyWith({String? transactionId, bool unlink = false}) =>
      InvoiceDocument(
        id: id,
        transactionId: unlink ? null : (transactionId ?? this.transactionId),
        storedPath: storedPath,
        originalName: originalName,
        fileType: fileType,
        createdAt: createdAt,
      );
}

/// 账单的原始来源记录（语音转写 / OCR 结果 / AI 解析结果）。
/// 用户修改账单不会动这里 —— 保证可追溯。
class SourceRecord {
  const SourceRecord({
    required this.id,
    required this.transactionId,
    required this.sourceType,
    required this.createdAt,
    this.rawText,
    this.imageReference,
    this.ocrResult,
    this.aiParseResult,
  });

  final String id;
  final String transactionId;
  final SourceType sourceType;
  final String? rawText;
  final String? imageReference;

  /// OCR 结构化结果（JSON）。
  final String? ocrResult;

  /// AI 结构化解析结果（JSON）。
  final String? aiParseResult;
  final DateTime createdAt;

  String get displayLabel => sourceType.label;
}
