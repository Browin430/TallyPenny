import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/fm_toast.dart';
import '../../data/services/remote_ai_services.dart';
import '../../domain/models/transaction_candidate.dart';
import '../../services/merchant_rule_matcher.dart';
import '../../state/app_providers.dart';
import '../../services/image_crop_flow.dart';
import 'candidate_review_card.dart';

/// 截图记账。
/// TODO(phase-4): 接入相册选择（image_picker）与端侧 OCR；
/// 当前提供两个内置示例账单，OCR → AI 解析 → 去重 → 入库链路真实可用。
class ScreenshotEntryPage extends ConsumerStatefulWidget {
  const ScreenshotEntryPage({super.key});

  @override
  ConsumerState<ScreenshotEntryPage> createState() =>
      _ScreenshotEntryPageState();
}

class _ScreenshotEntryPageState extends ConsumerState<ScreenshotEntryPage> {
  bool _busy = false;
  String? _ocrRawText;
  List<TransactionCandidate> _candidates = [];
  BackgroundJobSubmission? _submittedJob;

  final ImagePicker _picker = ImagePicker();

  /// 从相册选择真实账单截图（移动端）。
  Future<void> _pickAndRecognize() async {
    if (_busy) return;
    final selected = await _picker.pickMultiImage(
      imageQuality: 88,
    );
    if (selected.isEmpty) return;
    if (!mounted) return;
    if (selected.length > 10) {
      showFMToast(
        context,
        message: '一次最多选择 10 张截图',
        icon: FMIcons.warning,
      );
      return;
    }
    final prepared = <String>[];
    for (var index = 0; index < selected.length; index++) {
      if (!mounted) return;
      final path = await preparePickedImage(
        context,
        selected[index].path,
        cropTitle: selected.length == 1
            ? '裁剪账单截图'
            : '裁剪第 ${index + 1}/${selected.length} 张',
      );
      if (path != null) prepared.add(path);
    }
    if (prepared.isEmpty || !mounted) return;
    await _submitScreenshots(prepared);
  }

  Future<void> _submitScreenshots(List<String> imagePaths) async {
    final remote = ref.read(backgroundJobServiceProvider);
    if (remote == null) {
      showFMToast(
        context,
        message: 'AI 服务正在初始化，请稍后重试',
        icon: FMIcons.warning,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final merchantRules = MerchantRuleMatcher.toWireJson(
          ref.read(merchantRulesProvider).valueOrNull ?? const []);
      final submission = await remote.submitScreenshots(
        imagePaths,
        merchantRules: merchantRules.isEmpty ? null : merchantRules,
      );
      await ref.read(pendingAiJobServiceProvider).add(submission);
      if (!mounted) return;
      setState(() => _submittedJob = submission);
    } catch (e) {
      if (!mounted) return;
      showFMToast(
        context,
        message: e is RemoteException ? e.message : '上传失败，请重试',
        icon: FMIcons.warning,
        iconColor: context.colors.danger,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recognize(String imageReference) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final remote = ref.read(screenshotEntryProvider);
      if (remote != null && !kIsWeb) {
        // 远端一次完成 OCR + 多笔解析。
        final merchantRules = MerchantRuleMatcher.toWireJson(
            ref.read(merchantRulesProvider).valueOrNull ?? const []);
        final result = await remote.parseFile(
          imageReference,
          merchantRules: merchantRules.isEmpty ? null : merchantRules,
        );
        if (!mounted) return;
        setState(() {
          _ocrRawText = result.ocrText;
          _candidates = result.candidates;
        });
        return;
      }

      // 演示模式：Mock OCR → 解析（单笔）。
      final ocr = await ref.read(ocrServiceProvider).recognize(imageReference);
      if (ocr.rawText.isEmpty) {
        if (mounted) {
          showFMToast(
            context,
            message: '无法识别这张图片，请换一张账单截图',
            icon: FMIcons.warning,
            iconColor: context.colors.danger,
          );
        }
        return;
      }
      final candidate = await ref.read(parserProvider).parseFromOcr(ocr);
      if (!mounted) return;
      setState(() {
        _ocrRawText = ocr.rawText;
        _candidates = [candidate];
      });
    } catch (e) {
      if (mounted) {
        showFMToast(
          context,
          message: e is RemoteException ? e.message : '识别失败，请重试',
          icon: FMIcons.warning,
          iconColor: context.colors.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        title: const Text('截图记账'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: FMSpacing.l),
          children: [
            if (_submittedJob != null) ...[
              const SizedBox(height: FMSpacing.xl),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(FMSpacing.xl),
                decoration: BoxDecoration(
                  color: s.surface,
                  borderRadius: BorderRadius.circular(FMRadius.card),
                  border: Border.all(color: s.border, width: 0.5),
                ),
                child: Column(
                  children: [
                    Icon(FMIcons.checkCircle, size: 42, color: s.income),
                    const SizedBox(height: FMSpacing.l),
                    Text('上传成功，服务器正在处理', style: AppText.title(s.ink)),
                    const SizedBox(height: FMSpacing.s),
                    Text(
                      '已上传 ${_submittedJob!.fileCount} 张截图\n'
                      '预计约 ${_durationLabel(_submittedJob!.estimateSeconds)} 完成',
                      textAlign: TextAlign.center,
                      style: AppText.body(s.inkSecondary),
                    ),
                    const SizedBox(height: FMSpacing.m),
                    Text(
                      '现在可以退出 App，服务器会继续识别。稍后重新打开 App，账单会自动更新。',
                      textAlign: TextAlign.center,
                      style: AppText.sub(s.inkTertiary),
                    ),
                    const SizedBox(height: FMSpacing.xl),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('完成'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _submittedJob = null),
                      child: const Text('继续上传'),
                    ),
                  ],
                ),
              ),
            ] else if (_candidates.isEmpty) ...[
              const SizedBox(height: FMSpacing.s),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: FMSpacing.xl,
                  vertical: 42,
                ),
                decoration: BoxDecoration(
                  color: s.surface,
                  borderRadius: BorderRadius.circular(FMRadius.card),
                  border: Border.all(color: s.border, width: 1),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: s.accentSoft,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(FMIcons.camera, color: s.accent, size: 26),
                    ),
                    const SizedBox(height: FMSpacing.l),
                    Text('上传账单截图', style: AppText.title(s.ink)),
                    const SizedBox(height: FMSpacing.s),
                    Text(
                      '上传支付宝、微信或银行卡账单截图',
                      textAlign: TextAlign.center,
                      style: AppText.sub(s.inkSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FMSpacing.xl),
              if (!kIsWeb) ...[
                // 真实入口：相册选图（OCR → AI 解析）。
                GestureDetector(
                  onTap: _busy ? null : _pickAndRecognize,
                  child: Container(
                    width: double.infinity,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: s.accent,
                      borderRadius: BorderRadius.circular(FMRadius.button),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FMIcons.shareUp, size: 18, color: Colors.white),
                        const SizedBox(width: FMSpacing.s),
                        Text('从相册选择一张或多张截图',
                            style: AppText.bodyStrong(Colors.white)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: FMSpacing.xl),
                Text('或试试演示账单', style: AppText.bodyStrong(s.ink)),
              ] else ...[
                Text('选择演示账单', style: AppText.bodyStrong(s.ink)),
              ],
              const SizedBox(height: FMSpacing.m),
              const SizedBox(height: FMSpacing.m),
              _DemoSourceButton(
                icon: FMIcons.card,
                label: '支付宝账单示例',
                subtitle: 'XX烟酒商行 · ¥3.00',
                busy: _busy,
                onTap: () => _recognize('alipay_demo'),
                s: s,
              ),
              const SizedBox(height: FMSpacing.m),
              _DemoSourceButton(
                icon: FMIcons.globe,
                label: '微信支付示例',
                subtitle: '麦当劳 · ¥32.00',
                busy: _busy,
                onTap: () => _recognize('wechat_demo'),
                s: s,
              ),
              if (_busy) ...[
                const SizedBox(height: FMSpacing.xl),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    backgroundColor: s.separator,
                    color: s.accent,
                  ),
                ),
                const SizedBox(height: FMSpacing.m),
                Center(
                    child: Text('正在上传截图…', style: AppText.sub(s.inkSecondary))),
              ],
            ] else ...[
              if (_candidates.length > 1) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(FMSpacing.m),
                  decoration: BoxDecoration(
                    color: s.accentSoft,
                    borderRadius: BorderRadius.circular(FMRadius.card),
                  ),
                  child: Text(
                    '识别到 ${_candidates.length} 笔账单，已自动保存，点删除可撤销',
                    style: AppText.sub(s.accent),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: FMSpacing.m),
              ],
              for (final candidate
                  in List<TransactionCandidate>.of(_candidates))
                Padding(
                  padding: const EdgeInsets.only(bottom: FMSpacing.m),
                  child: CandidateReviewCard(
                    candidate: candidate,
                    onRemoved: () => _onCardRemoved(candidate),
                  ),
                ),
              if (_ocrRawText != null) ...[
                const SizedBox(height: FMSpacing.l),
                Text('识别文本（已留存原始记录）', style: AppText.caption(s.inkTertiary)),
                const SizedBox(height: FMSpacing.xs),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(FMSpacing.m),
                  decoration: BoxDecoration(
                    color: s.surfaceAlt,
                    borderRadius: BorderRadius.circular(FMRadius.field),
                    border: Border.all(color: s.border, width: 0.5),
                  ),
                  child: Text(
                    _ocrRawText!,
                    style:
                        AppText.caption(s.inkSecondary).copyWith(height: 1.6),
                  ),
                ),
              ],
              const SizedBox(height: FMSpacing.m),
              TextButton(
                onPressed: () => setState(() {
                  _candidates = [];
                  _ocrRawText = null;
                }),
                child: Text('识别另一张', style: AppText.sub(s.accent)),
              ),
            ],
            const SizedBox(height: FMSpacing.xxl),
          ],
        ),
      ),
    );
  }

  /// 用户删除某笔后从列表移除卡片；全部删完则退出页面。
  void _onCardRemoved(TransactionCandidate removed) {
    if (!mounted) return;
    final remaining = List<TransactionCandidate>.of(_candidates)
      ..remove(removed);
    if (remaining.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _candidates = remaining);
  }

  static String _durationLabel(int seconds) {
    if (seconds < 60) return '$seconds 秒';
    final minutes = (seconds / 60).ceil();
    return '$minutes 分钟';
  }
}

class _DemoSourceButton extends StatelessWidget {
  const _DemoSourceButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.busy,
    required this.onTap,
    required this.s,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool busy;
  final VoidCallback onTap;
  final FMScheme s;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: s.surface,
      borderRadius: BorderRadius.circular(FMRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(FMRadius.card),
        onTap: busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(FMSpacing.l),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FMRadius.card),
            border: Border.all(color: s.border, width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: s.accentSoft,
                  borderRadius: BorderRadius.circular(FMRadius.field),
                ),
                child: Icon(icon, color: s.accent, size: 20),
              ),
              const SizedBox(width: FMSpacing.l),
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
              Icon(FMIcons.chevronRight, size: 16, color: s.inkTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
