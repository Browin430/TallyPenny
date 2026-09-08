import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/id_gen.dart';
import '../../core/utils/money_utils.dart';
import '../../core/widgets/fm_sheets.dart';
import '../../core/widgets/fm_toast.dart';
import '../../domain/models/category.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/recurring_transaction.dart';
import '../../state/app_providers.dart';
import '../entry/category_picker_sheet.dart';

class RecurringTransactionsPage extends ConsumerWidget {
  const RecurringTransactionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.colors;
    final rules = ref.watch(recurringTransactionsProvider);
    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        title: const Text('周期记账'),
        actions: [
          IconButton(
            tooltip: '新建周期记账',
            icon: const Icon(FMIcons.plus),
            onPressed: () => _openEditor(context, ref),
          ),
        ],
      ),
      body: rules.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('加载失败：$error')),
        data: (items) => items.isEmpty
            ? _EmptyState(onAdd: () => _openEditor(context, ref))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  FMSpacing.l,
                  FMSpacing.m,
                  FMSpacing.l,
                  FMSpacing.xxl,
                ),
                itemCount: items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: FMSpacing.m),
                itemBuilder: (_, index) => _RuleCard(
                  rule: items[index],
                  onTap: () => _openEditor(context, ref, items[index]),
                  onToggle: (enabled) =>
                      _toggle(context, ref, items[index], enabled),
                  onDelete: () => _delete(context, ref, items[index]),
                ),
              ),
      ),
      floatingActionButton: rules.valueOrNull?.isNotEmpty == true
          ? FloatingActionButton(
              onPressed: () => _openEditor(context, ref),
              child: const Icon(FMIcons.plus),
            )
          : null,
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, [
    RecurringTransaction? existing,
  ]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecurringEditPage(existing: existing),
      ),
    );
    if (saved == true) ref.invalidate(recurringTransactionsProvider);
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    RecurringTransaction rule,
    bool enabled,
  ) async {
    final repository = ref.read(recurringTransactionRepositoryProvider);
    await repository.upsert(rule.copyWith(
      enabled: enabled,
      updatedAt: DateTime.now(),
      clearLastRunAt: enabled,
    ));
    ref.read(recurringVersionProvider.notifier).state++;
    if (enabled) {
      final inserted = await ref.read(recurringProcessorProvider).runDue();
      if (inserted > 0) ref.read(dataVersionProvider.notifier).state++;
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    RecurringTransaction rule,
  ) async {
    final ok = await showFMConfirm(
      context,
      title: '删除“${rule.title}”？',
      message: '只删除周期规则，已经生成的流水会保留。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(recurringTransactionRepositoryProvider).delete(rule.id);
    ref.read(recurringVersionProvider.notifier).state++;
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.rule,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  final RecurringTransaction rule;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final amountColor = rule.type == TransactionType.income ? s.income : s.ink;
    return Material(
      color: s.surface,
      borderRadius: BorderRadius.circular(FMRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FMRadius.card),
        child: Container(
          padding: const EdgeInsets.all(FMSpacing.l),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FMRadius.card),
            border: Border.all(color: s.border, width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s.accentSoft,
                  borderRadius: BorderRadius.circular(FMRadius.iconBox),
                ),
                child: Icon(FMIcons.sync, size: 19, color: s.accent),
              ),
              const SizedBox(width: FMSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rule.title, style: AppText.bodyStrong(s.ink)),
                    const SizedBox(height: 3),
                    Text(rule.scheduleLabel,
                        style: AppText.caption(s.inkTertiary)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${rule.type == TransactionType.income ? '+' : '-'}¥${Money.centsToText(rule.amountCents)}',
                    style: AppText.amountS(amountColor),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: onDelete,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(FMIcons.trash,
                              size: 15, color: s.inkTertiary),
                        ),
                      ),
                      Transform.scale(
                        scale: 0.8,
                        child: Switch(value: rule.enabled, onChanged: onToggle),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FMSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FMIcons.sync, size: 42, color: s.inkTertiary),
            const SizedBox(height: FMSpacing.l),
            Text('还没有周期记账', style: AppText.title(s.ink)),
            const SizedBox(height: FMSpacing.s),
            Text(
              '房租、工资、订阅等固定收支，可以按天、工作日、周或月自动补记。',
              textAlign: TextAlign.center,
              style: AppText.body(s.inkSecondary),
            ),
            const SizedBox(height: FMSpacing.xl),
            FilledButton(onPressed: onAdd, child: const Text('新建周期记账')),
          ],
        ),
      ),
    );
  }
}

class RecurringEditPage extends ConsumerStatefulWidget {
  const RecurringEditPage({super.key, this.existing});
  final RecurringTransaction? existing;

  @override
  ConsumerState<RecurringEditPage> createState() => _RecurringEditPageState();
}

class _RecurringEditPageState extends ConsumerState<RecurringEditPage> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  late TransactionType _type;
  late RecurringFrequency _frequency;
  late DateTime _startDate;
  DateTime? _endDate;
  late TimeOfDay _time;
  late int _weekday;
  late int _dayOfMonth;
  late bool _singleRestDay;
  String? _categoryId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final now = DateTime.now();
    _type = existing?.type ?? TransactionType.expense;
    _frequency = existing?.frequency ?? RecurringFrequency.monthly;
    _startDate = existing?.startDate ?? DateTime(now.year, now.month, now.day);
    _endDate = existing?.endDate;
    _time = TimeOfDay(
      hour: existing?.hour ?? 9,
      minute: existing?.minute ?? 0,
    );
    _weekday = existing != null && existing.daysOfWeek.isNotEmpty
        ? existing.daysOfWeek.first
        : _startDate.weekday;
    _dayOfMonth = existing?.dayOfMonth ?? _startDate.day;
    _singleRestDay = existing?.frequency == RecurringFrequency.workdays &&
        existing!.daysOfWeek.contains(DateTime.saturday);
    _categoryId = existing?.categoryId;
    _titleController.text = existing?.title ?? '';
    _amountController.text = existing == null
        ? ''
        : Money.centsToText(existing.amountCents).replaceAll(',', '');
    _merchantController.text = existing?.merchant ?? '';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _merchantController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        title: Text(widget.existing == null ? '新建周期记账' : '编辑周期记账'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text('保存', style: AppText.bodyStrong(s.accent)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          FMSpacing.l,
          FMSpacing.s,
          FMSpacing.l,
          FMSpacing.xxl,
        ),
        children: [
          _typeSegment(s),
          const SizedBox(height: FMSpacing.l),
          _InputCard(
            child: TextField(
              controller: _titleController,
              maxLength: 20,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '如：房租、工资、视频会员',
                counterText: '',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: FMSpacing.m),
          _InputCard(
            child: TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: AppText.amountM(s.ink),
              decoration: const InputDecoration(
                labelText: '金额',
                prefixText: '¥ ',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: FMSpacing.m),
          _ActionRow(
            icon: FMIcons.tag,
            label: '分类',
            value: _categoryName(),
            onTap: _pickCategory,
          ),
          const SizedBox(height: FMSpacing.m),
          _InputCard(
            child: TextField(
              controller: _merchantController,
              decoration: const InputDecoration(
                labelText: '商户（可选）',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: FMSpacing.l),
          Text('重复规则', style: AppText.caption(s.inkTertiary)),
          const SizedBox(height: FMSpacing.s),
          _InputCard(
            child: DropdownButtonFormField<RecurringFrequency>(
              initialValue: _frequency,
              decoration: const InputDecoration(
                labelText: '频率',
                border: InputBorder.none,
              ),
              items: RecurringFrequency.values
                  .map((value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.label),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _frequency = value);
              },
            ),
          ),
          if (_frequency == RecurringFrequency.weekly) ...[
            const SizedBox(height: FMSpacing.m),
            _InputCard(
              child: DropdownButtonFormField<int>(
                initialValue: _weekday,
                decoration: const InputDecoration(
                  labelText: '每周',
                  border: InputBorder.none,
                ),
                items: List.generate(
                  7,
                  (index) => DropdownMenuItem(
                    value: index + 1,
                    child: Text('星期${const [
                      '一',
                      '二',
                      '三',
                      '四',
                      '五',
                      '六',
                      '日'
                    ][index]}'),
                  ),
                ),
                onChanged: (value) => setState(() => _weekday = value ?? 1),
              ),
            ),
          ],
          if (_frequency == RecurringFrequency.workdays) ...[
            const SizedBox(height: FMSpacing.m),
            _InputCard(
              child: DropdownButtonFormField<bool>(
                initialValue: _singleRestDay,
                decoration: const InputDecoration(
                  labelText: '休息制度',
                  border: InputBorder.none,
                ),
                items: const [
                  DropdownMenuItem(
                    value: false,
                    child: Text('双休（周一至周五）'),
                  ),
                  DropdownMenuItem(
                    value: true,
                    child: Text('单休（周一至周六）'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _singleRestDay = value ?? false),
              ),
            ),
          ],
          if (_frequency == RecurringFrequency.monthly) ...[
            const SizedBox(height: FMSpacing.m),
            _InputCard(
              child: DropdownButtonFormField<int>(
                initialValue: _dayOfMonth,
                decoration: const InputDecoration(
                  labelText: '每月日期',
                  border: InputBorder.none,
                ),
                items: List.generate(
                  31,
                  (index) => DropdownMenuItem(
                    value: index + 1,
                    child: Text('${index + 1} 日'),
                  ),
                ),
                onChanged: (value) => setState(() => _dayOfMonth = value ?? 1),
              ),
            ),
          ],
          const SizedBox(height: FMSpacing.m),
          _ActionRow(
            icon: FMIcons.calendar,
            label: '开始日期',
            value: _dateLabel(_startDate),
            onTap: _pickStartDate,
          ),
          const SizedBox(height: FMSpacing.m),
          _ActionRow(
            icon: FMIcons.clock,
            label: '记账时间',
            value: _time.format(context),
            onTap: _pickTime,
          ),
          const SizedBox(height: FMSpacing.m),
          _ActionRow(
            icon: FMIcons.timer,
            label: '截止日期',
            value: _endDate == null ? '长期有效' : _dateLabel(_endDate!),
            onTap: _pickEndDate,
            trailing: _endDate == null
                ? null
                : IconButton(
                    tooltip: '清除截止日期',
                    icon: Icon(FMIcons.close, size: 16, color: s.inkTertiary),
                    onPressed: () => setState(() => _endDate = null),
                  ),
          ),
          const SizedBox(height: FMSpacing.xl),
          FilledButton(
            onPressed: _saving ? null : _save,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(_saving ? '保存中…' : '保存周期记账'),
          ),
        ],
      ),
    );
  }

  Widget _typeSegment(FMScheme s) => SegmentedButton<TransactionType>(
        segments: const [
          ButtonSegment(value: TransactionType.expense, label: Text('支出')),
          ButtonSegment(value: TransactionType.income, label: Text('收入')),
        ],
        selected: {_type},
        onSelectionChanged: (value) => setState(() {
          _type = value.first;
          _categoryId = null;
        }),
      );

  String _categoryName() {
    final map = ref.watch(categoryMapProvider).valueOrNull;
    return map?[_categoryId]?.name ??
        (_type == TransactionType.income ? '其他收入' : '其他');
  }

  Future<void> _pickCategory() async {
    final categories = await ref.read(visibleCategoriesProvider.future);
    if (!mounted) return;
    Category? current;
    if (_categoryId != null) {
      current = await ref.read(categoryRepositoryProvider).byId(_categoryId!);
    }
    if (!mounted) return;
    final picked = await showCategoryPicker(
      context,
      categories: categories,
      type: _type,
      current: current,
    );
    if (picked != null) {
      setState(() => _categoryId = picked.id);
    }
  }

  Future<void> _pickStartDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (value != null) {
      setState(() {
        _startDate = value;
        if (_frequency == RecurringFrequency.weekly) _weekday = value.weekday;
        if (_frequency == RecurringFrequency.monthly) _dayOfMonth = value.day;
      });
    }
  }

  Future<void> _pickEndDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate,
      firstDate: _startDate,
      lastDate: DateTime(2100),
    );
    if (value != null) setState(() => _endDate = value);
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(context: context, initialTime: _time);
    if (value != null) setState(() => _time = value);
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final amount = Money.parseToCents(_amountController.text);
    if (title.isEmpty || amount == null) {
      showFMToast(
        context,
        message: title.isEmpty ? '请输入名称' : '请输入有效金额',
        icon: FMIcons.warning,
      );
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now();
    final existing = widget.existing;
    final rule = RecurringTransaction(
      id: existing?.id ?? IdGen.newId(),
      userId: existing?.userId ?? 'local',
      title: title,
      amountCents: amount,
      type: _type,
      categoryId: _categoryId ??
          (_type == TransactionType.income ? 'other_income' : 'other'),
      merchant: _merchantController.text.trim().isEmpty
          ? null
          : _merchantController.text.trim(),
      frequency: _frequency,
      daysOfWeek: switch (_frequency) {
        RecurringFrequency.weekly => [_weekday],
        RecurringFrequency.workdays =>
          _singleRestDay ? const [1, 2, 3, 4, 5, 6] : const [1, 2, 3, 4, 5],
        _ => const [],
      },
      dayOfMonth: _frequency == RecurringFrequency.monthly ? _dayOfMonth : null,
      startDate: _startDate,
      endDate: _endDate,
      hour: _time.hour,
      minute: _time.minute,
      enabled: existing?.enabled ?? true,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      // 编辑后重新扫描；处理器按规则 id + 发生时间去重。
      lastRunAt: null,
    );
    await ref.read(recurringTransactionRepositoryProvider).upsert(rule);
    ref.read(recurringVersionProvider.notifier).state++;
    final processor = ref.read(recurringProcessorProvider);
    final changed = await processor.runDue();
    if (changed > 0) {
      ref.read(dataVersionProvider.notifier).state++;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  static String _dateLabel(DateTime value) =>
      '${value.year}年${value.month}月${value.day}日';
}

class _InputCard extends StatelessWidget {
  const _InputCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: FMSpacing.l),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(FMRadius.field),
          border: Border.all(color: context.colors.border, width: 0.5),
        ),
        child: child,
      );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Material(
      color: s.surface,
      borderRadius: BorderRadius.circular(FMRadius.field),
      child: InkWell(
        borderRadius: BorderRadius.circular(FMRadius.field),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: FMSpacing.l),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FMRadius.field),
            border: Border.all(color: s.border, width: 0.5),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: s.inkSecondary),
              const SizedBox(width: FMSpacing.m),
              Text(label, style: AppText.body(s.inkSecondary)),
              const Spacer(),
              Text(value, style: AppText.body(s.ink)),
              if (trailing != null)
                trailing!
              else ...[
                const SizedBox(width: FMSpacing.s),
                Icon(FMIcons.chevronRight, size: 14, color: s.inkTertiary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
