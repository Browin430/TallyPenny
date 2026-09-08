import '../domain/models/merchant_rule.dart';

/// 商户规则匹配：归一化精确 > 互包含；多命中取最长 pattern（最具体）。
class MerchantRuleMatcher {
  const MerchantRuleMatcher._();

  /// 与固定消费识别一致的归一化：去全部空白 + 小写。
  static String normalize(String raw) =>
      raw.replaceAll(RegExp(r'\s+'), '').toLowerCase().trim();

  /// [MerchantRule.merchantPattern] 是否命中商户名 [merchant]（均已归一化）。
  /// 精确相等或互为包含（较短一方长度 ≥ 2，防「肯」误中「肯德基」）。
  static bool _hits(String normPattern, String normMerchant) {
    if (normPattern.isEmpty || normMerchant.isEmpty) return false;
    if (normPattern == normMerchant) return true;
    final shorter = normPattern.length < normMerchant.length
        ? normPattern
        : normMerchant;
    final longer = identical(shorter, normPattern)
        ? normMerchant
        : normPattern;
    return shorter.length >= 2 && longer.contains(shorter);
  }

  /// 返回命中的规则；未命中返回 null。
  static MerchantRule? match(List<MerchantRule> rules, String? merchant) {
    if (merchant == null || merchant.trim().isEmpty) return null;
    final norm = normalize(merchant);
    MerchantRule? best;
    for (final rule in rules) {
      if (!_hits(normalize(rule.merchantPattern), norm)) continue;
      if (best == null ||
          rule.merchantPattern.length > best.merchantPattern.length) {
        best = rule;
      }
    }
    return best;
  }

  /// 随解析请求上传给服务器 AI 的精简格式（上限 50 条）。
  static List<Map<String, dynamic>> toWireJson(List<MerchantRule> rules) => [
        for (final rule in rules.take(50))
          {
            'merchant': rule.merchantPattern,
            'categoryId': rule.preferredCategory,
            if (rule.note != null && rule.note!.trim().isNotEmpty)
              'note': rule.note!.trim(),
          },
      ];
}
