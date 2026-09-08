import '../core/utils/id_gen.dart';
import '../domain/models/enums.dart';
import '../domain/models/recurring_transaction.dart';
import '../domain/models/transaction.dart';
import '../domain/repositories/recurring_transaction_repository.dart';
import '../domain/repositories/transaction_repository.dart';

/// 将已到期的周期规则补记为普通流水。
///
/// App 每次启动及用户保存规则后都会执行。若设备多日未打开，会自动补齐遗漏日期；
/// 已生成的规则+发生时间组合不会重复入账。
class RecurringProcessor {
  RecurringProcessor({
    required RecurringTransactionRepository recurringRepository,
    required TransactionRepository transactionRepository,
  })  : _recurring = recurringRepository,
        _transactions = transactionRepository;

  final RecurringTransactionRepository _recurring;
  final TransactionRepository _transactions;

  /// 返回实际发生的数据变更数（新增到期流水 + 同步历史周期流水分类）。
  Future<int> runDue({DateTime? at}) async {
    final now = at ?? DateTime.now();
    final rules = await _recurring.getAll();
    final existing = await _transactions.getAll();
    final occurrenceKeys = {
      for (final tx in existing)
        if (tx.recurringTransactionId != null)
          _occurrenceKey(tx.recurringTransactionId!, tx.transactionTime),
    };
    var changed = 0;

    for (final rule in rules.where((item) => item.enabled)) {
      // 周期规则是其生成流水的分类来源。App 启动时也会执行本方法，因此能
      // 修复旧版本中“规则已改分类、历史流水仍留在其他”的存量不一致。
      final targetCategory = rule.categoryId ??
          (rule.type == TransactionType.income ? 'other_income' : 'other');
      for (final tx in existing.where(
        (tx) =>
            tx.recurringTransactionId == rule.id &&
            tx.categoryId != targetCategory,
      )) {
        await _transactions.update(tx.copyWith(
          categoryId: targetCategory,
          updatedAt: DateTime.now(),
        ));
        changed++;
      }

      final occurrences = dueOccurrences(rule, now);
      for (final occurrence in occurrences) {
        final key = _occurrenceKey(rule.id, occurrence);
        if (!occurrenceKeys.add(key)) continue;
        final timestamp = DateTime.now();
        await _transactions.insert(
          TransactionEntity(
            id: IdGen.newId(),
            userId: rule.userId,
            type: rule.type,
            amountCents: rule.amountCents,
            currency: 'CNY',
            categoryId: rule.categoryId ??
                (rule.type == TransactionType.income
                    ? 'other_income'
                    : 'other'),
            merchant: rule.merchant,
            description: rule.description ?? rule.title,
            transactionTime: occurrence,
            createdAt: timestamp,
            updatedAt: timestamp,
            sourceType: SourceType.recurring,
            confidence: 1,
            status: TxStatus.confirmed,
            isRecurring: true,
            recurringTransactionId: rule.id,
            paymentMethod: rule.paymentMethod,
          ),
        );
        changed++;
      }
      await _recurring.upsert(rule.copyWith(
        lastRunAt: now,
        updatedAt: DateTime.now(),
      ));
    }
    return changed;
  }

  /// 返回 (lastRunAt, now] 内所有到期时间，首次执行从 startDate 开始。
  static List<DateTime> dueOccurrences(
    RecurringTransaction rule,
    DateTime now,
  ) {
    if (!rule.enabled || rule.startDate.isAfter(now)) return const [];
    final end = rule.endDate != null && rule.endDate!.isBefore(now)
        ? _endOfDay(rule.endDate!)
        : now;
    if (end.isBefore(rule.startDate)) return const [];
    final after = rule.lastRunAt;
    final result = <DateTime>[];

    bool include(DateTime value) =>
        !value.isBefore(rule.startDate) &&
        !value.isAfter(end) &&
        (after == null || value.isAfter(after));

    switch (rule.frequency) {
      case RecurringFrequency.daily:
        var cursor = _atRuleTime(rule.startDate, rule);
        while (!cursor.isAfter(end)) {
          if (include(cursor)) result.add(cursor);
          cursor = DateTime(
            cursor.year,
            cursor.month,
            cursor.day + 1,
            rule.hour,
            rule.minute,
          );
        }
        break;
      case RecurringFrequency.workdays:
        final workdays = rule.daysOfWeek.isEmpty
            ? const {
                DateTime.monday,
                DateTime.tuesday,
                DateTime.wednesday,
                DateTime.thursday,
                DateTime.friday
              }
            : rule.daysOfWeek.toSet();
        var cursor = _atRuleTime(rule.startDate, rule);
        while (!cursor.isAfter(end)) {
          if (workdays.contains(cursor.weekday) && include(cursor)) {
            result.add(cursor);
          }
          cursor = DateTime(
            cursor.year,
            cursor.month,
            cursor.day + 1,
            rule.hour,
            rule.minute,
          );
        }
        break;
      case RecurringFrequency.weekly:
        final weekday = rule.daysOfWeek.isEmpty
            ? rule.startDate.weekday
            : rule.daysOfWeek.first;
        var cursor = _atRuleTime(rule.startDate, rule);
        cursor = cursor.add(Duration(days: (weekday - cursor.weekday) % 7));
        while (!cursor.isAfter(end)) {
          if (include(cursor)) result.add(cursor);
          cursor = cursor.add(const Duration(days: 7));
        }
        break;
      case RecurringFrequency.monthly:
        var year = rule.startDate.year;
        var month = rule.startDate.month;
        while (true) {
          final day = _clampDay(
            year,
            month,
            rule.dayOfMonth ?? rule.startDate.day,
          );
          final cursor = DateTime(year, month, day, rule.hour, rule.minute);
          if (cursor.isAfter(end)) break;
          if (include(cursor)) result.add(cursor);
          month++;
          if (month > 12) {
            month = 1;
            year++;
          }
        }
        break;
    }
    return result;
  }

  static DateTime _atRuleTime(DateTime date, RecurringTransaction rule) =>
      DateTime(date.year, date.month, date.day, rule.hour, rule.minute);

  static DateTime _endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

  static int _clampDay(int year, int month, int requested) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return requested.clamp(1, lastDay);
  }

  static String _occurrenceKey(String ruleId, DateTime occurrence) =>
      '$ruleId:${occurrence.millisecondsSinceEpoch}';
}
