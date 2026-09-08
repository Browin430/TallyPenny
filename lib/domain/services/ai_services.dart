import '../models/transaction_candidate.dart';

/// OCR 结构化结果（由 OCRService 产出，交给 AITransactionParser 做语义分析）。
/// OCR 与 AI 职责分离：OCR 只出文字与版面字段，不理解"账单"。
class OcrResult {
  const OcrResult({
    required this.rawText,
    required this.confidence,
    this.platform,
    this.merchant,
    this.amountCents,
    this.isIncome,
    this.paidAt,
    this.orderNo,
    this.paymentMethodRaw,
  });

  /// 全部识别文本（原文留存，写入 transaction_sources.ocr_result）。
  final String rawText;
  final double confidence;

  /// 支付平台线索：alipay / wechat / bank / ecommerce / null。
  final String? platform;
  final String? merchant;
  final int? amountCents;
  final bool? isIncome;
  final DateTime? paidAt;
  final String? orderNo;
  final String? paymentMethodRaw;
}

// TODO(phase-3): SpeechRecognitionService 演进为流式接口（onPartial/onFinal）。
/// 语音转文字服务抽象。可替换：Apple Speech / 讯飞 / Google STT / 本地模型。
abstract class SpeechRecognitionService {
  Future<bool> requestPermission();

  /// 一次性识别。Mock 实现返回示例句子。
  Future<String> recognizeOnce();
}

// TODO(phase-4): 替换为端侧 OCR（ML Kit / Vision / PaddleOCR）。
/// OCR 服务抽象。
abstract class OCRService {
  /// [imageReference] 为本地图片路径。Mock 实现返回内置示例账单。
  Future<OcrResult> recognize(String imageReference);
}

// TODO(phase-5): 替换为 LLM 严格结构化输出（JSON Schema / Function Calling）。
/// AI 账单解析器：文本或 OCR 结果 → 结构化候选。禁止直接解析自然语言字符串入业务。
abstract class AITransactionParser {
  Future<TransactionCandidate> parseFromText(String text,
      {DateTime? referenceTime});

  Future<TransactionCandidate> parseFromOcr(OcrResult ocr);
}
