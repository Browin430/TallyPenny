/// 核心枚举：与数据库字符串值一一对应（db 值保持 snake_case 稳定，永不改动）。
library;

enum TransactionType {
  expense,
  income;

  String get label => this == expense ? '支出' : '收入';

  String toDb() => name;

  static TransactionType fromDb(String v) => v == 'income' ? income : expense;
}

/// 账单来源。
enum SourceType {
  manual,
  voice,
  screenshot,
  recurring,
  ai,
  imported;

  String get label => switch (this) {
        manual => '手动录入',
        voice => '语音',
        screenshot => '截图识别',
        recurring => '周期记账',
        ai => 'AI',
        imported => '导入',
      };

  String toDb() => switch (this) {
        imported => 'import',
        _ => name,
      };

  static SourceType fromDb(String v) => SourceType.values
      .firstWhere((e) => e.toDb() == v, orElse: () => SourceType.manual);
}

/// 账单状态。
enum TxStatus {
  confirmed,
  aiGenerated,
  needsReview,
  duplicatePending,
  archived;

  String get label => switch (this) {
        confirmed => '已确认',
        aiGenerated => 'AI 生成',
        needsReview => '待确认',
        duplicatePending => '疑似重复',
        archived => '已归档',
      };

  String toDb() => switch (this) {
        aiGenerated => 'ai_generated',
        needsReview => 'needs_review',
        duplicatePending => 'duplicate_pending',
        _ => name,
      };

  static TxStatus fromDb(String v) => TxStatus.values
      .firstWhere((e) => e.toDb() == v, orElse: () => TxStatus.confirmed);
}

/// 支付方式。
enum PaymentMethod {
  alipay,
  wechat,
  bankCard,
  cash,
  other;

  String get label => switch (this) {
        alipay => '支付宝',
        wechat => '微信支付',
        bankCard => '银行卡',
        cash => '现金',
        other => '其他',
      };

  String toDb() => switch (this) {
        bankCard => 'bank_card',
        _ => name,
      };

  static PaymentMethod? fromDb(String? v) {
    if (v == null) return null;
    return PaymentMethod.values
        .firstWhere((e) => e.toDb() == v, orElse: () => PaymentMethod.other);
  }
}
