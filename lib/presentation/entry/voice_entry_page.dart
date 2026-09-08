import 'dart:async';
import 'dart:io' show File, FileSystemException;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/money_utils.dart';
import '../../core/widgets/fm_toast.dart';
import '../../data/services/remote_ai_services.dart';
import '../../domain/models/category.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/transaction.dart';
import '../../domain/models/transaction_candidate.dart';
import '../../services/merchant_rule_matcher.dart';
import '../../state/app_providers.dart';
import 'candidate_review_card.dart';

/// 语音记账：移动端真实录音 → 千问 ASR + 意图解析。
/// 一句话可包含多笔账单（逐笔确认保存），也可修改已有账单（确认后更新）。
/// Web / 未配置后端时为演示模式。
class VoiceEntryPage extends ConsumerStatefulWidget {
  const VoiceEntryPage({super.key});

  @override
  ConsumerState<VoiceEntryPage> createState() => _VoiceEntryPageState();
}

enum _Phase { idle, recording, parsing, submitted, reviewing }

class _VoiceEntryPageState extends ConsumerState<VoiceEntryPage>
    with SingleTickerProviderStateMixin {
  _Phase _phase = _Phase.idle;
  String? _recognizedText;

  /// 演示模式：Mock 单笔。
  TransactionCandidate? _candidate;

  /// 真实模式 intent=create：待逐笔确认保存的新账单。
  List<TransactionCandidate> _candidates = [];

  /// 真实模式 intent=update：修改建议 + 匹配到的原账单。
  VoiceUpdateSuggestion? _updateSuggestion;
  TransactionEntity? _updateTarget;
  bool _applyingUpdate = false;
  BackgroundJobSubmission? _submittedJob;

  final AudioRecorder _recorder = AudioRecorder();
  Timer? _tick;
  int _seconds = 0;
  Future<void>? _startFuture;
  bool _pressActive = false;
  bool _stopInProgress = false;

  bool get _isDemo => kIsWeb || ref.read(voiceEntryProvider) == null;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ---- 录音 ----

  void _handlePressStart(PointerDownEvent event) {
    if (_phase != _Phase.idle || _pressActive) return;
    _pressActive = true;
    _startFuture = _start();
  }

  Future<void> _handlePressEnd(PointerEvent event) async {
    if (!_pressActive) return;
    _pressActive = false;
    await _startFuture;
    if (!mounted || _phase != _Phase.recording || _stopInProgress) return;
    await _stopAndParse();
  }

  Future<void> _start() async {
    if (_phase == _Phase.recording || _phase == _Phase.parsing) return;

    // 演示模式：Web 或未配置后端（保留原 Mock 流程）。
    if (_isDemo) return _startDemo();

    final ok = await _recorder.hasPermission();
    if (!ok) {
      if (!mounted) return;
      showFMToast(
        context,
        message: '需要麦克风权限，请在系统设置中允许',
        icon: FMIcons.warning,
        iconColor: context.colors.danger,
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_entry_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
    } catch (_) {
      if (!mounted) return;
      showFMToast(
        context,
        message: '录音启动失败，请重试',
        icon: FMIcons.warning,
        iconColor: context.colors.danger,
      );
      return;
    }

    _seconds = 0;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    setState(() => _phase = _Phase.recording);
    _pulse.repeat(reverse: true);
  }

  Future<void> _stopAndParse() async {
    if (_phase != _Phase.recording || _stopInProgress) return;
    _stopInProgress = true;
    _tick?.cancel();
    String? path;
    try {
      path = await _recorder.stop();
    } finally {
      _stopInProgress = false;
    }
    if (path == null) {
      setState(() => _phase = _Phase.idle);
      _pulse.stop();
      return;
    }

    setState(() => _phase = _Phase.parsing);
    try {
      final recent = await _recentTransactionsForAi();
      final merchantRules = MerchantRuleMatcher.toWireJson(
          ref.read(merchantRulesProvider).valueOrNull ?? const []);
      final remote = ref.read(backgroundJobServiceProvider);
      if (remote == null) throw RemoteException('AI 服务正在初始化，请稍后重试');
      final submission = await remote.submitAudio(
        path,
        durationSeconds: math.max(_seconds, 1),
        recentTransactions: recent,
        merchantRules:
            merchantRules.isEmpty ? null : merchantRules,
      );
      await ref.read(pendingAiJobServiceProvider).add(submission);
      if (!mounted) return;
      setState(() {
        _submittedJob = submission;
        _phase = _Phase.submitted;
      });
    } catch (e) {
      if (!mounted) return;
      showFMToast(
        context,
        message: e is RemoteException ? e.message : '语音服务不可用，请检查 AI 后端',
        icon: FMIcons.warning,
        iconColor: context.colors.danger,
      );
      setState(() => _phase = _Phase.idle);
    } finally {
      _pulse.stop();
      try {
        await File(path).delete();
      } on FileSystemException {
        // 临时录音由系统缓存目录兜底清理。
      }
    }
  }

  /// 最近 20 笔账单 → 供后端定位"修改"目标（含 id）。
  Future<List<Map<String, dynamic>>> _recentTransactionsForAi() async {
    final all = await ref.read(transactionRepositoryProvider).getAll();
    all.sort((a, b) => b.transactionTime.compareTo(a.transactionTime));
    return all
        .take(20)
        .map((t) => <String, dynamic>{
              'id': t.id,
              'type': t.isIncome ? 'income' : 'expense',
              'amountCents': t.amountCents,
              'merchant': t.merchant,
              'description': t.description,
              'categoryId': t.categoryId,
              'transactionTime': t.transactionTime.toIso8601String(),
            })
        .toList();
  }

  // ---- intent=create：已自动入库，删除一笔移除一张卡片 ----

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

  // ---- intent=update：应用修改 ----

  Future<void> _applyUpdate() async {
    final target = _updateTarget;
    final suggestion = _updateSuggestion;
    if (target == null || suggestion == null || _applyingUpdate) return;
    setState(() => _applyingUpdate = true);
    try {
      final updated = _applyFields(target, suggestion.fields)
          .copyWith(updatedAt: DateTime.now(), status: TxStatus.confirmed);
      await ref.read(transactionRepositoryProvider).update(updated);
      ref.read(dataVersionProvider.notifier).state++;
      if (!mounted) return;
      showFMToast(context, message: '已修改', icon: FMIcons.checkCircle);
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      showFMToast(
        context,
        message: '修改失败，请重试',
        icon: FMIcons.warning,
        iconColor: context.colors.danger,
      );
    } finally {
      if (mounted) setState(() => _applyingUpdate = false);
    }
  }

  /// 把服务器返回的字段增量应用到账单（只动给出的字段）。
  TransactionEntity _applyFields(
    TransactionEntity tx,
    Map<String, dynamic> fields,
  ) {
    var updated = tx;
    for (final entry in fields.entries) {
      final value = entry.value;
      switch (entry.key) {
        case 'type':
          if (value is String) {
            updated = updated.copyWith(
              type: value == 'income'
                  ? TransactionType.income
                  : TransactionType.expense,
            );
          }
        case 'amountCents':
          if (value is num) {
            updated = updated.copyWith(amountCents: value.round());
          }
        case 'currency':
          if (value is String && value.isNotEmpty) {
            updated = updated.copyWith(currency: value);
          }
        case 'categoryId':
          if (value is String && value.isNotEmpty) {
            updated = updated.copyWith(categoryId: value);
          }
        case 'subcategory':
          if (value is String) {
            updated = updated.copyWith(
              subcategory: value.isEmpty ? null : value,
              clearSubcategory: value.isEmpty,
            );
          }
        case 'merchant':
          if (value is String && value.isNotEmpty) {
            updated = updated.copyWith(merchant: value);
          }
        case 'description':
          if (value is String && value.isNotEmpty) {
            updated = updated.copyWith(description: value);
          }
        case 'transactionTime':
          final time = DateTime.tryParse('$value');
          if (time != null) updated = updated.copyWith(transactionTime: time);
        case 'paymentMethod':
          updated =
              updated.copyWith(paymentMethod: paymentMethodFromJson('$value'));
        case 'note':
          if (value is String && value.isNotEmpty) {
            updated = updated.copyWith(note: value);
          }
      }
    }
    return updated;
  }

  // ---- 演示模式 ----

  /// 演示模式：Mock 句子 + 当前解析器（远程不可用时降级规则引擎）。
  Future<void> _startDemo() async {
    setState(() => _phase = _Phase.parsing);
    _pulse.repeat(reverse: true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    final text = await ref.read(speechServiceProvider).recognizeOnce();
    final candidate = await ref.read(parserProvider).parseFromText(text);
    if (!mounted) return;
    setState(() {
      _recognizedText = text;
      _candidate = candidate;
      _phase = _Phase.reviewing;
    });
    _pulse.stop();
  }

  void _reset() {
    setState(() {
      _phase = _Phase.idle;
      _pressActive = false;
      _stopInProgress = false;
      _candidate = null;
      _candidates = [];
      _updateSuggestion = null;
      _updateTarget = null;
      _recognizedText = null;
      _submittedJob = null;
    });
  }

  String get _elapsed {
    final minutes = (_seconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        title: const Text('语音记账'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: FMSpacing.xl),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: switch (_phase) {
                    _Phase.idle || _Phase.recording => _HoldToRecordView(
                        pulse: _pulse,
                        recording: _phase == _Phase.recording,
                        elapsed: _elapsed,
                        onPointerDown: _handlePressStart,
                        onPointerUp: _handlePressEnd,
                        s: s,
                        isDemo: _isDemo,
                      ),
                    _Phase.parsing => _ParsingView(pulse: _pulse, s: s),
                    _Phase.submitted => _SubmittedVoiceView(
                        submission: _submittedJob!,
                        onDone: () => Navigator.of(context).pop(),
                        onAgain: _reset,
                        s: s,
                      ),
                    _Phase.reviewing => SingleChildScrollView(
                        child: Column(
                          children: [
                            if (_recognizedText != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(FMSpacing.l),
                                decoration: BoxDecoration(
                                  color: s.accentSoft,
                                  borderRadius:
                                      BorderRadius.circular(FMRadius.card),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(FMIcons.waveform,
                                        size: 16, color: s.accent),
                                    const SizedBox(width: FMSpacing.s),
                                    Expanded(
                                      child: Text(
                                        '“$_recognizedText”',
                                        style: AppText.body(s.ink),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: FMSpacing.l),
                            ],
                            if (_updateSuggestion != null &&
                                _updateTarget != null)
                              _buildUpdateConfirm(s)
                            else ...[
                              if (_candidates.length > 1) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(FMSpacing.m),
                                  decoration: BoxDecoration(
                                    color: s.accentSoft,
                                    borderRadius:
                                        BorderRadius.circular(FMRadius.card),
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
                                  padding: const EdgeInsets.only(
                                      bottom: FMSpacing.m),
                                  child: CandidateReviewCard(
                                    candidate: candidate,
                                    onRemoved: () => _onCardRemoved(candidate),
                                  ),
                                ),
                              if (_candidate != null)
                                CandidateReviewCard(
                                  candidate: _candidate!,
                                  onRemoved: () => Navigator.of(context).pop(),
                                ),
                            ],
                            const SizedBox(height: FMSpacing.m),
                            TextButton(
                              onPressed: _reset,
                              child: Text(
                                  _updateSuggestion != null ? '不改了' : '重新说一句',
                                  style: AppText.sub(s.accent)),
                            ),
                          ],
                        ),
                      ),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 修改确认视图 ----

  Widget _buildUpdateConfirm(FMScheme s) {
    final catMap = ref.watch(categoryMapProvider).valueOrNull ?? const {};
    final suggestion = _updateSuggestion!;
    return Container(
      width: double.infinity,
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
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: s.accentSoft,
                  borderRadius: BorderRadius.circular(FMRadius.field),
                ),
                child: Icon(FMIcons.edit, size: 17, color: s.accent),
              ),
              const SizedBox(width: FMSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('修改这笔账单', style: AppText.bodyStrong(s.ink)),
                    const SizedBox(height: 2),
                    Text(
                      suggestion.matchSummary.isEmpty
                          ? '已匹配到原有记录'
                          : suggestion.matchSummary,
                      style: AppText.caption(s.inkSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: FMSpacing.l),
          for (final entry in suggestion.fields.entries)
            _DiffRow(
              label: _fieldLabel(entry.key),
              oldValue: _oldValueFor(entry.key, catMap),
              newValue: _formatFieldValue(entry.key, entry.value, catMap),
              s: s,
            ),
          for (final w in suggestion.parseWarnings) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(FMIcons.warning, size: 13, color: s.warn),
                const SizedBox(width: FMSpacing.xs),
                Expanded(child: Text(w, style: AppText.caption(s.warn))),
              ],
            ),
          ],
          const SizedBox(height: FMSpacing.l),
          GestureDetector(
            onTap: _applyingUpdate ? null : _applyUpdate,
            child: Container(
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: s.accent,
                borderRadius: BorderRadius.circular(FMRadius.button),
              ),
              child: _applyingUpdate
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text('确认修改',
                      style: AppText.bodyStrong(Colors.white)
                          .copyWith(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  String _fieldLabel(String key) => switch (key) {
        'amountCents' => '金额',
        'categoryId' => '分类',
        'type' => '类型',
        'transactionTime' => '时间',
        'paymentMethod' => '支付方式',
        'merchant' => '商户',
        'description' => '描述',
        'subcategory' => '子分类',
        'note' => '备注',
        'currency' => '币种',
        _ => key,
      };

  String _oldValueFor(String key, Map<String, Category> catMap) {
    final t = _updateTarget!;
    return switch (key) {
      'amountCents' => '¥${Money.centsToText(t.amountCents)}',
      'categoryId' => t.categoryId == null
          ? '未分类'
          : (catMap[t.categoryId]?.name ?? t.categoryId!),
      'type' => t.type.label,
      'transactionTime' => AppDate.fullTitle(t.transactionTime),
      'paymentMethod' => t.paymentMethod?.label ?? '未记录',
      'merchant' => t.merchant ?? '（空）',
      'description' => t.description ?? '（空）',
      'subcategory' => t.subcategory ?? '（空）',
      'note' => t.note ?? '（空）',
      'currency' => t.currency,
      _ => '—',
    };
  }

  String _formatFieldValue(
    String key,
    Object? value,
    Map<String, Category> catMap,
  ) {
    return switch (key) {
      'amountCents' when value is num => '¥${Money.centsToText(value.round())}',
      'categoryId' when value is String => catMap[value]?.name ?? value,
      'type' when value is String => value == 'income' ? '收入' : '支出',
      'transactionTime' when value is String =>
        DateTime.tryParse(value)?.let(AppDate.fullTitle) ?? value,
      'paymentMethod' when value is String =>
        paymentMethodFromJson(value)?.label ?? value,
      _ when value == null || '$value'.isEmpty => '（清空）',
      _ => '$value',
    };
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.label,
    required this.oldValue,
    required this.newValue,
    required this.s,
  });

  final String label;
  final String oldValue;
  final String newValue;
  final FMScheme s;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FMSpacing.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Text(label, style: AppText.sub(s.inkSecondary)),
          ),
          Expanded(
            child: Text(
              oldValue,
              style: AppText.sub(s.inkTertiary)
                  .copyWith(decoration: TextDecoration.lineThrough),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(FMIcons.chevronRight, size: 12, color: s.inkTertiary),
          ),
          Expanded(
            child: Text(newValue, style: AppText.body(s.accent)),
          ),
        ],
      ),
    );
  }
}

class _HoldToRecordView extends StatelessWidget {
  const _HoldToRecordView({
    required this.pulse,
    required this.recording,
    required this.elapsed,
    required this.onPointerDown,
    required this.onPointerUp,
    required this.s,
    required this.isDemo,
  });

  final Animation<double> pulse;
  final bool recording;
  final String elapsed;
  final PointerDownEventListener onPointerDown;
  final void Function(PointerEvent) onPointerUp;
  final FMScheme s;
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (recording) ...[
          AnimatedBuilder(
            animation: pulse,
            builder: (context, _) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 7; i++)
                  Container(
                    width: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 12 +
                        34 *
                            (0.5 +
                                    0.5 *
                                        math.sin(pulse.value * math.pi * 2 +
                                            i * 0.9))
                                .abs(),
                    decoration: BoxDecoration(
                      color:
                          s.accent.withValues(alpha: 0.4 + 0.6 * (i % 3) / 2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: FMSpacing.xl),
          Text(elapsed, style: AppText.amountL(s.ink)),
          const SizedBox(height: FMSpacing.l),
        ],
        Semantics(
          button: true,
          label: recording ? '松开结束录音' : '按住开始录音',
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: recording ? null : onPointerDown,
            onPointerUp: onPointerUp,
            onPointerCancel: onPointerUp,
            child: AnimatedBuilder(
              animation: pulse,
              builder: (context, child) => Transform.scale(
                scale: recording ? 0.96 + pulse.value * 0.04 : 1,
                child: child,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 124,
                height: 124,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: recording ? s.danger : s.accent,
                  boxShadow: [
                    BoxShadow(
                      color: (recording ? s.danger : s.accent)
                          .withValues(alpha: 0.3),
                      blurRadius: 40,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Icon(
                  recording ? FMIcons.waveform : FMIcons.mic,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: FMSpacing.xl),
        Text(
          recording ? '松开结束' : (isDemo ? '按住体验（演示模式）' : '按住说话'),
          style: AppText.title(recording ? s.danger : s.ink),
        ),
        const SizedBox(height: FMSpacing.s),
        Text(
          recording
              ? '说完后松开，自动识别并记账'
              : (isDemo
                  ? '演示模式：按住后自动识别一句示例账单'
                  : '松开自动结束 · 可一次说多笔\n例如："吃饭28，打车15"'),
          textAlign: TextAlign.center,
          style: AppText.sub(s.inkTertiary),
        ),
      ],
    );
  }
}

class _ParsingView extends StatelessWidget {
  const _ParsingView({required this.pulse, required this.s});

  final Animation<double> pulse;
  final FMScheme s;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.04).animate(
            CurvedAnimation(parent: pulse, curve: Curves.easeInOut),
          ),
          child: Container(
            width: 88,
            height: 88,
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: s.accentSoft),
            child: Icon(FMIcons.waveform, color: s.accent, size: 34),
          ),
        ),
        const SizedBox(height: FMSpacing.xl),
        Text('正在上传录音…', style: AppText.title(s.ink)),
        const SizedBox(height: FMSpacing.s),
        Text('上传完成后可退出 App，由服务器继续处理',
            textAlign: TextAlign.center, style: AppText.sub(s.inkTertiary)),
      ],
    );
  }
}

class _SubmittedVoiceView extends StatelessWidget {
  const _SubmittedVoiceView({
    required this.submission,
    required this.onDone,
    required this.onAgain,
    required this.s,
  });

  final BackgroundJobSubmission submission;
  final VoidCallback onDone;
  final VoidCallback onAgain;
  final FMScheme s;

  String get _durationLabel {
    final seconds = submission.estimateSeconds;
    if (seconds < 60) return '$seconds 秒';
    final minutes = (seconds / 60).ceil();
    return '$minutes 分钟';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FMSpacing.xl),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(FMRadius.card),
        border: Border.all(color: s.border, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FMIcons.checkCircle, size: 42, color: s.income),
          const SizedBox(height: FMSpacing.l),
          Text('上传成功，服务器正在处理', style: AppText.title(s.ink)),
          const SizedBox(height: FMSpacing.s),
          Text(
            '根据录音时长，预计约 $_durationLabel 完成',
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
            onPressed: onDone,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('完成'),
          ),
          TextButton(onPressed: onAgain, child: const Text('继续录音')),
        ],
      ),
    );
  }
}

class FMBadgeLite extends StatelessWidget {
  const FMBadgeLite({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(label, style: AppText.micro(color)),
    );
  }
}
