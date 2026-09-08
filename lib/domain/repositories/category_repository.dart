import '../models/category.dart';

/// 分类仓库抽象。
abstract class CategoryRepository {
  Future<List<Category>> getAll();

  Future<Category?> byId(String id);

  Future<void> upsert(Category category);

  Future<void> setHidden(String id, bool hidden);

  Future<void> upsertAll(List<Category> categories);
}
