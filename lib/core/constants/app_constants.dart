/// 全局业务常量。
/// 注意：去重权重 / 阈值集中在这里，不写死在业务 UI，后续可迁移到用户设置或远端配置。
class DuplicateWeights {
  const DuplicateWeights._();

  // ---- 金额相似（满分 0.40）----
  static const double amountExact = 0.40;
  static const double amountWithin2Pct = 0.36;
  static const double amountWithin5Pct = 0.30;
  static const double amountWithin10Pct = 0.20;

  // ---- 时间相似（满分 0.25）----
  static const double timeWithin5Min = 0.25;
  static const double timeWithin30Min = 0.15;
  static const double timeWithin2Hours = 0.08;

  // ---- 内容 / 商户 / 分类 ----
  static const double descriptionSemantic = 0.20;
  static const double categorySame = 0.10;
  static const double merchantExact = 0.10;
  static const double merchantRelated = 0.05;

  /// 候选筛选窗口：新账单时间前后 N 小时。
  static const int candidateWindowHours = 24;

  /// 金额差异超过该比例则直接排除候选（硬性条件）。
  static const double candidateAmountTolerance = 0.15;
}

/// 去重判定阈值。
class DuplicateThresholds {
  const DuplicateThresholds._();

  /// >= 该分数：高度确定重复，可建议自动合并（仍保留审计记录）。
  static const double autoMerge = 0.85;

  /// >= 该分数且 < autoMerge：可能重复，必须弹出确认。
  static const double askUser = 0.55;
}

/// 置信度策略（高自动完成 / 中快速确认 / 低请求补充）。
class ConfidencePolicy {
  const ConfidencePolicy._();

  /// AI 结果置信度 >= 该值 → ai_generated，直接入库。
  static const double autoCommit = 0.85;

  /// 置信度 < 该值 → needs_review。
  static const double needsReview = 0.55;
}

/// 预算提醒节点。
class BudgetAlert {
  const BudgetAlert._();
  static const double warn = 0.8;
  static const double full = 1.0;
}

/// 用户默认资料（可在"我的"页修改）。
class DefaultProfile {
  const DefaultProfile._();
  static const String userName = '张先生';
  static const int monthlyIncomeCents = 1500000; // ¥15,000
  static const int fixedExpenseCents = 400000; // ¥4,000
  static const int savingsGoalCents = 300000; // ¥3,000/月
  static const int monthlyBudgetCents =
      monthlyIncomeCents - savingsGoalCents; // ¥12,000
}
