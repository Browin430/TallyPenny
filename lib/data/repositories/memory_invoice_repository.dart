import '../../domain/models/transaction.dart';
import '../../domain/repositories/invoice_repository.dart';

class MemoryInvoiceRepository implements InvoiceRepository {
  final List<InvoiceDocument> _documents = [];

  @override
  Future<void> insert(InvoiceDocument document) async =>
      _documents.add(document);

  @override
  Future<void> update(InvoiceDocument document) async {
    final index = _documents.indexWhere((item) => item.id == document.id);
    if (index >= 0) _documents[index] = document;
  }

  @override
  Future<void> delete(String id) async =>
      _documents.removeWhere((item) => item.id == id);

  @override
  Future<List<InvoiceDocument>> getAll() async {
    final result = List<InvoiceDocument>.of(_documents)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  @override
  Future<List<InvoiceDocument>> forTransaction(String transactionId) async =>
      (await getAll())
          .where((item) => item.transactionId == transactionId)
          .toList();
}
