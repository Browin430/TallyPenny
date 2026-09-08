import 'dart:convert';
import 'dart:io' show File, HttpClient;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../domain/models/enums.dart';
import '../../domain/models/transaction_candidate.dart';
import '../../domain/services/ai_services.dart';
import '../../domain/services/financial_advisor_service.dart';
import 'mock_ai_services.dart';
import 'rule_based_transaction_parser.dart';

/// 远程 AI 服务（千问后端）：远端优先，超时 / 断网 / 出错自动降级本地实现。
///
/// 后端契约见 server/README.md —— candidate JSON 与 [TransactionCandidate] 字段对齐。
class RemoteAiServices {
  const RemoteAiServices._();

  /// 默认后端地址；留空 = 未配置（全部走本地 Mock）。
  /// 自部署后端后在"我的→AI 服务设置"填写地址即可启用真实 AI。
  static const defaultBaseUrl = '';

  /// 构建时注入，不将公网访问令牌提交进源码。
  static const apiToken = String.fromEnvironment('FM_API_TOKEN');

  /// 历史遗留地址列表：命中时自动迁移到 [defaultBaseUrl]，自部署用户可按需维护。
  static const legacyBaseUrls = <String>{};

  /// SettingsRepository 存储键。
  static const prefKey = 'ai_server_base_url';

  /// baseUrl 为空（未配置）→ 全部返回本地 Mock。
  static SpeechRecognitionService speech({String? baseUrl}) =>
      MockAiServices.speech(); // TODO(phase-3): 真实 ASR（录音 + /api/parse/audio）。

  static OCRService ocr({String? baseUrl}) {
    if (baseUrl == null || baseUrl.trim().isEmpty) return MockAiServices.ocr();
    return RemoteOCRService(baseUrl: baseUrl);
  }

  static AITransactionParser parser({String? baseUrl}) {
    if (baseUrl == null || baseUrl.trim().isEmpty) {
      return MockAiServices.parser();
    }
    return RemoteAiTransactionParser(baseUrl: baseUrl);
  }

  static FinancialAdvisorService advisor({String? baseUrl}) {
    if (baseUrl == null || baseUrl.trim().isEmpty) {
      return MockAiServices.advisor();
    }
    return RemoteFinancialAdvisorService(baseUrl: baseUrl);
  }

  /// 语音入口（录音文件 → ASR + 解析一步完成）。未配置时返回 null（页面走演示）。
  static RemoteVoiceEntryService? voiceEntry({String? baseUrl}) {
    if (baseUrl == null || baseUrl.trim().isEmpty) return null;
    return RemoteVoiceEntryService(baseUrl: baseUrl);
  }

  /// 截图入口（图片 → OCR + 多笔解析一步完成）。未配置时返回 null（页面走演示）。
  static RemoteScreenshotEntryService? screenshotEntry({String? baseUrl}) {
    if (baseUrl == null || baseUrl.trim().isEmpty) return null;
    return RemoteScreenshotEntryService(baseUrl: baseUrl);
  }

  /// 可退出 App 的后台识别任务入口。
  static RemoteBackgroundJobService? backgroundJobs({String? baseUrl}) {
    if (baseUrl == null || baseUrl.trim().isEmpty) return null;
    return RemoteBackgroundJobService(baseUrl: baseUrl);
  }

  /// 规整用户输入的地址："192.168.1.5:8765" → "http://192.168.1.5:8765"。
  static String normalizeBaseUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return url;
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    return url;
  }

  static bool isLegacyBaseUrl(String raw) =>
      legacyBaseUrls.contains(normalizeBaseUrl(raw));
}

/// 千问后端统一的请求工具。
class _ApiClient {
  _ApiClient(this.baseUrl);

  final String baseUrl;

  static const _parseTimeout = Duration(seconds: 25);
  static const _mediaTimeout = Duration(seconds: 40);

  /// 长截图分割识别（多片 OCR + 解析 + 重叠合并）耗时随图片高度增长，
  /// 实测 1.3 万像素长图约 90 秒 —— 远大于普通媒体上传，单独放宽。
  static const _screenshotTimeout = Duration(seconds: 180);

  /// 后端只可能是局域网 / 本机地址：强制直连，绕过系统代理
  /// （Windows 下系统代理会拦截 127.0.0.1 返回 400）。
  static final http.Client _client = _createClient();

  static http.Client _createClient() {
    // Web 由浏览器决定代理；native 一律直连。
    if (kIsWeb) return http.Client();
    final inner = HttpClient()..findProxy = (_) => 'DIRECT';
    return IOClient(inner);
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final rawBody = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (kDebugMode) {
        debugPrint('[RemoteAI] HTTP ${response.statusCode} $rawBody');
      }
      String detail;
      try {
        final body = jsonDecode(rawBody);
        final raw = body is Map<String, dynamic> ? body['detail'] : null;
        detail = raw is String
            ? raw
            : (raw == null ? 'HTTP ${response.statusCode}' : raw.toString());
      } catch (_) {
        detail = 'HTTP ${response.statusCode}';
      }
      throw RemoteException(detail);
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    try {
      final request = http.Request('POST', Uri.parse('$baseUrl$path'))
        ..headers['Content-Type'] = 'application/json'
        ..headers['X-API-Key'] = RemoteAiServices.apiToken
        ..bodyBytes = utf8.encode(jsonEncode(body));
      final streamed =
          await _client.send(request).timeout(timeout ?? _parseTimeout);
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    } on RemoteException {
      rethrow;
    } catch (_) {
      // TimeoutException / SocketException / http.ClientException → 统一网络错误。
      throw RemoteException('无法连接 AI 后端（$baseUrl）');
    }
  }

  Future<Map<String, dynamic>> postFile(
    String path,
    String filePath, {
    Map<String, String>? fields,
    Duration? timeout,
  }) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
        ..headers['X-API-Key'] = RemoteAiServices.apiToken
        ..fields.addAll(fields ?? {})
        ..files.add(await http.MultipartFile.fromPath('file', filePath));
      final streamed =
          await _client.send(request).timeout(timeout ?? _mediaTimeout);
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    } on RemoteException {
      rethrow;
    } catch (_) {
      throw RemoteException('无法连接 AI 后端（$baseUrl）');
    }
  }

  Future<Map<String, dynamic>> postFiles(
    String path,
    List<String> filePaths, {
    Map<String, String>? fields,
  }) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
        ..headers['X-API-Key'] = RemoteAiServices.apiToken
        ..fields.addAll(fields ?? {});
      for (final filePath in filePaths) {
        request.files.add(
          await http.MultipartFile.fromPath('files', filePath),
        );
      }
      final streamed = await _client.send(request).timeout(_mediaTimeout);
      return _decode(await http.Response.fromStream(streamed));
    } on RemoteException {
      rethrow;
    } catch (_) {
      throw RemoteException('无法连接 AI 后端（$baseUrl）');
    }
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl$path'),
        headers: {'X-API-Key': RemoteAiServices.apiToken},
      ).timeout(timeout);
      return _decode(response);
    } on RemoteException {
      rethrow;
    } catch (_) {
      throw RemoteException('无法连接 AI 后端（$baseUrl）');
    }
  }

  Future<void> delete(String path) async {
    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl$path'),
        headers: {'X-API-Key': RemoteAiServices.apiToken},
      ).timeout(const Duration(seconds: 10));
      _decode(response);
    } on RemoteException {
      rethrow;
    } catch (_) {
      throw RemoteException('无法连接 AI 后端（$baseUrl）');
    }
  }
}

class RemoteException implements Exception {
  RemoteException(this.message);
  final String message;

  @override
  String toString() => message;
}

class BackgroundJobSubmission {
  const BackgroundJobSubmission({
    required this.jobId,
    required this.kind,
    required this.estimateSeconds,
    required this.fileCount,
  });

  final String jobId;
  final String kind;
  final int estimateSeconds;
  final int fileCount;
}

class BackgroundJobStatus {
  const BackgroundJobStatus({
    required this.jobId,
    required this.kind,
    required this.status,
    required this.estimateSeconds,
    required this.progress,
    this.result,
    this.error,
  });

  final String jobId;
  final String kind;
  final String status;
  final int estimateSeconds;
  final int progress;
  final Map<String, dynamic>? result;
  final String? error;

  bool get isFinished => status == 'completed' || status == 'failed';
}

class RemoteBackgroundJobService {
  RemoteBackgroundJobService({required String baseUrl})
      : _api = _ApiClient(baseUrl);

  final _ApiClient _api;

  Future<BackgroundJobSubmission> submitScreenshots(
    List<String> imagePaths, {
    List<Map<String, dynamic>>? merchantRules,
  }) async {
    final data = await _api.postFiles(
      '/api/jobs/screenshots',
      imagePaths,
      fields: {
        'referenceTime': DateTime.now().toIso8601String(),
        if (merchantRules != null && merchantRules.isNotEmpty)
          'merchantRules': jsonEncode(merchantRules),
      },
    );
    return _submissionFromJson(data);
  }

  Future<BackgroundJobSubmission> submitAudio(
    String audioPath, {
    required int durationSeconds,
    required List<Map<String, dynamic>> recentTransactions,
    List<Map<String, dynamic>>? merchantRules,
  }) async {
    final data = await _api.postFile(
      '/api/jobs/audio',
      audioPath,
      fields: {
        'durationSeconds': durationSeconds.toString(),
        'recentTransactions': jsonEncode(recentTransactions),
        if (merchantRules != null && merchantRules.isNotEmpty)
          'merchantRules': jsonEncode(merchantRules),
      },
    );
    return _submissionFromJson(data);
  }

  Future<BackgroundJobSubmission> submitStatements(
    List<String> filePaths,
  ) async {
    final data = await _api.postFiles('/api/jobs/statements', filePaths);
    return _submissionFromJson(data);
  }

  Future<BackgroundJobStatus> getJob(String jobId) async {
    final data = await _api.getJson('/api/jobs/$jobId');
    return BackgroundJobStatus(
      jobId: (data['jobId'] as String?) ?? jobId,
      kind: (data['kind'] as String?) ?? '',
      status: (data['status'] as String?) ?? 'failed',
      estimateSeconds: (data['estimateSeconds'] as num?)?.toInt() ?? 0,
      progress: (data['progress'] as num?)?.toInt() ?? 0,
      result: data['result'] as Map<String, dynamic>?,
      error: data['error'] as String?,
    );
  }

  Future<void> deleteJob(String jobId) => _api.delete('/api/jobs/$jobId');

  BackgroundJobSubmission _submissionFromJson(Map<String, dynamic> data) {
    final jobId = (data['jobId'] as String?) ?? '';
    if (jobId.isEmpty) throw RemoteException('服务器没有返回任务编号');
    return BackgroundJobSubmission(
      jobId: jobId,
      kind: (data['kind'] as String?) ?? '',
      estimateSeconds: (data['estimateSeconds'] as num?)?.toInt() ?? 30,
      fileCount: (data['fileCount'] as num?)?.toInt() ?? 1,
    );
  }
}

/// 服务器 candidate JSON → TransactionCandidate（各远程入口共用）。
TransactionCandidate candidateFromJson(
  Map<String, dynamic> json, {
  required SourceType fallbackSourceType,
  required String rawText,
  required String engine,
  OcrResult? ocr,
}) {
  final serverSourceType = switch (json['sourceType'] as String?) {
    'voice' => SourceType.voice,
    'screenshot' => SourceType.screenshot,
    'import' => SourceType.imported,
    _ => fallbackSourceType,
  };

  DateTime? time;
  final rawTime = json['transactionTime'] as String?;
  if (rawTime != null) time = DateTime.tryParse(rawTime);

  return TransactionCandidate(
    sourceType: serverSourceType,
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0.85,
    type: json['type'] == 'income'
        ? TransactionType.income
        : TransactionType.expense,
    amountCents: (json['amountCents'] as num?)?.toInt(),
    currency: (json['currency'] as String?) ?? 'CNY',
    categoryId: json['categoryId'] as String?,
    subcategory: json['subcategory'] as String?,
    merchant: json['merchant'] as String?,
    description: json['description'] as String?,
    transactionTime: time,
    timeConfident: json['timeConfident'] as bool? ?? false,
    paymentMethod: paymentMethodFromJson(json['paymentMethod'] as String?),
    note: json['note'] as String?,
    parseWarnings: (json['parseWarnings'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList(),
    sourceRecords: [
      SourceRecordDraft(
        sourceType: serverSourceType,
        rawText: rawText,
        ocrResultJson: ocr == null
            ? null
            : jsonEncode({
                'platform': ocr.platform,
                'merchant': ocr.merchant,
                'amountCents': ocr.amountCents,
                'orderNo': ocr.orderNo,
              }),
        aiParseResultJson: jsonEncode({'engine': engine, ...json}),
      ),
    ],
  );
}

/// 服务器 paymentMethod 字符串 → 枚举（bank_card / credit_card 归并银行卡）。
PaymentMethod? paymentMethodFromJson(String? value) {
  if (value == null) return null;
  return switch (value) {
    'alipay' => PaymentMethod.alipay,
    'wechat' => PaymentMethod.wechat,
    'bank_card' || 'credit_card' => PaymentMethod.bankCard,
    'cash' => PaymentMethod.cash,
    _ => null, // 未知支付方式不硬塞 "other"，交给用户确认时选择。
  };
}

// =====================================================================
// AI 账单解析器：远端千问优先，失败降级端侧规则引擎
// =====================================================================

class RemoteAiTransactionParser extends RuleBasedTransactionParser {
  RemoteAiTransactionParser({required String baseUrl})
      : _api = _ApiClient(baseUrl);

  final _ApiClient _api;

  @override
  Future<TransactionCandidate> parseFromText(
    String text, {
    DateTime? referenceTime,
    SourceType sourceType = SourceType.voice,
    List<Map<String, dynamic>>? merchantRules,
  }) async {
    try {
      final data = await _api.postJson('/api/parse/text', {
        'text': text,
        if (referenceTime != null)
          'referenceTime': referenceTime.toIso8601String(),
        if (merchantRules != null && merchantRules.isNotEmpty)
          'merchantRules': merchantRules,
      });
      return candidateFromJson(
        data['candidate'] as Map<String, dynamic>,
        fallbackSourceType: sourceType,
        rawText: text,
        engine: 'qwen_remote_v1',
      );
    } on RemoteException catch (e) {
      // 远端不可用 → 端侧规则引擎兜底（离线仍可记账）。
      if (kDebugMode) debugPrint('[RemoteParser] 降级规则引擎: text — ${e.message}');
      return super.parseFromText(text,
          referenceTime: referenceTime, sourceType: sourceType);
    }
  }

  @override
  Future<TransactionCandidate> parseFromOcr(
    OcrResult ocr, {
    List<Map<String, dynamic>>? merchantRules,
  }) async {
    try {
      final data = await _api.postJson('/api/parse/text', {
        'text': ocr.rawText,
        if (merchantRules != null && merchantRules.isNotEmpty)
          'merchantRules': merchantRules,
      });
      return candidateFromJson(
        data['candidate'] as Map<String, dynamic>,
        fallbackSourceType: SourceType.screenshot,
        rawText: ocr.rawText,
        engine: 'qwen_remote_v1',
        ocr: ocr,
      );
    } on RemoteException catch (e) {
      if (kDebugMode) debugPrint('[RemoteParser] 降级规则引擎: ocr — ${e.message}');
      return super.parseFromOcr(ocr);
    }
  }
}

// =====================================================================
// OCR：远端 qwen-vl（截图账单识别），失败降级 Mock
// =====================================================================

class RemoteOCRService implements OCRService {
  RemoteOCRService({required String baseUrl}) : _api = _ApiClient(baseUrl);

  final _ApiClient _api;

  @override
  Future<OcrResult> recognize(String imageReference) async {
    // Web 无本地文件系统；且 Mock 的 preset 引用不是真实路径 → 都走 Mock。
    final isRealFile = !kIsWeb && !imageReference.startsWith('assets/');
    if (!isRealFile || !File(imageReference).existsSync()) {
      return MockAiServices.ocr().recognize(imageReference);
    }
    try {
      final data = await _api.postFile(
        '/api/parse/screenshot',
        imageReference,
        fields: {'referenceTime': DateTime.now().toIso8601String()},
        timeout: _ApiClient._screenshotTimeout,
      );
      final ocrText = (data['ocrText'] as String?) ?? '';
      if (ocrText.isEmpty) {
        return const OcrResult(rawText: '', confidence: 0);
      }
      return OcrResult(
        rawText: ocrText,
        confidence: 0.9,
        platform: null,
      );
    } on RemoteException {
      if (kDebugMode) debugPrint('[RemoteOCR] 降级 Mock OCR');
      return MockAiServices.ocr().recognize(imageReference);
    }
  }
}

// =====================================================================
// 语音入口：录音文件 → /api/parse/audio（ASR + 解析一次完成）
// =====================================================================

class VoiceEntryResult {
  const VoiceEntryResult({required this.transcript, required this.candidate});

  final String transcript;
  final TransactionCandidate candidate;
}

/// 语音修改建议：目标账单 + 待更新字段（仅包含用户明确提到的字段）。
class VoiceUpdateSuggestion {
  const VoiceUpdateSuggestion({
    required this.targetId,
    required this.matchSummary,
    required this.fields,
    required this.parseWarnings,
  });

  final String targetId;

  /// 后端匹配到的原账单摘要（如"瑞幸咖啡 ¥15.90 8月27日"）。
  final String matchSummary;

  /// 待更新字段（camelCase，键为 TransactionEntity 字段名）。
  final Map<String, dynamic> fields;

  final List<String> parseWarnings;
}

/// 语音指令结果：新增（可多笔）/ 修改已有账单 / 无法理解。
class VoiceCommandResult {
  const VoiceCommandResult({
    required this.transcript,
    required this.intent,
    this.candidates = const [],
    this.update,
    this.reason,
  });

  final String transcript;

  /// "create" | "update" | "unknown"。
  final String intent;

  /// intent == create 时的全部新账单（一句话多笔 → 多个元素）。
  final List<TransactionCandidate> candidates;

  /// intent == update 时的修改建议。
  final VoiceUpdateSuggestion? update;

  /// intent == unknown 时给用户的解释。
  final String? reason;
}

class RemoteVoiceEntryService {
  RemoteVoiceEntryService({required String baseUrl})
      : _api = _ApiClient(baseUrl);

  final _ApiClient _api;

  /// [audioPath] 为录音文件（m4a/wav/mp3…）。
  Future<VoiceEntryResult> recognize(
    String audioPath, {
    List<Map<String, dynamic>>? merchantRules,
  }) async {
    final data = await _api.postFile(
      '/api/parse/audio',
      audioPath,
      fields: {
        'referenceTime': DateTime.now().toIso8601String(),
        if (merchantRules != null && merchantRules.isNotEmpty)
          'merchantRules': jsonEncode(merchantRules),
      },
    );
    final transcript = ((data['transcript'] as String?) ?? '').trim();
    final candidateJson = data['candidate'] as Map<String, dynamic>?;
    if (transcript.isEmpty || candidateJson == null) {
      throw RemoteException('没能听清，请再试一次');
    }
    final candidate = candidateFromJson(
      candidateJson,
      fallbackSourceType: SourceType.voice,
      rawText: transcript,
      engine: 'qwen_remote_v1',
    );
    return VoiceEntryResult(transcript: transcript, candidate: candidate);
  }

  /// 语音指令：结合最近账单判断意图 —— 新增多笔或修改已有账单。
  /// [recentTransactions] 为最近账单的 JSON 映射列表（含 id，供修改定位）。
  Future<VoiceCommandResult> command(
    String audioPath,
    List<Map<String, dynamic>> recentTransactions, {
    List<Map<String, dynamic>>? merchantRules,
  }) async {
    final data = await _api.postFile(
      '/api/voice_command',
      audioPath,
      fields: {
        'recentTransactions': jsonEncode(recentTransactions),
        if (merchantRules != null && merchantRules.isNotEmpty)
          'merchantRules': jsonEncode(merchantRules),
      },
    );
    final transcript = ((data['transcript'] as String?) ?? '').trim();
    if (transcript.isEmpty) throw RemoteException('没能听清，请再试一次');

    final candidates = ((data['records'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((json) => candidateFromJson(
              json,
              fallbackSourceType: SourceType.voice,
              rawText: transcript,
              engine: 'qwen_command_v1',
            ))
        .toList();

    VoiceUpdateSuggestion? update;
    final updateJson = data['update'];
    if (updateJson is Map<String, dynamic>) {
      update = VoiceUpdateSuggestion(
        targetId: (updateJson['targetId'] as String?) ?? '',
        matchSummary: (updateJson['matchSummary'] as String?) ?? '',
        fields: (updateJson['fields'] as Map<String, dynamic>?) ?? const {},
        parseWarnings:
            (updateJson['parseWarnings'] as List<dynamic>? ?? const [])
                .map((e) => e.toString())
                .toList(),
      );
    }

    return VoiceCommandResult(
      transcript: transcript,
      intent: (data['intent'] as String?) ?? 'unknown',
      candidates: candidates,
      update: update,
      reason: (data['reason'] as String?),
    );
  }
}

// =====================================================================
// 截图入口：图片 → /api/parse/screenshot（OCR + 多笔解析一次完成）
// =====================================================================

class ScreenshotParseResult {
  const ScreenshotParseResult(
      {required this.ocrText, required this.candidates});

  final String ocrText;

  /// 截图中的全部账单（账单列表截图可含多笔）。
  final List<TransactionCandidate> candidates;
}

class RemoteScreenshotEntryService {
  RemoteScreenshotEntryService({required String baseUrl})
      : _api = _ApiClient(baseUrl);

  final _ApiClient _api;

  Future<ScreenshotParseResult> parseFile(
    String imagePath, {
    List<Map<String, dynamic>>? merchantRules,
  }) async {
    final data = await _api.postFile(
      '/api/parse/screenshot',
      imagePath,
      fields: {
        'referenceTime': DateTime.now().toIso8601String(),
        if (merchantRules != null && merchantRules.isNotEmpty)
          'merchantRules': jsonEncode(merchantRules),
      },
      timeout: _ApiClient._screenshotTimeout,
    );
    final ocrText = ((data['ocrText'] as String?) ?? '').trim();
    if (ocrText.isEmpty) throw RemoteException('未能识别图中账单');

    final rawList = data['candidates'] as List<dynamic>?;
    final single = data['candidate'] as Map<String, dynamic>?;
    final items = rawList ?? (single != null ? [single] : []);
    if (items.isEmpty) throw RemoteException('未能从截图中解析出账单记录');

    final candidates = items
        .whereType<Map<String, dynamic>>()
        .map((json) => candidateFromJson(
              json,
              fallbackSourceType: SourceType.screenshot,
              rawText: ocrText,
              engine: 'qwen_remote_v1',
            ))
        .toList();
    if (candidates.isEmpty) throw RemoteException('未能从截图中解析出账单记录');
    return ScreenshotParseResult(ocrText: ocrText, candidates: candidates);
  }
}

// =====================================================================
// 财务顾问：远端千问优先，失败降级 Mock
// =====================================================================

class RemoteFinancialAdvisorService implements FinancialAdvisorService {
  RemoteFinancialAdvisorService({required String baseUrl})
      : _api = _ApiClient(baseUrl);

  final _ApiClient _api;

  @override
  Future<AdvisorAnswer> ask(String question, AdvisorSnapshot snapshot) async {
    try {
      final data = await _api.postJson(
        '/api/advisor',
        {
          'question': question,
          'snapshot': {
            'monthlyIncomeCents': snapshot.monthlyIncomeCents,
            'avgMonthlyExpenseCents': snapshot.avgMonthlyExpenseCents,
            'fixedExpenseCents': snapshot.fixedExpenseCents,
            'savingsCents': snapshot.savingsCents,
            'debtCents': snapshot.debtCents,
            'monthlyBudgetCents': snapshot.monthlyBudgetCents,
            'savingsGoalCents': snapshot.savingsGoalCents,
            'last6MonthsNetCents': snapshot.last6MonthsNetCents,
          },
        },
        timeout: const Duration(seconds: 40),
      );
      final answer = ((data['answer'] as String?) ?? '').trim();
      if (answer.isEmpty) throw RemoteException('AI 顾问返回为空');
      return _splitAnswer(
        answer,
        (data['disclaimer'] as String?) ?? '以上为一般性参考，不构成投资建议。',
      );
    } on RemoteException {
      if (kDebugMode) debugPrint('[RemoteAdvisor] 降级 Mock 顾问');
      return MockAiServices.advisor().ask(question, snapshot);
    }
  }

  /// 服务器自由文本 → summary + analysisPoints（首行为 summary，其余为要点）。
  AdvisorAnswer _splitAnswer(String answer, String disclaimer) {
    final lines = answer
        .split('\n')
        .map((line) => line
            .replaceFirst(RegExp(r'^\s*[-*•]\s*'), '')
            .replaceFirst(RegExp(r'^\s*\d+[.、]\s*'), '')
            .trim())
        .where((line) => line.isNotEmpty && !line.contains('不构成'))
        .toList();
    if (lines.isEmpty) {
      return AdvisorAnswer(
        summary: answer,
        analysisPoints: const [],
        disclaimer: disclaimer,
      );
    }
    return AdvisorAnswer(
      summary: lines.first,
      analysisPoints: lines.skip(1).toList(),
      disclaimer: disclaimer,
    );
  }
}
