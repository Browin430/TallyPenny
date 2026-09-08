import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money_utils.dart';
import '../../core/widgets/fm_sheets.dart';
import '../../core/widgets/fm_toast.dart';
import '../../domain/models/category.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/transaction.dart';
import '../../domain/models/transaction_candidate.dart';
import '../../state/app_providers.dart';
import 'category_picker_sheet.dart';
import 'entry_flow.dart';

/// 手动记账 / 编辑账单（[existing] 非空时为编辑模式）。
class ManualEntryPage extends ConsumerStatefulWidget {
  const ManualEntryPage({super.key, this.existing});

  final TransactionEntity? existing;

  @override
  ConsumerState<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends ConsumerState<ManualEntryPage> {
  late TransactionType _type;
  late DateTime _time;
  PaymentMethod? _payment;
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  final _noteController = TextEditingController();
  final _amountFocus = FocusNode();
  bool _saving = false;
  String? _amountError;
  late bool _invoiceRequired;
  late bool _invoiceIssued;
  late bool _invoiceWaived;
  late bool _reimbursed;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? TransactionType.expense;
    _time = e?.transactionTime ?? DateTime.now();
    _payment = e?.paymentMethod;
    _invoiceRequired = e?.invoiceRequired ?? false;
    _invoiceIssued = e?.invoiceIssued ?? false;
    _invoiceWaived = e?.invoiceWaived ?? false;
    _reimbursed = e?.reimbursed ?? false;
    if (e != null) {
      _amountController.text = Money.centsToText(e.amountCents);
      _merchantController.text = e.merchant ?? '';
      _noteController.text = e.note ?? '';
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _noteController.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  String? get _categoryId {
    final e = widget.existing;
    if (e != null) return e.categoryId;
    return _type == TransactionType.income ? 'other_income' : 'food';
  }

  Future<void> _pickCategory() async {
    final categories = await ref.read(visibleCategoriesProvider.future);
    if (!mounted) return;
    final categoriesRepo = ref.read(categoryRepositoryProvider);
    final current =
        _categoryId != null ? await categoriesRepo.byId(_categoryId!) : null;
    if (!mounted) return;
    final picked = await showCategoryPicker(
      context,
      categories: categories,
      type: _type,
      current: current,
    );
    if (picked != null) {
      // 手动模式下直接替换分类。
      setState(() => _manualCategory = picked);
    }
  }

  Category? _manualCategory;

  Future<void> _save() async {
    final cents = Money.parseToCents(_amountController.text);
    if (cents == null) {
      setState(() => _amountError = '请输入有效金额');
      _amountFocus.requestFocus();
      return;
    }
    setState(() {
      _saving = true;
      _amountError = null;
    });

    try {
      final e = widget.existing;
      if (e != null) {
        // 编辑模式：直接更新（保留原始 source records）。
        final updated = TransactionEntity(
          id: e.id,
          userId: e.userId,
          type: _type,
          amountCents: cents,
          currency: e.currency,
          categoryId: _manualCategory?.id ?? e.categoryId,
          subcategory: e.subcategory,
          merchant: _merchantController.text.trim().isEmpty
              ? null
              : _merchantController.text.trim(),
          description: e.description,
          transactionTime: _time,
          createdAt: e.createdAt,
          updatedAt: DateTime.now(),
          sourceType: e.sourceType,
          confidence: e.confidence,
          status: TxStatus.confirmed,
          isRecurring: e.isRecurring,
          recurringTransactionId: e.recurringTransactionId,
          paymentMethod: _payment,
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
          invoiceRequired: _invoiceRequired,
          invoiceIssued: _invoiceIssued,
          invoiceWaived: _invoiceWaived,
          reimbursed: _reimbursed,
          isDeleted: e.isDeleted,
          deletedAt: e.deletedAt,
        );
        await ref.read(transactionRepositoryProvider).update(updated);
        ref.read(dataVersionProvider.notifier).state++;
        if (mounted) {
          showFMToast(context, message: '已更新', icon: FMIcons.checkCircle);
          Navigator.of(context).pop(true);
        }
        return;
      }

      final candidate = TransactionCandidate(
        sourceType: SourceType.manual,
        confidence: 1.0,
        type: _type,
        amountCents: cents,
        categoryId: _manualCategory?.id ?? _categoryId,
        merchant: _merchantController.text.trim(),
        description: null,
        transactionTime: _time,
        paymentMethod: _payment,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        invoiceRequired: _invoiceRequired,
        invoiceIssued: _invoiceIssued,
        invoiceWaived: _invoiceWaived,
        reimbursed: _reimbursed,
      );
      final saved = await saveCandidateFlow(context, ref, candidate);
      if (saved && mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final isEdit = widget.existing != null;
    final catName = _categoryName();
    final invoiceEnabled =
        ref.watch(invoiceManagementProvider).valueOrNull ?? false;

    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        title: Text(isEdit ? '编辑账单' : '手动记账'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('保存', style: AppText.bodyStrong(s.accent)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            FMSpacing.l, FMSpacing.s, FMSpacing.l, FMSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- 类型切换 ----
            _buildTypeSegment(s),

            // ---- 金额 ----
            const SizedBox(height: FMSpacing.xl),
            TextField(
              controller: _amountController,
              focusNode: _amountFocus,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              autofocus: !isEdit,
              style: AppText.amountXL(s.ink),
              cursorColor: s.accent,
              decoration: InputDecoration(
                hintText: '0.00',
                errorText: _amountError,
                prefixText: '¥ ',
                prefixStyle: AppText.amountL(s.inkTertiary),
                border: InputBorder.none,
              ),
            ),

            // ---- 分类 ----
            const SizedBox(height: FMSpacing.l),
            _FieldRow(
              icon: FMIcons.tag,
              label: '分类',
              value: catName,
              onTap: _pickCategory,
            ),

            // ---- 时间 ----
            const SizedBox(height: FMSpacing.m),
            _FieldRow(
              icon: FMIcons.clock,
              label: '时间',
              value: AppDate.fullTitle(_time),
              onTap: _pickTime,
            ),
            if (_time.isAfter(DateTime.now()))
              Padding(
                padding: const EdgeInsets.only(top: FMSpacing.xs, right: 4),
                child: Text(
                  '未来账单，到期前不计入本月结余',
                  textAlign: TextAlign.right,
                  style: AppText.caption(s.warn),
                ),
              ),

            // ---- 商户 ----
            const SizedBox(height: FMSpacing.m),
            _FieldRow(
              icon: FMIcons.store,
              label: '商户',
              value: null,
              child: TextField(
                controller: _merchantController,
                textAlign: TextAlign.end,
                textAlignVertical: TextAlignVertical.center,
                style: AppText.body(s.ink),
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: '如：星巴克',
                  hintStyle: AppText.body(s.inkTertiary),
                  border: InputBorder.none,
                ),
              ),
            ),

            // ---- 支付方式 ----
            if (_type == TransactionType.expense) ...[
              const SizedBox(height: FMSpacing.m),
              _FieldRow(
                icon: FMIcons.card,
                label: '支付方式',
                value: _payment?.label,
                onTap: _pickPayment,
              ),
            ],

            // ---- 备注 ----
            const SizedBox(height: FMSpacing.m),
            _FieldRow(
              icon: FMIcons.note,
              label: '备注',
              value: null,
              child: TextField(
                controller: _noteController,
                textAlign: TextAlign.end,
                textAlignVertical: TextAlignVertical.center,
                style: AppText.body(s.ink),
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: '备注',
                  hintStyle: AppText.body(s.inkTertiary),
                  border: InputBorder.none,
                ),
              ),
            ),

            if (invoiceEnabled) ...[
              const SizedBox(height: FMSpacing.m),
              _InvoiceStatusCard(
                invoiceRequired: _invoiceRequired,
                invoiceIssued: _invoiceIssued,
                invoiceWaived: _invoiceWaived,
                reimbursed: _reimbursed,
                onRequiredChanged: (value) => setState(() {
                  _invoiceRequired = value;
                  if (value) _invoiceWaived = false;
                  if (!value) {
                    _invoiceIssued = false;
                  }
                }),
                onIssuedChanged: (value) => setState(() {
                  _invoiceIssued = value;
                  if (value) {
                    _invoiceRequired = true;
                    _invoiceWaived = false;
                  }
                }),
                onWaivedChanged: (value) => setState(() {
                  _invoiceWaived = value;
                  if (value) {
                    _invoiceRequired = false;
                    _invoiceIssued = false;
                  }
                }),
                onReimbursedChanged: (value) =>
                    setState(() => _reimbursed = value),
              ),
            ],

            const SizedBox(height: FMSpacing.xxl),
            // ---- 保存按钮 ----
            GestureDetector(
              onTap: _saving ? null : _save,
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _saving ? s.accent.withValues(alpha: 0.5) : s.accent,
                  borderRadius: BorderRadius.circular(FMRadius.button),
                ),
                child: Text(
                  isEdit ? '保存修改' : '保存',
                  style:
                      AppText.bodyStrong(Colors.white).copyWith(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryName() {
    if (_manualCategory != null) return _manualCategory!.name;
    final e = widget.existing;
    if (e != null) {
      final map = ref.read(categoryMapProvider).valueOrNull;
      return map?[e.categoryId]?.name ?? '未分类';
    }
    return _type == TransactionType.income ? '其他收入' : '餐饮';
  }

  Widget _buildTypeSegment(FMScheme s) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: s.ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        children: [
          for (final t in TransactionType.values)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _type = t;
                  _manualCategory = null;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _type == t
                        ? (t == TransactionType.income ? s.income : s.accent)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    t.label,
                    style: AppText.bodyStrong(
                      _type == t ? Colors.white : s.inkSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _time,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100, 12, 31),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
    );
    if (!mounted) return;
    setState(() {
      _time = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _time.hour,
        time?.minute ?? _time.minute,
      );
    });
  }

  Future<void> _pickPayment() async {
    final picked = await showFMSheet<PaymentMethod>(
      context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FMSpacing.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in PaymentMethod.values)
                ListTile(
                  title: Text(p.label,
                      style: AppText.bodyStrong(context.colors.ink)),
                  trailing: _payment == p
                      ? Icon(FMIcons.check,
                          size: 18, color: context.colors.accent)
                      : null,
                  onTap: () => Navigator.of(context).pop(p),
                ),
              const SizedBox(height: FMSpacing.m),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _payment = picked);
  }
}

class _InvoiceStatusCard extends StatelessWidget {
  const _InvoiceStatusCard({
    required this.invoiceRequired,
    required this.invoiceIssued,
    required this.invoiceWaived,
    required this.reimbursed,
    required this.onRequiredChanged,
    required this.onIssuedChanged,
    required this.onWaivedChanged,
    required this.onReimbursedChanged,
  });

  final bool invoiceRequired;
  final bool invoiceIssued;
  final bool invoiceWaived;
  final bool reimbursed;
  final ValueChanged<bool> onRequiredChanged;
  final ValueChanged<bool> onIssuedChanged;
  final ValueChanged<bool> onWaivedChanged;
  final ValueChanged<bool> onReimbursedChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(FMRadius.field),
        border: Border.all(color: s.border, width: 0.5),
      ),
      child: Column(
        children: [
          _InvoiceSwitch(
            label: '需要开票',
            value: invoiceRequired,
            onChanged: onRequiredChanged,
          ),
          _InvoiceSwitch(
            label: '已经开票',
            value: invoiceIssued,
            onChanged: onIssuedChanged,
          ),
          _InvoiceSwitch(
            label: '无需开票',
            value: invoiceWaived,
            onChanged: onWaivedChanged,
          ),
          _InvoiceSwitch(
            label: '已经报销',
            value: reimbursed,
            onChanged: onReimbursedChanged,
          ),
        ],
      ),
    );
  }
}

class _InvoiceSwitch extends StatelessWidget {
  const _InvoiceSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: FMSpacing.l),
          Text(label, style: AppText.body(s.ink)),
          const Spacer(),
          Switch.adaptive(
            value: value,
            activeTrackColor: s.accent,
            onChanged: onChanged,
          ),
          const SizedBox(width: FMSpacing.s),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.child,
  });

  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: FMSpacing.l, vertical: 6),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(FMRadius.field),
        border: Border.all(color: s.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: s.inkSecondary),
          const SizedBox(width: FMSpacing.m),
          Text(label, style: AppText.body(s.inkSecondary)),
          const SizedBox(width: FMSpacing.l),
          Expanded(
            child: child ??
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: Text(
                    value ?? '点击选择',
                    textAlign: TextAlign.end,
                    style: AppText.body(
                      value != null ? s.ink : s.inkTertiary,
                    ),
                  ),
                ),
          ),
          if (child == null && onTap != null) ...[
            const SizedBox(width: FMSpacing.xs),
            Icon(FMIcons.chevronRight, size: 14, color: s.inkTertiary),
          ],
        ],
      ),
    );
  }
}
