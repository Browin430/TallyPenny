import 'package:intl/intl.dart';

/// 日期工具：中文展示与月份区间计算。
class AppDate {
  const AppDate._();

  static const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  /// 问候语（按小时）。
  static String greeting(DateTime now) {
    if (now.hour < 6) return '夜深了';
    if (now.hour < 12) return '早上好';
    if (now.hour < 14) return '中午好';
    if (now.hour < 18) return '下午好';
    return '晚上好';
  }

  /// "2026年8月"
  static String monthTitle(DateTime d) => '${d.year}年${d.month}月';

  /// "8月28日 周五"
  static String dayTitle(DateTime d) =>
      '${d.month}月${d.day}日 ${_weekdays[d.weekday - 1]}';

  /// "8月28日"
  static String shortDayTitle(DateTime d) => '${d.month}月${d.day}日';

  /// "10:23"
  static String timeHM(DateTime d) => DateFormat('HH:mm').format(d);

  /// "2026年8月28日 10:23"
  static String fullTitle(DateTime d) =>
      '${d.year}年${d.month}月${d.day}日 ${DateFormat('HH:mm').format(d)}';

  /// 今天 / 昨天 / M月d日
  static String relativeDayTitle(DateTime d, DateTime now) {
    if (_sameDay(d, now)) return '今天';
    if (_sameDay(d, now.subtract(const Duration(days: 1)))) return '昨天';
    return shortDayTitle(d);
  }

  /// 下个月 / 上个月（锚定 1 号，避免月末溢出）。
  static DateTime addMonths(DateTime month, int delta) {
    final first = DateTime(month.year, month.month, 1);
    var y = first.year;
    var m = first.month + delta;
    while (m > 12) {
      m -= 12;
      y += 1;
    }
    while (m < 1) {
      m += 12;
      y -= 1;
    }
    return DateTime(y, m, 1);
  }

  /// 该月天数。
  static int daysInMonth(DateTime month) {
    final next = addMonths(month, 1);
    return DateTime(next.year, next.month, 0).day;
  }

  /// 月份区间 [start, end)。
  static (DateTime, DateTime) monthRange(DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end = addMonths(month, 1);
    return (start, end);
  }

  static bool isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  static bool isToday(DateTime d) => _sameDay(d, DateTime.now());

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
