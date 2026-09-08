import 'package:flutter/material.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/fm_category_icon.dart';
import '../../core/widgets/fm_sheets.dart';
import '../../domain/models/category.dart';
import '../../domain/models/enums.dart';

/// 分类选择底部弹层：按收支方向过滤，网格展示。
/// [allowTypeSwitch] 为 true 时顶部提供 支出/收入 切换（返回分类的类型即最终方向）。
Future<Category?> showCategoryPicker(
  BuildContext context, {
  required List<Category> categories,
  required TransactionType type,
  Category? current,
  bool allowTypeSwitch = false,
}) {
  return showFMSheet<Category>(
    context,
    builder: (_) => _CategoryPickerSheet(
      categories: categories,
      type: type,
      current: current,
      allowTypeSwitch: allowTypeSwitch,
    ),
  );
}

class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({
    required this.categories,
    required this.type,
    this.current,
    this.allowTypeSwitch = false,
  });

  final List<Category> categories;
  final TransactionType type;
  final Category? current;
  final bool allowTypeSwitch;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  late TransactionType _type = widget.type;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final list = widget.categories
        .where((c) => c.type == _type && !c.isHidden)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            FMSpacing.l, FMSpacing.xs, FMSpacing.l, FMSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: FMSpacing.l),
              child: Text(
                widget.allowTypeSwitch ? '选择分类' : '选择${_type.label}分类',
                style: AppText.title(s.ink),
                textAlign: TextAlign.center,
              ),
            ),
            if (widget.allowTypeSwitch) ...[
              Row(
                children: [
                  for (final t in TransactionType.values)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _type = t),
                        child: Container(
                          height: 40,
                          alignment: Alignment.center,
                          margin: EdgeInsets.only(
                            right:
                                t == TransactionType.expense ? FMSpacing.s : 0,
                          ),
                          decoration: BoxDecoration(
                            color: _type == t ? s.accentSoft : s.surfaceAlt,
                            borderRadius: BorderRadius.circular(FMRadius.field),
                            border: Border.all(
                              color: _type == t ? s.accent : s.border,
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            t.label,
                            style: AppText.sub(
                              _type == t ? s.accent : s.inkSecondary,
                            ).copyWith(
                                fontWeight: _type == t
                                    ? FontWeight.w600
                                    : FontWeight.w400),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: FMSpacing.m),
            ],
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: FMSpacing.m,
              crossAxisSpacing: FMSpacing.s,
              childAspectRatio: 0.95,
              children: [
                for (final c in list)
                  _CategoryCell(
                    category: c,
                    selected: widget.current?.id == c.id,
                    onTap: () => Navigator.of(context).pop(c),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCell extends StatelessWidget {
  const _CategoryCell({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              FMCategoryIcon(category: category, size: 48),
              if (selected)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: s.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: s.surface, width: 1.5),
                    ),
                    child: Icon(FMIcons.check, size: 8, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: FMSpacing.xs),
          Text(
            category.name,
            style: AppText.caption(selected ? s.ink : s.inkSecondary).copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
