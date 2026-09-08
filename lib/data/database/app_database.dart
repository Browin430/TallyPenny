import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'db_schema.dart';

/// SQLite 连接管理。Web 平台返回 null（改用内存仓库实现）。
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  /// 原始连接（data 层 DAO 使用）。
  Database get raw => _db;

  static Future<AppDatabase> open({String fileName = DbSchema.name}) async {
    assert(!kIsWeb, 'Web 平台请使用内存仓库');
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, fileName),
      version: DbSchema.version,
      singleInstance: false,
      onCreate: (db, version) async {
        for (final ddl in DbSchema.allTables) {
          await db.execute(ddl);
        }
        for (final idx in DbSchema.indexes) {
          await db.execute(idx);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE transactions ADD COLUMN invoice_required INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE transactions ADD COLUMN invoice_issued INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE transactions ADD COLUMN reimbursed INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(DbSchema.createInvoiceDocumentsTable);
          await db.execute(
            'CREATE INDEX idx_invoice_tx ON invoice_documents(transaction_id)',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE transactions ADD COLUMN invoice_waived INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE transactions ADD COLUMN deleted_at INTEGER',
          );
          // 旧版本的软删除记录没有删除时间；升级时从最后更新时间起保留 24 小时。
          await db.execute(
            'UPDATE transactions SET deleted_at = updated_at WHERE is_deleted = 1 AND deleted_at IS NULL',
          );
        }
        if (oldVersion < 4) {
          // 商户个性化：v1 起就有 user_merchant_rules 表但从未写入，无存量数据。
          await db.execute('ALTER TABLE user_merchant_rules ADD COLUMN note TEXT');
          await db.execute(
            'CREATE UNIQUE INDEX idx_merchant_rules_pattern ON user_merchant_rules(merchant_pattern)',
          );
        }
      },
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
    return AppDatabase._(db);
  }

  /// 升级账户系统前的默认数据库是否已有真实内容。
  static Future<bool> legacyHasData() async {
    if (!supportsSqlite) return false;
    final path = p.join(await getDatabasesPath(), DbSchema.name);
    if (!await databaseExists(path)) return false;
    Database? db;
    try {
      db = await openDatabase(path, readOnly: true, singleInstance: false);
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='transactions'",
      );
      if (tables.isEmpty) return false;
      final count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM transactions'),
          ) ??
          0;
      return count > 0;
    } on Object {
      return false;
    } finally {
      await db?.close();
    }
  }

  /// 直接注入已有连接（测试用）。
  factory AppDatabase.forTesting(Database db) {
    return AppDatabase._(db);
  }

  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) =>
      _db.transaction(action);

  /// 导出整库到 JSON（数据导出 / 备份用，Phase 10 完善）。
  Future<Map<String, List<Map<String, Object?>>>> exportAll() async {
    final result = <String, List<Map<String, Object?>>>{};
    for (final table in const [
      'categories',
      'transactions',
      'transaction_sources',
      'duplicate_candidates',
      'recurring_transactions',
      'invoice_documents',
      'budgets',
    ]) {
      result[table] = await _db.query(table);
    }
    return result;
  }

  Future<void> close() => _db.close();
}

/// 平台能力检查：仅 iOS / Android 使用 SQLite。
bool get supportsSqlite =>
    !kIsWeb && (Platform.isIOS || Platform.isAndroid || Platform.isMacOS);
