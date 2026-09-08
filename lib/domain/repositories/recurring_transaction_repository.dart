import '../models/recurring_transaction.dart';

abstract class RecurringTransactionRepository {
  Future<List<RecurringTransaction>> getAll();
  Future<void> upsert(RecurringTransaction recurring);
  Future<void> delete(String id);
  Future<void> clearAll();
}
