import 'dart:convert';

import '../data/services/remote_ai_services.dart';
import '../domain/models/enums.dart';
import '../domain/models/transaction_candidate.dart';
import '../domain/pipeline/transaction_pipeline.dart';
import '../domain/repositories/settings_repository.dart';
import '../domain/repositories/transaction_repository.dart';
import 'refund_reconciliation_service.dart';

class PendingAiJob {
  const PendingAiJob({
    required this.id,
    required this.kind,
    required this.estimateSeconds,
    required this.createdAt,
    this.nextResultIndex = 0,
  });

  final String id;
  final String kind;
  final int estimateSeconds;
  final DateTime createdAt;
  final int nextResultIndex;

  PendingAiJob copyWith({int? nextResultIndex}) => PendingAiJob(
        id: id,
        kind: kind,
        estimateSeconds: estimateSeconds,
        createdAt: createdAt,
        nextResultIndex: nextResultIndex ?? this.nextResultIndex,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'estimateSeconds': estimateSeconds,
        'createdAt': createdAt.toIso8601String(),
        'nextResultIndex': nextResultIndex,
      };

  static PendingAiJob fromJson(Map<String, dynamic> json) => PendingAiJob(
        id: json['id'] as String,
        kind: (json['kind'] as String?) ?? '',
        estimateSeconds: (json['estimateSeconds'] as num?)?.toInt() ?? 30,
        createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
        nextResultIndex: (json['nextResultIndex'] as num?)?.toInt() ?? 0,
      );
}

class PendingAiJobSyncResult {
  const PendingAiJobSyncResult({
    required this.imported,
    required this.pending,
    required this.failed,
  });

  final int imported;
  final int pending;
  final int failed;
}

/// 本机只保存任务编号和消费进度；原始媒体与识别运算全部留在服务器。
class PendingAiJobService {
  PendingAiJobService({
    required SettingsRepository settingsRepository,
    required TransactionRepository transactionRepository,
    required TransactionPipeline pipeline,
  })  : _settings = settingsRepository,
        _transactions = transactionRepository,
        _pipeline = pipeline,
        _refunds = RefundReconciliationService(transactionRepository);

  static const _storageKey = 'pending_ai_jobs_v1';

  final SettingsRepository _settings;
  final TransactionRepository _transactions;
  final TransactionPipeline _pipeline;
  final RefundReconciliationService _refunds;

  Future<void> add(BackgroundJobSubmission submission) async {
    final jobs = await load();
    if (jobs.any((job) => job.id == submission.jobId)) return;
    jobs.add(PendingAiJob(
      id: submission.jobId,
      kind: submission.kind,
      estimateSeconds: submission.estimateSeconds,
      createdAt: DateTime.now(),
    ));
    await _save(jobs);
  }

  Future<List<PendingAiJob>> load() async {
    final raw = await _settings.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(PendingAiJob.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<PendingAiJobSyncResult> sync(RemoteBackgroundJobService remote) async {
    final working = await load();
    if (working.isEmpty) {
      return const PendingAiJobSyncResult(imported: 0, pending: 0, failed: 0);
    }

    var imported = 0;
    var failed = 0;
    var cursor = 0;
    while (cursor < working.length) {
      var job = working[cursor];
      BackgroundJobStatus status;
      try {
        status = await remote.getJob(job.id);
      } on RemoteException {
        cursor++;
        continue;
      }
      if (status.status == 'queued' || status.status == 'processing') {
        cursor++;
        continue;
      }
      if (status.status == 'failed' || status.result == null) {
        failed++;
        await _deleteRemoteQuietly(remote, job.id);
        working.removeAt(cursor);
        await _save(working);
        continue;
      }

      // 保持服务器结果下标稳定，确保闪退或被系统回收后能从精确位置续传。
      // 新后端会先移除同批退款对；旧任务则在逐笔入库时与本地账单冲销。
      final candidates = _candidatesFromResult(job.kind, status.result!);
      for (var index = job.nextResultIndex;
          index < candidates.length;
          index++) {
        final candidate = candidates[index];
        if (await _autoSave(candidate)) {
          imported++;
        }
        job = job.copyWith(nextResultIndex: index + 1);
        working[cursor] = job;
        // 每笔保存后记录消费进度，异常退出时最多只会重新检查当前这一笔。
        await _save(working);
        if (index % 8 == 7) {
          // 大批量长截图结果分段入库，让 Flutter 有机会响应生命周期与绘制。
          await Future<void>.delayed(Duration.zero);
        }
      }

      if (job.kind == 'audio') {
        final result = status.result!;
        if (result['intent'] == 'update' &&
            await _applyVoiceUpdate(result['update'])) {
          imported++;
        } else if (result['intent'] == 'unknown') {
          failed++;
        }
      }
      if (job.kind == 'screenshot' || job.kind == 'statement') {
        imported += await _refunds.reconcileExistingImportedPairs();
      }
      await _deleteRemoteQuietly(remote, job.id);
      working.removeAt(cursor);
      await _save(working);
    }

    return PendingAiJobSyncResult(
      imported: imported,
      pending: working.length,
      failed: failed,
    );
  }

  List<TransactionCandidate> _candidatesFromResult(
    String kind,
    Map<String, dynamic> result,
  ) {
    final rawText = switch (kind) {
      'audio' => (result['transcript'] as String?) ?? '',
      'statement' => (result['sourceSummary'] as String?) ?? '账单文件导入',
      _ => (result['ocrText'] as String?) ?? '',
    };
    final rawItems = kind == 'audio'
        ? (result['records'] as List<dynamic>? ?? const [])
        : (result['candidates'] as List<dynamic>? ?? const []);
    final candidates = <TransactionCandidate>[];
    var rawTextAttached = false;
    for (final item in rawItems) {
      if (item is! Map<String, dynamic>) continue;
      candidates.add(candidateFromJson(
        item,
        fallbackSourceType: switch (kind) {
          'audio' => SourceType.voice,
          'statement' => SourceType.imported,
          _ => SourceType.screenshot,
        },
        // 一份长截图 OCR 只存一次，避免数百笔账单重复保存整段原文导致
        // 内存与 SQLite 体积成倍增长。每笔的 AI 结构化 JSON 仍独立保留。
        rawText: rawTextAttached ? '' : rawText,
        engine: 'qwen_background_v1',
      ));
      rawTextAttached = true;
    }
    return candidates;
  }

  Future<bool> _autoSave(TransactionCandidate candidate) async {
    // 平台账单可能只导出退款而没有原订单；退款条目直接忽略，既不
    // 记收入，也不猜测删除其他账单。
    if (await _refunds.cancelAgainstExisting(candidate)) {
      return false;
    }
    final result = await _pipeline.process(candidate);
    switch (result) {
      case PipelineSaved():
        return true;
      case PipelineDuplicateSuspected(:final match):
        await _pipeline.keepBoth(match);
        return true;
      case PipelineNeedsReview():
        return false;
    }
  }

  Future<bool> _applyVoiceUpdate(dynamic rawUpdate) async {
    if (rawUpdate is! Map<String, dynamic>) return false;
    final targetId = rawUpdate['targetId'] as String?;
    final fields = rawUpdate['fields'] as Map<String, dynamic>?;
    if (targetId == null || fields == null || fields.isEmpty) return false;
    final target = await _transactions.getById(targetId);
    if (target == null) return false;
    var updated = target;
    for (final entry in fields.entries) {
      final value = entry.value;
      switch (entry.key) {
        case 'type':
          updated = updated.copyWith(
            type: value == 'income'
                ? TransactionType.income
                : TransactionType.expense,
          );
        case 'amountCents':
          if (value is num) {
            updated = updated.copyWith(amountCents: value.round());
          }
        case 'currency':
          if (value is String && value.isNotEmpty) {
            updated = updated.copyWith(currency: value);
          }
        case 'categoryId':
          if (value is String && value.isNotEmpty) {
            updated = updated.copyWith(categoryId: value);
          }
        case 'merchant':
          if (value is String && value.isNotEmpty) {
            updated = updated.copyWith(merchant: value);
          }
        case 'description':
          if (value is String && value.isNotEmpty) {
            updated = updated.copyWith(description: value);
          }
        case 'transactionTime':
          final time = DateTime.tryParse('$value');
          if (time != null) updated = updated.copyWith(transactionTime: time);
        case 'paymentMethod':
          updated =
              updated.copyWith(paymentMethod: paymentMethodFromJson('$value'));
        case 'note':
          if (value is String && value.isNotEmpty) {
            updated = updated.copyWith(note: value);
          }
      }
    }
    await _transactions.update(updated.copyWith(
      updatedAt: DateTime.now(),
      status: TxStatus.confirmed,
    ));
    return true;
  }

  Future<void> _save(List<PendingAiJob> jobs) => _settings.setString(
        _storageKey,
        jsonEncode(jobs.map((job) => job.toJson()).toList()),
      );

  Future<void> _deleteRemoteQuietly(
    RemoteBackgroundJobService remote,
    String jobId,
  ) async {
    try {
      await remote.deleteJob(jobId);
    } on RemoteException {
      // 本机已消费完成即可移除；服务端会按保留期清理结果。
    }
  }
}
