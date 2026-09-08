import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/fm_amount_text.dart';
import '../../core/widgets/fm_category_icon.dart';
import '../../core/widgets/fm_sheets.dart';
import '../../core/widgets/fm_toast.dart';
import '../../domain/models/category.dart';
import '../../domain/models/transaction.dart';
import '../../state/app_providers.dart';

/// 软删除账单保留 24 小时。普通账单查询和 AI 修改查询均不会读取这里。
class RecycleBinPage extends ConsumerStatefulWidget {
  const RecycleBinPage({super.key});

  @override
  ConsumerState<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends ConsumerState<RecycleBinPage> {
  List<TransactionEntity>? _transactions;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = ref.read(transactionRepositoryProvider);
    await repository.purgeDeletedBefore(
      DateTime.now().subtract(const Duration(hours: 24)),
    );
    final result = await repository.getDeleted();
    if (mounted) setState(() => _transactions = result);
  }

  Future<void> _restore(TransactionEntity transaction) async {
    await ref.read(transactionRepositoryProvider).restore(transaction.id);
    ref.read(dataVersionProvider.notifier).state++;
    await _load();
    if (mounted) {
      showFMToast(context, message: '账单已还原', icon: FMIcons.checkCircle);
    }
  }

  Future<void> _restoreAll() async {
    final transactions = _transactions ?? const <TransactionEntity>[];
    if (transactions.isEmpty) return;
    final ok = await showFMConfirm(
      context,
      title: '还原全部账单？',
      message: '将还原回收箱中的 ${transactions.length} 笔账单。',
      confirmText: '全部还原',
    );
    if (!ok) return;
    final repository = ref.read(transactionRepositoryProvider);
    for (final transaction in transactions) {
      await repository.restore(transaction.id);
    }
    ref.read(dataVersionProvider.notifier).state++;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final categories = ref.watch(categoryMapProvider).valueOrNull ?? const {};
    final transactions = _transactions;
    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        title: const Text('回收箱'),
        actions: [
          if (transactions?.isNotEmpty ?? false)
            TextButton(onPressed: _restoreAll, child: const Text('全部还原')),
        ],
      ),
      body: transactions == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : transactions.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(FMSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FMIcons.trash, size: 44, color: s.inkTertiary),
                        const SizedBox(height: FMSpacing.m),
                        Text('回收箱是空的', style: AppText.title(s.ink)),
                        const SizedBox(height: FMSpacing.xs),
                        Text(
                          '删除的账单会在这里保留 24 小时',
                          style: AppText.sub(s.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    FMSpacing.l,
                    FMSpacing.m,
                    FMSpacing.l,
                    FMSpacing.xl,
                  ),
                  itemCount: transactions.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: FMSpacing.s),
                  itemBuilder: (context, index) => _DeletedTile(
                    transaction: transactions[index],
                    category: categories[transactions[index].categoryId],
                    onRestore: () => _restore(transactions[index]),
                  ),
                ),
    );
  }
}

class _DeletedTile extends StatelessWidget {
  const _DeletedTile({
    required this.transaction,
    required this.category,
    required this.onRestore,
  });

  final TransactionEntity transaction;
  final Category? category;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final deletedAt = transaction.deletedAt ?? transaction.updatedAt;
    final expiresAt = deletedAt.add(const Duration(hours: 24));
    final remaining = expiresAt.difference(DateTime.now());
    final remainingText = remaining.inMinutes <= 0
        ? '即将彻底删除'
        : remaining.inHours > 0
            ? '${remaining.inHours}小时后彻底删除'
            : '${remaining.inMinutes}分钟后彻底删除';
    return Container(
      padding: const EdgeInsets.all(FMSpacing.m),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(FMRadius.card),
        border: Border.all(color: s.border, width: 0.5),
      ),
      child: Row(
        children: [
          FMCategoryIcon(category: category),
          const SizedBox(width: FMSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyStrong(s.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  '${deletedAt.month}月${deletedAt.day}日 '
                  '${deletedAt.hour.toString().padLeft(2, '0')}:'
                  '${deletedAt.minute.toString().padLeft(2, '0')} 删除 · $remainingText',
                  style: AppText.caption(s.inkTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: FMSpacing.s),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FMAmountText(
                transaction.amountCents,
                type: transaction.type,
                style: AppText.amountM(s.ink),
              ),
              const SizedBox(height: 3),
              TextButton(onPressed: onRestore, child: const Text('还原')),
            ],
          ),
        ],
      ),
    );
  }
}
