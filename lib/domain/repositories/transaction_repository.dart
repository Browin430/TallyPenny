import '../../core/constants/app_constants.dart';
import '../models/duplicate_match.dart';
import '../models/enums.dart';
import '../models/transaction.dart';
import '../models/transaction_candidate.dart';

/// 账单仓库抽象。实现：sqflite（移动端）/ 内存（Web 预览与测试）。
abstract class TransactionRepository {
  Future<void> insert(TransactionEntity tx);

  Future<void> update(TransactionEntity tx);

  Future<void> softDelete(String id);

  Future<void> softDeleteMany(Iterable<String> ids);

  /// 回收站内容，按删除时间从新到旧。
  Future<List<TransactionEntity>> getDeleted();

  Future<void> restore(String id);

  /// 永久清除删除时间早于 [cutoff] 的账单及其来源记录。
  Future<int> purgeDeletedBefore(DateTime cutoff);

  Future<TransactionEntity?> getById(String id);

  /// [end) 左闭右开。search 匹配商户 / 描述 / 分类名（分类名由实现层决定是否参与）。
  Future<List<TransactionEntity>> getByRange(
    DateTime start,
    DateTime end, {
    TransactionType? type,
    Set<String>? categoryIds,
    String? search,
  });

  /// 全量（分析页跨月计算用；个人账单量级可接受）。
  Future<List<TransactionEntity>> getAll();

  /// 去重候选：时间 [center±windowHours] 内、同方向、金额差在容差内的账单。
  Future<List<TransactionEntity>> duplicateWindow({
    required DateTime center,
    required TransactionType type,
    required int amountCents,
    int windowHours = DuplicateWeights.candidateWindowHours,
  });

  /// 附加原始来源记录（语音转写 / OCR / AI 解析），原始数据永不丢失。
  Future<void> attachSource(
    SourceRecordDraft draft, {
    required String transactionId,
  });

  Future<List<SourceRecord>> sourcesOf(String transactionId);

  /// 记录一次去重判定事件（merged / kept_both），完整审计。
  Future<void> logDuplicateEvent(DuplicateEvent event);

  Future<void> clearAll();
}
