import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/app_date_utils.dart';
import '../core/utils/settlement_policy.dart';
import '../data/services/remote_ai_services.dart';
import '../domain/models/ai_insight.dart';
import '../domain/models/local_account.dart';
import '../domain/models/category.dart';
import '../domain/models/enums.dart';
import '../domain/models/merchant_rule.dart';
import '../domain/models/recurring_transaction.dart';
import '../domain/models/transaction.dart';
import '../domain/pipeline/transaction_pipeline.dart';
import '../domain/repositories/category_repository.dart';
import '../domain/repositories/invoice_repository.dart';
import '../domain/repositories/merchant_rule_repository.dart';
import '../domain/repositories/recurring_transaction_repository.dart';
import '../domain/repositories/settings_repository.dart';
import '../domain/repositories/transaction_repository.dart';
import '../domain/services/ai_services.dart';
import '../domain/services/financial_advisor_service.dart';
import '../services/duplicate_detection_service.dart';
import '../services/analysis_pin_service.dart';
import '../services/insights_service.dart';
import '../services/invoice_file_storage.dart';
import '../services/monthly_fixed_expense_detector.dart';
import '../services/pending_ai_job_service.dart';
import '../services/recurring_processor.dart';
import '../services/seed_data_service.dart';

// =====================================================================
// 可替换实现（main 中 override：sqflite / 内存）
// =====================================================================

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => throw UnimplementedError('在 main 中 override'),
);

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => throw UnimplementedError('在 main 中 override'),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => throw UnimplementedError('在 main 中 override'),
);

final recurringTransactionRepositoryProvider =
    Provider<RecurringTransactionRepository>(
  (ref) => throw UnimplementedError('在 main 中 override'),
);

final invoiceRepositoryProvider = Provider<InvoiceRepository>(
  (ref) => throw UnimplementedError('在 main 中 override'),
);

final merchantRuleRepositoryProvider = Provider<MerchantRuleRepository>(
  (ref) => throw UnimplementedError('在 main 中 override'),
);

final invoiceFileStorageProvider =
    Provider<InvoiceFileStorage>((ref) => const InvoiceFileStorage());

final currentAccountProvider = Provider<LocalAccount>(
  (ref) => LocalAccount(
    id: 'local-test',
    username: UserProfile.fallback.name,
    passwordSalt: '',
    passwordHash: '',
    databaseName: 'flowmoney.db',
    settingsPrefix: '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  ),
);

final logoutActionProvider = Provider<Future<void> Function()>(
  (ref) => throw UnimplementedError('在账户启动器中 override'),
);

// =====================================================================
// AI / OCR / 语音服务：按配置的后端地址选择远程千问实现，未配置时为 Mock。
// （TODO(phase) 注释见 MockAiServices / RemoteAiServices）
// =====================================================================

/// AI 后端地址：默认使用公网服务；旧版局域网地址会在升级时自动迁移。
final aiBaseUrlProvider = FutureProvider<String>((ref) async {
  final settings = ref.watch(settingsRepositoryProvider);
  final saved = await settings.getString(RemoteAiServices.prefKey) ?? '';
  if (saved.trim().isEmpty || RemoteAiServices.isLegacyBaseUrl(saved)) {
    await settings.setString(
      RemoteAiServices.prefKey,
      RemoteAiServices.defaultBaseUrl,
    );
    return RemoteAiServices.defaultBaseUrl;
  }
  return RemoteAiServices.normalizeBaseUrl(saved);
});

final speechServiceProvider =
    Provider<SpeechRecognitionService>((ref) => RemoteAiServices.speech());

final ocrServiceProvider = Provider<OCRService>((ref) {
  final baseUrl = ref.watch(aiBaseUrlProvider).asData?.value;
  return RemoteAiServices.ocr(baseUrl: baseUrl);
});

final parserProvider = Provider<AITransactionParser>((ref) {
  final baseUrl = ref.watch(aiBaseUrlProvider).asData?.value;
  return RemoteAiServices.parser(baseUrl: baseUrl);
});

final advisorProvider = Provider<FinancialAdvisorService>((ref) {
  final baseUrl = ref.watch(aiBaseUrlProvider).asData?.value;
  return RemoteAiServices.advisor(baseUrl: baseUrl);
});

/// 语音入口（真实录音 → 后端 ASR）。未配置后端时为 null（页面走演示模式）。
final voiceEntryProvider = Provider<RemoteVoiceEntryService?>((ref) {
  final baseUrl = ref.watch(aiBaseUrlProvider).asData?.value;
  return RemoteAiServices.voiceEntry(baseUrl: baseUrl);
});

/// 截图入口（真实选图 → 后端 OCR + 多笔解析）。未配置后端时为 null（演示模式）。
final screenshotEntryProvider = Provider<RemoteScreenshotEntryService?>((ref) {
  final baseUrl = ref.watch(aiBaseUrlProvider).asData?.value;
  return RemoteAiServices.screenshotEntry(baseUrl: baseUrl);
});

final backgroundJobServiceProvider =
    Provider<RemoteBackgroundJobService?>((ref) {
  final baseUrl = ref.watch(aiBaseUrlProvider).asData?.value;
  return RemoteAiServices.backgroundJobs(baseUrl: baseUrl);
});

final insightsProvider =
    Provider<InsightsService>((ref) => const InsightsService());

final seedServiceProvider = Provider<SeedDataService>((ref) => SeedDataService(
      transactionRepository: ref.watch(transactionRepositoryProvider),
      categoryRepository: ref.watch(categoryRepositoryProvider),
      settingsRepository: ref.watch(settingsRepositoryProvider),
    ));

final pipelineProvider = Provider<TransactionPipeline>((ref) {
  final repo = ref.watch(transactionRepositoryProvider);
  return TransactionPipeline(
    transactionRepository: repo,
    duplicateDetection: DuplicateDetectionService(repo),
    merchantRules: ref.watch(merchantRuleRepositoryProvider),
  );
});

final pendingAiJobServiceProvider = Provider<PendingAiJobService>((ref) {
  return PendingAiJobService(
    settingsRepository: ref.watch(settingsRepositoryProvider),
    transactionRepository: ref.watch(transactionRepositoryProvider),
    pipeline: ref.watch(pipelineProvider),
  );
});

// =====================================================================
// 数据版本号：任何写操作 +1，读模型自动重算
// =====================================================================

final dataVersionProvider = StateProvider<int>((ref) => 0);

/// 周期规则列表变化版本号；与普通流水分开，避免无关页面重复查询。
final recurringVersionProvider = StateProvider<int>((ref) => 0);

final recurringProcessorProvider = Provider<RecurringProcessor>((ref) {
  return RecurringProcessor(
    recurringRepository: ref.watch(recurringTransactionRepositoryProvider),
    transactionRepository: ref.watch(transactionRepositoryProvider),
  );
});

final recurringTransactionsProvider =
    FutureProvider<List<RecurringTransaction>>((ref) async {
  ref.watch(recurringVersionProvider);
  return ref.watch(recurringTransactionRepositoryProvider).getAll();
});

// =====================================================================
// 商户个性化
// =====================================================================

final merchantRuleVersionProvider = StateProvider<int>((ref) => 0);

final merchantRulesProvider = FutureProvider<List<MerchantRule>>((ref) async {
  ref.watch(merchantRuleVersionProvider);
  return ref.watch(merchantRuleRepositoryProvider).getAll();
});

class AnalysisPinNotifier extends AsyncNotifier<bool> {
  AnalysisPinService get _service =>
      AnalysisPinService(ref.read(settingsRepositoryProvider));

  @override
  Future<bool> build() => _service.isConfigured;

  Future<void> setPin(String pin) async {
    await _service.setPin(pin);
    state = const AsyncData(true);
  }

  Future<bool> verify(String pin) => _service.verify(pin);

  Future<void> clear() async {
    await _service.clear();
    state = const AsyncData(false);
  }
}

final analysisPinProvider =
    AsyncNotifierProvider<AnalysisPinNotifier, bool>(AnalysisPinNotifier.new);

class InvoiceManagementNotifier extends AsyncNotifier<bool> {
  static const settingsKey = 'invoice_management_enabled';

  @override
  Future<bool> build() => ref
      .watch(settingsRepositoryProvider)
      .getBool(settingsKey, fallback: false);

  Future<void> setEnabled(bool enabled) async {
    await ref.read(settingsRepositoryProvider).setBool(settingsKey, enabled);
    state = AsyncData(enabled);
  }
}

final invoiceManagementProvider =
    AsyncNotifierProvider<InvoiceManagementNotifier, bool>(
  InvoiceManagementNotifier.new,
);

final invoiceVersionProvider = StateProvider<int>((ref) => 0);

final invoiceDocumentsProvider =
    FutureProvider<List<InvoiceDocument>>((ref) async {
  ref.watch(invoiceVersionProvider);
  return ref.watch(invoiceRepositoryProvider).getAll();
});

final transactionInvoicesProvider =
    FutureProvider.family<List<InvoiceDocument>, String>((ref, transactionId) {
  ref.watch(invoiceVersionProvider);
  return ref.watch(invoiceRepositoryProvider).forTransaction(transactionId);
});

// =====================================================================
// 主题
// =====================================================================

/// 初始主题（main 中根据持久化设置 override）。
final initialThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.system);

class ThemeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(initialThemeModeProvider);

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await ref
        .read(settingsRepositoryProvider)
        .setString('theme_mode', mode.name);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeNotifier, ThemeMode>(ThemeNotifier.new);

// =====================================================================
// 分类
// =====================================================================

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.watch(categoryRepositoryProvider).getAll();
});

final categoryMapProvider = FutureProvider<Map<String, Category>>((ref) async {
  final list = await ref.watch(categoriesProvider.future);
  return {for (final c in list) c.id: c};
});

/// 参与展示的分类（隐藏的不算）。
final visibleCategoriesProvider = FutureProvider<List<Category>>((ref) async {
  final list = await ref.watch(categoriesProvider.future);
  return list.where((c) => !c.isHidden).toList();
});

// =====================================================================
// 用户资料
// =====================================================================

class UserProfile {
  const UserProfile({
    required this.name,
    required this.monthlyIncomeCents,
    required this.fixedExpenseCents,
    required this.savingsGoalCents,
  });

  final String name;
  final int monthlyIncomeCents;
  final int fixedExpenseCents;
  final int savingsGoalCents;

  /// 本月可支配预算始终由收入减去储蓄目标得到，不再读取旧版隐藏预算。
  int get monthlyBudgetCents {
    final budget = monthlyIncomeCents - savingsGoalCents;
    return budget > 0 ? budget : 0;
  }

  static const fallback = UserProfile(
    name: DefaultProfile.userName,
    monthlyIncomeCents: DefaultProfile.monthlyIncomeCents,
    fixedExpenseCents: DefaultProfile.fixedExpenseCents,
    savingsGoalCents: DefaultProfile.savingsGoalCents,
  );
}

class ProfileNotifier extends AsyncNotifier<UserProfile> {
  @override
  Future<UserProfile> build() async {
    final s = ref.watch(settingsRepositoryProvider);
    final account = ref.watch(currentAccountProvider);
    final name = await s.getString('profile_name');
    final income = await s.getInt('profile_income');
    final fixed = await s.getInt('profile_fixed');
    final savings = await s.getInt('profile_savings');
    return UserProfile(
      name: name ?? account.username,
      monthlyIncomeCents: income ?? UserProfile.fallback.monthlyIncomeCents,
      fixedExpenseCents: fixed ?? UserProfile.fallback.fixedExpenseCents,
      savingsGoalCents: savings ?? UserProfile.fallback.savingsGoalCents,
    );
  }

  Future<void> save(UserProfile profile) async {
    final s = ref.read(settingsRepositoryProvider);
    await s.setString('profile_name', profile.name);
    await s.setInt('profile_income', profile.monthlyIncomeCents);
    await s.setInt('profile_fixed', profile.fixedExpenseCents);
    await s.setInt('profile_savings', profile.savingsGoalCents);
    state = AsyncData(profile);
  }
}

final profileProvider =
    AsyncNotifierProvider<ProfileNotifier, UserProfile>(ProfileNotifier.new);

// =====================================================================
// 首页读模型
// =====================================================================

class HomeData {
  const HomeData({
    required this.month,
    required this.incomeCents,
    required this.expenseCents,
    required this.prevIncomeCents,
    required this.prevExpenseCents,
    required this.variableExpenseCents,
    required this.prevVariableSamePeriodCents,
    required this.budgetCents,
    required this.today,
    required this.todayExpenseCents,
    required this.todayIncomeCents,
    required this.insights,
  });

  final DateTime month;
  final int incomeCents;
  final int expenseCents;
  final int prevIncomeCents;

  /// 上月整月支出（参考值）。
  final int prevExpenseCents;

  /// 本月至今支出中剔除「每月固定一次消费」（房租/水电等）后的可变部分。
  final int variableExpenseCents;

  /// 上月同期（对齐到本月第 N 天，上月天数不足时按日均外推）的可变支出。
  final int prevVariableSamePeriodCents;
  final int budgetCents;
  final List<TransactionEntity> today;
  final int todayExpenseCents;
  final int todayIncomeCents;
  final List<AiInsight> insights;

  int get balanceCents => incomeCents - expenseCents;

  double get budgetRatio =>
      budgetCents > 0 ? (expenseCents / budgetCents).clamp(0.0, 1.0) : 0;

  /// 可变支出同期环比百分比（月初大额房租不干扰口径）；上月无数据返回 null。
  double? get expenseMoMPct => prevVariableSamePeriodCents <= 0
      ? null
      : (variableExpenseCents - prevVariableSamePeriodCents) /
          prevVariableSamePeriodCents *
          100;
}

final homeDataProvider = FutureProvider<HomeData>((ref) async {
  ref.watch(dataVersionProvider);
  final repo = ref.watch(transactionRepositoryProvider);
  final profile = await ref.watch(profileProvider.future);

  final now = DateTime.now();
  final month = DateTime(now.year, now.month, 1);
  final prev = AppDate.addMonths(month, -1);
  final all = await repo.getAll();
  final settledAll = SettlementPolicy.personalOccurred(all, now);

  int sum(Iterable<TransactionEntity> txs, bool income) => txs
      .where((t) => t.isIncome == income)
      .fold(0, (s, t) => s + t.amountCents);

  List<TransactionEntity> between(DateTime s, DateTime e) => settledAll
      .where((t) =>
          !t.transactionTime.isBefore(s) && t.transactionTime.isBefore(e))
      .toList();

  final (mStart, mEnd) = AppDate.monthRange(month);
  final (pStart, pEnd) = AppDate.monthRange(prev);
  final monthTx = between(mStart, mEnd);
  final prevTx = between(pStart, pEnd);

  final todayStart = DateTime(now.year, now.month, now.day);
  final today = monthTx
      .where((t) => !t.transactionTime.isBefore(todayStart))
      .toList()
    ..sort((a, b) => b.transactionTime.compareTo(a.transactionTime));

  final insights = ref.watch(insightsProvider).insightsForMonth(
        month: month,
        all: settledAll,
        monthlyBudgetCents: profile.monthlyBudgetCents,
      );

  // 固定月度消费（房租/水电）：同期环比口径下两侧剔除。
  final fixedItems = MonthlyFixedExpenseDetector.detect(
    settledExpenses: settledAll.where((t) => !t.isIncome),
    anchorMonth: month,
  );
  final fixedKeys = fixedItems.map((f) => f.key).toSet();
  bool isFixed(TransactionEntity t) =>
      fixedKeys.contains(MonthlyFixedExpenseDetector.keyOf(t));

  // 上月同期窗口：对齐到本月第 N 天；上月不足 N 天时按整月日均外推。
  final prevDaysInMonth = DateTime(prev.year, prev.month + 1, 0).day;
  final n = now.day;
  final prevAlignedEnd = DateTime(prev.year, prev.month, n + 1);
  final prevTxAligned = n <= prevDaysInMonth
      ? prevTx
          .where((t) => t.transactionTime.isBefore(prevAlignedEnd))
          .toList()
      : prevTx;
  final prevVariableFull = sum(prevTx.where((t) => !isFixed(t)), false);
  final prevVariableSamePeriod = n <= prevDaysInMonth
      ? sum(prevTxAligned.where((t) => !isFixed(t)), false)
      : (prevVariableFull / prevDaysInMonth * n).round();

  return HomeData(
    month: month,
    incomeCents: profile.monthlyIncomeCents + sum(monthTx, true),
    expenseCents: sum(monthTx, false),
    prevIncomeCents:
        profile.monthlyIncomeCents + sum(prevTxAligned, true),
    prevExpenseCents: sum(prevTx, false),
    variableExpenseCents: sum(monthTx.where((t) => !isFixed(t)), false),
    prevVariableSamePeriodCents: prevVariableSamePeriod,
    budgetCents: profile.monthlyBudgetCents,
    today: today,
    todayExpenseCents: sum(today, false),
    todayIncomeCents: sum(today, true),
    insights: insights,
  );
});

// =====================================================================
// 流水页读模型
// =====================================================================

enum TransactionViewMode { category, time }

class TransactionViewModeNotifier extends AsyncNotifier<TransactionViewMode> {
  static const settingsKey = 'transaction_view_mode';

  @override
  Future<TransactionViewMode> build() async {
    final saved = await ref.watch(settingsRepositoryProvider).getString(
          settingsKey,
        );
    return TransactionViewMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => TransactionViewMode.category,
    );
  }

  Future<void> setMode(TransactionViewMode mode) async {
    await ref.read(settingsRepositoryProvider).setString(
          settingsKey,
          mode.name,
        );
    state = AsyncData(mode);
  }
}

final transactionViewModeProvider =
    AsyncNotifierProvider<TransactionViewModeNotifier, TransactionViewMode>(
  TransactionViewModeNotifier.new,
);

class TxFilter {
  const TxFilter({
    required this.month,
    this.search = '',
    this.type,
    this.categoryIds = const {},
  });

  final DateTime month;
  final String search;
  final TransactionType? type;
  final Set<String> categoryIds;

  bool get isActive =>
      search.isNotEmpty || type != null || categoryIds.isNotEmpty;

  TxFilter copyWith({
    DateTime? month,
    String? search,
    TransactionType? type,
    Set<String>? categoryIds,
    bool clearType = false,
    bool clearCategories = false,
  }) =>
      TxFilter(
        month: month ?? this.month,
        search: search ?? this.search,
        type: clearType ? null : (type ?? this.type),
        categoryIds:
            clearCategories ? const {} : (categoryIds ?? this.categoryIds),
      );
}

class TxFilterNotifier extends Notifier<TxFilter> {
  @override
  TxFilter build() {
    final now = DateTime.now();
    return TxFilter(month: DateTime(now.year, now.month, 1));
  }

  void setMonth(DateTime month) =>
      state = state.copyWith(month: DateTime(month.year, month.month, 1));

  void setSearch(String search) => state = state.copyWith(search: search);

  void setType(TransactionType? type) =>
      state = state.copyWith(type: type, clearType: type == null);

  void setCategories(Set<String> ids) => state = state.copyWith(
        categoryIds: ids,
        clearCategories: ids.isEmpty,
      );

  void reset() {
    final now = DateTime.now();
    state = TxFilter(month: DateTime(now.year, now.month, 1));
  }
}

final txFilterProvider =
    NotifierProvider<TxFilterNotifier, TxFilter>(TxFilterNotifier.new);

class MonthSummary {
  const MonthSummary({required this.incomeCents, required this.expenseCents});

  final int incomeCents;
  final int expenseCents;
}

final monthSummaryProvider =
    FutureProvider.family<MonthSummary, DateTime>((ref, month) async {
  ref.watch(dataVersionProvider);
  final repo = ref.watch(transactionRepositoryProvider);
  final (s, e) = AppDate.monthRange(month);
  final txs = await repo.getByRange(s, e);
  final now = DateTime.now();
  var income = 0;
  var expense = 0;
  for (final t in txs) {
    if (!SettlementPolicy.countsTowardPersonalFinance(t, now)) continue;
    t.isIncome ? income += t.amountCents : expense += t.amountCents;
  }
  return MonthSummary(incomeCents: income, expenseCents: expense);
});

final filteredTxProvider = FutureProvider<List<TransactionEntity>>((ref) async {
  final filter = ref.watch(txFilterProvider);
  ref.watch(dataVersionProvider);
  final repo = ref.watch(transactionRepositoryProvider);
  final (s, e) = AppDate.monthRange(filter.month);
  final transactions = await repo.getByRange(
    s,
    e,
    type: filter.type,
    categoryIds: filter.categoryIds.isEmpty ? null : filter.categoryIds,
    search: filter.search.isEmpty ? null : filter.search,
  );
  // 已报销账单只在“发票与报销”中保留，流水页不再重复展示。
  return transactions.where((transaction) => !transaction.reimbursed).toList();
});

final allTransactionsProvider =
    FutureProvider<List<TransactionEntity>>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.watch(transactionRepositoryProvider).getAll();
});

// =====================================================================
// 分析页读模型
// =====================================================================

class CategorySlice {
  const CategorySlice({required this.category, required this.cents});

  final Category category;
  final int cents;
}

class MonthTrendPoint {
  const MonthTrendPoint(
      {required this.label, required this.income, required this.expense});

  final String label; // "3月"
  final int income;
  final int expense;
}

class AnalysisData {
  const AnalysisData({
    required this.month,
    required this.expenseTotal,
    required this.incomeTotal,
    required this.slices,
    required this.trend,
    required this.monthTransactions,
  });

  final DateTime month;
  final int expenseTotal;
  final int incomeTotal;

  /// 支出分类占比（金额降序）。
  final List<CategorySlice> slices;

  /// 近 6 个月（旧 → 新）。
  final List<MonthTrendPoint> trend;
  final List<TransactionEntity> monthTransactions;
}

final analysisDataProvider =
    FutureProvider.family<AnalysisData, DateTime>((ref, month) async {
  ref.watch(dataVersionProvider);
  final repo = ref.watch(transactionRepositoryProvider);
  final categories = await ref.watch(categoryMapProvider.future);

  final all = await repo.getAll();
  final settledAll = SettlementPolicy.personalOccurred(all, DateTime.now());
  final (mStart, mEnd) = AppDate.monthRange(month);
  final monthTx = settledAll
      .where((t) =>
          !t.transactionTime.isBefore(mStart) &&
          t.transactionTime.isBefore(mEnd))
      .toList()
    ..sort((a, b) => b.transactionTime.compareTo(a.transactionTime));

  final byCategory = <String, int>{};
  var incomeTotal = 0;
  var expenseTotal = 0;
  for (final t in monthTx) {
    if (t.isIncome) {
      incomeTotal += t.amountCents;
      continue;
    }
    expenseTotal += t.amountCents;
    final key = t.categoryId ?? 'other';
    byCategory[key] = (byCategory[key] ?? 0) + t.amountCents;
  }

  final slices = byCategory.entries
      .map((e) => CategorySlice(
            category: categories[e.key] ??
                Category(
                  id: e.key,
                  name: '未知分类',
                  iconCode: 'other',
                  colorValue: 0xFF98A2B3,
                  type: TransactionType.expense,
                ),
            cents: e.value,
          ))
      .toList()
    ..sort((a, b) => b.cents.compareTo(a.cents));

  final trend = <MonthTrendPoint>[];
  for (var i = 5; i >= 0; i--) {
    final m = AppDate.addMonths(month, -i);
    final (s, e) = AppDate.monthRange(m);
    final txs = settledAll.where(
        (t) => !t.transactionTime.isBefore(s) && t.transactionTime.isBefore(e));
    var income = 0;
    var expense = 0;
    for (final t in txs) {
      t.isIncome ? income += t.amountCents : expense += t.amountCents;
    }
    trend.add(MonthTrendPoint(
        label: '${m.month}月', income: income, expense: expense));
  }

  return AnalysisData(
    month: month,
    expenseTotal: expenseTotal,
    incomeTotal: incomeTotal,
    slices: slices,
    trend: trend,
    monthTransactions: monthTx,
  );
});
