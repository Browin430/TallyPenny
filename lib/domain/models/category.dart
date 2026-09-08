import 'package:flutter/material.dart';

import 'enums.dart';

/// 消费 / 收入分类。
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.iconCode,
    required this.colorValue,
    required this.type,
    this.sortOrder = 0,
    this.isSystem = false,
    this.isHidden = false,
  });

  final String id;
  final String name;

  /// 图标代码（AppIcons.codeOf 映射），与具体 IconData 解耦。
  final String iconCode;

  /// ARGB int，存储友好。
  final int colorValue;
  final TransactionType type;
  final int sortOrder;
  final bool isSystem;
  final bool isHidden;

  Color get color => Color(colorValue);

  Category copyWith({
    String? name,
    String? iconCode,
    int? colorValue,
    int? sortOrder,
    bool? isHidden,
  }) =>
      Category(
        id: id,
        name: name ?? this.name,
        iconCode: iconCode ?? this.iconCode,
        colorValue: colorValue ?? this.colorValue,
        type: type,
        sortOrder: sortOrder ?? this.sortOrder,
        isSystem: isSystem,
        isHidden: isHidden ?? this.isHidden,
      );
}
