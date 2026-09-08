import '../../domain/models/category.dart';
import '../../domain/repositories/category_repository.dart';

class MemoryCategoryRepository implements CategoryRepository {
  final Map<String, Category> _categories = {};

  @override
  Future<List<Category>> getAll() async {
    final list = _categories.values.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  @override
  Future<Category?> byId(String id) async => _categories[id];

  @override
  Future<void> upsert(Category category) async =>
      _categories[category.id] = category;

  @override
  Future<void> upsertAll(List<Category> categories) async {
    for (final c in categories) {
      _categories[c.id] = c;
    }
  }

  @override
  Future<void> setHidden(String id, bool hidden) async {
    final c = _categories[id];
    if (c != null) _categories[id] = c.copyWith(isHidden: hidden);
  }
}
