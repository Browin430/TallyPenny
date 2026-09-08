import 'enums.dart';

enum RecurringFrequency {
  daily,
  workdays,
  weekly,
  monthly;

  String get label => switch (this) {
        daily => '每天',
        workdays => '每个工作日',
        weekly => '每周',
        monthly => '每月',
      };

  String toDb() => name;

  static RecurringFrequency fromDb(String value) => values.firstWhere(
        (frequency) => frequency.name == value,
        orElse: () => RecurringFrequency.monthly,
      );
}

/// 一条周期记账规则。规则保存在本机，到期账单由 [RecurringProcessor] 生成。
class RecurringTransaction {
  const RecurringTransaction({
    required this.id,
    required this.userId,
    required this.title,
    required this.amountCents,
    required this.type,
    required this.frequency,
    required this.startDate,
    required this.hour,
    required this.minute,
    required this.createdAt,
    required this.updatedAt,
    this.categoryId,
    this.merchant,
    this.description,
    this.paymentMethod,
    this.daysOfWeek = const [],
    this.dayOfMonth,
    this.endDate,
    this.enabled = true,
    this.lastRunAt,
  });

  final String id;
  final String userId;
  final String title;
  final int amountCents;
  final TransactionType type;
  final String? categoryId;
  final String? merchant;
  final String? description;
  final PaymentMethod? paymentMethod;
  final RecurringFrequency frequency;

  /// ISO weekday：周一=1，周日=7。当前界面使用单个星期值，模型保留多选能力。
  final List<int> daysOfWeek;
  final int? dayOfMonth;
  final DateTime startDate;
  final DateTime? endDate;
  final int hour;
  final int minute;
  final bool enabled;
  final DateTime? lastRunAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get scheduleLabel => switch (frequency) {
        RecurringFrequency.daily => '每天 ${_two(hour)}:${_two(minute)}',
        RecurringFrequency.workdays =>
          '${daysOfWeek.contains(DateTime.saturday) ? '单休' : '双休'}工作日 '
              '${_two(hour)}:${_two(minute)}',
        RecurringFrequency.weekly =>
          '每周${_weekdayLabel(daysOfWeek.isEmpty ? startDate.weekday : daysOfWeek.first)} '
              '${_two(hour)}:${_two(minute)}',
        RecurringFrequency.monthly => '每月 ${dayOfMonth ?? startDate.day} 日 '
            '${_two(hour)}:${_two(minute)}',
      };

  RecurringTransaction copyWith({
    String? title,
    int? amountCents,
    TransactionType? type,
    String? categoryId,
    String? merchant,
    String? description,
    PaymentMethod? paymentMethod,
    RecurringFrequency? frequency,
    List<int>? daysOfWeek,
    int? dayOfMonth,
    DateTime? startDate,
    DateTime? endDate,
    int? hour,
    int? minute,
    bool? enabled,
    DateTime? lastRunAt,
    DateTime? updatedAt,
    bool clearEndDate = false,
    bool clearLastRunAt = false,
  }) =>
      RecurringTransaction(
        id: id,
        userId: userId,
        title: title ?? this.title,
        amountCents: amountCents ?? this.amountCents,
        type: type ?? this.type,
        categoryId: categoryId ?? this.categoryId,
        merchant: merchant ?? this.merchant,
        description: description ?? this.description,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        frequency: frequency ?? this.frequency,
        daysOfWeek: daysOfWeek ?? this.daysOfWeek,
        dayOfMonth: dayOfMonth ?? this.dayOfMonth,
        startDate: startDate ?? this.startDate,
        endDate: clearEndDate ? null : (endDate ?? this.endDate),
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        enabled: enabled ?? this.enabled,
        lastRunAt: clearLastRunAt ? null : (lastRunAt ?? this.lastRunAt),
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _weekdayLabel(int weekday) =>
      const {
        1: '一',
        2: '二',
        3: '三',
        4: '四',
        5: '五',
        6: '六',
        7: '日',
      }[weekday] ??
      '一';
}
