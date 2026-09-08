import '../../domain/models/recurring_transaction.dart';
import '../../domain/repositories/recurring_transaction_repository.dart';

class MemoryRecurringTransactionRepository
    implements RecurringTransactionRepository {
  final List<RecurringTransaction> _items = [];

  @override
  Future<List<RecurringTransaction>> getAll() async {
    final result = List<RecurringTransaction>.of(_items)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  @override
  Future<void> upsert(RecurringTransaction recurring) async {
    final index = _items.indexWhere((item) => item.id == recurring.id);
    if (index < 0) {
      _items.add(recurring);
    } else {
      _items[index] = recurring;
    }
  }

  @override
  Future<void> delete(String id) async =>
      _items.removeWhere((item) => item.id == id);

  @override
  Future<void> clearAll() async => _items.clear();
}
