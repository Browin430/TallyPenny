import 'package:flutter/material.dart';

import '../../domain/models/category.dart';
import '../icons/app_icons.dart';
import '../theme/app_colors.dart';

/// 分类图标：圆角方形底 + 分类色。浅色下用 12% 透明底色，深色下 18%。
class FMCategoryIcon extends StatelessWidget {
  const FMCategoryIcon({
    super.key,
    this.category,
    this.size = 40,
    this.icon,
    this.color,
  });

  final Category? category;
  final double size;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final c = color ??
        (category != null
            ? category!.color
            : CategoryPalette.expense['other']!);
    final alpha = s.brightness == Brightness.dark ? 0.20 : 0.13;
    final iconSize = size * 0.5;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: alpha),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        icon ??
            (category != null
                ? FMIcons.categoryIcon(category!.iconCode)
                : FMIcons.fallback),
        size: iconSize,
        color: c,
      ),
    );
  }
}
