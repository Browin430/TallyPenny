import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/money_utils.dart';
import '../../core/widgets/fm_sheets.dart';
import '../../core/widgets/fm_toast.dart';
import '../../data/services/remote_ai_services.dart';
import '../../services/bill_export_service.dart';
import '../../state/app_providers.dart';
import '../privacy/analysis_pin_dialog.dart';
import 'category_manage_page.dart';
import 'invoice_management_page.dart';
import 'merchant_rules_page.dart';
import 'recycle_bin_page.dart';
import 'recurring_transactions_page.dart';

/// 我的：用户资料 / 财务档案 / 设置。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.colors;
    final profile =
        ref.watch(profileProvider).valueOrNull ?? UserProfile.fallback;
    final themeMode = ref.watch(themeModeProvider);
    final aiBaseUrl = ref.watch(aiBaseUrlProvider).asData?.value;
    final pinConfigured = ref.watch(analysisPinProvider).valueOrNull ?? false;
    final invoiceEnabled =
        ref.watch(invoiceManagementProvider).valueOrNull ?? false;
    final account = ref.watch(currentAccountProvider);

    return Scaffold(
      backgroundColor: s.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              FMSpacing.l, FMSpacing.l, FMSpacing.l, 130),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: FMSpacing.xs),
              child: Text('我的', style: AppText.headline(s.ink)),
            ),
            const SizedBox(height: FMSpacing.l),
            // ---- 用户卡片 ----
            GestureDetector(
              onTap: () => _editName(context, ref, profile.name),
              child: Container(
                padding: const EdgeInsets.all(FMSpacing.l),
                decoration: BoxDecoration(
                  color: s.surface,
                  borderRadius: BorderRadius.circular(FMRadius.card),
                  border: Border.all(color: s.border, width: 0.5),
                  boxShadow: s.cardShadow,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: s.accentSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        profile.name.isEmpty
                            ? '?'
                            : profile.name.characters.first,
                        style: AppText.title(s.accent).copyWith(fontSize: 22),
                      ),
                    ),
                    const SizedBox(width: FMSpacing.l),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(profile.name, style: AppText.title(s.ink)),
                          const SizedBox(height: 2),
                          Text(
                            '账号 ${account.username} · 点击修改昵称',
                            style: AppText.caption(s.inkTertiary),
                          ),
                        ],
                      ),
                    ),
                    Icon(FMIcons.chevronRight, size: 16, color: s.inkTertiary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: FMSpacing.m),

            _FinancialSnapshot(profile: profile),
            const SizedBox(height: FMSpacing.l),

            // ---- 财务档案 ----
            _SectionTitle('财务设置'),
            _GroupCard(
              children: [
                _ValueRow(
                  label: '月收入',
                  value: '¥${Money.centsToCompact(profile.monthlyIncomeCents)}',
                  onTap: () => _editFinance(context, ref),
                ),
                _ValueRow(
                  label: '储蓄目标',
                  value: '¥${Money.centsToCompact(profile.savingsGoalCents)}/月',
                  onTap: () => _editFinance(context, ref),
                ),
              ],
            ),
            const SizedBox(height: FMSpacing.m),

            // ---- 记账 ----
            _SectionTitle('记账设置'),
            _GroupCard(
              children: [
                _NavRow(
                  icon: FMIcons.tag,
                  label: '分类管理',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const CategoryManagePage()),
                  ),
                ),
                _NavRow(
                  icon: FMIcons.trash,
                  label: '回收箱',
                  badge: '保留24小时',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RecycleBinPage(),
                    ),
                  ),
                ),
                _NavRow(
                  icon: FMIcons.sync,
                  label: '周期记账',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RecurringTransactionsPage(),
                    ),
                  ),
                ),
                _NavRow(
                  icon: FMIcons.store,
                  label: '商户个性化',
                  badge: _merchantRuleBadge(ref),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MerchantRulesPage(),
                    ),
                  ),
                ),
                _NavRow(
                  icon: FMIcons.mic,
                  label: 'AI 服务设置',
                  badge: aiBaseUrl == null ? null : '已连接',
                  onTap: () => _editAiServer(context, ref),
                ),
                _SwitchRow(
                  icon: FMIcons.invoice,
                  label: '发票管理',
                  subtitle: '记录开票与报销状态',
                  value: invoiceEnabled,
                  onChanged: (value) => ref
                      .read(invoiceManagementProvider.notifier)
                      .setEnabled(value),
                ),
                if (invoiceEnabled)
                  _NavRow(
                    icon: FMIcons.invoice,
                    label: '发票与报销',
                    badge: '进入管理',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const InvoiceManagementPage(),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: FMSpacing.m),

            // ---- 外观 ----
            _SectionTitle('App 设置'),
            _GroupCard(
              children: [
                Padding(
                  padding: const EdgeInsets.all(FMSpacing.l),
                  child: Row(
                    children: [
                      Icon(FMIcons.eye, size: 18, color: s.inkSecondary),
                      const SizedBox(width: FMSpacing.m),
                      Text('主题', style: AppText.bodyStrong(s.ink)),
                      const Spacer(),
                      _ThemeSegmented(mode: themeMode),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: FMSpacing.m),

            // ---- 隐私与数据 ----
            _SectionTitle('隐私与数据'),
            _GroupCard(
              children: [
                _NavRow(
                  icon: FMIcons.lock,
                  label: '4位数密码',
                  badge: pinConfigured ? '已开启' : '未设置',
                  onTap: () =>
                      _configureAnalysisPin(context, ref, pinConfigured),
                ),
                _NavRow(
                  icon: FMIcons.shareUp,
                  label: '数据导出',
                  badge: 'Excel',
                  onTap: () => _exportData(context, ref),
                ),
                _NavRow(
                  icon: FMIcons.sync,
                  label: '重新生成演示数据',
                  onTap: () => _regenerateDemo(context, ref),
                ),
                _NavRow(
                  icon: FMIcons.trash,
                  label: '清空所有账单',
                  danger: true,
                  onTap: () => _clearAll(context, ref),
                ),
                _NavRow(
                  icon: FMIcons.logout,
                  label: '退出当前账户',
                  onTap: () => _confirmLogout(context, ref),
                ),
              ],
            ),
            const SizedBox(height: FMSpacing.l),
            Padding(
              padding: const EdgeInsets.all(FMSpacing.s),
              child: Text(
                '所有财务数据仅存储在本机，不会上传。AI 分析只使用完成任务所必需的数据。',
                style: AppText.caption(s.inkTertiary),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出当前账户？'),
        content: const Text('账单仍安全保存在此账户中，下次登录即可继续使用。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (confirmed == true) await ref.read(logoutActionProvider)();
  }

  Future<void> _editName(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('昵称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 12,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final profile =
        ref.read(profileProvider).valueOrNull ?? UserProfile.fallback;
    await ref.read(profileProvider.notifier).save(
          UserProfile(
            name: name,
            monthlyIncomeCents: profile.monthlyIncomeCents,
            fixedExpenseCents: profile.fixedExpenseCents,
            savingsGoalCents: profile.savingsGoalCents,
          ),
        );
  }

  Future<void> _configureAnalysisPin(
    BuildContext context,
    WidgetRef ref,
    bool configured,
  ) async {
    if (!configured) {
      await _setNewPin(context, ref);
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('4位数密码'),
        content: const Text('密码用于保护“流水”和“分析”页面，首页和记账不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('clear'),
            child: Text('关闭密码', style: TextStyle(color: context.colors.danger)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('change'),
            child: const Text('更改密码'),
          ),
        ],
      ),
    );
    if (action == null || !context.mounted) return;

    final current = await showFourDigitPinDialog(
      context,
      title: '验证当前密码',
      confirmText: '验证',
      verify: true,
    );
    if (current == null || !context.mounted) return;
    final valid = await ref.read(analysisPinProvider.notifier).verify(current);
    if (!valid) {
      if (context.mounted) {
        showFMToast(
          context,
          message: '当前密码不正确',
          icon: FMIcons.warning,
        );
      }
      return;
    }

    if (action == 'clear') {
      await ref.read(analysisPinProvider.notifier).clear();
      if (context.mounted) {
        showFMToast(context, message: '已关闭密码保护', icon: FMIcons.checkCircle);
      }
      return;
    }
    if (context.mounted) await _setNewPin(context, ref);
  }

  Future<void> _setNewPin(BuildContext context, WidgetRef ref) async {
    final first = await showFourDigitPinDialog(
      context,
      title: '设置4位数密码',
      message: '设置后，每次打开流水或分析页面都需要验证。',
      confirmText: '下一步',
    );
    if (first == null || !context.mounted) return;
    final second = await showFourDigitPinDialog(
      context,
      title: '再次输入密码',
      confirmText: '保存',
    );
    if (second == null || !context.mounted) return;
    if (first != second) {
      showFMToast(context, message: '两次输入不一致', icon: FMIcons.warning);
      return;
    }
    await ref.read(analysisPinProvider.notifier).setPin(first);
    if (context.mounted) {
      showFMToast(context, message: '密码保护已开启', icon: FMIcons.checkCircle);
    }
  }

  Future<void> _editFinance(BuildContext context, WidgetRef ref) async {
    final profile =
        ref.read(profileProvider).valueOrNull ?? UserProfile.fallback;
    final income = TextEditingController(
        text: (profile.monthlyIncomeCents / 100).toStringAsFixed(0));
    final savings = TextEditingController(
        text: (profile.savingsGoalCents / 100).toStringAsFixed(0));

    final s = context.colors;
    final ok = await showFMSheet<bool>(
      context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FMSpacing.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('编辑财务档案',
                  style: AppText.title(s.ink), textAlign: TextAlign.center),
              const SizedBox(height: FMSpacing.l),
              _MoneyField(controller: income, label: '月收入 (¥)'),
              const SizedBox(height: FMSpacing.m),
              _MoneyField(controller: savings, label: '储蓄目标/月 (¥)'),
              const SizedBox(height: FMSpacing.xl),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(true),
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
    if (ok != true) return;
    await ref.read(profileProvider.notifier).save(
          UserProfile(
            name: profile.name,
            monthlyIncomeCents:
                Money.parseToCents(income.text) ?? profile.monthlyIncomeCents,
            fixedExpenseCents: profile.fixedExpenseCents,
            savingsGoalCents:
                Money.parseToCents(savings.text) ?? profile.savingsGoalCents,
          ),
        );
  }

  /// 配置 AI 后端服务器地址（千问服务）。留空 = 使用内置演示引擎。
  Future<void> _editAiServer(BuildContext context, WidgetRef ref) async {
    final current = ref.read(aiBaseUrlProvider).asData?.value ?? '';
    final controller = TextEditingController(text: current);

    final saved = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('AI 服务设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI 后端服务器地址（千问）。'
                '留空恢复默认，仅当电脑 IP 变化时需要修改。'),
            const SizedBox(height: FMSpacing.m),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: RemoteAiServices.defaultBaseUrl,
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == null) return;

    final url = RemoteAiServices.normalizeBaseUrl(saved);
    await ref
        .read(settingsRepositoryProvider)
        .setString(RemoteAiServices.prefKey, url);
    ref.invalidate(aiBaseUrlProvider); // 重建各 AI 服务实例
    if (!context.mounted) return;
    final effective = url.isEmpty ? RemoteAiServices.defaultBaseUrl : url;
    showFMToast(
      context,
      message: 'AI 后端：$effective',
      icon: FMIcons.checkCircle,
    );
  }

  /// 商户个性化角标：无规则时不显示，有规则时显示条数。
  String? _merchantRuleBadge(WidgetRef ref) {
    final count = ref.watch(merchantRulesProvider).valueOrNull?.length ?? 0;
    return count == 0 ? null : '$count 条';
  }

  /// 数据导出：全部账单 → 微信账单流水格式的 XLSX → 系统分享面板。
  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    if (kIsWeb) {
      showFMToast(context, message: '数据导出请在手机上使用');
      return;
    }
    final transactions = await ref.read(transactionRepositoryProvider).getAll();
    if (!context.mounted) return;
    if (transactions.isEmpty) {
      showFMToast(context, message: '还没有可导出的账单');
      return;
    }
    final categories = await ref.read(categoryMapProvider.future);
    if (!context.mounted) return;
    final account = ref.read(currentAccountProvider);
    try {
      final result = await BillExportService.export(
        transactions: transactions,
        categories: categories,
        username: account.username,
      );
      if (!context.mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(result.file.path)],
          fileNameOverrides: [result.fileName],
        ),
      );
    } on Object {
      if (context.mounted) {
        showFMToast(
          context,
          message: '导出失败，请重试',
          icon: FMIcons.warning,
          iconColor: context.colors.danger,
        );
      }
    }
  }

  Future<void> _regenerateDemo(BuildContext context, WidgetRef ref) async {
    final ok = await showFMConfirm(
      context,
      title: '重新生成演示数据？',
      message: '将清空现有账单并生成近 6 个月的演示数据。',
      confirmText: '生成',
    );
    if (!ok) return;
    await ref.read(seedServiceProvider).regenerateDemo();
    ref.read(dataVersionProvider.notifier).state++;
    if (context.mounted) {
      showFMToast(context, message: '演示数据已重新生成', icon: FMIcons.checkCircle);
    }
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final ok = await showFMConfirm(
      context,
      title: '清空所有账单？',
      message: '该操作不可撤销（演示阶段未启用回收站）。',
      confirmText: '清空',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(transactionRepositoryProvider).clearAll();
    ref.read(dataVersionProvider.notifier).state++;
    if (context.mounted) {
      showFMToast(context, message: '已清空', icon: FMIcons.trash);
    }
  }
}

// =====================================================================
// 小组件
// =====================================================================

class _FinancialSnapshot extends StatelessWidget {
  const _FinancialSnapshot({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FMSpacing.m,
        vertical: FMSpacing.l,
      ),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(FMRadius.card),
        border: Border.all(color: s.border, width: 0.5),
        boxShadow: s.cardShadow,
      ),
      child: Row(
        children: [
          _SnapshotItem(
            label: '本月收入',
            value: '¥${Money.centsToCompact(profile.monthlyIncomeCents)}',
          ),
          Container(width: 0.5, height: 36, color: s.separator),
          _SnapshotItem(
            label: '储蓄目标',
            value: '¥${Money.centsToCompact(profile.savingsGoalCents)}',
          ),
        ],
      ),
    );
  }
}

class _SnapshotItem extends StatelessWidget {
  const _SnapshotItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Expanded(
      child: Column(
        children: [
          Text(label, style: AppText.caption(s.inkTertiary)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: AppText.amountS(s.ink)),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: FMSpacing.xs, bottom: FMSpacing.s),
      child: Text(text, style: AppText.caption(s.inkTertiary)),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(FMRadius.card),
        border: Border.all(color: s.border, width: 0.5),
        boxShadow: s.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FMSpacing.l,
          vertical: FMSpacing.m + 2,
        ),
        child: Row(
          children: [
            Text(label, style: AppText.body(s.inkSecondary)),
            const Spacer(),
            Text(value, style: AppText.bodyStrong(s.ink)),
            const SizedBox(width: FMSpacing.s),
            Icon(FMIcons.edit, size: 13, color: s.inkTertiary),
          ],
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    this.badge,
    this.danger = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? badge;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FMSpacing.l,
          vertical: FMSpacing.m + 2,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: danger ? s.danger : s.inkSecondary),
            const SizedBox(width: FMSpacing.m),
            Expanded(
              child: Text(
                label,
                style: AppText.bodyStrong(danger ? s.danger : s.ink),
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: s.ink.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(badge!, style: AppText.micro(s.inkTertiary)),
              ),
            const SizedBox(width: FMSpacing.s),
            Icon(FMIcons.chevronRight, size: 15, color: s.inkTertiary),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FMSpacing.l,
        FMSpacing.s,
        FMSpacing.s,
        FMSpacing.s,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: s.inkSecondary),
          const SizedBox(width: FMSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.bodyStrong(s.ink)),
                const SizedBox(height: 2),
                Text(subtitle, style: AppText.caption(s.inkSecondary)),
              ],
            ),
          ),
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

class _ThemeSegmented extends ConsumerWidget {
  const _ThemeSegmented({required this.mode});

  final ThemeMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: context.colors.ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (m, label) in const [
            (ThemeMode.system, '自动'),
            (ThemeMode.light, '浅色'),
            (ThemeMode.dark, '深色'),
          ])
            GestureDetector(
              onTap: () => ref.read(themeModeProvider.notifier).setMode(m),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: FMSpacing.m, vertical: 5),
                decoration: BoxDecoration(
                  color:
                      mode == m ? context.colors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  label,
                  style: AppText.caption(
                    mode == m
                        ? context.colors.ink
                        : context.colors.inkSecondary,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: FMSpacing.l, vertical: 4),
      decoration: BoxDecoration(
        color: s.surfaceAlt,
        borderRadius: BorderRadius.circular(FMRadius.field),
        border: Border.all(color: s.border, width: 0.5),
      ),
      child: Row(
        children: [
          Text(label, style: AppText.sub(s.inkSecondary)),
          const SizedBox(width: FMSpacing.m),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              style: AppText.bodyStrong(s.ink),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
