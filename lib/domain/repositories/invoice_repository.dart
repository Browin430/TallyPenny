import '../models/transaction.dart';

abstract class InvoiceRepository {
  Future<void> insert(InvoiceDocument document);

  Future<void> update(InvoiceDocument document);

  Future<void> delete(String id);

  Future<List<InvoiceDocument>> getAll();

  Future<List<InvoiceDocument>> forTransaction(String transactionId);
}
