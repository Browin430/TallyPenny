import 'package:flutter/material.dart';

/// Design tokens — 字体层级。
/// 系统字体（iOS: SF Pro / Android: Roboto），金额使用 Tabular Numbers 保证对齐。
class AppText {
  const AppText._();

  static const _tabular = [FontFeature.tabularFigures()];

  /// 超大金额（首页结余）。
  static TextStyle amountXL(Color color) => TextStyle(
        fontSize: 40,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -1,
        fontFeatures: _tabular,
        color: color,
      );

  /// 大金额（详情页 / 记账金额输入）。
  static TextStyle amountL(Color color) => TextStyle(
        fontSize: 32,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        fontFeatures: _tabular,
        color: color,
      );

  /// 中金额（卡片、流水行）。
  static TextStyle amountM(Color color) => TextStyle(
        fontSize: 17,
        height: 1.3,
        fontWeight: FontWeight.w600,
        fontFeatures: _tabular,
        color: color,
      );

  static TextStyle amountS(Color color) => TextStyle(
        fontSize: 15,
        height: 1.3,
        fontWeight: FontWeight.w600,
        fontFeatures: _tabular,
        color: color,
      );

  /// 页面大标题。
  static TextStyle headline(Color color) => TextStyle(
        fontSize: 30,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: color,
      );

  /// 卡片标题 / 分组标题。
  static TextStyle title(Color color) => TextStyle(
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: color,
      );

  static TextStyle bodyStrong(Color color) => TextStyle(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle body(Color color) => TextStyle(
        fontSize: 16,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static TextStyle sub(Color color) => TextStyle(
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: color,
      );

  /// 辅助小字（时间、来源标签）。
  static TextStyle caption(Color color) => TextStyle(
        fontSize: 12,
        height: 1.35,
        fontWeight: FontWeight.w400,
        fontFeatures: _tabular,
        color: color,
      );

  /// 极小标签（徽章、来源标记）。
  static TextStyle micro(Color color) => TextStyle(
        fontSize: 11,
        height: 1.3,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
        color: color,
      );
}

/// Design tokens — 间距（4 的倍数制）。
class FMSpacing {
  const FMSpacing._();
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Design tokens — 圆角。
class FMRadius {
  const FMRadius._();
  static const double card = 20;
  static const double cardSmall = 16;
  static const double sheet = 24;
  static const double field = 16;
  static const double chip = 12;
  static const double iconBox = 12;
  static const double button = 16;
}
