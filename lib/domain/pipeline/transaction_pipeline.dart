import 'dart:async';

import '../../core/constants/app_constants.dart';
import '../../core/utils/id_gen.dart';
import '../../services/duplicate_detection_service.dart';
import '../../services/merchant_rule_matcher.dart';
import '../models/duplicate_match.dart';
import '../models/enums.dart';
import '../models/merchant_rule.dart';
import '../models/transaction.dart';
import '../models/transaction_candidate.dart';
import '../repositories/merchant_rule_repository.dart';
import '../repositories/transaction_repository.dart';

/// 统一记账流水线输出。
sealed class PipelineResult {}

/// 已入库（含"自动合并到已有账单"的情况）。
class PipelineSaved extends PipelineResult {
  PipelineSaved({required this.transaction, this.mergedIntoExisting = false});

  final TransactionEntity transaction;

  /// true：未新建账单，而是合并进了已有账单（原始数据保留在 sources）。
  final bool mergedIntoExisting;
}

/// 信息不足（如没有金额），需要用户补充。
class PipelineNeedsReview extends PipelineResult {
  PipelineNeedsReview(this.candidate, this.reason);

  final TransactionCandidate candidate;
  final String reason;
}

/// 疑似重复，必须让用户确认。
class PipelineDuplicateSuspected extends PipelineResult {
  PipelineDuplicateSuspected(this.match);

  final DuplicateMatch match;
}

/// 统一记账流水线。
///
/// 所有来源（手动 / 语音 / 截图 / 导入 / 周期）都走这一条路：
/// 归一化 → 校验 → 分类兜底 → 去重检测 → 置信度评估 → 保存 / 请求确认。
/// 绝不为某种输入来源复制一套业务逻辑。
class TransactionPipeline {
  TransactionPipeline({
    required TransactionRepository transactionRepository,
    required DuplicateDetectionService duplicateDetection,
    MerchantRuleRepository? merchantRules,
  })  : _transactions = transactionRepository,
        _dedup = duplicateDetection,
        _merchantRules = merchantRules;

  final TransactionRepository _transactions;
  final DuplicateDetectionService _dedup;

  /// 商户个性化规则（可选）：命中则覆盖分类（用户显式声明优先于模型猜测）。
  final MerchantRuleRepository? _merchantRules;

  DateTime Function() now = DateTime.now;

  /// 解析最终分类：商户规则 > 候选分类 > other/other_income 兜底。
  Future<String> _resolveCategory(
    TransactionCandidate candidate,
    TransactionType type,
  ) async {
    final merchant = candidate.merchant?.trim();
    if (merchant != null && merchant.isNotEmpty && _merchantRules != null) {
      final rules = await _merchantRules.getAll();
      final rule = MerchantRuleMatcher.match(rules, merchant);
      if (rule != null) {
        _bumpHitCount(rule);
        return rule.preferredCategory;
      }
    }
    return candidate.categoryId ??
        (type == TransactionType.income ? 'other_income' : 'other');
  }

  /// best-effort 命中计数（失败忽略，绝不影响入账）。
  void _bumpHitCount(MerchantRule rule) {
    final repo = _merchantRules;
    if (repo == null) return;
    unawaited(() async {
      try {
        await repo.upsert(
          rule.copyWith(hitCount: rule.hitCount + 1, updatedAt: now()),
        );
      } on Object {
        // 计数失败无所谓。
      }
    }());
  }

  Future<PipelineResult> process(TransactionCandidate candidate) async {
    // ---- 1. 校验：金额必须存在且 > 0（绝不静默生成 ¥0 账单）----
    if (!candidate.hasAmount) {
      return PipelineNeedsReview(candidate, 'missing_amount');
    }

    // ---- 2. 归一化 ----
    final type = candidate.type ?? TransactionType.expense;
    final time = candidate.transactionTime ?? now();

    // ---- 3. 分类：商户规则 > 候选分类 > "其他"（不强制猜测）----
    final categoryId = await _resolveCategory(candidate, type);

    final draft = TransactionEntity(
      id: IdGen.newId(),
      userId: 'local',
      type: type,
      amountCents: candidate.amountCents!,
      currency: candidate.currency,
      categoryId: categoryId,
      subcategory: candidate.subcategory,
      merchant: candidate.merchant?.trim().isEmpty ?? true
          ? null
          : candidate.merchant!.trim(),
      description: candidate.description,
      transactionTime: time,
      createdAt: now(),
      updatedAt: now(),
      sourceType: candidate.sourceType,
      confidence: candidate.confidence,
      status: _statusFor(candidate),
      isRecurring: candidate.sourceType == SourceType.recurring,
      paymentMethod: candidate.paymentMethod,
      note: candidate.note,
      invoiceRequired: candidate.invoiceRequired,
      invoiceIssued: candidate.invoiceIssued,
      invoiceWaived: candidate.invoiceWaived,
      reimbursed: candidate.reimbursed,
    );

    // ---- 4. 去重检测 ----
    final match = await _dedup.findMatch(draft, candidate);
    if (match != null && match.shouldAutoMerge) {
      // 高度确定重复：建议自动合并（保留完整审计信息），不打扰用户。
      final id = await merge(match);
      final merged = await _transactions.getById(id);
      if (merged != null) {
        return PipelineSaved(transaction: merged, mergedIntoExisting: true);
      }
    }
    if (match != null) {
      return PipelineDuplicateSuspected(match);
    }

    // ---- 5. 入库（含原始来源记录）----
    await _transactions.insert(draft);
    return PipelineSaved(transaction: draft);
  }

  /// 用户确认"合并为一笔"：保留已有账单为正身，
  /// 新候选的原始数据并入其 source_records，绝不删除任何原始信息。
  Future<String> merge(DuplicateMatch match) async {
    final existing = match.existing;
    final incoming = match.incoming;

    // 用新数据补全旧账单缺失的字段（如截图带来的准确商户）。
    String? fill(String? current, String? incomingValue) =>
        (current == null || current.isEmpty) ? incomingValue : current;

    final updated = TransactionEntity(
      id: existing.id,
      userId: existing.userId,
      type: existing.type,
      amountCents: existing.amountCents,
      currency: existing.currency,
      categoryId: existing.categoryId ?? incoming.categoryId,
      subcategory: fill(existing.subcategory, incoming.subcategory),
      merchant: fill(existing.merchant, incoming.merchant),
      description: fill(existing.description, incoming.description),
      transactionTime: existing.transactionTime,
      createdAt: existing.createdAt,
      updatedAt: now(),
      sourceType: existing.sourceType,
      confidence: existing.confidence,
      status: TxStatus.confirmed,
      isRecurring: existing.isRecurring,
      recurringTransactionId: existing.recurringTransactionId,
      paymentMethod: existing.paymentMethod ?? incoming.paymentMethod,
      note: existing.note,
      invoiceRequired: existing.invoiceRequired,
      invoiceIssued: existing.invoiceIssued,
      invoiceWaived: existing.invoiceWaived,
      reimbursed: existing.reimbursed,
      isDeleted: existing.isDeleted,
    );
    await _transactions.update(updated);

    for (final source in incoming.sourceRecords) {
      await _transactions.attachSource(source, transactionId: existing.id);
    }
    await _transactions.logDuplicateEvent(
      DuplicateEvent(
        score: match.score,
        reasons: match.reasons,
        status: 'merged',
        existingId: existing.id,
      ),
    );
    return existing.id;
  }

  /// 用户确认"这是两笔消费"：新候选正常入库，并保留判定事件供审计。
  Future<TransactionEntity> keepBoth(DuplicateMatch match) async {
    final candidate = match.incoming;
    final type = candidate.type ?? TransactionType.expense;
    final entity = TransactionEntity(
      id: IdGen.newId(),
      userId: 'local',
      type: type,
      amountCents: candidate.amountCents!,
      currency: candidate.currency,
      categoryId: await _resolveCategory(candidate, type),
      subcategory: candidate.subcategory,
      merchant: candidate.merchant,
      description: candidate.description,
      transactionTime: candidate.transactionTime ?? now(),
      createdAt: now(),
      updatedAt: now(),
      sourceType: candidate.sourceType,
      confidence: candidate.confidence,
      status: TxStatus.confirmed,
      paymentMethod: candidate.paymentMethod,
      note: candidate.note,
      invoiceRequired: candidate.invoiceRequired,
      invoiceIssued: candidate.invoiceIssued,
      invoiceWaived: candidate.invoiceWaived,
      reimbursed: candidate.reimbursed,
    );
    await _transactions.insert(entity);
    await _transactions.logDuplicateEvent(
      DuplicateEvent(
        score: match.score,
        reasons: match.reasons,
        status: 'kept_both',
        existingId: match.existing.id,
        keptId: entity.id,
      ),
    );
    return entity;
  }

  TxStatus _statusFor(TransactionCandidate candidate) {
    if (candidate.confidence >= ConfidencePolicy.autoCommit) {
      return TxStatus.aiGenerated;
    }
    if (candidate.confidence < ConfidencePolicy.needsReview) {
      return TxStatus.needsReview;
    }
    return TxStatus.needsReview;
  }
}
