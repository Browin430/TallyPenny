/// 数据库 Schema v1 —— 一次性建全所有核心表，后续阶段不再改表。
/// 金额一律为分（INTEGER）；时间为毫秒时间戳（INTEGER）；布尔为 0/1。
class DbSchema {
  const DbSchema._();

  static const name = 'flowmoney.db';
  static const version = 4;

  static const createUserTable = '''
    CREATE TABLE users (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      avatar TEXT,
      currency TEXT NOT NULL DEFAULT 'CNY',
      created_at INTEGER NOT NULL
    )
  ''';

  static const createCategoriesTable = '''
    CREATE TABLE categories (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      icon TEXT NOT NULL,
      color INTEGER NOT NULL,
      type TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0,
      is_system INTEGER NOT NULL DEFAULT 0,
      is_hidden INTEGER NOT NULL DEFAULT 0
    )
  ''';

  static const createTransactionsTable = '''
    CREATE TABLE transactions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      type TEXT NOT NULL,
      amount INTEGER NOT NULL,
      currency TEXT NOT NULL DEFAULT 'CNY',
      category_id TEXT,
      subcategory TEXT,
      merchant TEXT,
      description TEXT,
      transaction_time INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      source_type TEXT NOT NULL,
      confidence REAL NOT NULL DEFAULT 1.0,
      status TEXT NOT NULL,
      is_recurring INTEGER NOT NULL DEFAULT 0,
      recurring_transaction_id TEXT,
      payment_method TEXT,
      note TEXT,
      invoice_required INTEGER NOT NULL DEFAULT 0,
      invoice_issued INTEGER NOT NULL DEFAULT 0,
      invoice_waived INTEGER NOT NULL DEFAULT 0,
      reimbursed INTEGER NOT NULL DEFAULT 0,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      deleted_at INTEGER
    )
  ''';

  static const createTransactionSourcesTable = '''
    CREATE TABLE transaction_sources (
      id TEXT PRIMARY KEY,
      transaction_id TEXT NOT NULL,
      source_type TEXT NOT NULL,
      raw_text TEXT,
      image_reference TEXT,
      ocr_result TEXT,
      ai_parse_result TEXT,
      created_at INTEGER NOT NULL
    )
  ''';

  static const createRecurringTransactionsTable = '''
    CREATE TABLE recurring_transactions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      title TEXT NOT NULL,
      amount INTEGER NOT NULL,
      type TEXT NOT NULL,
      category_id TEXT,
      merchant TEXT,
      description TEXT,
      payment_method TEXT,
      frequency TEXT NOT NULL,
      days_of_week TEXT,
      day_of_month INTEGER,
      time_of_day TEXT,
      start_date INTEGER NOT NULL,
      end_date INTEGER,
      enabled INTEGER NOT NULL DEFAULT 1,
      last_run_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''';

  static const createInvoiceDocumentsTable = '''
    CREATE TABLE invoice_documents (
      id TEXT PRIMARY KEY,
      transaction_id TEXT,
      stored_path TEXT NOT NULL,
      original_name TEXT NOT NULL,
      file_type TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )
  ''';

  static const createBudgetsTable = '''
    CREATE TABLE budgets (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      category_id TEXT,
      amount INTEGER NOT NULL,
      period TEXT NOT NULL DEFAULT 'monthly',
      enabled INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL
    )
  ''';

  static const createFinancialProfilesTable = '''
    CREATE TABLE financial_profiles (
      user_id TEXT PRIMARY KEY,
      monthly_income INTEGER,
      fixed_expense INTEGER,
      monthly_budget INTEGER,
      savings_goal INTEGER,
      assets INTEGER NOT NULL DEFAULT 0,
      liabilities INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL
    )
  ''';

  static const createFinancialGoalsTable = '''
    CREATE TABLE financial_goals (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      title TEXT NOT NULL,
      target_amount INTEGER NOT NULL,
      saved_amount INTEGER NOT NULL DEFAULT 0,
      target_date INTEGER,
      created_at INTEGER NOT NULL
    )
  ''';

  static const createAiInsightsTable = '''
    CREATE TABLE ai_insights (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      payload TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      is_read INTEGER NOT NULL DEFAULT 0
    )
  ''';

  static const createDuplicateCandidatesTable = '''
    CREATE TABLE duplicate_candidates (
      id TEXT PRIMARY KEY,
      existing_transaction_id TEXT,
      kept_transaction_id TEXT,
      score REAL NOT NULL,
      reasons TEXT NOT NULL,
      status TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      resolved_at INTEGER
    )
  ''';

  static const createUserMerchantRulesTable = '''
    CREATE TABLE user_merchant_rules (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      merchant_pattern TEXT NOT NULL,
      preferred_category TEXT NOT NULL,
      note TEXT,
      confidence REAL NOT NULL DEFAULT 0.5,
      hit_count INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''';

  static const indexes = [
    'CREATE INDEX idx_tx_time ON transactions(transaction_time)',
    'CREATE INDEX idx_tx_category ON transactions(category_id)',
    'CREATE INDEX idx_tx_user_time ON transactions(user_id, transaction_time)',
    'CREATE INDEX idx_src_tx ON transaction_sources(transaction_id)',
    'CREATE INDEX idx_dup_existing ON duplicate_candidates(existing_transaction_id)',
    'CREATE INDEX idx_invoice_tx ON invoice_documents(transaction_id)',
    'CREATE UNIQUE INDEX idx_merchant_rules_pattern ON user_merchant_rules(merchant_pattern)',
  ];

  static const allTables = [
    createUserTable,
    createCategoriesTable,
    createTransactionsTable,
    createTransactionSourcesTable,
    createRecurringTransactionsTable,
    createInvoiceDocumentsTable,
    createBudgetsTable,
    createFinancialProfilesTable,
    createFinancialGoalsTable,
    createAiInsightsTable,
    createDuplicateCandidatesTable,
    createUserMerchantRulesTable,
  ];
}
