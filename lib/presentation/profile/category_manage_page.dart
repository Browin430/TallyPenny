import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/id_gen.dart';
import '../../core/widgets/fm_category_icon.dart';
import '../../core/widgets/fm_sheets.dart';
import '../../core/widgets/fm_toast.dart';
import '../../domain/models/category.dart';
import '../../domain/models/enums.dart';
import '../../state/app_providers.dart';

/// 分类管理：查看全部分类、隐藏 / 显示、新增自定义分类。
class CategoryManagePage extends ConsumerWidget {
  const CategoryManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.colors;
    final categories = ref.watch(categoriesProvider).valueOrNull;

    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        backgroundColor: s.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text('分类管理', style: AppText.title(s.ink)),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(FMIcons.chevronLeft, color: s.ink, size: 22),
        ),
        actions: [
          IconButton(
            onPressed: () => _addCategory(context, ref),
            icon: Icon(FMIcons.plus, color: s.accent, size: 22),
          ),
        ],
      ),
      body: categories == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  FMSpacing.l, FMSpacing.s, FMSpacing.l, 40),
              children: [
                for (final (type, label) in const [
                  (TransactionType.expense, '支出分类'),
                  (TransactionType.income, '收入分类'),
                ]) ...[
                  Padding(
                    padding: const EdgeInsets.only(
                        left: FMSpacing.xs, bottom: FMSpacing.s),
                    child: Text(label, style: AppText.caption(s.inkTertiary)),
                  ),
                  _CategoryGroup(
                    categories: categories.where((c) => c.type == type).toList()
                      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
                  ),
                  const SizedBox(height: FMSpacing.m),
                ],
                Padding(
                  padding: const EdgeInsets.all(FMSpacing.s),
                  child: Text(
                    '隐藏的分类不会出现在记账与筛选中，历史账单不受影响。系统分类不可删除。',
                    style: AppText.caption(s.inkTertiary),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _addCategory(BuildContext context, WidgetRef ref) async {
    final created = await showFMSheet<bool>(
      context,
      builder: (_) => const _NewCategorySheet(),
    );
    if (created == true && context.mounted) {
      showFMToast(context, message: '分类已创建', icon: FMIcons.checkCircle);
    }
  }
}

// =====================================================================
// 分类分组
// =====================================================================

class _CategoryGroup extends ConsumerWidget {
  const _CategoryGroup({required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(FMRadius.card),
        border: Border.all(color: s.border, width: 0.5),
        boxShadow: s.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, c) in categories.indexed) ...[
            InkWell(
              onTap: () async {
                await ref
                    .read(categoryRepositoryProvider)
                    .setHidden(c.id, !c.isHidden);
                ref.read(dataVersionProvider.notifier).state++;
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: FMSpacing.l,
                  vertical: FMSpacing.m + 1,
                ),
                child: Row(
                  children: [
                    FMCategoryIcon(category: c, size: 32),
                    const SizedBox(width: FMSpacing.m),
                    Expanded(
                      child: Text(
                        c.name,
                        style: AppText.bodyStrong(
                          c.isHidden ? s.inkTertiary : s.ink,
                        ),
                      ),
                    ),
                    if (c.isSystem)
                      Text('系统', style: AppText.micro(s.inkTertiary))
                    else
                      Text('自定义', style: AppText.micro(s.accent)),
                    const SizedBox(width: FMSpacing.m),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        c.isHidden ? FMIcons.eyeOff : FMIcons.check,
                        key: ValueKey(c.isHidden),
                        size: 16,
                        color: c.isHidden ? s.inkTertiary : s.income,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (i != categories.length - 1)
              Divider(height: 0.5, thickness: 0.5, color: s.separator),
          ],
        ],
      ),
    );
  }
}

// =====================================================================
// 新增自定义分类弹层
// =====================================================================

class _NewCategorySheet extends ConsumerStatefulWidget {
  const _NewCategorySheet();

  @override
  ConsumerState<_NewCategorySheet> createState() => _NewCategorySheetState();
}

class _NewCategorySheetState extends ConsumerState<_NewCategorySheet> {
  final _nameController = TextEditingController();
  var _type = TransactionType.expense;
  var _iconCode = 'other';
  var _colorValue = 0xFF98A2B3;

  static const _iconChoices = [
    'food',
    'transport',
    'shopping',
    'housing',
    'entertainment',
    'medical',
    'education',
    'travel',
    'pet',
    'telecom',
    'utilities',
    'subscription',
    'insurance',
    'car',
    'gift',
    'social',
    'investment',
    'other',
  ];

  static const _colorChoices = [
    0xFFFF9500,
    0xFF3E7BFA,
    0xFFA855F7,
    0xFFF76E6C,
    0xFFEC4899,
    0xFFEF4444,
    0xFF14B8A6,
    0xFF06B6D4,
    0xFFF59E0B,
    0xFF10B981,
    0xFF64748B,
    0xFF8B5CF6,
    0xFF22C55E,
    0xFF98A2B3,
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final preview = Category(
      id: 'preview',
      name: _nameController.text.isEmpty ? '预览' : _nameController.text,
      iconCode: _iconCode,
      colorValue: _colorValue,
      type: _type,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            FMSpacing.l, FMSpacing.xs, FMSpacing.l, FMSpacing.xl),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('新建分类',
                  style: AppText.title(s.ink), textAlign: TextAlign.center),
              const SizedBox(height: FMSpacing.l),

              // 预览
              Center(
                child: Column(
                  children: [
                    FMCategoryIcon(category: preview, size: 48),
                    const SizedBox(height: FMSpacing.s),
                    Text(preview.name, style: AppText.sub(s.inkSecondary)),
                  ],
                ),
              ),
              const SizedBox(height: FMSpacing.l),

              // 名称
              TextField(
                controller: _nameController,
                maxLength: 6,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                style: AppText.bodyStrong(s.ink),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '分类名称（最多 6 字）',
                  hintStyle: AppText.sub(s.inkTertiary),
                  filled: true,
                  fillColor: s.surfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(FMRadius.field),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: FMSpacing.m),

              // 类型
              Row(
                children: [
                  for (final (t, label) in const [
                    (TransactionType.expense, '支出'),
                    (TransactionType.income, '收入'),
                  ])
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _type = t;
                          _iconCode = 'other';
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _type == t
                                ? (t == TransactionType.income
                                    ? s.incomeSoft
                                    : s.accentSoft)
                                : s.ink.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(FMRadius.field),
                          ),
                          child: Text(
                            label,
                            style: AppText.sub(_type == t
                                    ? (t == TransactionType.income
                                        ? s.income
                                        : s.accent)
                                    : s.inkSecondary)
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: FMSpacing.l),

              // 图标
              Text('图标', style: AppText.caption(s.inkTertiary)),
              const SizedBox(height: FMSpacing.s),
              Wrap(
                spacing: FMSpacing.s,
                runSpacing: FMSpacing.s,
                children: [
                  for (final code in _iconChoices)
                    GestureDetector(
                      onTap: () => setState(() => _iconCode = code),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _iconCode == code
                              ? Color(_colorValue).withValues(alpha: 0.16)
                              : s.ink.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _iconCode == code
                                ? Color(_colorValue)
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          FMIcons.categoryIcon(code),
                          size: 18,
                          color: _iconCode == code
                              ? Color(_colorValue)
                              : s.inkSecondary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: FMSpacing.l),

              // 颜色
              Text('颜色', style: AppText.caption(s.inkTertiary)),
              const SizedBox(height: FMSpacing.s),
              Wrap(
                spacing: FMSpacing.m,
                runSpacing: FMSpacing.m,
                children: [
                  for (final c in _colorChoices)
                    GestureDetector(
                      onTap: () => setState(() => _colorValue = c),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: _colorValue == c
                              ? Border.all(color: s.ink, width: 2.5)
                              : null,
                        ),
                        child: _colorValue == c
                            ? Icon(FMIcons.check, size: 14, color: Colors.white)
                            : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: FMSpacing.xl),

              // 保存
              GestureDetector(
                onTap: _save,
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: s.accent,
                    borderRadius: BorderRadius.circular(FMRadius.button),
                  ),
                  child: Text('保存', style: AppText.bodyStrong(Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final existing = await ref.read(categoryRepositoryProvider).getAll();
    if (existing.any((c) => c.name == name)) {
      if (mounted) {
        showFMToast(context, message: '已有同名分类', icon: FMIcons.warning);
      }
      return;
    }
    final maxOrder = existing
        .where((c) => c.type == _type)
        .fold(0, (m, c) => c.sortOrder > m ? c.sortOrder : m);
    await ref.read(categoryRepositoryProvider).upsert(
          Category(
            id: IdGen.newId(),
            name: name,
            iconCode: _iconCode,
            colorValue: _colorValue,
            type: _type,
            sortOrder: maxOrder + 1,
          ),
        );
    ref.read(dataVersionProvider.notifier).state++;
    if (mounted) Navigator.of(context).pop(true);
  }
}
