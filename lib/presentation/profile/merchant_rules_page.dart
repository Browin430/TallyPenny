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
import '../../domain/models/merchant_rule.dart';
import '../../services/merchant_rule_matcher.dart';
import '../../state/app_providers.dart';
import '../entry/category_picker_sheet.dart';

/// 商户个性化：给常用商户配备注与默认分类，越备注越智能。
class MerchantRulesPage extends ConsumerWidget {
  const MerchantRulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.colors;
    final rules = ref.watch(merchantRulesProvider);
    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        title: const Text('商户个性化'),
        actions: [
          IconButton(
            tooltip: '新建商户规则',
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
    MerchantRule? existing,
  ]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MerchantRuleEditPage(existing: existing),
      ),
    );
    if (saved == true) ref.invalidate(merchantRulesProvider);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    MerchantRule rule,
  ) async {
    final ok = await showFMConfirm(
      context,
      title: '删除“${rule.merchantPattern}”？',
      message: '只删除个性化规则，已按规则分类的账单保持不变。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(merchantRuleRepositoryProvider).delete(rule.id);
    ref.read(merchantRuleVersionProvider.notifier).state++;
  }
}

class _RuleCard extends ConsumerWidget {
  const _RuleCard({
    required this.rule,
    required this.onTap,
    required this.onDelete,
  });

  final MerchantRule rule;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.colors;
    final category = ref
        .watch(categoriesProvider)
        .valueOrNull
        ?.where((c) => c.id == rule.preferredCategory)
        .firstOrNull;
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
              FMCategoryIcon(category: category, size: 40),
              const SizedBox(width: FMSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rule.merchantPattern,
                        style: AppText.bodyStrong(s.ink)),
                    const SizedBox(height: 3),
                    Text(
                      (rule.note?.trim().isNotEmpty ?? false)
                          ? rule.note!.trim()
                          : category?.name ?? rule.preferredCategory,
                      style: AppText.caption(s.inkTertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(category?.name ?? rule.preferredCategory,
                      style: AppText.caption(s.inkSecondary)),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (rule.hitCount > 1)
                        Text('已分类 ${rule.hitCount} 次',
                            style: AppText.micro(s.inkTertiary)),
                      GestureDetector(
                        onTap: onDelete,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(FMIcons.trash,
                              size: 15, color: s.inkTertiary),
                        ),
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
        padding: const EdgeInsets.all(FMSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(FMIcons.store, size: 44, color: s.inkTertiary),
            const SizedBox(height: FMSpacing.m),
            Text('还没有商户个性化', style: AppText.title(s.ink)),
            const SizedBox(height: FMSpacing.xs),
            Text(
              '给常去的商户备注分类，例如「C.L 是公司楼下的黄焖鸡」，之后自动归类。',
              textAlign: TextAlign.center,
              style: AppText.caption(s.inkTertiary),
            ),
            const SizedBox(height: FMSpacing.l),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(FMIcons.plus, size: 16),
              label: const Text('新建规则'),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// 编辑页
// =====================================================================

class MerchantRuleEditPage extends ConsumerStatefulWidget {
  const MerchantRuleEditPage({super.key, this.existing});

  final MerchantRule? existing;

  @override
  ConsumerState<MerchantRuleEditPage> createState() =>
      _MerchantRuleEditPageState();
}

class _MerchantRuleEditPageState extends ConsumerState<MerchantRuleEditPage> {
  final _merchantController = TextEditingController();
  final _noteController = TextEditingController();
  Category? _category;
  List<String> _recentMerchants = const [];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _merchantController.text = existing.merchantPattern;
      _noteController.text = existing.note ?? '';
    }
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final categories =
        await ref.read(categoriesProvider.future);
    final existing = widget.existing;
    if (existing != null) {
      final match = categories
          .where((c) => c.id == existing.preferredCategory)
          .firstOrNull;
      if (match != null && mounted) setState(() => _category = match);
    }
    // 最近商户快捷选择：从近期账单取没有规则的商户名。
    final transactions =
        await ref.read(transactionRepositoryProvider).getAll();
    final existingRules =
        await ref.read(merchantRuleRepositoryProvider).getAll();
    final merchants = <String>[];
    for (final t in transactions) {
      final m = t.merchant?.trim();
      if (m == null || m.isEmpty) continue;
      final normalized = MerchantRuleMatcher.normalize(m);
      if (merchants.any((x) => MerchantRuleMatcher.normalize(x) == normalized)) {
        continue;
      }
      if (existingRules.any(
        (r) => MerchantRuleMatcher.match([r], m) != null,
      )) {
        continue;
      }
      merchants.add(m);
      if (merchants.length >= 20) break;
    }
    if (mounted && merchants.isNotEmpty) {
      setState(() => _recentMerchants = merchants);
    }
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickCategory() async {
    // 仅系统白名单分类：与服务端 AI 分类白名单一致，保证规则跨端生效。
    final all = await ref.read(visibleCategoriesProvider.future);
    if (!mounted) return;
    final whitelist = all.where((c) => c.isSystem).toList();
    final picked = await showCategoryPicker(
      context,
      categories: whitelist,
      type: _category?.type ?? TransactionType.expense,
      current: _category,
      allowTypeSwitch: true,
    );
    if (picked != null && mounted) setState(() => _category = picked);
  }

  Future<void> _save() async {
    final merchant = _merchantController.text.trim();
    final category = _category;
    if (merchant.isEmpty) {
      showFMToast(context, message: '请填写商户名');
      return;
    }
    if (category == null) {
      showFMToast(context, message: '请选择分类');
      return;
    }

    final repository = ref.read(merchantRuleRepositoryProvider);
    final rules = await repository.getAll();
    // 同 pattern 查重（排除正在编辑的这条）。
    final duplicate = rules.where((r) {
      if (widget.existing != null && r.id == widget.existing!.id) return false;
      return MerchantRuleMatcher.normalize(r.merchantPattern) ==
          MerchantRuleMatcher.normalize(merchant);
    }).firstOrNull;
    if (duplicate != null) {
      if (mounted) {
        showFMToast(context, message: '「${duplicate.merchantPattern}」已有规则');
      }
      return;
    }

    final now = DateTime.now();
    final account = ref.read(currentAccountProvider);
    final rule = MerchantRule(
      id: widget.existing?.id ?? IdGen.newId(),
      userId: account.id,
      merchantPattern: merchant,
      preferredCategory: category.id,
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      hitCount: widget.existing?.hitCount ?? 0,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    // 历史修正确认：该商户已有但分类不同的账单，一键改为规则分类。
    final transactions = await ref.read(transactionRepositoryProvider).getAll();
    final affected = transactions
        .where((t) =>
            !t.isDeleted &&
            t.categoryId != category.id &&
            MerchantRuleMatcher.match([rule], t.merchant) != null)
        .toList();

    if (affected.isNotEmpty && mounted) {
      final ok = await showFMConfirm(
        context,
        title: '同时修正历史账单？',
        message: '将「$merchant」的 ${affected.length} 笔账单分类改为「${category.name}」。',
        confirmText: '修正 ${affected.length} 笔',
      );
      if (ok) {
        final txRepo = ref.read(transactionRepositoryProvider);
        for (final t in affected) {
          await txRepo.update(t.copyWith(
            categoryId: category.id,
            updatedAt: DateTime.now(),
          ));
        }
        ref.read(dataVersionProvider.notifier).state++;
      }
    }

    await repository.upsert(rule);
    ref.read(merchantRuleVersionProvider.notifier).state++;
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        title: Text(widget.existing == null ? '新建商户规则' : '编辑商户规则'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          FMSpacing.l, FMSpacing.m, FMSpacing.l, FMSpacing.xxl),
        children: [
          _InputCard(
            controller: _merchantController,
            label: '商户名',
            hint: '如：C.L、瑞幸咖啡',
            onChanged: (_) => setState(() {}),
          ),
          if (_recentMerchants.isNotEmpty &&
              _merchantController.text.isEmpty) ...[
            const SizedBox(height: FMSpacing.m),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: FMSpacing.xs),
              child: Text('最近商户', style: AppText.caption(s.inkTertiary)),
            ),
            const SizedBox(height: FMSpacing.s),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _recentMerchants)
                  ActionChip(
                    label: Text(m, style: AppText.caption(s.ink)),
                    backgroundColor: s.surface,
                    side: BorderSide(color: s.border, width: 0.5),
                    onPressed: () {
                      setState(() => _merchantController.text = m);
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: FMSpacing.m),
          _InputCard(
            controller: _noteController,
            label: '备注（可选）',
            hint: '如：公司楼下的黄焖鸡',
            maxLines: 2,
          ),
          const SizedBox(height: FMSpacing.m),
          Material(
            color: s.surface,
            borderRadius: BorderRadius.circular(FMRadius.card),
            child: InkWell(
              onTap: _pickCategory,
              borderRadius: BorderRadius.circular(FMRadius.card),
              child: Container(
                padding: const EdgeInsets.all(FMSpacing.l),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(FMRadius.card),
                  border: Border.all(color: s.border, width: 0.5),
                ),
                child: Row(
                  children: [
                    FMCategoryIcon(category: _category, size: 36),
                    const SizedBox(width: FMSpacing.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('默认分类',
                              style: AppText.caption(s.inkTertiary)),
                          const SizedBox(height: 2),
                          Text(
                            _category?.name ?? '点击选择',
                            style: AppText.bodyStrong(
                                _category == null ? s.inkTertiary : s.ink),
                          ),
                        ],
                      ),
                    ),
                    Icon(FMIcons.chevronRight, size: 16, color: s.inkTertiary),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: FMSpacing.m),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: FMSpacing.xs),
            child: Text(
              '保存后，该商户的新账单（手动 / 语音 / 截图 / 导入）都会自动使用这个分类；解析请求也会携带该偏好给 AI。',
              style: AppText.caption(s.inkTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Container(
      padding: const EdgeInsets.all(FMSpacing.l),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(FMRadius.card),
        border: Border.all(color: s.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.caption(s.inkTertiary)),
          const SizedBox(height: FMSpacing.s),
          TextField(
            controller: controller,
            maxLines: maxLines,
            style: AppText.body(s.ink),
            decoration: InputDecoration.collapsed(hintText: hint),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
