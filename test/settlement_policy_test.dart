import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowmoney/core/utils/settlement_policy.dart';
import 'package:flowmoney/data/repositories/memory_transaction_repository.dart';
import 'package:flowmoney/data/repositories/memory_category_repository.dart';
import 'package:flowmoney/domain/models/enums.dart';
import 'package:flowmoney/domain/models/transaction.dart';
import 'package:flowmoney/domain/repositories/settings_repository.dart';
import 'package:flowmoney/state/app_providers.dart';

void main() {
  TransactionEntity transaction({
    required String id,
    required int amount,
    required DateTime time,
    TransactionType type = TransactionType.expense,
    bool invoiceRequired = false,
    bool invoiceIssued = false,
    bool invoiceWaived = false,
    bool reimbursed = false,
  }) {
    return TransactionEntity(
      id: id,
      userId: 'local',
      type: type,
      amountCents: amount,
      currency: 'CNY',
      transactionTime: time,
      createdAt: time,
      updatedAt: time,
      sourceType: SourceType.manual,
      confidence: 1,
      status: TxStatus.confirmed,
      invoiceRequired: invoiceRequired,
      invoiceIssued: invoiceIssued,
      invoiceWaived: invoiceWaived,
      reimbursed: reimbursed,
    );
  }

  test('未来账单会保存，但在到期前不属于已结算账单', () {
    final now = DateTime(2026, 8, 28, 18);
    final past = transaction(
      id: 'past',
      amount: 1000,
      time: now.subtract(const Duration(minutes: 1)),
    );
    final future = transaction(
      id: 'future',
      amount: 2000,
      time: now.add(const Duration(minutes: 1)),
    );

    expect(SettlementPolicy.hasOccurred(past, now), isTrue);
    expect(SettlementPolicy.hasOccurred(future, now), isFalse);
    expect(SettlementPolicy.occurred([past, future], now), [past]);
  });

  test('本月结余收入包含财务设置中的月收入并排除未来账单', () async {
    final now = DateTime.now();
    final repository = MemoryTransactionRepository();
    await repository.insert(transaction(
      id: 'income',
      amount: 50000,
      time: now.subtract(const Duration(minutes: 2)),
      type: TransactionType.income,
    ));
    await repository.insert(transaction(
      id: 'expense',
      amount: 3000,
      time: now.subtract(const Duration(minutes: 1)),
    ));
    await repository.insert(transaction(
      id: 'future-expense',
      amount: 9000,
      time: now.add(const Duration(minutes: 10)),
    ));

    final settings = _MemorySettings({
      'profile_income': 1200000,
      'profile_fixed': 0,
      'profile_budget': 800000,
      'profile_savings': 300000,
    });
    final container = ProviderContainer(overrides: [
      transactionRepositoryProvider.overrideWithValue(repository),
      categoryRepositoryProvider.overrideWithValue(MemoryCategoryRepository()),
      settingsRepositoryProvider.overrideWithValue(settings),
    ]);
    addTearDown(container.dispose);

    final data = await container.read(homeDataProvider.future);
    expect(data.incomeCents, 1250000);
    expect(data.expenseCents, 3000);
    expect(data.balanceCents, 1247000);
    expect(data.budgetCents, 900000);
  });

  test('开票及报销账单保留但不计入个人结余', () async {
    final now = DateTime.now();
    final repository = MemoryTransactionRepository();
    await repository.insert(transaction(
      id: 'personal',
      amount: 2000,
      time: now.subtract(const Duration(minutes: 5)),
    ));
    await repository.insert(transaction(
      id: 'invoice',
      amount: 8000,
      time: now.subtract(const Duration(minutes: 4)),
      invoiceRequired: true,
    ));
    await repository.insert(transaction(
      id: 'reimbursed',
      amount: 12000,
      time: now.subtract(const Duration(minutes: 3)),
      reimbursed: true,
    ));
    await repository.insert(transaction(
      id: 'waived-reimbursement',
      amount: 5000,
      time: now.subtract(const Duration(minutes: 2)),
      invoiceWaived: true,
      reimbursed: true,
    ));
    await repository.insert(transaction(
      id: 'company-reimbursement-income',
      amount: 12000,
      time: now.subtract(const Duration(minutes: 1)),
      type: TransactionType.income,
      reimbursed: true,
    ));

    final settings = _MemorySettings({
      'profile_income': 100000,
      'profile_fixed': 0,
      'profile_budget': 80000,
      'profile_savings': 30000,
    });
    final container = ProviderContainer(overrides: [
      transactionRepositoryProvider.overrideWithValue(repository),
      categoryRepositoryProvider.overrideWithValue(MemoryCategoryRepository()),
      settingsRepositoryProvider.overrideWithValue(settings),
    ]);
    addTearDown(container.dispose);

    final home = await container.read(homeDataProvider.future);
    final summary = await container.read(
      monthSummaryProvider(DateTime(now.year, now.month, 1)).future,
    );
    final analysis = await container.read(
      analysisDataProvider(DateTime(now.year, now.month, 1)).future,
    );
    final visibleTransactions = await container.read(filteredTxProvider.future);

    expect(await repository.getAll(), hasLength(5));
    expect(home.incomeCents, 100000);
    expect(home.expenseCents, 2000);
    expect(home.balanceCents, 98000);
    expect(home.budgetCents, 70000);
    expect(summary.expenseCents, 2000);
    expect(analysis.expenseTotal, 2000);
    expect(analysis.incomeTotal, 0);
    expect(analysis.monthTransactions.map((item) => item.id), ['personal']);
    expect(
      visibleTransactions.map((item) => item.id).toSet(),
      {'personal', 'invoice'},
    );
  });

  test('储蓄目标高于月收入时预算最低为零', () {
    const profile = UserProfile(
      name: '测试',
      monthlyIncomeCents: 10000,
      fixedExpenseCents: 0,
      savingsGoalCents: 12000,
    );

    expect(profile.monthlyBudgetCents, 0);
  });

  test('流水分类和时间显示模式会按账户设置保存', () async {
    final settings = _MemorySettings({});
    final container = ProviderContainer(overrides: [
      settingsRepositoryProvider.overrideWithValue(settings),
    ]);
    addTearDown(container.dispose);

    expect(
      await container.read(transactionViewModeProvider.future),
      TransactionViewMode.category,
    );
    await container
        .read(transactionViewModeProvider.notifier)
        .setMode(TransactionViewMode.time);

    expect(settings.values['transaction_view_mode'], 'time');
    expect(
      container.read(transactionViewModeProvider).value,
      TransactionViewMode.time,
    );
  });
}

class _MemorySettings implements SettingsRepository {
  _MemorySettings(this.values);

  final Map<String, Object> values;

  @override
  Future<bool> getBool(String key, {bool fallback = false}) async =>
      values[key] as bool? ?? fallback;

  @override
  Future<int?> getInt(String key) async => values[key] as int?;

  @override
  Future<String?> getString(String key) async => values[key] as String?;

  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;

  @override
  Future<void> setInt(String key, int value) async => values[key] = value;

  @override
  Future<void> setString(String key, String value) async => values[key] = value;
}
