import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money_utils.dart';
import '../../core/widgets/fm_toast.dart';
import '../../domain/models/category.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/transaction.dart';
import '../../domain/models/transaction_candidate.dart';
import '../../state/app_providers.dart';
import 'category_picker_sheet.dart';
import 'entry_flow.dart';

/// AI 解析结果卡片（语音 / 截图共用）。
/// 产品原则：识别即入库（[autoSave]，缺金额时才保留"保存"按钮），
/// 用户编辑金额/分类/商户直接同步已入库记录，不想要点删除（软删除）。
class CandidateReviewCard extends ConsumerStatefulWidget {
  const CandidateReviewCard({
    super.key,
    required this.candidate,
    required this.onRemoved,
    this.headerText,
    this.autoSave = true,
  });

  final TransactionCandidate candidate;

  /// 顶部说明（如"你说的：" 或 识别文本）。
  final String? headerText;

  /// 卡片被移除（用户删除，或手动保存完成）后回调，父级据此从列表清除。
  final VoidCallback onRemoved;

  /// true：挂载即自动入库；false：保留旧的"点保存"流程。
  final bool autoSave;

  @override
  ConsumerState<CandidateReviewCard> createState() =>
      _CandidateReviewCardState();
}

class _CandidateReviewCardState extends ConsumerState<CandidateReviewCard> {
  late final TextEditingController _amountController;
  late final TextEditingController _merchantController;
  final FocusNode _amountFocus = FocusNode();
  final FocusNode _merchantFocus = FocusNode();
  Category? _categoryOverride;
  TransactionType? _typeOverride;
  String? _amountError;
  late DateTime _time;

  bool _autoSaving = true;
  bool _saving = false; // 缺金额时的手动保存

  /// 已入库的账单（自动合并时为被合并进的原有账单）。
  TransactionEntity? _savedTx;
  bool _mergedIntoExisting = false;
  bool _duplicateKept = false;
  bool _deleted = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.candidate.amountCents == null
          ? ''
          : Money.centsToText(widget.candidate.amountCents!),
    );
    _merchantController = TextEditingController(
      text: widget.candidate.merchant ?? '',
    );
    _time = widget.candidate.transactionTime ?? DateTime.now();
    _amountFocus.addListener(_onFocusLost);
    _merchantFocus.addListener(_onFocusLost);
    if (widget.autoSave && widget.candidate.hasAmount) {
      _autoSave();
    } else {
      _autoSaving = false;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _amountFocus.dispose();
    _merchantFocus.dispose();
    super.dispose();
  }

  // ---- 自动保存 ----

  Future<void> _autoSave() async {
    final outcome = await autoSaveCandidateFlow(ref, widget.candidate);
    if (!mounted) return;
    switch (outcome) {
      case AutoSaved(
          :final transaction,
          :final mergedIntoExisting,
          :final duplicateKept,
        ):
        setState(() {
          _savedTx = transaction;
          _time = transaction.transactionTime;
          _mergedIntoExisting = mergedIntoExisting;
          _duplicateKept = duplicateKept;
          _autoSaving = false;
        });
      case AutoSaveNeedsAmount():
        setState(() => _autoSaving = false);
    }
  }

  // ---- 编辑同步（金额 / 商户失焦落库；分类点选即落库）----

  void _onFocusLost() {
    if (_amountFocus.hasFocus || _merchantFocus.hasFocus) return;
    _syncEditsFromControllers();
  }

  void _syncEditsFromControllers() {
    final tx = _savedTx;
    if (tx == null || _deleted) return;

    if (_amountController.text.trim().isEmpty) {
      _amountController.text = Money.centsToText(tx.amountCents);
    }
    final cents = Money.parseToCents(_amountController.text);
    if (cents == null) {
      setState(() => _amountError = '请输入有效金额');
      return;
    }
    final merchant = _merchantController.text.trim();
    final amountChanged = cents != tx.amountCents;
    final merchantChanged = merchant != (tx.merchant ?? '');
    if (!amountChanged && !merchantChanged) return;

    setState(() => _amountError = null);
    var updated = tx;
    if (amountChanged) updated = updated.copyWith(amountCents: cents);
    if (merchantChanged) {
      updated = updated.copyWith(merchant: merchant.isEmpty ? null : merchant);
    }
    _persist(updated);
  }

  Future<void> _persist(TransactionEntity updated) async {
    try {
      await ref.read(transactionRepositoryProvider).update(updated.copyWith(
            updatedAt: DateTime.now(),
            status: TxStatus.confirmed,
          ));
      ref.read(dataVersionProvider.notifier).state++;
      if (mounted) setState(() => _savedTx = updated);
    } catch (_) {
      if (mounted) {
        showFMToast(
          context,
          message: '更新失败，请重试',
          icon: FMIcons.warning,
          iconColor: context.colors.danger,
        );
      }
    }
  }

  // ---- 删除（软删除）----

  Future<void> _deleteSaved() async {
    final tx = _savedTx;
    if (tx == null || _deleted) return;
    setState(() => _deleted = true);
    await ref.read(transactionRepositoryProvider).softDelete(tx.id);
    ref.read(dataVersionProvider.notifier).state++;
    if (mounted) widget.onRemoved();
  }

  // ---- 分类（可切换支出/收入）----

  TransactionType get _effectiveType =>
      _typeOverride ?? widget.candidate.type ?? TransactionType.expense;

  Category? _categoryOf() {
    if (_categoryOverride != null) return _categoryOverride;
    final map = ref.watch(categoryMapProvider).valueOrNull;
    return widget.candidate.categoryId == null
        ? null
        : map?[widget.candidate.categoryId];
  }

  Future<void> _pickCategory() async {
    final categories = await ref.read(visibleCategoriesProvider.future);
    if (!mounted) return;
    final picked = await showCategoryPicker(
      context,
      categories: categories,
      type: _effectiveType,
      current: _categoryOf(),
      allowTypeSwitch: true,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _categoryOverride = picked;
      _typeOverride = picked.type;
    });
    final tx = _savedTx;
    if (tx != null && (tx.categoryId != picked.id || tx.type != picked.type)) {
      await _persist(tx.copyWith(categoryId: picked.id, type: picked.type));
    }
  }

  Future<void> _pickTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _time,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (date == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
    );
    if (!mounted) return;
    final updatedTime = DateTime(
      date.year,
      date.month,
      date.day,
      pickedTime?.hour ?? _time.hour,
      pickedTime?.minute ?? _time.minute,
    );
    setState(() => _time = updatedTime);
    final tx = _savedTx;
    if (tx != null && tx.transactionTime != updatedTime) {
      await _persist(tx.copyWith(transactionTime: updatedTime));
    }
  }

  // ---- 缺金额时的手动保存 ----

  Future<void> _saveManually() async {
    final cents = Money.parseToCents(_amountController.text);
    if (cents == null) {
      setState(() => _amountError = '请输入有效金额');
      return;
    }
    setState(() {
      _saving = true;
      _amountError = null;
    });
    try {
      final c = widget.candidate;
      final updated = TransactionCandidate(
        sourceType: c.sourceType,
        confidence: c.confidence,
        type: _effectiveType,
        amountCents: cents,
        currency: c.currency,
        categoryId: _categoryOverride?.id ?? c.categoryId,
        subcategory: c.subcategory,
        merchant: _merchantController.text.trim().isEmpty
            ? null
            : _merchantController.text.trim(),
        description: c.description,
        transactionTime: _time,
        timeConfident: c.timeConfident,
        paymentMethod: c.paymentMethod,
        note: c.note,
        invoiceRequired: c.invoiceRequired,
        invoiceIssued: c.invoiceIssued,
        invoiceWaived: c.invoiceWaived,
        reimbursed: c.reimbursed,
        parseWarnings: c.parseWarnings,
        sourceRecords: c.sourceRecords,
      );
      final saved = await saveCandidateFlow(context, ref, updated);
      if (saved && mounted) widget.onRemoved();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final c = widget.candidate;
    final category = _categoryOf();
    final saved = _savedTx;

    return Container(
      padding: const EdgeInsets.all(FMSpacing.l),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(FMRadius.card),
        border: Border.all(color: s.border, width: 0.5),
        boxShadow: s.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.headerText != null) ...[
            Text(widget.headerText!, style: AppText.body(s.ink)),
            const SizedBox(height: FMSpacing.l),
          ],

          // ---- 状态行：保存状态 + 删除 ----
          Row(
            children: [
              _statusPill(s),
              const Spacer(),
              if (saved != null && !_mergedIntoExisting && !_deleted)
                GestureDetector(
                  onTap: _deleteSaved,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Icon(FMIcons.trash, size: 14, color: s.inkTertiary),
                      const SizedBox(width: 3),
                      Text('删除', style: AppText.caption(s.inkTertiary)),
                    ],
                  ),
                ),
            ],
          ),

          // ---- 金额 ----
          TextField(
            controller: _amountController,
            focusNode: _amountFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            enabled: saved != null || !widget.autoSave,
            style: AppText.amountL(
              _effectiveType == TransactionType.income ? s.income : s.ink,
            ),
            decoration: InputDecoration(
              hintText: '请输入金额',
              hintStyle: AppText.amountL(s.inkTertiary),
              errorText: _amountError,
              prefixText: '¥ ',
              prefixStyle: AppText.title(s.inkTertiary),
              border: InputBorder.none,
            ),
          ),

          // ---- 解析结果行 ----
          const SizedBox(height: FMSpacing.m),
          _Row(
            icon: FMIcons.tag,
            label: '分类',
            value: '${_effectiveType.label} · ${category?.name ?? '其他（待确认）'}',
            onTap: _pickCategory,
          ),
          _Row(
            icon: FMIcons.clock,
            label: '时间',
            value: AppDate.fullTitle(_time),
            onTap: _autoSaving ? null : _pickTime,
            sublabel: _time.isAfter(DateTime.now())
                ? '未来账单，到期前不计入结余'
                : (c.timeConfident ? null : '时间不明确，按当前时间记录'),
          ),
          _Row(
            icon: FMIcons.store,
            label: '商户',
            value: null,
            child: TextField(
              controller: _merchantController,
              focusNode: _merchantFocus,
              textAlign: TextAlign.end,
              textAlignVertical: TextAlignVertical.center,
              style: AppText.sub(s.ink),
              enabled: saved != null || !widget.autoSave,
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
                hintText: '未识别到商户',
                hintStyle: AppText.sub(s.inkTertiary),
                border: InputBorder.none,
              ),
            ),
          ),

          // ---- 解析警告 ----
          if (c.parseWarnings.isNotEmpty) ...[
            const SizedBox(height: FMSpacing.m),
            for (final w in c.parseWarnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Icon(FMIcons.warning, size: 13, color: s.warn),
                    const SizedBox(width: FMSpacing.xs),
                    Expanded(child: Text(w, style: AppText.caption(s.warn))),
                  ],
                ),
              ),
          ],

          // ---- 缺金额 / 未自动保存时的保存按钮 ----
          if (saved == null && !_autoSaving) ...[
            const SizedBox(height: FMSpacing.l),
            GestureDetector(
              onTap: _saving ? null : _saveManually,
              child: Container(
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s.accent,
                  borderRadius: BorderRadius.circular(FMRadius.button),
                ),
                child: _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      )
                    : Text(
                        '保存',
                        style: AppText.bodyStrong(Colors.white)
                            .copyWith(fontSize: 16),
                      ),
              ),
            ),
          ] else if (_mergedIntoExisting) ...[
            const SizedBox(height: FMSpacing.l),
            GestureDetector(
              onTap: widget.onRemoved,
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s.surfaceAlt,
                  borderRadius: BorderRadius.circular(FMRadius.button),
                ),
                child: Text('知道了', style: AppText.bodyStrong(s.inkSecondary)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 顶部保存状态标识。
  Widget _statusPill(FMScheme s) {
    if (_autoSaving) {
      return _Pill(label: '保存中…', color: s.inkTertiary, s: s);
    }
    if (_mergedIntoExisting) {
      return _Pill(
          label: '已与已有账单合并', color: s.accent, s: s, icon: FMIcons.merge);
    }
    if (_deleted) {
      return _Pill(label: '已删除', color: s.inkTertiary, s: s);
    }
    if (_duplicateKept) {
      return _Pill(label: '已保存 · 疑似重复已保留两笔', color: s.warn, s: s);
    }
    return _Pill(label: '已保存', color: s.income, s: s, icon: FMIcons.check);
  }
}

class _Pill extends StatelessWidget {
  const _Pill(
      {required this.label, required this.color, required this.s, this.icon});

  final String label;
  final Color color;
  final FMScheme s;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(label, style: AppText.micro(color)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.child,
    this.sublabel,
  });

  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Widget? child;
  final String? sublabel;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: FMSpacing.s),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: s.inkSecondary),
              const SizedBox(width: FMSpacing.s),
              Text(label, style: AppText.sub(s.inkSecondary)),
              const SizedBox(width: FMSpacing.l),
              Expanded(
                child: child ??
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onTap,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              value ?? '点击选择',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: AppText.sub(
                                value != null ? s.ink : s.inkTertiary,
                              ),
                            ),
                          ),
                          if (onTap != null) ...[
                            const SizedBox(width: 2),
                            Icon(FMIcons.chevronRight,
                                size: 12, color: s.inkTertiary),
                          ],
                        ],
                      ),
                    ),
              ),
            ],
          ),
          if (sublabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(sublabel!, style: AppText.caption(s.warn)),
              ),
            ),
        ],
      ),
    );
  }
}
