import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../core/utils/settlement_policy.dart';
import '../domain/models/category.dart';
import '../domain/models/transaction.dart';

/// 数据导出结果。
class BillExportResult {
  const BillExportResult({
    required this.file,
    required this.fileName,
    required this.totalCount,
  });

  final File file;
  final String fileName;
  final int totalCount;
}

/// 把账单导出为微信支付账单流水格式的 XLSX：
/// 17 行表头块（标题/账户/起止时间/统计/注释，整行合并）+ 分隔线 +
/// 11 列数据（交易时间/交易类型/交易对方/商品/收/支/金额(元)/支付方式/当前状态/交易单号/商户单号/备注）。
class BillExportService {
  static const columnCount = 11;
  static const columnHeaderRowIndex = 17;
  static const dataStartRowIndex = 18;

  /// 纯数据构建（可测）：返回全部行（含表头块与列头），每行恰好 [columnCount] 格。
  static List<List<String>> buildRows({
    required List<TransactionEntity> transactions,
    required Map<String, Category> categories,
    required String username,
    required DateTime exportedAt,
  }) {
    final sorted = transactions.where((item) => !item.isDeleted).toList()
      ..sort((a, b) => b.transactionTime.compareTo(a.transactionTime));

    final timeFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    String money(int cents) {
      // 金额(元)：不带货币符号与千分位，便于表格软件直接求和。
      final yuan = cents ~/ 100;
      final fen = (cents % 100).abs().toString().padLeft(2, '0');
      return '$yuan.$fen';
    }

    String categoryName(String? id) => categories[id]?.name ?? id ?? '/';

    var incomeCount = 0;
    var incomeCents = 0;
    var expenseCount = 0;
    var expenseCents = 0;
    var companyCount = 0;
    var companyCents = 0;
    final dataRows = <List<String>>[];
    for (final t in sorted) {
      final isCompany = !SettlementPolicy.isPersonal(t);
      if (t.isIncome) {
        incomeCount++;
        incomeCents += t.amountCents;
      } else {
        expenseCount++;
        expenseCents += t.amountCents;
      }
      if (isCompany && !t.isIncome) {
        companyCount++;
        companyCents += t.amountCents;
      }
      String status;
      if (t.reimbursed) {
        status = '已报销';
      } else if (t.invoiceIssued) {
        status = '已开票';
      } else if (t.invoiceWaived) {
        status = '无需开票';
      } else if (t.invoiceRequired) {
        status = '需开票';
      } else {
        status = t.status.label;
      }
      dataRows.add([
        timeFmt.format(t.transactionTime),
        categoryName(t.categoryId),
        (t.merchant?.trim().isNotEmpty ?? false) ? t.merchant!.trim() : '/',
        (t.description?.trim().isNotEmpty ?? false)
            ? t.description!.trim()
            : '/',
        t.isIncome ? '收入' : '支出',
        money(t.amountCents),
        t.paymentMethod?.label ?? '/',
        status,
        t.id,
        t.recurringTransactionId ?? '/',
        (t.note?.trim().isNotEmpty ?? false) ? t.note!.trim() : '/',
      ]);
    }

    final first = sorted.isEmpty ? exportedAt : sorted.last.transactionTime;
    final last = sorted.isEmpty ? exportedAt : sorted.first.transactionTime;
    final blank = List<String>.filled(columnCount, '');
    List<String> merged(String text) =>
        <String>[text, ...List<String>.filled(columnCount - 1, '')];

    return [
      merged('智账账单明细'),
      merged('智账账户：[$username]'),
      merged(
        '起始时间：[${timeFmt.format(first)}] 终止时间：[${timeFmt.format(last)}]',
      ),
      merged('导出类型：[全部账单]'),
      merged('导出时间：[${timeFmt.format(exportedAt)}]'),
      List<String>.from(blank),
      merged('共${sorted.length}笔记录'),
      merged('收入：$incomeCount笔 ${money(incomeCents)}元'),
      merged('支出：$expenseCount笔 ${money(expenseCents)}元'),
      merged('公司账单（开票/报销）：$companyCount笔 ${money(companyCents)}元'),
      merged('注：'),
      merged('1. 公司账单指勾选了开票或报销状态的账单，金额已计入收支行'),
      merged('2. 回收站中已删除的账单不包含在导出内'),
      merged('3. 本明细仅供个人对账使用'),
      merged('4. 本账单中所有时间均为UTC+08:00时间'),
      List<String>.from(blank),
      merged('----------------------智账账单明细列表--------------------'),
      [
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
      ],
      ...dataRows,
    ];
  }

  /// 构建可直接保存或分享的 XLSX 字节。日期和金额使用真正的 Excel
  /// 数值类型，长交易单号强制保存为文本，避免被表格软件转成科学计数法。
  static List<int> buildWorkbookBytes({
    required List<TransactionEntity> transactions,
    required Map<String, Category> categories,
    required String username,
    required DateTime exportedAt,
  }) {
    final exportedTransactions = transactions
        .where((item) => !item.isDeleted)
        .toList()
      ..sort((a, b) => b.transactionTime.compareTo(a.transactionTime));
    final rows = buildRows(
      transactions: exportedTransactions,
      categories: categories,
      username: username,
      exportedAt: exportedAt,
    );

    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    for (var row = 0; row < columnHeaderRowIndex; row++) {
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(
          columnIndex: columnCount - 1,
          rowIndex: row,
        ),
      );
    }

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      for (var columnIndex = 0; columnIndex < columnCount; columnIndex++) {
        // A:K 已合并的表头行只写左上角。继续写 B:K 会通过 excel
        // 包的合并单元格代理反向覆盖 A 列，导致标题最终变成空字符串。
        if (rowIndex < columnHeaderRowIndex && columnIndex > 0) continue;
        // 合并后的空白分隔行不写共享字符串。部分表格读取器会把空串
        // 的共享字符串下标误显示成数字（例如“5”）。
        if (rowIndex < columnHeaderRowIndex &&
            rows[rowIndex][columnIndex].isEmpty) {
          continue;
        }
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: columnIndex,
            rowIndex: rowIndex,
          ),
        );
        if (rowIndex >= dataStartRowIndex) {
          final transaction =
              exportedTransactions[rowIndex - dataStartRowIndex];
          if (columnIndex == 0) {
            cell.value = DateTimeCellValue.fromDateTime(
              transaction.transactionTime,
            );
            cell.cellStyle = CellStyle(
              numberFormat: CustomDateTimeNumFormat(
                formatCode: 'yyyy-mm-dd hh:mm:ss',
              ),
            );
            continue;
          }
          if (columnIndex == 5) {
            cell.value = DoubleCellValue(transaction.amountCents / 100);
            cell.cellStyle = CellStyle(
              numberFormat: CustomNumericNumFormat(
                formatCode: '¥#,##0.00',
              ),
            );
            continue;
          }
        }
        cell.value = TextCellValue(rows[rowIndex][columnIndex]);
        if (rowIndex >= columnHeaderRowIndex) {
          cell.cellStyle = CellStyle(textWrapping: TextWrapping.WrapText);
        }
      }
    }

    const widths = [
      21.71,
      23.71,
      35.71,
      79.71,
      7.71,
      11.71,
      22.71,
      12.71,
      38.71,
      34.71,
      14.71,
    ];
    for (var column = 0; column < widths.length; column++) {
      sheet.setColumnWidth(column, widths[column]);
    }

    final bytes = excel.save();
    if (bytes == null) throw StateError('生成表格失败');
    return bytes;
  }

  /// 生成 XLSX 并写入临时目录（供分享面板使用）。
  static Future<BillExportResult> export({
    required List<TransactionEntity> transactions,
    required Map<String, Category> categories,
    required String username,
  }) async {
    final exportedAt = DateTime.now();
    final bytes = buildWorkbookBytes(
      transactions: transactions,
      categories: categories,
      username: username,
      exportedAt: exportedAt,
    );

    final stamp = DateFormat('yyyyMMdd_HHmmss').format(exportedAt);
    final fileName = '智账账单流水文件_$stamp.xlsx';
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return BillExportResult(
      file: file,
      fileName: fileName,
      totalCount: transactions.length,
    );
  }
}
