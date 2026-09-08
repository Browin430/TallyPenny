import 'package:sqflite/sqflite.dart';

import '../../domain/models/category.dart';
import '../../domain/repositories/category_repository.dart';
import '../dao/mappers.dart';
import '../database/app_database.dart';

class SqfliteCategoryRepository implements CategoryRepository {
  SqfliteCategoryRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<Category>> getAll() async {
    final rows = await _db.raw.query('categories', orderBy: 'sort_order ASC');
    return rows.map(categoryFromMap).toList();
  }

  @override
  Future<Category?> byId(String id) async {
    final rows = await _db.raw.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : categoryFromMap(rows.first);
  }

  @override
  Future<void> upsert(Category category) async {
    await _db.raw.insert(
      'categories',
      categoryToMap(category),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> upsertAll(List<Category> categories) async {
    final batch = _db.raw.batch();
    for (final c in categories) {
      batch.insert(
        'categories',
        categoryToMap(c),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> setHidden(String id, bool hidden) async {
    await _db.raw.update(
      'categories',
      {'is_hidden': hidden ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
