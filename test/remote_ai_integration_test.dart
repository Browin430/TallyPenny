import 'package:flutter_test/flutter_test.dart';
import 'package:flowmoney/data/services/remote_ai_services.dart';
import 'package:flowmoney/domain/models/enums.dart';

/// 端到端集成测试：需要本地 AI 后端运行（python server/main.py）。
/// 服务器不可达时自动 skip（降级为规则引擎），不影响常规 `flutter test`。
void main() {
  // 注意：不要 ensureInitialized() —— flutter_test 的 binding 会拦截真实 HTTP。
  // 本测试只验证纯 Dart 逻辑（http 包直连本地后端）。

  const baseUrl = 'http://127.0.0.1:8765';

  test('RemoteAiTransactionParser 走千问后端解析中文账单', () async {
    final parser = RemoteAiServices.parser(baseUrl: baseUrl);

    final candidate = await parser.parseFromText(
      '昨天晚上在海底捞吃火锅花了328块钱',
      referenceTime: DateTime(2026, 8, 28, 20, 0),
    );

    // 远端命中：aiParseResultJson 应含 qwen_remote_v1（降级时为 rule_based_v1）。
    final record = candidate.sourceRecords.first;
    final engineJson = record.aiParseResultJson ?? '';
    if (!engineJson.contains('qwen_remote_v1')) {
      markTestSkipped('AI 后端不可达，远端解析被跳过（降级为规则引擎）');
    }

    expect(candidate.type, TransactionType.expense);
    expect(candidate.amountCents, 32800);
    expect(candidate.categoryId, 'food');
    expect(candidate.hasAmount, isTrue);
  });

  test('未配置 baseUrl → 返回本地 Mock（规则引擎）', () async {
    final parser = RemoteAiServices.parser(baseUrl: '');
    final candidate =
        await parser.parseFromText('花了28块5', referenceTime: DateTime.now());
    expect(candidate.sourceRecords.first.aiParseResultJson ?? '',
        contains('rule_based_v1'));
  });
}
