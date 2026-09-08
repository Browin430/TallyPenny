import '../../domain/services/ai_services.dart';
import '../../domain/services/financial_advisor_service.dart';
import 'rule_based_transaction_parser.dart';

/// Mock 语音识别：轮换返回内置示例句子。
/// TODO(phase-3): 替换为 Apple Speech / 讯飞 / Google STT 真实实现。
class MockSpeechRecognitionService implements SpeechRecognitionService {
  static const _samples = [
    '今天早上九点坐地铁花了3块钱。',
    '中午吃饭花了28块5。',
    '刚刚买可乐花了3块。',
    '昨天晚上淘宝买衣服花了399。',
    '下午打车去公司花了35块。',
    '今天工资到账15000。',
    '在全家买了瓶水花了2块。',
    '下午三点半在瑞幸买了拿铁花了16块。',
  ];

  int _index = 0;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<String> recognizeOnce() async {
    final text = _samples[_index % _samples.length];
    _index++;
    return text;
  }
}

/// Mock OCR：返回内置的支付宝 / 微信示例账单文本。
/// TODO(phase-4): 替换为端侧 OCR（ML Kit / Vision），接口签名保持不变。
class MockOCRService implements OCRService {
  MockOCRService({Map<String, OcrResult>? presets})
      : _presets = presets ?? _defaultPresets();

  final Map<String, OcrResult> _presets;

  static Map<String, OcrResult> _defaultPresets() => {
        'alipay_demo': OcrResult(
          rawText: '支付宝\n交易成功\nXX烟酒商行\n-3.00\n2026-08-28 09:03:22\n交易说明：可乐',
          confidence: 0.95,
          platform: 'alipay',
          merchant: 'XX烟酒商行',
          amountCents: 300,
          isIncome: false,
          paidAt: DateTime(2026, 8, 28, 9, 3),
          orderNo: '2026082822001400001',
          paymentMethodRaw: '余额',
        ),
        'wechat_demo': OcrResult(
          rawText:
              '微信支付\n支付成功\n¥32.00\n麦当劳\n当前状态：已支付\n支付时间：2026-08-28 12:18\n支付方式：零钱',
          confidence: 0.93,
          platform: 'wechat',
          merchant: '麦当劳',
          amountCents: 3200,
          isIncome: false,
          paidAt: DateTime(2026, 8, 28, 12, 18),
          paymentMethodRaw: '零钱',
        ),
      };

  @override
  Future<OcrResult> recognize(String imageReference) async {
    final preset = _presets[imageReference];
    if (preset != null) return preset;
    // 未知的图片引用：返回空结果（业务层显示"无法识别"）。
    return OcrResult(
      rawText: '',
      confidence: 0,
      platform: null,
    );
  }
}

/// Mock AI 账单解析器：用规则引擎模拟 LLM 结构化输出。
/// TODO(phase-5): 替换为 LLM 严格结构化输出（JSON Schema / Function Calling）。
class MockAITransactionParser extends RuleBasedTransactionParser {
  MockAITransactionParser();
}

/// Mock 财务顾问：返回固定格式的分析框架与免责声明。
/// TODO(phase-9): 接入 LLM + 真实利率数据（禁止编造利率）。
class MockFinancialAdvisorService implements FinancialAdvisorService {
  @override
  Future<AdvisorAnswer> ask(String question, AdvisorSnapshot snapshot) async {
    final avgSave =
        snapshot.monthlyIncomeCents - snapshot.avgMonthlyExpenseCents;
    return AdvisorAnswer(
      summary:
          '根据你近 6 个月的财务数据，你平均每月可以结余约 ¥${(avgSave / 100).toStringAsFixed(0)}。',
      analysisPoints: [
        '月收入 ¥${snapshot.monthlyIncomeCents ~/ 100}，平均月支出 ¥${snapshot.avgMonthlyExpenseCents ~/ 100}。',
        '固定支出 ¥${snapshot.fixedExpenseCents ~/ 100}/月。',
        'AI 财务顾问将在 Phase 9 接入大语言模型，提供完整的多方案分析。',
      ],
      verdictLabel: null,
      disclaimer: '以上为个人财务规划参考，不构成专业投资、贷款、税务或法律建议。',
    );
  }
}

/// 统一出口：当前阶段默认的 AI 服务组合。
class MockAiServices {
  const MockAiServices._();

  static SpeechRecognitionService speech() => MockSpeechRecognitionService();
  static OCRService ocr() => MockOCRService();
  static AITransactionParser parser() => MockAITransactionParser();
  static FinancialAdvisorService advisor() => MockFinancialAdvisorService();
}
