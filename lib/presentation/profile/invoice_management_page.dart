import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/id_gen.dart';
import '../../core/utils/money_utils.dart';
import '../../core/widgets/fm_sheets.dart';
import '../../core/widgets/fm_toast.dart';
import '../../domain/models/transaction.dart';
import '../../services/image_crop_flow.dart';
import '../../services/invoice_management_service.dart';
import '../../state/app_providers.dart';
import '../detail/transaction_detail_page.dart';

class InvoiceManagementPage extends ConsumerStatefulWidget {
  const InvoiceManagementPage({super.key});

  @override
  ConsumerState<InvoiceManagementPage> createState() =>
      _InvoiceManagementPageState();
}

class _InvoiceManagementPageState extends ConsumerState<InvoiceManagementPage> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _uploading = false;
  InvoiceStatusView _selectedStatus = InvoiceStatusView.waitingInvoice;

  Future<void> _upload() async {
    if (_uploading) return;
    final kind = await showFMSheet<_UploadKind>(
      context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(FMIcons.photo),
                title: const Text('上传图片'),
                subtitle: const Text('支持裁剪后保存'),
                onTap: () => Navigator.of(sheetContext).pop(_UploadKind.image),
              ),
              ListTile(
                leading: const Icon(FMIcons.note),
                title: const Text('上传 PDF'),
                onTap: () => Navigator.of(sheetContext).pop(_UploadKind.pdf),
              ),
            ],
          ),
        ),
      ),
    );
    if (kind == null || !mounted) return;

    String? sourcePath;
    String? originalName;
    if (kind == _UploadKind.image) {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 96,
      );
      if (picked == null || !mounted) return;
      sourcePath = await preparePickedImage(
        context,
        picked.path,
        cropTitle: '裁剪发票',
      );
      originalName = picked.name;
    } else {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      sourcePath = picked?.path;
      originalName = picked?.name;
    }
    if (sourcePath == null || originalName == null || !mounted) return;

    final transactions = await ref.read(allTransactionsProvider.future);
    if (!mounted) return;
    final link = await _chooseTransaction(transactions);
    if (link == null || !mounted) return;

    setState(() => _uploading = true);
    String? storedPath;
    try {
      storedPath = await ref.read(invoiceFileStorageProvider).persist(
            sourcePath: sourcePath,
            originalName: originalName,
          );
      final document = InvoiceDocument(
        id: IdGen.newId(),
        transactionId: link.transactionId,
        storedPath: storedPath,
        originalName: originalName,
        fileType: kind == _UploadKind.pdf ? 'pdf' : 'image',
        createdAt: DateTime.now(),
      );
      await ref.read(invoiceRepositoryProvider).insert(document);
      if (link.transactionId != null) {
        final repo = ref.read(transactionRepositoryProvider);
        final tx = await repo.getById(link.transactionId!);
        if (tx != null) {
          await repo.update(tx.copyWith(
            invoiceRequired: true,
            invoiceIssued: true,
            invoiceWaived: false,
            updatedAt: DateTime.now(),
          ));
          ref.read(dataVersionProvider.notifier).state++;
        }
      }
      ref.read(invoiceVersionProvider.notifier).state++;
      if (mounted) {
        showFMToast(
          context,
          message: link.transactionId == null ? '发票已保存' : '发票已保存并关联账单',
          icon: FMIcons.checkCircle,
        );
      }
    } catch (_) {
      if (storedPath != null) {
        await ref.read(invoiceFileStorageProvider).deleteIfPresent(storedPath);
      }
      if (mounted) {
        showFMToast(
          context,
          message: '发票保存失败，请重试',
          icon: FMIcons.warning,
          iconColor: context.colors.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<_LinkChoice?> _chooseTransaction(
    List<TransactionEntity> transactions,
  ) {
    final sortedTransactions = [...transactions]..sort((a, b) {
        final byAmount = b.amountCents.compareTo(a.amountCents);
        return byAmount != 0
            ? byAmount
            : b.transactionTime.compareTo(a.transactionTime);
      });
    return showFMSheet<_LinkChoice>(
      context,
      builder: (sheetContext) {
        final s = sheetContext.colors;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.68,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(FMSpacing.l),
                  child: Row(
                    children: [
                      Text('关联账单', style: AppText.title(s.ink)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(sheetContext)
                            .pop(const _LinkChoice(null)),
                        child: const Text('暂不关联'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: sortedTransactions.isEmpty
                      ? Center(
                          child:
                              Text('暂无账单', style: AppText.body(s.inkSecondary)),
                        )
                      : ListView.builder(
                          itemCount: sortedTransactions.length,
                          itemBuilder: (_, index) {
                            final tx = sortedTransactions[index];
                            return ListTile(
                              title: Text(tx.displayTitle,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                AppDate.fullTitle(tx.transactionTime),
                              ),
                              trailing: Text(
                                '¥${Money.centsToText(tx.amountCents)}',
                                style: AppText.bodyStrong(s.ink),
                              ),
                              onTap: () => Navigator.of(sheetContext)
                                  .pop(_LinkChoice(tx.id)),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openDocument(InvoiceDocument document) async {
    if (document.isPdf) {
      final result = await OpenFilex.open(document.storedPath);
      if (mounted && result.type != ResultType.done) {
        showFMToast(
          context,
          message: '没有可打开 PDF 的应用',
          icon: FMIcons.info,
        );
      }
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Center(
                child: Image.file(
                  File(document.storedPath),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(48),
                    child:
                        Text('图片文件不存在', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filled(
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteDocument(InvoiceDocument document) async {
    final confirmed = await showFMConfirm(
      context,
      title: '删除这张发票？',
      message: 'App 内保存的文件副本会一并删除，原相册或原 PDF 不受影响。',
      confirmText: '删除',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(invoiceRepositoryProvider).delete(document.id);
    await ref
        .read(invoiceFileStorageProvider)
        .deleteIfPresent(document.storedPath);
    ref.read(invoiceVersionProvider.notifier).state++;
    if (mounted) {
      showFMToast(context, message: '发票已删除', icon: FMIcons.trash);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final transactions = ref.watch(allTransactionsProvider).valueOrNull ?? [];
    final documents = ref.watch(invoiceDocumentsProvider).valueOrNull ?? [];
    final transactionMap = {for (final tx in transactions) tx.id: tx};
    final managed = transactions.where(InvoiceManagementService.isManaged);
    final filtered = InvoiceManagementService.filteredAndSorted(
      transactions,
      _selectedStatus,
    );
    final waitingInvoice = InvoiceManagementService.count(
      transactions,
      InvoiceStatusView.waitingInvoice,
    );
    final waitingReimbursement = InvoiceManagementService.count(
      transactions,
      InvoiceStatusView.waitingReimbursement,
    );
    final reimbursed = InvoiceManagementService.count(
      transactions,
      InvoiceStatusView.reimbursed,
    );

    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        title: const Text('发票与报销'),
        actions: [
          TextButton.icon(
            onPressed: _uploading ? null : _upload,
            icon: _uploading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add, size: 18),
            label: const Text('上传'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          FMSpacing.l,
          FMSpacing.s,
          FMSpacing.l,
          48,
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  label: '待开票',
                  count: waitingInvoice,
                  color: s.warn,
                  selected: _selectedStatus == InvoiceStatusView.waitingInvoice,
                  onTap: () => setState(
                    () => _selectedStatus = InvoiceStatusView.waitingInvoice,
                  ),
                ),
              ),
              const SizedBox(width: FMSpacing.s),
              Expanded(
                child: _SummaryCard(
                  label: '待报销',
                  count: waitingReimbursement,
                  color: s.accent,
                  selected:
                      _selectedStatus == InvoiceStatusView.waitingReimbursement,
                  onTap: () => setState(
                    () => _selectedStatus =
                        InvoiceStatusView.waitingReimbursement,
                  ),
                ),
              ),
              const SizedBox(width: FMSpacing.s),
              Expanded(
                child: _SummaryCard(
                  label: '已报销',
                  count: reimbursed,
                  color: s.income,
                  selected: _selectedStatus == InvoiceStatusView.reimbursed,
                  onTap: () => setState(
                    () => _selectedStatus = InvoiceStatusView.reimbursed,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: FMSpacing.xl),
          _SectionTitle('${_selectedStatus.label}账单 · ${filtered.length}'),
          if (managed.isEmpty)
            _EmptyCard(
              icon: FMIcons.invoice,
              text: '在账单详情或编辑页设置开票状态',
            )
          else if (filtered.isEmpty)
            _EmptyCard(
              icon: FMIcons.invoice,
              text: '暂无${_selectedStatus.label}账单',
            )
          else
            Container(
              decoration: BoxDecoration(
                color: s.surface,
                borderRadius: BorderRadius.circular(FMRadius.card),
                border: Border.all(color: s.border, width: 0.5),
              ),
              child: Column(
                children: [
                  for (final tx in filtered)
                    _TransactionStatusTile(
                      transaction: tx,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TransactionDetailPage(
                            transactionId: tx.id,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: FMSpacing.xl),
          _SectionTitle('发票文件 · ${documents.length}'),
          if (documents.isEmpty)
            _EmptyCard(
              icon: FMIcons.photo,
              text: '支持保存发票图片或 PDF',
            )
          else
            for (final document in documents)
              Padding(
                padding: const EdgeInsets.only(bottom: FMSpacing.s),
                child: _DocumentTile(
                  document: document,
                  linkedTransaction: transactionMap[document.transactionId],
                  onOpen: () => _openDocument(document),
                  onDelete: () => _deleteDocument(document),
                ),
              ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _upload,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('上传发票'),
      ),
    );
  }
}

enum _UploadKind { image, pdf }

class _LinkChoice {
  const _LinkChoice(this.transactionId);

  final String? transactionId;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Material(
      color: selected ? color.withValues(alpha: 0.08) : s.surface,
      borderRadius: BorderRadius.circular(FMRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FMRadius.card),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: FMSpacing.l),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FMRadius.card),
            border: Border.all(
              color: selected ? color : s.border,
              width: selected ? 1.2 : 0.5,
            ),
          ),
          child: Column(
            children: [
              Text('$count', style: AppText.amountL(color)),
              const SizedBox(height: 3),
              Text(
                label,
                style: AppText.caption(selected ? color : s.inkSecondary)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on InvoiceStatusView {
  String get label => switch (this) {
        InvoiceStatusView.waitingInvoice => '待开票',
        InvoiceStatusView.waitingReimbursement => '待报销',
        InvoiceStatusView.reimbursed => '已报销',
      };
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text, style: AppText.bodyStrong(context.colors.ink)),
      );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Container(
      padding: const EdgeInsets.all(FMSpacing.xl),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(FMRadius.card),
        border: Border.all(color: s.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: s.inkTertiary),
          const SizedBox(width: FMSpacing.m),
          Expanded(child: Text(text, style: AppText.sub(s.inkSecondary))),
        ],
      ),
    );
  }
}

class _TransactionStatusTile extends StatelessWidget {
  const _TransactionStatusTile({
    required this.transaction,
    required this.onTap,
  });

  final TransactionEntity transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return ListTile(
      onTap: onTap,
      leading: Icon(FMIcons.invoice, color: s.accent),
      title: Text(
        transaction.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 5,
          runSpacing: 4,
          children: [
            if (transaction.invoiceRequired)
              _StatusTag(label: '需开票', color: s.warn),
            if (transaction.invoiceIssued)
              _StatusTag(label: '已开票', color: s.accent),
            if (transaction.invoiceWaived)
              _StatusTag(label: '无需开票', color: s.inkSecondary),
            if (transaction.reimbursed)
              _StatusTag(label: '已报销', color: s.income),
          ],
        ),
      ),
      trailing: Text(
        '¥${Money.centsToText(transaction.amountCents)}',
        style: AppText.bodyStrong(s.ink),
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(label, style: AppText.micro(color)),
      );
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.document,
    required this.linkedTransaction,
    required this.onOpen,
    required this.onDelete,
  });

  final InvoiceDocument document;
  final TransactionEntity? linkedTransaction;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Material(
      color: s.surface,
      borderRadius: BorderRadius.circular(FMRadius.card),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(FMRadius.card),
        child: Container(
          padding: const EdgeInsets.all(FMSpacing.m),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FMRadius.card),
            border: Border.all(color: s.border, width: 0.5),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: document.isPdf
                      ? ColoredBox(
                          color: s.accentSoft,
                          child: Center(
                            child: Text('PDF',
                                style: AppText.micro(s.accent)
                                    .copyWith(fontWeight: FontWeight.w700)),
                          ),
                        )
                      : Image.file(
                          File(document.storedPath),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => ColoredBox(
                            color: s.surfaceAlt,
                            child: Icon(FMIcons.photo, color: s.inkTertiary),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: FMSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.originalName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong(s.ink),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      linkedTransaction?.displayTitle ?? '未关联账单',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption(s.inkSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: Icon(FMIcons.trash, size: 18, color: s.inkTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
