/// AI / 规则产生的财务洞察（首页与分析页展示）。
library;

enum InsightSeverity { info, warning, positive }

extension InsightSeverityX on InsightSeverity {
  bool get isWarning => this == InsightSeverity.warning;
  bool get isPositive => this == InsightSeverity.positive;
}

class AiInsight {
  const AiInsight({
    required this.id,
    required this.severity,
    required this.iconCode,
    required this.text,
    this.linksToAnalysis = true,
  });

  final String id;
  final InsightSeverity severity;
  final String iconCode;
  final String text;
  final bool linksToAnalysis;
}
