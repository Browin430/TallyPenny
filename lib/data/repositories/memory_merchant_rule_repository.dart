import '../../domain/models/merchant_rule.dart';
import '../../domain/repositories/merchant_rule_repository.dart';

class MemoryMerchantRuleRepository implements MerchantRuleRepository {
  final List<MerchantRule> _items = [];

  @override
  Future<List<MerchantRule>> getAll() async {
    final result = List<MerchantRule>.of(_items)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  @override
  Future<void> upsert(MerchantRule rule) async {
    final index = _items.indexWhere((item) => item.id == rule.id);
    if (index < 0) {
      _items.add(rule);
    } else {
      _items[index] = rule;
    }
  }

  @override
  Future<void> delete(String id) async =>
      _items.removeWhere((item) => item.id == id);

  @override
  Future<void> clearAll() async => _items.clear();
}
