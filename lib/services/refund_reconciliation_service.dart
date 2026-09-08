import '../domain/models/enums.dart';
import '../domain/models/transaction.dart';
import '../domain/models/transaction_candidate.dart';
import '../domain/repositories/transaction_repository.dart';

class RefundPairFilteringResult {
  const RefundPairFilteringResult({
    required this.remaining,
    required this.cancelledPairs,
  });

  final List<TransactionCandidate> remaining;
  final int cancelledPairs;
}

/// 忽略退款收入及明确标记已全额退款的原支出。
class RefundReconciliationService {
  RefundReconciliationService(this._transactions);

  final TransactionRepository _transactions;

  RefundPairFilteringResult removePairsWithinBatch(
    List<TransactionCandidate> candidates,
  ) {
    // 平台导出的退款常常只有“全额退款”这一条，没有原始支出。
    // 因此退款不再作为收入写入，也不尝试猜测并删除另一笔支出。
    final remaining =
        candidates.where((item) => !_isRefundCandidate(item)).toList();
    final ignored = candidates.length - remaining.length;
    return RefundPairFilteringResult(
      remaining: remaining,
      cancelledPairs: ignored,
    );
  }

  /// 返回 true 表示该候选是退款，应直接忽略且不改动其他账单。
  Future<bool> cancelAgainstExisting(TransactionCandidate candidate) async =>
      _isRefundCandidate(candidate);

  /// 清理旧版本写入流水的自动识别退款；原始支出不做猜测性删除。
  Future<int> reconcileExistingImportedPairs() async {
    final existing = await _transactions.getAll();
    var ignoredRefunds = 0;
    for (final transaction in existing) {
      if (_isAutomatedImport(transaction.sourceType) &&
          _isRefundTransaction(transaction)) {
        await _transactions.softDelete(transaction.id);
        ignoredRefunds++;
      }
    }
    return ignoredRefunds;
  }

  bool _isAutomatedImport(SourceType sourceType) =>
      sourceType == SourceType.screenshot || sourceType == SourceType.imported;

  bool _isRefundCandidate(TransactionCandidate candidate) {
    final probe = '${candidate.categoryId ?? ''} ${candidate.merchant ?? ''} '
        '${candidate.description ?? ''} ${candidate.note ?? ''} ${candidate.subcategory ?? ''}';
    return _isFullyRefunded(probe) ||
        (candidate.type == TransactionType.income &&
            (candidate.categoryId == 'refund' || probe.contains('退款')));
  }

  bool _isRefundTransaction(TransactionEntity transaction) {
    final probe =
        '${transaction.categoryId ?? ''} ${transaction.merchant ?? ''} '
        '${transaction.description ?? ''} ${transaction.note ?? ''} ${transaction.subcategory ?? ''}';
    return _isFullyRefunded(probe) ||
        (transaction.type == TransactionType.income &&
            (transaction.categoryId == 'refund' || probe.contains('退款')));
  }

  bool _isFullyRefunded(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    return const ['已全额退款', '已全退款', '全额退款成功', '全额已退款']
        .any(compact.contains);
  }
}
