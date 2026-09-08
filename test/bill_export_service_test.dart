import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowmoney/domain/models/category.dart';
import 'package:flowmoney/domain/models/enums.dart';
import 'package:flowmoney/domain/models/transaction.dart';
import 'package:flowmoney/services/bill_export_service.dart';

void main() {
  const categories = <String, Category>{
    'food': Category(
      id: 'food',
      name: '餐饮',
      iconCode: 'food',
      colorValue: 0xFF000000,
      type: TransactionType.expense,
    ),
  };
  final transactionTime = DateTime(2026, 8, 28, 20, 26, 8);
  final transaction = TransactionEntity(
    id: 'tx-00000000000000000001',
    userId: 'local',
    type: TransactionType.expense,
    amountCents: 1330,
    currency: 'CNY',
    categoryId: 'food',
    merchant: '滴滴出行',
    description: '特惠快车打车',
    transactionTime: transactionTime,
    createdAt: transactionTime,
    updatedAt: transactionTime,
    sourceType: SourceType.imported,
    confidence: 1,
    status: TxStatus.confirmed,
    paymentMethod: PaymentMethod.wechat,
  );

  test('导出行结构与微信账单样例一致', () {
    final rows = BillExportService.buildRows(
      transactions: [transaction],
      categories: categories,
      username: 'Browin',
      exportedAt: DateTime(2026, 8, 29, 0, 43, 32),
    );

    expect(rows, hasLength(19));
    expect(rows.every((row) => row.length == 11), isTrue);
    expect(rows[0][0], '智账账单明细');
    expect(rows[1][0], '智账账户：[Browin]');
    expect(
      rows[2][0],
      '起始时间：[2026-08-28 20:26:08] 终止时间：[2026-08-28 20:26:08]',
    );
    expect(rows[17], [
      '交易时间',
      '交易类型',
      '交易对方',
      '商品',
      '收/支',
      '金额(元)',
      '支付方式',
      '当前状态',
      '交易单号',
      '商户单号',
      '备注',
    ]);
    expect(rows[18][1], '餐饮');
    expect(rows[18][4], '支出');
    expect(rows[18][5], '13.30');
  });

  test('XLSX 中日期金额为数值且长交易单号保持文本', () {
    final bytes = BillExportService.buildWorkbookBytes(
      transactions: [transaction],
      categories: categories,
      username: 'Browin',
      exportedAt: DateTime(2026, 8, 29, 0, 43, 32),
    );
    final workbook = Excel.decodeBytes(bytes);
    final sheet = workbook['Sheet1'];

    expect(
      sheet.cell(CellIndex.indexByString('A1')).value,
      TextCellValue('智账账单明细'),
    );
    expect(sheet.cell(CellIndex.indexByString('A6')).value, isNull);
    expect(
      sheet.cell(CellIndex.indexByString('A19')).value,
      DateTimeCellValue.fromDateTime(transactionTime),
    );
    expect(
      sheet.cell(CellIndex.indexByString('F19')).value,
      const DoubleCellValue(13.3),
    );
    expect(
      sheet.cell(CellIndex.indexByString('I19')).value,
      TextCellValue('tx-00000000000000000001'),
    );
  });

  test('回收站账单不会导出', () {
    final rows = BillExportService.buildRows(
      transactions: [transaction.copyWith(isDeleted: true)],
      categories: categories,
      username: 'Browin',
      exportedAt: DateTime(2026, 8, 29),
    );

    expect(rows, hasLength(BillExportService.dataStartRowIndex));
    expect(rows[6][0], '共0笔记录');
  });
}
