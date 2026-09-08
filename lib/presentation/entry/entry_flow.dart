import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_icons.dart';
import '../../core/widgets/fm_toast.dart';
import '../../domain/models/transaction.dart';
import '../../domain/models/transaction_candidate.dart';
import '../../domain/pipeline/transaction_pipeline.dart';
import '../../state/app_providers.dart';
import 'duplicate_confirm_sheet.dart';

/// 统一保存流程：所有入口（语音 / 截图 / 手动 / 未来导入）共用。
/// 处理：Pipeline 结果分发 → 重复确认弹窗 → Toast → 刷新数据。
/// 返回 true 表示账单已落库（含合并）。
Future<bool> saveCandidateFlow(
  BuildContext context,
  WidgetRef ref,
  TransactionCandidate candidate,
) async {
  final pipeline = ref.read(pipelineProvider);
  final result = await pipeline.process(candidate);

  Future<void> bump() async {
    ref.read(dataVersionProvider.notifier).state++;
  }

  switch (result) {
    case PipelineSaved():
      await bump();
      if (!context.mounted) return true;
      showFMToast(
        context,
        message: result.mergedIntoExisting ? '与已有账单重复，已自动合并' : '已记录',
        icon: FMIcons.checkCircle,
      );
      return true;

    case PipelineNeedsReview(:final reason):
      if (!context.mounted) return false;
      final message = switch (reason) {
        'missing_amount' => '没有识别到金额，请补充后再保存',
        _ => '信息不完整，请检查后重试',
      };
      showFMToast(
        context,
        message: message,
        icon: FMIcons.warning,
        iconColor: Theme.of(context).colorScheme.error,
      );
      return false;

    case PipelineDuplicateSuspected(:final match):
      if (!context.mounted) return false;
      final categories = await ref.read(categoryMapProvider.future);
      if (!context.mounted) return false;
      final decision = await showDuplicateConfirmSheet(
        context,
        match: match,
        existingCategory: categories[match.existing.categoryId],
        incomingCategory: candidate.categoryId == null
            ? null
            : categories[candidate.categoryId],
      );
      if (decision == null) return false;
      if (decision == DuplicateDecision.merge) {
        await pipeline.merge(match);
        await bump();
        if (context.mounted) {
          showFMToast(context, message: '已合并为一笔', icon: FMIcons.merge);
        }
        return true;
      } else {
        await pipeline.keepBoth(match);
        await bump();
        if (context.mounted) {
          showFMToast(context, message: '已作为两笔消费记录', icon: FMIcons.checkCircle);
        }
        return true;
      }
  }
}

// =====================================================================
// 自动保存（识别类入口默认入库，用户只在不想要时删除）
// =====================================================================

/// 自动保存结果。
sealed class AutoSaveOutcome {}

/// 已入库。疑似重复时不弹窗、按"两笔保留"处理（审计事件已记录）。
class AutoSaved implements AutoSaveOutcome {
  AutoSaved({
    required this.transaction,
    this.mergedIntoExisting = false,
    this.duplicateKept = false,
  });

  final TransactionEntity transaction;
  final bool mergedIntoExisting;
  final bool duplicateKept;
}

/// 缺金额，无法自动入库 —— 卡片保留"保存"按钮由用户补齐。
class AutoSaveNeedsAmount implements AutoSaveOutcome {
  AutoSaveNeedsAmount(this.candidate);

  final TransactionCandidate candidate;
}

/// 识别结果的无人值守保存：不打断、不弹窗。
/// 与 [saveCandidateFlow] 走同一条 [TransactionPipeline]，只是分发方式不同。
Future<AutoSaveOutcome> autoSaveCandidateFlow(
  WidgetRef ref,
  TransactionCandidate candidate,
) async {
  final pipeline = ref.read(pipelineProvider);
  final result = await pipeline.process(candidate);

  switch (result) {
    case PipelineSaved(:final transaction, :final mergedIntoExisting):
      ref.read(dataVersionProvider.notifier).state++;
      return AutoSaved(
        transaction: transaction,
        mergedIntoExisting: mergedIntoExisting,
      );
    case PipelineDuplicateSuspected(:final match):
      final entity = await pipeline.keepBoth(match);
      ref.read(dataVersionProvider.notifier).state++;
      return AutoSaved(transaction: entity, duplicateKept: true);
    case PipelineNeedsReview():
      return AutoSaveNeedsAmount(candidate);
  }
}
