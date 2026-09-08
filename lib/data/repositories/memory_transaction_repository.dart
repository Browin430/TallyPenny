import '../../core/constants/app_constants.dart';
import '../../domain/models/duplicate_match.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/transaction.dart';
import '../../domain/models/transaction_candidate.dart';
import '../../domain/repositories/transaction_repository.dart';

/// 内存实现：Web 预览（Edge/Chrome）与单元测试使用。
/// 与 sqflite 实现语义保持一致，业务层完全无感。
class MemoryTransactionRepository implements TransactionRepository {
  final List<TransactionEntity> _txs = [];
  final Map<String, List<SourceRecord>> _sources = {};
  final List<DuplicateEvent> _duplicateLog = [];

  @override
  Future<void> insert(TransactionEntity tx) async => _txs.add(tx);

  @override
  Future<void> update(TransactionEntity tx) async {
    final i = _txs.indexWhere((t) => t.id == tx.id);
    if (i >= 0) _txs[i] = tx;
  }

  @override
  Future<void> softDelete(String id) async {
    final i = _txs.indexWhere((t) => t.id == id);
    if (i >= 0) {
      final now = DateTime.now();
      _txs[i] = _txs[i].copyWith(
        isDeleted: true,
        deletedAt: now,
        updatedAt: now,
      );
    }
  }

  @override
  Future<void> softDeleteMany(Iterable<String> ids) async {
    final wanted = ids.toSet();
    final now = DateTime.now();
    for (var i = 0; i < _txs.length; i++) {
      if (wanted.contains(_txs[i].id)) {
        _txs[i] = _txs[i].copyWith(
          isDeleted: true,
          deletedAt: now,
          updatedAt: now,
        );
      }
    }
  }

  @override
  Future<List<TransactionEntity>> getDeleted() async {
    final result = _txs.where((t) => t.isDeleted).toList()
      ..sort((a, b) =>
          (b.deletedAt ?? b.updatedAt).compareTo(a.deletedAt ?? a.updatedAt));
    return result;
  }

  @override
  Future<void> restore(String id) async {
    final i = _txs.indexWhere((t) => t.id == id);
    if (i >= 0) {
      _txs[i] = _txs[i].copyWith(
        isDeleted: false,
        clearDeletedAt: true,
        updatedAt: DateTime.now(),
      );
    }
  }

  @override
  Future<int> purgeDeletedBefore(DateTime cutoff) async {
    final ids = _txs
        .where((t) =>
            t.isDeleted && t.deletedAt != null && !t.deletedAt!.isAfter(cutoff))
        .map((t) => t.id)
        .toSet();
    _txs.removeWhere((t) => ids.contains(t.id));
    for (final id in ids) {
      _sources.remove(id);
    }
    return ids.length;
  }

  @override
  Future<TransactionEntity?> getById(String id) async {
    for (final t in _txs) {
      if (t.id == id && !t.isDeleted) return t;
    }
    return null;
  }

  @override
  Future<List<TransactionEntity>> getByRange(
    DateTime start,
    DateTime end, {
    TransactionType? type,
    Set<String>? categoryIds,
    String? search,
  }) async {
    Iterable<TransactionEntity> result = _txs.where(
      (t) =>
          !t.isDeleted &&
          !t.transactionTime.isBefore(start) &&
          t.transactionTime.isBefore(end),
    );
    if (type != null) result = result.where((t) => t.type == type);
    if (categoryIds != null && categoryIds.isNotEmpty) {
      result = result.where(
          (t) => t.categoryId != null && categoryIds.contains(t.categoryId));
    }
    if (search != null && search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      result = result.where((t) {
        final haystack =
            '${t.merchant ?? ''} ${t.description ?? ''} ${t.note ?? ''}'
                .toLowerCase();
        return haystack.contains(q);
      });
    }
    final list = result.toList()
      ..sort((a, b) => b.transactionTime.compareTo(a.transactionTime));
    return list;
  }

  @override
  Future<List<TransactionEntity>> getAll() async {
    final list = _txs.where((t) => !t.isDeleted).toList()
      ..sort((a, b) => b.transactionTime.compareTo(a.transactionTime));
    return list;
  }

  @override
  Future<List<TransactionEntity>> duplicateWindow({
    required DateTime center,
    required TransactionType type,
    required int amountCents,
    int windowHours = DuplicateWeights.candidateWindowHours,
  }) async {
    final start = center.subtract(Duration(hours: windowHours));
    final end = center.add(Duration(hours: windowHours));
    final tolerance =
        (amountCents * DuplicateWeights.candidateAmountTolerance).round();
    return _txs
        .where((t) =>
            !t.isDeleted &&
            t.status != TxStatus.archived &&
            t.type == type &&
            !t.transactionTime.isBefore(start) &&
            !t.transactionTime.isAfter(end) &&
            (t.amountCents - amountCents).abs() <= tolerance)
        .toList();
  }

  @override
  Future<void> attachSource(
    SourceRecordDraft draft, {
    required String transactionId,
  }) async {
    final record = SourceRecord(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      transactionId: transactionId,
      sourceType: draft.sourceType,
      rawText: draft.rawText,
      imageReference: draft.imageReference,
      ocrResult: draft.ocrResultJson,
      aiParseResult: draft.aiParseResultJson,
      createdAt: DateTime.now(),
    );
    _sources.putIfAbsent(transactionId, () => []).add(record);
  }

  @override
  Future<List<SourceRecord>> sourcesOf(String transactionId) async =>
      List.unmodifiable(_sources[transactionId] ?? const []);

  @override
  Future<void> logDuplicateEvent(DuplicateEvent event) async =>
      _duplicateLog.add(event);

  @override
  Future<void> clearAll() async {
    _txs.clear();
    _sources.clear();
    _duplicateLog.clear();
  }
}
