// TODO(phase-9): 接入 LLM 财务顾问。输出必须包含免责声明；
// 涉及利率时禁止编造 —— 无实际利率则要求用户提供或明确标注"假设利率"。

/// 提供给 AI 的最小必要财务快照（隐私原则：只给完成分析所必需的数据）。
class AdvisorSnapshot {
  const AdvisorSnapshot({
    required this.monthlyIncomeCents,
    required this.avgMonthlyExpenseCents,
    required this.fixedExpenseCents,
    required this.savingsCents,
    required this.debtCents,
    required this.monthlyBudgetCents,
    required this.savingsGoalCents,
    required this.last6MonthsNetCents,
  });

  final int monthlyIncomeCents;
  final int avgMonthlyExpenseCents;
  final int fixedExpenseCents;
  final int savingsCents;
  final int debtCents;
  final int monthlyBudgetCents;
  final int savingsGoalCents;

  /// 近 6 个月结余（用于趋势判断）。
  final List<int> last6MonthsNetCents;
}

class AdvisorAnswer {
  const AdvisorAnswer({
    required this.summary,
    required this.analysisPoints,
    required this.disclaimer,
    this.verdictLabel,
  });

  final String summary;
  final List<String> analysisPoints;

  /// 购买压力结论：低 / 中 / 高（可空）。
  final String? verdictLabel;
  final String disclaimer;
}

abstract class FinancialAdvisorService {
  Future<AdvisorAnswer> ask(String question, AdvisorSnapshot snapshot);
}
