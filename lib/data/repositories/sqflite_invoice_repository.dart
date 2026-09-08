import '../../domain/models/transaction.dart';
import '../../domain/repositories/invoice_repository.dart';
import '../dao/mappers.dart';
import '../database/app_database.dart';

class SqfliteInvoiceRepository implements InvoiceRepository {
  SqfliteInvoiceRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> insert(InvoiceDocument document) =>
      _db.raw.insert('invoice_documents', invoiceToMap(document));

  @override
  Future<void> update(InvoiceDocument document) => _db.raw.update(
        'invoice_documents',
        invoiceToMap(document),
        where: 'id = ?',
        whereArgs: [document.id],
      );

  @override
  Future<void> delete(String id) => _db.raw.delete(
        'invoice_documents',
        where: 'id = ?',
        whereArgs: [id],
      );

  @override
  Future<List<InvoiceDocument>> getAll() async {
    final rows = await _db.raw.query(
      'invoice_documents',
      orderBy: 'created_at DESC',
    );
    return rows.map(invoiceFromMap).toList();
  }

  @override
  Future<List<InvoiceDocument>> forTransaction(String transactionId) async {
    final rows = await _db.raw.query(
      'invoice_documents',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
      orderBy: 'created_at DESC',
    );
    return rows.map(invoiceFromMap).toList();
  }
}
