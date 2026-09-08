import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'data/database/app_database.dart';
import 'data/repositories/memory_category_repository.dart';
import 'data/repositories/memory_invoice_repository.dart';
import 'data/repositories/memory_merchant_rule_repository.dart';
import 'data/repositories/memory_recurring_transaction_repository.dart';
import 'data/repositories/memory_transaction_repository.dart';
import 'data/repositories/prefs_settings_repository.dart';
import 'data/repositories/sqflite_category_repository.dart';
import 'data/repositories/sqflite_invoice_repository.dart';
import 'data/repositories/sqflite_merchant_rule_repository.dart';
import 'data/repositories/sqflite_recurring_transaction_repository.dart';
import 'data/repositories/sqflite_transaction_repository.dart';
import 'data/services/remote_ai_services.dart';
import 'domain/models/local_account.dart';
import 'domain/pipeline/transaction_pipeline.dart';
import 'domain/repositories/category_repository.dart';
import 'domain/repositories/invoice_repository.dart';
import 'domain/repositories/merchant_rule_repository.dart';
import 'domain/repositories/recurring_transaction_repository.dart';
import 'domain/repositories/transaction_repository.dart';
import 'presentation/auth/auth_page.dart';
import 'services/classification_repair_service.dart';
import 'services/duplicate_detection_service.dart';
import 'services/local_auth_service.dart';
import 'services/pending_ai_job_service.dart';
import 'services/recurring_processor.dart';
import 'services/refund_reconciliation_service.dart';
import 'services/seed_data_service.dart';
import 'state/app_providers.dart';

class FlowMoneyBootstrap extends StatefulWidget {
  const FlowMoneyBootstrap({
    super.key,
    required this.preferences,
    required this.auth,
    required this.initialAccount,
    required this.hasAccounts,
  });

  final SharedPreferences preferences;
  final LocalAuthService auth;
  final LocalAccount? initialAccount;
  final bool hasAccounts;

  @override
  State<FlowMoneyBootstrap> createState() => _FlowMoneyBootstrapState();
}

class _FlowMoneyBootstrapState extends State<FlowMoneyBootstrap> {
  LocalAccount? _account;
  Future<_UserWorkspace>? _workspace;
  _UserWorkspace? _openedWorkspace;
  late bool _hasAccounts;

  @override
  void initState() {
    super.initState();
    _account = widget.initialAccount;
    _hasAccounts = widget.hasAccounts;
    if (_account != null) _workspace = _open(_account!);
  }

  Future<_UserWorkspace> _open(LocalAccount account) async {
    final workspace = await _UserWorkspace.open(
      account,
      widget.preferences,
    );
    _openedWorkspace = workspace;
    return workspace;
  }

  Future<void> _activate(LocalAccount account) async {
    await _openedWorkspace?.close();
    if (!mounted) return;
    setState(() {
      _account = account;
      _hasAccounts = true;
      _workspace = _open(account);
    });
  }

  Future<void> _login(String username, String password) async {
    await _activate(await widget.auth.login(username, password));
  }

  Future<void> _register(String username, String password) async {
    await _activate(await widget.auth.register(username, password));
  }

  Future<void> _logout() async {
    await widget.auth.logout();
    await _openedWorkspace?.close();
    _openedWorkspace = null;
    if (!mounted) return;
    setState(() {
      _account = null;
      _workspace = null;
      _hasAccounts = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    if (account == null) {
      return MaterialApp(
        title: '智账',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.of(FMScheme.light),
        darkTheme: AppTheme.of(FMScheme.dark),
        home: AuthPage(
          hasAccounts: _hasAccounts,
          onLogin: _login,
          onRegister: _register,
        ),
      );
    }

    return FutureBuilder<_UserWorkspace>(
      future: _workspace,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _BootstrapMessage(
            title: '无法打开账户数据',
            action: _logout,
          );
        }
        final workspace = snapshot.data;
        if (workspace == null) {
          return const _BootstrapMessage(title: '正在打开私人账单空间…');
        }
        return ProviderScope(
          key: ValueKey(account.id),
          overrides: [
            transactionRepositoryProvider
                .overrideWithValue(workspace.transactions),
            categoryRepositoryProvider.overrideWithValue(workspace.categories),
            invoiceRepositoryProvider.overrideWithValue(workspace.invoices),
            recurringTransactionRepositoryProvider
                .overrideWithValue(workspace.recurring),
            merchantRuleRepositoryProvider
                .overrideWithValue(workspace.merchantRules),
            settingsRepositoryProvider.overrideWithValue(workspace.settings),
            initialThemeModeProvider.overrideWithValue(workspace.themeMode),
            currentAccountProvider.overrideWithValue(account),
            logoutActionProvider.overrideWithValue(_logout),
          ],
          child: const MoneyApp(),
        );
      },
    );
  }
}

class _UserWorkspace {
  const _UserWorkspace({
    required this.transactions,
    required this.categories,
    required this.invoices,
    required this.recurring,
    required this.merchantRules,
    required this.settings,
    required this.themeMode,
    this.database,
  });

  final TransactionRepository transactions;
  final CategoryRepository categories;
  final InvoiceRepository invoices;
  final RecurringTransactionRepository recurring;
  final MerchantRuleRepository merchantRules;
  final PrefsSettingsRepository settings;
  final ThemeMode themeMode;
  final AppDatabase? database;

  static Future<_UserWorkspace> open(
    LocalAccount account,
    SharedPreferences preferences,
  ) async {
    final settings = PrefsSettingsRepository(
      preferences,
      prefix: account.settingsPrefix,
    );
    final TransactionRepository transactions;
    final CategoryRepository categories;
    final InvoiceRepository invoices;
    final RecurringTransactionRepository recurring;
    final MerchantRuleRepository merchantRules;
    AppDatabase? database;

    if (supportsSqlite) {
      database = await AppDatabase.open(fileName: account.databaseName);
      transactions = SqfliteTransactionRepository(database);
      categories = SqfliteCategoryRepository(database);
      invoices = SqfliteInvoiceRepository(database);
      recurring = SqfliteRecurringTransactionRepository(database);
      merchantRules = SqfliteMerchantRuleRepository(database);
    } else {
      transactions = MemoryTransactionRepository();
      categories = MemoryCategoryRepository();
      invoices = MemoryInvoiceRepository();
      recurring = MemoryRecurringTransactionRepository();
      merchantRules = MemoryMerchantRuleRepository();
    }

    await SeedDataService(
      transactionRepository: transactions,
      categoryRepository: categories,
      settingsRepository: settings,
    ).seedIfNeeded(includeDemo: false);
    await RecurringProcessor(
      recurringRepository: recurring,
      transactionRepository: transactions,
    ).runDue();
    await transactions.purgeDeletedBefore(
      DateTime.now().subtract(const Duration(hours: 24)),
    );
    await ClassificationRepairService(transactions).repairExisting();

    final savedBaseUrl = await settings.getString(RemoteAiServices.prefKey);
    final baseUrl = savedBaseUrl == null ||
            savedBaseUrl.trim().isEmpty ||
            RemoteAiServices.isLegacyBaseUrl(savedBaseUrl)
        ? RemoteAiServices.defaultBaseUrl
        : RemoteAiServices.normalizeBaseUrl(savedBaseUrl);
    final pendingJobs = PendingAiJobService(
      settingsRepository: settings,
      transactionRepository: transactions,
      pipeline: TransactionPipeline(
        transactionRepository: transactions,
        duplicateDetection: DuplicateDetectionService(transactions),
        merchantRules: merchantRules,
      ),
    );
    try {
      await pendingJobs.sync(RemoteBackgroundJobService(baseUrl: baseUrl));
    } on Object {
      // 网络问题不阻断登录；任务仍保留在当前账户的命名空间中。
    }
    await RefundReconciliationService(transactions)
        .reconcileExistingImportedPairs();

    final themeName = await settings.getString('theme_mode');
    final themeMode = ThemeMode.values
        .where((mode) => mode.name == themeName)
        .firstOrNullValue(ThemeMode.system);
    return _UserWorkspace(
      transactions: transactions,
      categories: categories,
      invoices: invoices,
      recurring: recurring,
      merchantRules: merchantRules,
      settings: settings,
      themeMode: themeMode,
      database: database,
    );
  }

  Future<void> close() async => database?.close();
}

class _BootstrapMessage extends StatelessWidget {
  const _BootstrapMessage({required this.title, this.action});
  final String title;
  final Future<void> Function()? action;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.of(FMScheme.light),
        darkTheme: AppTheme.of(FMScheme.dark),
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: 18),
                Text(title),
                if (action != null)
                  TextButton(onPressed: action, child: const Text('返回登录')),
              ],
            ),
          ),
        ),
      );
}

extension on Iterable<ThemeMode> {
  ThemeMode firstOrNullValue(ThemeMode fallback) => isEmpty ? fallback : first;
}
