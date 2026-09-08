import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/money_utils.dart';
import '../../core/widgets/fm_amount_text.dart';
import '../../core/widgets/fm_card.dart';
import '../../core/widgets/fm_category_icon.dart';
import '../../core/widgets/fm_month_switcher.dart';
import '../../core/widgets/fm_sheets.dart';
import '../../core/widgets/fm_toast.dart';
import '../../core/widgets/fm_transaction_tile.dart';
import '../../domain/models/category.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/transaction.dart';
import '../../services/transaction_grouping_service.dart';
import '../../state/app_providers.dart';
import '../detail/transaction_detail_page.dart';
import '../entry/category_picker_sheet.dart';

/// 流水页：月份汇总 + 搜索 / 筛选 + 商户优先折叠列表。
class TransactionsPage extends ConsumerWidget {
  const TransactionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.colors;
    final filter = ref.watch(txFilterProvider);
    final summary = ref.watch(monthSummaryProvider(filter.month)).valueOrNull;
    final txs = ref.watch(filteredTxProvider).valueOrNull;
    final viewMode = ref.watch(transactionViewModeProvider).valueOrNull ??
        TransactionViewMode.category;

    return Scaffold(
      backgroundColor: s.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ---- 顶部：月份 + 汇总 ----
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  FMSpacing.l, FMSpacing.s, FMSpacing.l, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('流水', style: AppText.headline(s.ink)),
                  const SizedBox(height: FMSpacing.m),
                  FMMonthSwitcher(
                    month: filter.month,
                    onChanged: (m) =>
                        ref.read(txFilterProvider.notifier).setMonth(m),
                  ),
                  const SizedBox(height: FMSpacing.m),
                  Row(
                    children: [
                      _SummaryCell(
                        label: '本月支出',
                        cents: summary?.expenseCents ?? 0,
                        color: s.ink,
                      ),
                      const SizedBox(width: FMSpacing.xl),
                      _SummaryCell(
                        label: '本月收入',
                        cents: summary?.incomeCents ?? 0,
                        color: s.income,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '汇总已排除开票与报销账单，明细仍完整显示',
                    style: AppText.caption(s.inkTertiary),
                  ),
                ],
              ),
            ),

            // ---- 搜索 + 筛选 ----
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  FMSpacing.l, FMSpacing.m, FMSpacing.l, FMSpacing.s),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 38,
                      padding:
                          const EdgeInsets.symmetric(horizontal: FMSpacing.m),
                      decoration: BoxDecoration(
                        color: s.ink.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Row(
                        children: [
                          Icon(FMIcons.search, size: 15, color: s.inkTertiary),
                          const SizedBox(width: FMSpacing.s),
                          Expanded(
                            child: TextField(
                              onChanged: (v) => ref
                                  .read(txFilterProvider.notifier)
                                  .setSearch(v),
                              style: AppText.body(s.ink),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: '搜索商户 / 描述 / 备注',
                                hintStyle: AppText.sub(s.inkTertiary),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: FMSpacing.s),
                  GestureDetector(
                    onTap: () => _showTypeFilter(context, ref, filter),
                    child: Container(
                      height: 38,
                      padding:
                          const EdgeInsets.symmetric(horizontal: FMSpacing.m),
                      decoration: BoxDecoration(
                        color: filter.type != null
                            ? s.accentSoft
                            : s.ink.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Center(
                        child: Text(
                          filter.type?.label ?? '全部',
                          style: AppText.sub(
                            filter.type != null ? s.accent : s.inkSecondary,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: FMSpacing.s),
                  GestureDetector(
                    onTap: () => _showCategoryFilter(context, ref, filter),
                    child: Container(
                      height: 38,
                      padding:
                          const EdgeInsets.symmetric(horizontal: FMSpacing.m),
                      decoration: BoxDecoration(
                        color: filter.categoryIds.isNotEmpty
                            ? s.accentSoft
                            : s.ink.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            FMIcons.tag,
                            size: 13,
                            color: filter.categoryIds.isNotEmpty
                                ? s.accent
                                : s.inkSecondary,
                          ),
                          if (filter.categoryIds.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Text(
                              '${filter.categoryIds.length}',
                              style: AppText.sub(s.accent)
                                  .copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const _QuickFilters(),
            const SizedBox(height: FMSpacing.s),
            const _ViewModeSwitch(),

            // ---- 列表 ----
            Expanded(
              child: txs == null
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : txs.isEmpty
                      ? FMEmptyState(
                          icon: FMIcons.list,
                          title: filter.isActive ? '没有符合条件的账单' : '本月还没有账单',
                          subtitle: filter.isActive ? '试试调整筛选条件' : '点下方【+】记一笔吧',
                        )
                      : _GroupedList(txs: txs, viewMode: viewMode),
            ),
          ],
        ),
      ),
    );
  }

  void _showTypeFilter(BuildContext context, WidgetRef ref, TxFilter filter) {
    final options = <(TransactionType?, String)>[
      (null, '全部'),
      (TransactionType.expense, '支出'),
      (TransactionType.income, '收入'),
    ];
    showFMSheet<void>(
      context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FMSpacing.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (t, label) in options)
                ListTile(
                  title: Text(label,
                      style: AppText.bodyStrong(context.colors.ink)),
                  trailing: filter.type == t
                      ? Icon(FMIcons.check,
                          size: 18, color: context.colors.accent)
                      : null,
                  onTap: () {
                    ref.read(txFilterProvider.notifier).setType(t);
                    Navigator.of(context).pop();
                  },
                ),
              const SizedBox(height: FMSpacing.m),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCategoryFilter(
    BuildContext context,
    WidgetRef ref,
    TxFilter filter,
  ) async {
    final categories = await ref.read(visibleCategoriesProvider.future);
    if (!context.mounted) return;
    final selected = {...filter.categoryIds};
    final result = await showFMSheet<Set<String>>(
      context,
      builder: (_) => _CategoryFilterSheet(
        categories: categories,
        selected: selected,
      ),
    );
    if (result != null) {
      ref.read(txFilterProvider.notifier).setCategories(result);
    }
  }
}

class _ViewModeSwitch extends ConsumerWidget {
  const _ViewModeSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.colors;
    final selected = ref.watch(transactionViewModeProvider).valueOrNull ??
        TransactionViewMode.category;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FMSpacing.l),
      child: Container(
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: s.ink.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            for (final mode in TransactionViewMode.values)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: selected == mode,
                  label:
                      mode == TransactionViewMode.category ? '按分类显示' : '按时间显示',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: () => ref
                        .read(transactionViewModeProvider.notifier)
                        .setMode(mode),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color:
                            selected == mode ? s.surface : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: selected == mode ? s.cardShadow : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            mode == TransactionViewMode.category
                                ? FMIcons.tag
                                : FMIcons.clock,
                            size: 14,
                            color: selected == mode ? s.ink : s.inkTertiary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            mode == TransactionViewMode.category ? '分类' : '时间',
                            style: AppText.sub(
                              selected == mode ? s.ink : s.inkTertiary,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuickFilters extends ConsumerWidget {
  const _QuickFilters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.colors;
    final filter = ref.watch(txFilterProvider);
    final items = <({String label, TransactionType? type, String? category})>[
      (label: '全部', type: null, category: null),
      (label: '支出', type: TransactionType.expense, category: null),
      (label: '收入', type: TransactionType.income, category: null),
      (label: '餐饮', type: TransactionType.expense, category: 'food'),
      (label: '交通', type: TransactionType.expense, category: 'transport'),
      (label: '购物', type: TransactionType.expense, category: 'shopping'),
    ];

    bool selected(
        ({String label, TransactionType? type, String? category}) item) {
      if (item.label == '全部') {
        return filter.type == null && filter.categoryIds.isEmpty;
      }
      if (item.category != null) {
        return filter.categoryIds.length == 1 &&
            filter.categoryIds.contains(item.category);
      }
      return filter.type == item.type && filter.categoryIds.isEmpty;
    }

    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: FMSpacing.l),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: FMSpacing.s),
        itemBuilder: (context, index) {
          final item = items[index];
          final active = selected(item);
          return Material(
            color: active ? s.ink : s.surface,
            borderRadius: BorderRadius.circular(100),
            child: InkWell(
              borderRadius: BorderRadius.circular(100),
              onTap: () {
                ref.read(txFilterProvider.notifier).setType(item.type);
                ref.read(txFilterProvider.notifier).setCategories(
                      item.category == null ? const {} : {item.category!},
                    );
              },
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: FMSpacing.l),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: active ? Colors.transparent : s.border,
                    width: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  item.label,
                  style: AppText.sub(active ? s.bg : s.inkSecondary)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.label,
    required this.cents,
    required this.color,
  });

  final String label;
  final int cents;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.caption(s.inkTertiary)),
        const SizedBox(height: 2),
        FMAmountText(
          cents,
          type: label.contains('收入')
              ? TransactionType.income
              : TransactionType.expense,
          style: AppText.amountL(color).copyWith(fontSize: 24),
          showSign: false,
        ),
      ],
    );
  }
}

class _GroupedList extends ConsumerStatefulWidget {
  const _GroupedList({required this.txs, required this.viewMode});

  final List<TransactionEntity> txs;
  final TransactionViewMode viewMode;

  @override
  ConsumerState<_GroupedList> createState() => _GroupedListState();
}

class _GroupedListState extends ConsumerState<_GroupedList> {
  final Set<String> _selectedIds = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  @override
  void didUpdateWidget(covariant _GroupedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final visibleIds = widget.txs.map((transaction) => transaction.id).toSet();
    _selectedIds.removeWhere((id) => !visibleIds.contains(id));
  }

  void _toggleTransaction(String id) {
    setState(() {
      _selectedIds.contains(id)
          ? _selectedIds.remove(id)
          : _selectedIds.add(id);
    });
  }

  void _toggleGroup(TransactionDisplayGroup group) {
    final ids = group.transactions.map((transaction) => transaction.id).toSet();
    final allSelected = ids.every(_selectedIds.contains);
    setState(() {
      allSelected ? _selectedIds.removeAll(ids) : _selectedIds.addAll(ids);
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    if (count == 0) return;
    final ok = await showFMConfirm(
      context,
      title: '删除选中的 $count 笔账单？',
      message: '账单会进入回收箱，24 小时内可以还原。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await ref.read(transactionRepositoryProvider).softDeleteMany(_selectedIds);
    setState(_selectedIds.clear);
    ref.read(dataVersionProvider.notifier).state++;
    if (mounted) {
      showFMToast(
        context,
        message: '已将 $count 笔移入回收箱',
        icon: FMIcons.trash,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoryMapProvider).valueOrNull ?? const {};
    final grouping = TransactionGroupingService.group(widget.txs);
    final timeline = TransactionGroupingService.timeline(widget.txs);
    final showInvoiceStatus =
        ref.watch(invoiceManagementProvider).valueOrNull ?? false;

    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.fromLTRB(
            FMSpacing.l,
            _selectionMode ? 66 : 0,
            FMSpacing.l,
            130,
          ),
          children: widget.viewMode == TransactionViewMode.time
              ? [
                  for (final group in timeline)
                    _CollapsibleGroupCard(
                      key: ValueKey('timeline:${group.key}'),
                      group: group,
                      categories: categories,
                      showInvoiceStatus: true,
                      selectedIds: _selectedIds,
                      selectionMode: _selectionMode,
                      onToggleTransaction: _toggleTransaction,
                      onToggleGroup: () => _toggleGroup(group),
                    ),
                ]
              : [
                  if (grouping.merchants.isNotEmpty) ...[
                    const _GroupSectionLabel(
                      title: '常用商户',
                      subtitle: '3 笔及以上；长按标题可选择整组',
                    ),
                    for (final group in grouping.merchants)
                      _CollapsibleGroupCard(
                        key: ValueKey('merchant:${group.key}'),
                        group: group,
                        categories: categories,
                        showInvoiceStatus: showInvoiceStatus,
                        selectedIds: _selectedIds,
                        selectionMode: _selectionMode,
                        onToggleTransaction: _toggleTransaction,
                        onToggleGroup: () => _toggleGroup(group),
                      ),
                  ],
                  if (grouping.scatteredCategories.isNotEmpty) ...[
                    const _GroupSectionLabel(
                      title: '散单',
                      subtitle: '1 至 2 笔；长按标题可选择整组',
                    ),
                    for (final group in grouping.scatteredCategories)
                      _CollapsibleGroupCard(
                        key: ValueKey('category:${group.key}'),
                        group: group,
                        categories: categories,
                        showInvoiceStatus: showInvoiceStatus,
                        selectedIds: _selectedIds,
                        selectionMode: _selectionMode,
                        onToggleTransaction: _toggleTransaction,
                        onToggleGroup: () => _toggleGroup(group),
                      ),
                  ],
                  if (grouping.company case final company?) ...[
                    const _GroupSectionLabel(
                      title: '公司账单',
                      subtitle: '开票或报销账单；不计入个人收支',
                    ),
                    _CollapsibleGroupCard(
                      key: const ValueKey('company'),
                      group: company,
                      categories: categories,
                      showInvoiceStatus: true,
                      selectedIds: _selectedIds,
                      selectionMode: _selectionMode,
                      onToggleTransaction: _toggleTransaction,
                      onToggleGroup: () => _toggleGroup(company),
                    ),
                  ],
                ],
        ),
        if (_selectionMode)
          Positioned(
            left: FMSpacing.l,
            right: FMSpacing.l,
            top: FMSpacing.xs,
            child: _SelectionToolbar(
              count: _selectedIds.length,
              allSelected: _selectedIds.length == widget.txs.length,
              onSelectAll: () => setState(() {
                if (_selectedIds.length == widget.txs.length) {
                  _selectedIds.clear();
                } else {
                  _selectedIds
                    ..clear()
                    ..addAll(widget.txs.map((transaction) => transaction.id));
                }
              }),
              onCancel: () => setState(_selectedIds.clear),
              onDelete: _deleteSelected,
            ),
          ),
      ],
    );
  }
}

class _GroupSectionLabel extends StatelessWidget {
  const _GroupSectionLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FMSpacing.xs,
        FMSpacing.l,
        FMSpacing.xs,
        FMSpacing.s,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(title,
              style: AppText.bodyStrong(s.ink)
                  .copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(width: FMSpacing.s),
          Expanded(
            child: Text(
              subtitle,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption(s.inkTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.count,
    required this.allSelected,
    required this.onSelectAll,
    required this.onCancel,
    required this.onDelete,
  });

  final int count;
  final bool allSelected;
  final VoidCallback onSelectAll;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Material(
      color: s.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(FMRadius.card),
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            const SizedBox(width: FMSpacing.m),
            IconButton(
              tooltip: '取消选择',
              onPressed: onCancel,
              icon: Icon(FMIcons.close, color: s.inkSecondary, size: 19),
            ),
            Text('已选择 $count 笔', style: AppText.bodyStrong(s.ink)),
            const Spacer(),
            TextButton(
              onPressed: onSelectAll,
              child: Text(allSelected ? '取消全选' : '全选本月'),
            ),
            IconButton(
              tooltip: '删除所选账单',
              onPressed: onDelete,
              icon: Icon(FMIcons.trash, color: s.danger, size: 20),
            ),
            const SizedBox(width: FMSpacing.xs),
          ],
        ),
      ),
    );
  }
}

class _CollapsibleGroupCard extends ConsumerStatefulWidget {
  const _CollapsibleGroupCard({
    super.key,
    required this.group,
    required this.categories,
    required this.showInvoiceStatus,
    required this.selectedIds,
    required this.selectionMode,
    required this.onToggleTransaction,
    required this.onToggleGroup,
  });

  final TransactionDisplayGroup group;
  final Map<String, Category> categories;
  final bool showInvoiceStatus;
  final Set<String> selectedIds;
  final bool selectionMode;
  final ValueChanged<String> onToggleTransaction;
  final VoidCallback onToggleGroup;

  @override
  ConsumerState<_CollapsibleGroupCard> createState() =>
      _CollapsibleGroupCardState();
}

class _CollapsibleGroupCardState extends ConsumerState<_CollapsibleGroupCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final group = widget.group;
    final category =
        group.categoryId == null ? null : widget.categories[group.categoryId];
    final title = switch (group.kind) {
      TransactionGroupKind.merchant => group.title,
      TransactionGroupKind.category => category?.name ?? '未分类',
      TransactionGroupKind.company => '公司账单',
      TransactionGroupKind.timeline => group.title,
    };
    final selectedCount = group.transactions
        .where((transaction) => widget.selectedIds.contains(transaction.id))
        .length;

    return Padding(
      padding: const EdgeInsets.only(bottom: FMSpacing.m),
      child: Container(
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: BorderRadius.circular(FMRadius.card),
          border: selectedCount > 0
              ? Border.all(color: s.accent, width: 1)
              : s.brightness == Brightness.dark
                  ? Border.all(color: s.border, width: 0.5)
                  : null,
          boxShadow: s.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Material(
              color: selectedCount > 0 ? s.accentSoft : Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                onLongPress: widget.onToggleGroup,
                child: Padding(
                  padding: const EdgeInsets.all(FMSpacing.l),
                  child: Row(
                    children: [
                      if (group.kind == TransactionGroupKind.category)
                        FMCategoryIcon(category: category)
                      else
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: s.accentSoft,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            switch (group.kind) {
                              TransactionGroupKind.company => FMIcons.company,
                              TransactionGroupKind.timeline => FMIcons.clock,
                              _ => FMIcons.store,
                            },
                            size: 19,
                            color: s.accent,
                          ),
                        ),
                      const SizedBox(width: FMSpacing.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.bodyStrong(s.ink),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _groupSubtitle(group, selectedCount),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption(s.inkTertiary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: FMSpacing.s),
                      Text(
                        _amountSummary(group),
                        style: AppText.amountM(s.ink),
                      ),
                      const SizedBox(width: FMSpacing.s),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(FMIcons.chevronDown,
                            size: 15, color: s.inkTertiary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_expanded) ...[
              Divider(height: 0.5, thickness: 0.5, color: s.separator),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: FMSpacing.m),
                child: Column(
                  children: [
                    for (final (index, transaction)
                        in group.transactions.indexed) ...[
                      FMTransactionTile(
                        transaction: transaction,
                        category: transaction.categoryId == null
                            ? null
                            : widget.categories[transaction.categoryId],
                        title: group.kind == TransactionGroupKind.merchant
                            ? _descriptionTitle(transaction)
                            : null,
                        subtitle: _transactionSubtitle(
                          transaction,
                          widget.categories[transaction.categoryId],
                          widget.showInvoiceStatus,
                          isCompany: group.kind == TransactionGroupKind.company,
                          isTimeline:
                              group.kind == TransactionGroupKind.timeline,
                        ),
                        selectionMode: widget.selectionMode,
                        selected: widget.selectedIds.contains(transaction.id),
                        onLongPress: () =>
                            widget.onToggleTransaction(transaction.id),
                        onCategoryTap: widget.selectionMode
                            ? null
                            : () => _changeCategory(transaction),
                        onTap: () {
                          if (widget.selectionMode) {
                            widget.onToggleTransaction(transaction.id);
                            return;
                          }
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => TransactionDetailPage(
                                transactionId: transaction.id,
                              ),
                            ),
                          );
                        },
                      ),
                      if (index != group.transactions.length - 1)
                        Divider(
                          height: 0.5,
                          thickness: 0.5,
                          color: s.separator,
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _amountSummary(TransactionDisplayGroup group) {
    if (group.expenseCents > 0 && group.incomeCents > 0) {
      return '支 ¥${Money.centsToCompact(group.expenseCents)} · '
          '收 ¥${Money.centsToCompact(group.incomeCents)}';
    }
    final prefix = group.incomeCents > 0 ? '+' : '-';
    final amount =
        group.incomeCents > 0 ? group.incomeCents : group.expenseCents;
    return '$prefix¥${Money.centsToCompact(amount)}';
  }

  String _groupSubtitle(TransactionDisplayGroup group, int selectedCount) {
    final selection = selectedCount > 0
        ? '已选择 $selectedCount/${group.transactions.length} 笔'
        : '${group.transactions.length} 笔';
    if (group.kind == TransactionGroupKind.timeline) {
      return '$selection · 按时间从新到旧';
    }
    return '$selection · ${_datePreview(group.transactions)}';
  }

  String _datePreview(List<TransactionEntity> transactions) {
    final dates = <String>[];
    for (final transaction in transactions) {
      final value = _monthDay(transaction.transactionTime);
      if (!dates.contains(value)) dates.add(value);
      if (dates.length == 3) break;
    }
    return dates.join('、');
  }

  String _transactionSubtitle(
    TransactionEntity transaction,
    Category? category,
    bool showInvoiceStatus, {
    bool isCompany = false,
    bool isTimeline = false,
  }) {
    return [
      if (isTimeline)
        _hourMinute(transaction.transactionTime)
      else
        _monthDay(transaction.transactionTime),
      if (isCompany ||
          (isTimeline &&
              (transaction.invoiceRequired ||
                  transaction.invoiceIssued ||
                  transaction.invoiceWaived ||
                  transaction.reimbursed)))
        '公司账单',
      category?.name ?? '未分类',
      if (transaction.status == TxStatus.needsReview) '待确认',
      if (transaction.transactionTime.isAfter(DateTime.now())) '待发生',
      if (showInvoiceStatus && transaction.reimbursed)
        '已报销'
      else if (showInvoiceStatus && transaction.invoiceWaived)
        '无需开票'
      else if (showInvoiceStatus && transaction.invoiceIssued)
        '已开票'
      else if (showInvoiceStatus && transaction.invoiceRequired)
        '需开票',
    ].join(' · ');
  }

  String _monthDay(DateTime time) => '${time.month}月${time.day}日';

  String _hourMinute(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  String _descriptionTitle(TransactionEntity transaction) {
    final description = transaction.description?.trim() ?? '';
    if (description.isNotEmpty) return description;
    final note = transaction.note?.trim() ?? '';
    return note.isNotEmpty ? note : '未填写描述';
  }

  Future<void> _changeCategory(TransactionEntity transaction) async {
    final categories = await ref.read(visibleCategoriesProvider.future);
    if (!mounted) return;
    final current = transaction.categoryId == null
        ? null
        : widget.categories[transaction.categoryId];
    final picked = await showCategoryPicker(
      context,
      categories: categories,
      type: transaction.type,
      current: current,
    );
    if (picked == null || picked.id == transaction.categoryId) return;
    await ref.read(transactionRepositoryProvider).update(
          transaction.copyWith(
            categoryId: picked.id,
            clearSubcategory: true,
            updatedAt: DateTime.now(),
          ),
        );
    ref.read(dataVersionProvider.notifier).state++;
    if (mounted) {
      showFMToast(
        context,
        message: '已改为${picked.name}',
        icon: FMIcons.checkCircle,
      );
    }
  }
}

class _CategoryFilterSheet extends StatefulWidget {
  const _CategoryFilterSheet(
      {required this.categories, required this.selected});

  final List<Category> categories;
  final Set<String> selected;

  @override
  State<_CategoryFilterSheet> createState() => _CategoryFilterSheetState();
}

class _CategoryFilterSheetState extends State<_CategoryFilterSheet> {
  late final Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            FMSpacing.l, FMSpacing.xs, FMSpacing.l, FMSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('按分类筛选',
                style: AppText.title(s.ink), textAlign: TextAlign.center),
            const SizedBox(height: FMSpacing.l),
            Wrap(
              spacing: FMSpacing.s,
              runSpacing: FMSpacing.s,
              children: [
                for (final c in widget.categories)
                  GestureDetector(
                    onTap: () => setState(() {
                      _selected.contains(c.id)
                          ? _selected.remove(c.id)
                          : _selected.add(c.id);
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: FMSpacing.m, vertical: 8),
                      decoration: BoxDecoration(
                        color: _selected.contains(c.id)
                            ? c.color.withValues(alpha: 0.15)
                            : s.ink.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: _selected.contains(c.id)
                              ? c.color.withValues(alpha: 0.5)
                              : Colors.transparent,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FMCategoryIcon(category: c, size: 20),
                          const SizedBox(width: 6),
                          Text(c.name,
                              style: AppText.sub(
                                _selected.contains(c.id)
                                    ? s.ink
                                    : s.inkSecondary,
                              )),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: FMSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(_selected.clear),
                    child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: s.ink.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(FMRadius.button),
                      ),
                      child:
                          Text('清除', style: AppText.bodyStrong(s.inkSecondary)),
                    ),
                  ),
                ),
                const SizedBox(width: FMSpacing.m),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(_selected),
                    child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: s.accent,
                        borderRadius: BorderRadius.circular(FMRadius.button),
                      ),
                      child:
                          Text('确定', style: AppText.bodyStrong(Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
