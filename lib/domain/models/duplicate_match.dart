import '../../core/constants/app_constants.dart';
import 'transaction.dart';
import 'transaction_candidate.dart';

/// 去重引擎的输出：新候选与一笔已有账单的相似度判定结果。
class DuplicateMatch {
  const DuplicateMatch({
    required this.existing,
    required this.incoming,
    required this.score,
    required this.reasons,
  });

  /// 已存在的账单（数据库中）。
  final TransactionEntity existing;

  /// 正在录入的新候选。
  final TransactionCandidate incoming;

  /// 0 ~ 1。
  final double score;

  /// 人类可读的判定理由，用于解释"为什么 AI 认为这两笔可能重复"。
  final List<String> reasons;

  bool get shouldAutoMerge => score >= DuplicateThresholds.autoMerge;

  bool get shouldAskUser =>
      score >= DuplicateThresholds.askUser && !shouldAutoMerge;
}

/// 去重事件的落库审计记录（merged / kept_both），供未来追溯与统计。
class DuplicateEvent {
  const DuplicateEvent({
    required this.score,
    required this.reasons,
    required this.status,
    this.existingId,
    this.keptId,
  });

  final double score;
  final List<String> reasons;

  /// merged：合并为一笔；kept_both：确认是两笔。
  final String status;
  final String? existingId;
  final String? keptId;
}
