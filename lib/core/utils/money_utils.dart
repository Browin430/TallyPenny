import 'package:intl/intl.dart';

/// 金额工具：内部一律以"分"（int）存储，仅展示层格式化。
class Money {
  const Money._();

  static final _grouped = NumberFormat('#,##0.00');
  static final _groupedInt = NumberFormat('#,##0');

  /// 812300 -> "8,123.00"
  static String centsToText(int cents) => _grouped.format(cents / 100);

  /// 图表 / 趋势轴用：金额较大时省略小数。812300 -> "8,123"
  static String centsToCompact(int cents) => cents % 100 == 0
      ? _groupedInt.format(cents ~/ 100)
      : _grouped.format(cents / 100);

  /// 带符号展示：expense → "-¥3.00"，income → "+¥15,000.00"。
  static String signed(int cents,
      {required bool isIncome, String symbol = '¥'}) {
    final sign = isIncome ? '+' : '-';
    return '$sign$symbol${centsToText(cents)}';
  }

  /// 解析用户输入金额为分；非法或 <=0 返回 null。
  static int? parseToCents(String input) {
    final cleaned = input.trim().replaceAll(',', '');
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    if (value == null || value <= 0) return null;
    return (value * 100).round();
  }
}
