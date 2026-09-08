import 'package:flutter/material.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'manual_entry_page.dart';
import 'screenshot_entry_page.dart';
import 'statement_import_page.dart';
import 'voice_entry_page.dart';

/// 首页中央【+】弹出的记账方式选择。
class EntryModeSheet extends StatelessWidget {
  const EntryModeSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          FMSpacing.l,
          FMSpacing.m,
          FMSpacing.l,
          FMSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                  left: FMSpacing.xs, bottom: FMSpacing.l),
              child: Text('记一笔', style: AppText.headline(s.ink)),
            ),
            _ModeTile(
              icon: FMIcons.mic,
              color: s.accent,
              title: '语音记账',
              subtitle: '说一句话，自动识别金额和分类',
              onTap: () => _push(context, const VoiceEntryPage()),
            ),
            const SizedBox(height: FMSpacing.m),
            _ModeTile(
              icon: FMIcons.camera,
              color: s.income,
              title: '截图记账',
              subtitle: '识别支付宝 / 微信支付账单截图',
              onTap: () => _push(context, const ScreenshotEntryPage()),
            ),
            const SizedBox(height: FMSpacing.m),
            _ModeTile(
              icon: FMIcons.note,
              color: s.accent,
              title: '账单文件导入',
              subtitle: '导入支付宝 CSV / 微信支付 XLSX',
              onTap: () => _push(context, const StatementImportPage()),
            ),
            const SizedBox(height: FMSpacing.m),
            _ModeTile(
              icon: FMIcons.keyboard,
              color: s.warn,
              title: '手动记账',
              subtitle: '自己填写完整账单信息',
              onTap: () => _push(context, const ManualEntryPage()),
            ),
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(FMRadius.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(FMSpacing.l),
          decoration: BoxDecoration(
            color: s.surfaceAlt,
            borderRadius: BorderRadius.circular(FMRadius.card),
            border: Border.all(color: s.border, width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(FMRadius.field),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: FMSpacing.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.bodyStrong(s.ink)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppText.caption(s.inkSecondary)),
                  ],
                ),
              ),
              Icon(FMIcons.chevronRight, size: 16, color: s.inkTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
