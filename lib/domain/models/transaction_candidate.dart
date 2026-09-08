import 'enums.dart';

/// 统一记账流水线的输入候选。
/// 语音 / 截图 / 手动 / 导入 / 周期，全部归一化成这个结构后再进入 Pipeline。
class TransactionCandidate {
  const TransactionCandidate({
    required this.sourceType,
    required this.confidence,
    this.type,
    this.amountCents,
    this.currency = 'CNY',
    this.categoryId,
    this.subcategory,
    this.merchant,
    this.description,
    this.transactionTime,
    this.timeConfident = true,
    this.paymentMethod,
    this.note,
    this.invoiceRequired = false,
    this.invoiceIssued = false,
    this.invoiceWaived = false,
    this.reimbursed = false,
    this.parseWarnings = const [],
    this.sourceRecords = const [],
  });

  final SourceType sourceType;

  /// AI / OCR 综合置信度 0~1。手动录入为 1.0。
  final double confidence;
  final TransactionType? type;
  final int? amountCents;
  final String currency;
  final String? categoryId;
  final String? subcategory;
  final String? merchant;
  final String? description;

  /// 时间不明确时 UI 需要知道（timeConfident=false → 展示"时间待确认"）。
  final DateTime? transactionTime;
  final bool timeConfident;
  final PaymentMethod? paymentMethod;
  final String? note;
  final bool invoiceRequired;
  final bool invoiceIssued;
  final bool invoiceWaived;
  final bool reimbursed;

  /// 解析过程中的警告（如"未识别到金额""识别到多个金额"）。
  final List<String> parseWarnings;

  /// 原始来源记录（必须与账单一同持久化）。
  final List<SourceRecordDraft> sourceRecords;

  bool get hasAmount => amountCents != null && amountCents! > 0;
}

/// 来源记录草稿（尚未分配 transactionId）。
class SourceRecordDraft {
  const SourceRecordDraft({
    required this.sourceType,
    this.rawText,
    this.imageReference,
    this.ocrResultJson,
    this.aiParseResultJson,
  });

  final SourceType sourceType;
  final String? rawText;
  final String? imageReference;
  final String? ocrResultJson;
  final String? aiParseResultJson;
}
