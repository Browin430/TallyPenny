import 'package:flutter/material.dart';

/// Design tokens — 颜色体系。
/// 参考 Apple 原生质感：暖白灰背景、深灰卡片、克制的中性色、柔和分类色。
class FMScheme {
  const FMScheme({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.inkSecondary,
    required this.inkTertiary,
    required this.separator,
    required this.border,
    required this.accent,
    required this.accentSoft,
    required this.income,
    required this.incomeSoft,
    required this.warn,
    required this.warnSoft,
    required this.danger,
    required this.dangerSoft,
    required this.navBar,
    required this.overlayBarrier,
    required this.cardShadow,
  });

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color ink;
  final Color inkSecondary;
  final Color inkTertiary;
  final Color separator;
  final Color border;
  final Color accent;
  final Color accentSoft;
  final Color income;
  final Color incomeSoft;
  final Color warn;
  final Color warnSoft;
  final Color danger;
  final Color dangerSoft;
  final Color navBar;
  final Color overlayBarrier;
  final List<BoxShadow> cardShadow;

  static const FMScheme light = FMScheme(
    brightness: Brightness.light,
    bg: Color(0xFFF5F5F7),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFFAFAFC),
    ink: Color(0xFF1D1D1F),
    inkSecondary: Color(0xFF6E6E73),
    inkTertiary: Color(0xFFAEAEB2),
    separator: Color(0xFFE8E8ED),
    border: Color(0xFFECECF1),
    accent: Color(0xFF2167D5),
    accentSoft: Color(0x182167D5),
    income: Color(0xFF30A46C),
    incomeSoft: Color(0x1A30A46C),
    warn: Color(0xFFE8930C),
    warnSoft: Color(0x1AE8930C),
    danger: Color(0xFFE0524E),
    dangerSoft: Color(0x1AE0524E),
    navBar: Color(0xD9FFFFFF),
    overlayBarrier: Color(0x66000000),
    cardShadow: [
      BoxShadow(color: Color(0x0A1D1D1F), blurRadius: 20, offset: Offset(0, 7)),
    ],
  );

  static const FMScheme dark = FMScheme(
    brightness: Brightness.dark,
    bg: Color(0xFF050506),
    surface: Color(0xFF1C1C1E),
    surfaceAlt: Color(0xFF242426),
    ink: Color(0xFFF5F5F7),
    inkSecondary: Color(0xFF98989F),
    inkTertiary: Color(0xFF636366),
    separator: Color(0xFF2E2E30),
    border: Color(0xFF2C2C2E),
    accent: Color(0xFF5B93F8),
    accentSoft: Color(0x265B93F8),
    income: Color(0xFF3DBE7B),
    incomeSoft: Color(0x263DBE7B),
    warn: Color(0xFFF5A83C),
    warnSoft: Color(0x26F5A83C),
    danger: Color(0xFFEB6A66),
    dangerSoft: Color(0x26EB6A66),
    navBar: Color(0xD91C1C1E),
    overlayBarrier: Color(0x99000000),
    cardShadow: [],
  );
}

extension FMSchemeContext on BuildContext {
  /// 当前明暗模式对应的设计 Token。
  FMScheme get colors => Theme.of(this).brightness == Brightness.dark
      ? FMScheme.dark
      : FMScheme.light;
}

/// 分类色板 —— 柔和、明暗两版通用。
class CategoryPalette {
  const CategoryPalette._();

  /// categoryId → 主色。分类 icon 底色、图表、标签均取自这里。
  static const Map<String, Color> expense = {
    'food': Color(0xFFFF9500),
    'transport': Color(0xFF3E7BFA),
    'shopping': Color(0xFFA855F7),
    'housing': Color(0xFFF76E6C),
    'entertainment': Color(0xFFEC4899),
    'medical': Color(0xFFEF4444),
    'education': Color(0xFF14B8A6),
    'travel': Color(0xFF06B6D4),
    'pet': Color(0xFFF59E0B),
    'telecom': Color(0xFF64748B),
    'utilities': Color(0xFFFBBF24),
    'subscription': Color(0xFF8B5CF6),
    'insurance': Color(0xFF10B981),
    'car': Color(0xFF7A8AA0),
    'gift': Color(0xFFF472B6),
    'social': Color(0xFFFB7185),
    'investment': Color(0xFF22C55E),
    'other': Color(0xFF98A2B3),
  };

  static const Map<String, Color> income = {
    'salary': Color(0xFF30A46C),
    'bonus': Color(0xFF4ADE80),
    'parttime': Color(0xFF34D399),
    'invest_return': Color(0xFF10B981),
    'refund': Color(0xFF2DD4BF),
    'redpacket': Color(0xFFF0655A),
    'other_income': Color(0xFF86EFAC),
  };

  static Color of(String categoryId, {bool isIncome = false}) {
    final map = isIncome ? income : expense;
    return map[categoryId] ?? expense['other']!;
  }
}
