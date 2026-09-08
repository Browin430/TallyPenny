/// 商户个性化规则：用户显式声明某商户的备注与默认分类。
/// 例：C.L → 备注「公司楼下黄焖鸡」、分类 food。
class MerchantRule {
  const MerchantRule({
    required this.id,
    required this.userId,
    required this.merchantPattern,
    required this.preferredCategory,
    required this.hitCount,
    required this.createdAt,
    required this.updatedAt,
    this.note,
    this.confidence = 1,
  });

  final String id;
  final String userId;

  /// 商户名（支持归一化后精确/包含匹配）。
  final String merchantPattern;

  /// 白名单分类 id（如 food）。
  final String preferredCategory;

  /// 用户备注（这是什么商户/为什么这样分类）。
  final String? note;

  final double confidence;

  /// 自动命中的次数（展示「已自动分类 N 次」）。
  final int hitCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  MerchantRule copyWith({
    String? merchantPattern,
    String? preferredCategory,
    String? note,
    bool clearNote = false,
    int? hitCount,
    double? confidence,
    DateTime? updatedAt,
  }) =>
      MerchantRule(
        id: id,
        userId: userId,
        merchantPattern: merchantPattern ?? this.merchantPattern,
        preferredCategory: preferredCategory ?? this.preferredCategory,
        note: clearNote ? null : (note ?? this.note),
        confidence: confidence ?? this.confidence,
        hitCount: hitCount ?? this.hitCount,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
