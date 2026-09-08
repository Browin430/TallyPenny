import 'package:sqflite/sqflite.dart';

import '../../domain/models/merchant_rule.dart';
import '../../domain/repositories/merchant_rule_repository.dart';
import '../database/app_database.dart';

class SqfliteMerchantRuleRepository implements MerchantRuleRepository {
  SqfliteMerchantRuleRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<MerchantRule>> getAll() async {
    final rows = await _db.raw.query(
      'user_merchant_rules',
      orderBy: 'updated_at DESC',
    );
    return rows.map(_fromMap).toList();
  }

  @override
  Future<void> upsert(MerchantRule rule) async {
    await _db.raw.insert(
      'user_merchant_rules',
      _toMap(rule),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> delete(String id) async => _db.raw.delete(
        'user_merchant_rules',
        where: 'id = ?',
        whereArgs: [id],
      );

  @override
  Future<void> clearAll() async => _db.raw.delete('user_merchant_rules');

  Map<String, Object?> _toMap(MerchantRule item) => {
        'id': item.id,
        'user_id': item.userId,
        'merchant_pattern': item.merchantPattern,
        'preferred_category': item.preferredCategory,
        'note': item.note,
        'confidence': item.confidence,
        'hit_count': item.hitCount,
        'created_at': item.createdAt.millisecondsSinceEpoch,
        'updated_at': item.updatedAt.millisecondsSinceEpoch,
      };

  MerchantRule _fromMap(Map<String, Object?> map) => MerchantRule(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        merchantPattern: map['merchant_pattern'] as String,
        preferredCategory: map['preferred_category'] as String,
        note: map['note'] as String?,
        confidence: (map['confidence'] as num?)?.toDouble() ?? 1,
        hitCount: (map['hit_count'] as int?) ?? 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      );
}
