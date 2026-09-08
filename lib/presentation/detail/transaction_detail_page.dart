import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/widgets/fm_amount_text.dart';
import '../../core/widgets/fm_category_icon.dart';
import '../../core/widgets/fm_card.dart';
import '../../core/widgets/fm_sheets.dart';
import '../../core/widgets/fm_toast.dart';
import '../../domain/models/category.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/transaction.dart';
import '../../state/app_providers.dart';
import '../entry/manual_entry_page.dart';
import '../profile/invoice_management_page.dart';

/// 账单详情：完整字段 + 原始来源记录 + 编辑 / 删除。
class TransactionDetailPage extends ConsumerStatefulWidget {
  const TransactionDetailPage({super.key, required this.transactionId});

  final String transactionId;

  @override
  ConsumerState<TransactionDetailPage> createState() =>
      _TransactionDetailPageState();
}

class _TransactionDetailPageState extends ConsumerState<TransactionDetailPage> {
  TransactionEntity? _tx;
  List<SourceRecord> _sources = const [];
  Map<String, Category> _categories = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final repo = ref.read(transactionRepositoryProvider);
    final tx = await repo.getById(widget.transactionId);
    final sources = await repo.sourcesOf(widget.transactionId);
    final categories = await ref.read(categoryMapProvider.future);
    if (!mounted) return;
    setState(() {
      _tx = tx;
      _sources = sources;
      _categories = categories;
      _loading = false;
    });
  }

  Future<void> _delete() async {
    final ok = await showFMConfirm(
      context,
      title: '删除这笔账单？',
      message: '账单会进入回收箱，24 小时内可以还原。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await ref
        .read(transactionRepositoryProvider)
        .softDelete(widget.transactionId);
    ref.read(dataVersionProvider.notifier).state++;
    if (mounted) {
      showFMToast(context, message: '已移入回收箱', icon: FMIcons.trash);
      Navigator.of(context).pop();
    }
  }

  Future<void> _edit() async {
    if (_tx == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => ManualEntryPage(existing: _tx),
      ),
    );
    _reload();
  }

  Future<void> _updateInvoiceStatus({
    bool? required,
    bool? issued,
    bool? waived,
    bool? reimbursed,
  }) async {
    final current = _tx;
    if (current == null) return;
    var nextRequired = required ?? current.invoiceRequired;
    var nextIssued = issued ?? current.invoiceIssued;
    var nextWaived = waived ?? current.invoiceWaived;
    var nextReimbursed = reimbursed ?? current.reimbursed;
    if (waived == true) {
      nextRequired = false;
      nextIssued = false;
    } else if (required == true || issued == true) {
      nextWaived = false;
    }
    if (issued == true) {
      nextRequired = true;
    }
    if (required == false) {
      nextIssued = false;
    }
    final updated = current.copyWith(
      invoiceRequired: nextRequired,
      invoiceIssued: nextIssued,
      invoiceWaived: nextWaived,
      reimbursed: nextReimbursed,
      updatedAt: DateTime.now(),
    );
    await ref.read(transactionRepositoryProvider).update(updated);
    ref.read(dataVersionProvider.notifier).state++;
    if (mounted) setState(() => _tx = updated);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    if (_loading) {
      return Scaffold(
        backgroundColor: s.bg,
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final tx = _tx;
    if (tx == null) {
      return Scaffold(
        backgroundColor: s.bg,
        appBar: AppBar(),
        body: const FMEmptyState(
          icon: FMIcons.info,
          title: '账单不存在或已删除',
        ),
      );
    }

    final category = tx.categoryId == null ? null : _categories[tx.categoryId];
    final invoiceEnabled =
        ref.watch(invoiceManagementProvider).valueOrNull ?? false;
    final invoices = ref
            .watch(transactionInvoicesProvider(widget.transactionId))
            .valueOrNull ??
        const <InvoiceDocument>[];

    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        title: const Text('账单详情'),
        actions: [
          TextButton(
            onPressed: _edit,
            child: Text('编辑', style: AppText.bodyStrong(s.accent)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            FMSpacing.l, FMSpacing.s, FMSpacing.l, 48),
        children: [
          // ---- 金额区 ----
          Container(
            padding: const EdgeInsets.all(FMSpacing.xl),
            alignment: Alignment.center,
            child: Column(
              children: [
                FMCategoryIcon(category: category, size: 56),
                const SizedBox(height: FMSpacing.l),
                FMAmountText(
                  tx.amountCents,
                  type: tx.type,
                  style: AppText.amountL(
                    tx.isIncome ? s.income : s.ink,
                  ).copyWith(fontSize: 36),
                ),
                const SizedBox(height: FMSpacing.s),
                Text(
                  tx.displayTitle,
                  style: AppText.title(s.ink),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: FMSpacing.s),
                Wrap(
                  spacing: FMSpacing.s,
                  alignment: WrapAlignment.center,
                  children: [
                    if (tx.status != TxStatus.confirmed)
                      FMBadge(
                        label: tx.status == TxStatus.needsReview
                            ? '待确认'
                            : tx.status.label,
                        color: tx.status == TxStatus.needsReview
                            ? s.warn
                            : s.accent,
                      ),
                    if (tx.confidence < 1)
                      FMBadge(
                        label:
                            'AI 置信度 ${(tx.confidence * 100).toStringAsFixed(0)}%',
                        color: s.accent,
                      ),
                    if (tx.transactionTime.isAfter(DateTime.now()))
                      FMBadge(label: '未来账单 · 暂不计入结余', color: s.warn),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: FMSpacing.m),

          // ---- 字段 ----
          _SectionCard(
            children: [
              _Row(
                icon: FMIcons.tag,
                label: '分类',
                value: category == null
                    ? '未分类'
                    : (tx.subcategory == null
                        ? category.name
                        : '${category.name} · ${tx.subcategory}'),
              ),
              if (tx.merchant != null && tx.merchant!.isNotEmpty)
                _Row(icon: FMIcons.store, label: '商户', value: tx.merchant!),
              if (tx.description != null && tx.description!.isNotEmpty)
                _Row(icon: FMIcons.note, label: '描述', value: tx.description!),
              _Row(
                icon: FMIcons.clock,
                label: '时间',
                value: AppDate.fullTitle(tx.transactionTime),
              ),
              if (tx.paymentMethod != null)
                _Row(
                  icon: FMIcons.card,
                  label: '支付方式',
                  value: tx.paymentMethod!.label,
                ),
              _Row(
                  icon: FMIcons.location,
                  label: '来源',
                  value: tx.sourceType.label),
              if (tx.isRecurring)
                const _Row(
                  icon: FMIcons.sync,
                  label: '周期',
                  value: '来自周期记账',
                ),
              if (tx.note != null && tx.note!.isNotEmpty)
                _Row(icon: FMIcons.note, label: '备注', value: tx.note!),
            ],
          ),

          if (invoiceEnabled) ...[
            const SizedBox(height: FMSpacing.l),
            Padding(
              padding: const EdgeInsets.only(
                  left: FMSpacing.xs, bottom: FMSpacing.s),
              child: Text('发票与报销', style: AppText.caption(s.inkTertiary)),
            ),
            _SectionCard(
              children: [
                _InvoiceToggleRow(
                  label: '需要开票',
                  value: tx.invoiceRequired,
                  onChanged: (value) => _updateInvoiceStatus(required: value),
                ),
                _InvoiceToggleRow(
                  label: '已经开票',
                  value: tx.invoiceIssued,
                  onChanged: (value) => _updateInvoiceStatus(issued: value),
                ),
                _InvoiceToggleRow(
                  label: '无需开票',
                  value: tx.invoiceWaived,
                  onChanged: (value) => _updateInvoiceStatus(waived: value),
                ),
                _InvoiceToggleRow(
                  label: '已经报销',
                  value: tx.reimbursed,
                  onChanged: (value) => _updateInvoiceStatus(reimbursed: value),
                ),
                InkWell(
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const InvoiceManagementPage(),
                      ),
                    );
                    _reload();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: FMSpacing.m),
                    child: Row(
                      children: [
                        Icon(FMIcons.invoice, size: 16, color: s.accent),
                        const SizedBox(width: FMSpacing.m),
                        Text(
                          invoices.isEmpty
                              ? '上传并关联发票'
                              : '已关联 ${invoices.length} 个文件',
                          style: AppText.bodyStrong(s.accent),
                        ),
                        const Spacer(),
                        Icon(FMIcons.chevronRight,
                            size: 15, color: s.inkTertiary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],

          // ---- 原始来源记录 ----
          if (_sources.isNotEmpty) ...[
            const SizedBox(height: FMSpacing.l),
            Padding(
              padding: const EdgeInsets.only(
                  left: FMSpacing.xs, bottom: FMSpacing.s),
              child: Text('原始识别记录', style: AppText.caption(s.inkTertiary)),
            ),
            _SectionCard(
              children: [
                for (final source in _sources) ...[
                  Row(
                    children: [
                      FMBadge(label: source.displayLabel, color: s.accent),
                      const Spacer(),
                      Text(
                        AppDate.fullTitle(source.createdAt),
                        style: AppText.caption(s.inkTertiary),
                      ),
                    ],
                  ),
                  if (source.rawText != null && source.rawText!.isNotEmpty) ...[
                    const SizedBox(height: FMSpacing.s),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(FMSpacing.m),
                      decoration: BoxDecoration(
                        color: s.surfaceAlt,
                        borderRadius: BorderRadius.circular(FMRadius.field),
                      ),
                      child: Text(
                        source.rawText!,
                        style: AppText.caption(s.inkSecondary)
                            .copyWith(height: 1.6),
                      ),
                    ),
                  ],
                  const SizedBox(height: FMSpacing.s),
                ],
              ],
            ),
          ],
          const SizedBox(height: FMSpacing.xl),
          Material(
            color: s.ink,
            borderRadius: BorderRadius.circular(FMRadius.button),
            child: InkWell(
              onTap: _edit,
              borderRadius: BorderRadius.circular(FMRadius.button),
              child: SizedBox(
                height: 52,
                child: Center(
                  child: Text(
                    '修改账单',
                    style: AppText.bodyStrong(s.bg),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: FMSpacing.s),
          TextButton(
            onPressed: _delete,
            child: Text('删除账单', style: AppText.bodyStrong(s.danger)),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: FMSpacing.l, vertical: FMSpacing.s),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(FMRadius.card),
        border: Border.all(color: s.border, width: 0.5),
        boxShadow: s.cardShadow,
      ),
      child: Column(children: children),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FMSpacing.m),
      child: Row(
        children: [
          Icon(icon, size: 16, color: s.inkTertiary),
          const SizedBox(width: FMSpacing.m),
          SizedBox(
            width: 62,
            child: Text(label, style: AppText.body(s.inkSecondary)),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                value,
                maxLines: 2,
                textAlign: TextAlign.right,
                style: AppText.bodyStrong(s.ink),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceToggleRow extends StatelessWidget {
  const _InvoiceToggleRow({
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
          Text(label, style: AppText.body(s.inkSecondary)),
          const Spacer(),
          Switch.adaptive(
            value: value,
            activeTrackColor: s.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
