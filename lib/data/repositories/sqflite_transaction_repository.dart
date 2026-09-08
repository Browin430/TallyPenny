import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../domain/models/duplicate_match.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/transaction.dart';
import '../../domain/models/transaction_candidate.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../dao/mappers.dart';
import '../database/app_database.dart';

/// sqflite 实现（iOS / Android）。
class SqfliteTransactionRepository implements TransactionRepository {
  SqfliteTransactionRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> insert(TransactionEntity tx) async {
    await _db.raw.insert('transactions', txToMap(tx));
  }

  @override
  Future<void> update(TransactionEntity tx) async {
    await _db.raw.update('transactions', txToMap(tx),
        where: 'id = ?', whereArgs: [tx.id]);
  }

  @override
  Future<void> softDelete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.raw.update(
      'transactions',
      {'is_deleted': 1, 'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> softDeleteMany(Iterable<String> ids) async {
    final values = ids.toSet().toList();
    if (values.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      for (var offset = 0; offset < values.length; offset += 400) {
        final end = offset + 400 < values.length ? offset + 400 : values.length;
        final batch = values.sublist(offset, end);
        await txn.update(
          'transactions',
          {'is_deleted': 1, 'deleted_at': now, 'updated_at': now},
          where: 'id IN (${List.filled(batch.length, '?').join(',')})',
          whereArgs: batch,
        );
      }
    });
  }

  @override
  Future<List<TransactionEntity>> getDeleted() async {
    final rows = await _db.raw.query(
      'transactions',
      where: 'is_deleted = 1',
      orderBy: 'deleted_at DESC, updated_at DESC',
    );
    return rows.map(txFromMap).toList();
  }

  @override
  Future<void> restore(String id) async {
    await _db.raw.update(
      'transactions',
      {
        'is_deleted': 0,
        'deleted_at': null,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<int> purgeDeletedBefore(DateTime cutoff) async {
    return _db.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        columns: ['id'],
        where: 'is_deleted = 1 AND deleted_at IS NOT NULL AND deleted_at <= ?',
        whereArgs: [cutoff.millisecondsSinceEpoch],
      );
      final ids = rows.map((row) => row['id'] as String).toList();
      if (ids.isEmpty) return 0;
      for (var offset = 0; offset < ids.length; offset += 400) {
        final end = offset + 400 < ids.length ? offset + 400 : ids.length;
        final batch = ids.sublist(offset, end);
        final marks = List.filled(batch.length, '?').join(',');
        await txn.delete('transaction_sources',
            where: 'transaction_id IN ($marks)', whereArgs: batch);
        await txn.delete('invoice_documents',
            where: 'transaction_id IN ($marks)', whereArgs: batch);
        await txn.delete(
          'duplicate_candidates',
          where:
              'existing_transaction_id IN ($marks) OR kept_transaction_id IN ($marks)',
          whereArgs: [...batch, ...batch],
        );
        await txn.delete('transactions',
            where: 'id IN ($marks)', whereArgs: batch);
      }
      return ids.length;
    });
  }

  @override
  Future<TransactionEntity?> getById(String id) async {
    final rows = await _db.raw.query('transactions',
        where: 'id = ? AND is_deleted = 0', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return txFromMap(rows.first);
  }

  @override
  Future<List<TransactionEntity>> getByRange(
    DateTime start,
    DateTime end, {
    TransactionType? type,
    Set<String>? categoryIds,
    String? search,
  }) async {
    final where = <String>[
      'is_deleted = 0',
      'transaction_time >= ?',
      'transaction_time < ?'
    ];
    final args = <Object?>[
      start.millisecondsSinceEpoch,
      end.millisecondsSinceEpoch,
    ];
    if (type != null) {
      where.add('type = ?');
      args.add(type.toDb());
    }
    if (categoryIds != null && categoryIds.isNotEmpty) {
      where.add(
        'category_id IN (${List.filled(categoryIds.length, '?').join(',')})',
      );
      args.addAll(categoryIds);
    }
    if (search != null && search.trim().isNotEmpty) {
      final like = '%${search.trim()}%';
      where.add('(merchant LIKE ? OR description LIKE ? OR note LIKE ?)');
      args.addAll([like, like, like]);
    }
    final rows = await _db.raw.query(
      'transactions',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'transaction_time DESC',
    );
    return rows.map(txFromMap).toList();
  }

  @override
  Future<List<TransactionEntity>> getAll() async {
    final rows = await _db.raw.query(
      'transactions',
      where: 'is_deleted = 0',
      orderBy: 'transaction_time DESC',
    );
    return rows.map(txFromMap).toList();
  }

  @override
  Future<List<TransactionEntity>> duplicateWindow({
    required DateTime center,
    required TransactionType type,
    required int amountCents,
    int windowHours = DuplicateWeights.candidateWindowHours,
  }) async {
    final tolerance =
        (amountCents * DuplicateWeights.candidateAmountTolerance).round();
    final start = center.subtract(Duration(hours: windowHours));
    final end = center.add(Duration(hours: windowHours));
    final rows = await _db.raw.query(
      'transactions',
      where:
          'is_deleted = 0 AND status != ? AND type = ? AND transaction_time >= ? AND transaction_time <= ? AND ABS(amount - ?) <= ?',
      whereArgs: [
        TxStatus.archived.toDb(),
        type.toDb(),
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
        amountCents,
        tolerance,
      ],
      orderBy: 'transaction_time DESC',
    );
    return rows.map(txFromMap).toList();
  }

  @override
  Future<void> attachSource(
    SourceRecordDraft draft, {
    required String transactionId,
  }) async {
    await _db.raw
        .insert('transaction_sources', sourceToMap(draft, transactionId));
  }

  @override
  Future<List<SourceRecord>> sourcesOf(String transactionId) async {
    final rows = await _db.raw.query(
      'transaction_sources',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
      orderBy: 'created_at ASC',
    );
    return rows.map(sourceFromMap).toList();
  }

  @override
  Future<void> logDuplicateEvent(DuplicateEvent event) async {
    await _db.raw.insert('duplicate_candidates', {
      'id': DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      'existing_transaction_id': event.existingId,
      'kept_transaction_id': event.keptId,
      'score': event.score,
      'reasons': jsonEncode(event.reasons),
      'status': event.status,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'resolved_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> clearAll() async {
    await _db.raw.delete('transactions');
    await _db.raw.delete('transaction_sources');
    await _db.raw.delete('duplicate_candidates');
  }
}
