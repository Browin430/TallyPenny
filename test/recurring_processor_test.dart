import 'package:flutter_test/flutter_test.dart';
import 'package:flowmoney/data/repositories/memory_recurring_transaction_repository.dart';
import 'package:flowmoney/data/repositories/memory_transaction_repository.dart';
import 'package:flowmoney/domain/models/enums.dart';
import 'package:flowmoney/domain/models/recurring_transaction.dart';
import 'package:flowmoney/services/recurring_processor.dart';

void main() {
  RecurringTransaction monthlyRule({DateTime? lastRunAt}) {
    final created = DateTime(2026, 1, 1);
    return RecurringTransaction(
      id: 'rent',
      userId: 'local',
      title: '房租',
      amountCents: 300000,
      type: TransactionType.expense,
      categoryId: 'housing',
      merchant: '房东',
      frequency: RecurringFrequency.monthly,
      dayOfMonth: 31,
      startDate: DateTime(2026, 1, 1),
      hour: 9,
      minute: 30,
      lastRunAt: lastRunAt,
      createdAt: created,
      updatedAt: created,
    );
  }

  test('每月31日规则在短月份取月末并补齐历史到期项', () {
    final due = RecurringProcessor.dueOccurrences(
      monthlyRule(),
      DateTime(2026, 3, 31, 12),
    );
    expect(due, [
      DateTime(2026, 1, 31, 9, 30),
      DateTime(2026, 2, 28, 9, 30),
      DateTime(2026, 3, 31, 9, 30),
    ]);
  });

  test('重复执行不会重复生成流水', () async {
    final recurring = MemoryRecurringTransactionRepository();
    final transactions = MemoryTransactionRepository();
    await recurring.upsert(monthlyRule());
    final processor = RecurringProcessor(
      recurringRepository: recurring,
      transactionRepository: transactions,
    );

    final first = await processor.runDue(at: DateTime(2026, 2, 28, 12));
    final second = await processor.runDue(at: DateTime(2026, 2, 28, 13));

    expect(first, 2);
    expect(second, 0);
    final generated = await transactions.getAll();
    expect(generated, hasLength(2));
    expect(generated.every((item) => item.isRecurring), isTrue);
    expect(
      generated.every((item) => item.recurringTransactionId == 'rent'),
      isTrue,
    );
  });

  test('双休工作日跳过周六和周日', () {
    final created = DateTime(2026, 8, 1);
    final rule = RecurringTransaction(
      id: 'weekday-double-rest',
      userId: 'local',
      title: '工作日午餐',
      amountCents: 2000,
      type: TransactionType.expense,
      frequency: RecurringFrequency.workdays,
      daysOfWeek: const [1, 2, 3, 4, 5],
      startDate: DateTime(2026, 8, 28),
      hour: 12,
      minute: 0,
      createdAt: created,
      updatedAt: created,
    );

    final due = RecurringProcessor.dueOccurrences(
      rule,
      DateTime(2026, 9, 1, 13),
    );

    expect(due, [
      DateTime(2026, 8, 28, 12),
      DateTime(2026, 8, 31, 12),
      DateTime(2026, 9, 1, 12),
    ]);
  });

  test('单休工作日包含周六但跳过周日', () {
    final created = DateTime(2026, 8, 1);
    final rule = RecurringTransaction(
      id: 'weekday-single-rest',
      userId: 'local',
      title: '工作日通勤',
      amountCents: 500,
      type: TransactionType.expense,
      frequency: RecurringFrequency.workdays,
      daysOfWeek: const [1, 2, 3, 4, 5, 6],
      startDate: DateTime(2026, 8, 28),
      hour: 8,
      minute: 30,
      createdAt: created,
      updatedAt: created,
    );

    final due = RecurringProcessor.dueOccurrences(
      rule,
      DateTime(2026, 8, 31, 9),
    );

    expect(due, [
      DateTime(2026, 8, 28, 8, 30),
      DateTime(2026, 8, 29, 8, 30),
      DateTime(2026, 8, 31, 8, 30),
    ]);
  });

  test('启动处理器会修复规则已改但历史流水仍为旧分类的存量数据', () async {
    final recurring = MemoryRecurringTransactionRepository();
    final transactions = MemoryTransactionRepository();
    final oldRule = monthlyRule().copyWith(categoryId: 'other');
    await recurring.upsert(oldRule);
    final processor = RecurringProcessor(
      recurringRepository: recurring,
      transactionRepository: transactions,
    );
    await processor.runDue(at: DateTime(2026, 1, 31, 12));
    final storedRule = (await recurring.getAll()).single;
    await recurring.upsert(storedRule.copyWith(categoryId: 'housing'));

    final changed = await processor.runDue(at: DateTime(2026, 1, 31, 13));

    expect(changed, 1);
    expect((await transactions.getAll()).single.categoryId, 'housing');
  });
}
