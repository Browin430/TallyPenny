import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/models/enums.dart';
import '../../domain/models/recurring_transaction.dart';
import '../../domain/repositories/recurring_transaction_repository.dart';
import '../database/app_database.dart';

class SqfliteRecurringTransactionRepository
    implements RecurringTransactionRepository {
  SqfliteRecurringTransactionRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<RecurringTransaction>> getAll() async {
    final rows = await _db.raw.query(
      'recurring_transactions',
      orderBy: 'updated_at DESC',
    );
    return rows.map(_fromMap).toList();
  }

  @override
  Future<void> upsert(RecurringTransaction recurring) async {
    await _db.raw.insert(
      'recurring_transactions',
      _toMap(recurring),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> delete(String id) async => _db.raw.delete(
        'recurring_transactions',
        where: 'id = ?',
        whereArgs: [id],
      );

  @override
  Future<void> clearAll() async => _db.raw.delete('recurring_transactions');

  Map<String, Object?> _toMap(RecurringTransaction item) => {
        'id': item.id,
        'user_id': item.userId,
        'title': item.title,
        'amount': item.amountCents,
        'type': item.type.toDb(),
        'category_id': item.categoryId,
        'merchant': item.merchant,
        'description': item.description,
        'payment_method': item.paymentMethod?.toDb(),
        'frequency': item.frequency.toDb(),
        'days_of_week':
            item.daysOfWeek.isEmpty ? null : jsonEncode(item.daysOfWeek),
        'day_of_month': item.dayOfMonth,
        'time_of_day':
            '${item.hour.toString().padLeft(2, '0')}:${item.minute.toString().padLeft(2, '0')}',
        'start_date': item.startDate.millisecondsSinceEpoch,
        'end_date': item.endDate?.millisecondsSinceEpoch,
        'enabled': item.enabled ? 1 : 0,
        'last_run_at': item.lastRunAt?.millisecondsSinceEpoch,
        'created_at': item.createdAt.millisecondsSinceEpoch,
        'updated_at': item.updatedAt.millisecondsSinceEpoch,
      };

  RecurringTransaction _fromMap(Map<String, Object?> map) {
    final time = (map['time_of_day'] as String? ?? '09:00').split(':');
    final daysRaw = map['days_of_week'] as String?;
    final days = daysRaw == null
        ? const <int>[]
        : (jsonDecode(daysRaw) as List).map((value) => value as int).toList();
    return RecurringTransaction(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      title: map['title'] as String,
      amountCents: map['amount'] as int,
      type: TransactionType.fromDb(map['type'] as String),
      categoryId: map['category_id'] as String?,
      merchant: map['merchant'] as String?,
      description: map['description'] as String?,
      paymentMethod: PaymentMethod.fromDb(map['payment_method'] as String?),
      frequency: RecurringFrequency.fromDb(map['frequency'] as String),
      daysOfWeek: days,
      dayOfMonth: map['day_of_month'] as int?,
      hour: int.tryParse(time.first) ?? 9,
      minute: time.length > 1 ? int.tryParse(time[1]) ?? 0 : 0,
      startDate: DateTime.fromMillisecondsSinceEpoch(map['start_date'] as int),
      endDate: map['end_date'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['end_date'] as int),
      enabled: (map['enabled'] as int? ?? 1) == 1,
      lastRunAt: map['last_run_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['last_run_at'] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }
}
