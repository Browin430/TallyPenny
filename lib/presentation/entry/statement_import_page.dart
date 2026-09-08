import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/fm_toast.dart';
import '../../data/services/remote_ai_services.dart';
import '../../state/app_providers.dart';

class StatementImportPage extends ConsumerStatefulWidget {
  const StatementImportPage({super.key});

  @override
  ConsumerState<StatementImportPage> createState() =>
      _StatementImportPageState();
}

class _StatementImportPageState extends ConsumerState<StatementImportPage> {
  bool _busy = false;
  BackgroundJobSubmission? _submission;

  Future<void> _pickFiles() async {
    if (_busy) return;
    final files = await FilePicker.pickFiles(
      dialogTitle: '选择支付宝或微信账单文件',
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx'],
    );
    if (files.isEmpty || !mounted) return;
    if (files.length > 5) {
      showFMToast(
        context,
        message: '一次最多选择 5 个账单文件',
        icon: FMIcons.warning,
      );
      return;
    }
    final paths = files.map((file) => file.path).whereType<String>().toList();
    if (paths.length != files.length) {
      showFMToast(
        context,
        message: '无法读取所选文件，请先保存到手机本地',
        icon: FMIcons.warning,
      );
      return;
    }
    final remote = ref.read(backgroundJobServiceProvider);
    if (remote == null) {
      showFMToast(
        context,
        message: '账单服务正在初始化，请稍后重试',
        icon: FMIcons.warning,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final submission = await remote.submitStatements(paths);
      await ref.read(pendingAiJobServiceProvider).add(submission);
      if (!mounted) return;
      setState(() => _submission = submission);
    } catch (error) {
      if (!mounted) return;
      showFMToast(
        context,
        message: error is RemoteException ? error.message : '账单文件上传失败',
        icon: FMIcons.warning,
        iconColor: context.colors.danger,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(title: const Text('账单文件导入')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FMSpacing.l),
          children: [
            if (_submission != null)
              _SubmittedStatementCard(
                submission: _submission!,
                onDone: () => Navigator.of(context).pop(),
                onAgain: () => setState(() => _submission = null),
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(FMSpacing.xl),
                decoration: BoxDecoration(
                  color: s.surface,
                  borderRadius: BorderRadius.circular(FMRadius.card),
                  border: Border.all(color: s.border, width: 0.5),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: s.accentSoft,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(FMIcons.note, color: s.accent, size: 27),
                    ),
                    const SizedBox(height: FMSpacing.l),
                    Text('导入官方账单文件', style: AppText.title(s.ink)),
                    const SizedBox(height: FMSpacing.s),
                    Text(
                      '支持支付宝导出的 CSV 和微信支付导出的 XLSX，可一次选择多个文件。',
                      textAlign: TextAlign.center,
                      style: AppText.sub(s.inkSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FMSpacing.l),
              _ImportRuleRow(
                icon: FMIcons.checkCircle,
                text: '自动识别表头、收支方向、商户、时间和支付方式',
              ),
              _ImportRuleRow(
                icon: FMIcons.merge,
                text: '自动去重；退款记录直接忽略，不计入收入或支出',
              ),
              _ImportRuleRow(
                icon: FMIcons.info,
                text: '中性交易、交易关闭和失败记录不会计入流水',
              ),
              const SizedBox(height: FMSpacing.xl),
              FilledButton.icon(
                onPressed: _busy ? null : _pickFiles,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(FMIcons.shareUp, size: 18),
                label: Text(_busy ? '正在上传…' : '选择账单文件'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImportRuleRow extends StatelessWidget {
  const _ImportRuleRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FMSpacing.s),
      child: Row(
        children: [
          Icon(icon, size: 17, color: s.accent),
          const SizedBox(width: FMSpacing.m),
          Expanded(child: Text(text, style: AppText.sub(s.inkSecondary))),
        ],
      ),
    );
  }
}

class _SubmittedStatementCard extends StatelessWidget {
  const _SubmittedStatementCard({
    required this.submission,
    required this.onDone,
    required this.onAgain,
  });

  final BackgroundJobSubmission submission;
  final VoidCallback onDone;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final duration = submission.estimateSeconds < 60
        ? '${submission.estimateSeconds} 秒'
        : '${(submission.estimateSeconds / 60).ceil()} 分钟';
    return Container(
      padding: const EdgeInsets.all(FMSpacing.xl),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(FMRadius.card),
        border: Border.all(color: s.border, width: 0.5),
      ),
      child: Column(
        children: [
          Icon(FMIcons.checkCircle, size: 44, color: s.income),
          const SizedBox(height: FMSpacing.l),
          Text('上传成功，服务器正在整理', style: AppText.title(s.ink)),
          const SizedBox(height: FMSpacing.s),
          Text(
            '已上传 ${submission.fileCount} 个文件，预计约 $duration 完成',
            textAlign: TextAlign.center,
            style: AppText.body(s.inkSecondary),
          ),
          const SizedBox(height: FMSpacing.m),
          Text(
            '现在可以退出 App。稍后重新打开，账单会自动去重并更新到流水。',
            textAlign: TextAlign.center,
            style: AppText.sub(s.inkTertiary),
          ),
          const SizedBox(height: FMSpacing.xl),
          FilledButton(
            onPressed: onDone,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('完成'),
          ),
          TextButton(onPressed: onAgain, child: const Text('继续导入')),
        ],
      ),
    );
  }
}
