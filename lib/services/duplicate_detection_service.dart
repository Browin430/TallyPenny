import '../core/constants/app_constants.dart';
import '../domain/models/duplicate_match.dart';
import '../domain/models/transaction.dart';
import '../domain/models/transaction_candidate.dart';
import '../domain/repositories/transaction_repository.dart';

/// 多来源账单智能去重引擎。
///
/// 流程：候选粗筛（方向/金额/时间硬性条件）→ 多维相似度打分 → 生成
/// duplicate_score（0~1）与 duplicate_reason（人类可读解释）。
///
/// 权重与阈值全部来自 [DuplicateWeights] / [DuplicateThresholds]，可配置、不写死。
class DuplicateDetectionService {
  DuplicateDetectionService(this._repo);

  final TransactionRepository _repo;

  /// 为新候选寻找最佳重复匹配。低于 askUser 阈值返回 null（正常入库）。
  Future<DuplicateMatch?> findMatch(
    TransactionEntity draft,
    TransactionCandidate candidate,
  ) async {
    final candidates = await _repo.duplicateWindow(
      center: draft.transactionTime,
      type: draft.type,
      amountCents: draft.amountCents,
    );
    DuplicateMatch? best;
    for (final existing in candidates) {
      final match = scorePair(existing, draft, candidate);
      if (best == null || match.score > best.score) best = match;
    }
    if (best == null || best.score < DuplicateThresholds.askUser) return null;
    return best;
  }

  /// 计算两笔账单的 duplicate_score 与判定理由。
  DuplicateMatch scorePair(
    TransactionEntity existing,
    TransactionEntity draft,
    TransactionCandidate candidate,
  ) {
    double score = 0;
    final reasons = <String>[];

    // ---------- 1. 金额（满分 0.40）----------
    final maxAmount = existing.amountCents > draft.amountCents
        ? existing.amountCents
        : draft.amountCents;
    final diff = (existing.amountCents - draft.amountCents).abs() / maxAmount;
    if (diff == 0) {
      score += DuplicateWeights.amountExact;
      reasons.add('金额完全相同');
    } else if (diff < 0.02) {
      score += DuplicateWeights.amountWithin2Pct;
      reasons.add('金额基本一致');
    } else if (diff < 0.05) {
      score += DuplicateWeights.amountWithin5Pct;
      reasons.add('金额相差不到 5%');
    } else if (diff < 0.10) {
      score += DuplicateWeights.amountWithin10Pct;
      reasons.add('金额相差不到 10%');
    } else {
      score += DuplicateWeights.amountWithin10Pct * 0.4;
    }

    // ---------- 2. 时间（满分 0.25）----------
    final diffMin = existing.transactionTime
        .difference(draft.transactionTime)
        .inMinutes
        .abs();
    if (diffMin < 5) {
      score += DuplicateWeights.timeWithin5Min;
      reasons.add('交易时间相差 $diffMin 分钟');
    } else if (diffMin < 30) {
      score += DuplicateWeights.timeWithin30Min;
      reasons.add('交易时间相差 $diffMin 分钟');
    } else if (diffMin < 120) {
      score += DuplicateWeights.timeWithin2Hours;
      reasons.add('交易时间相差 ${diffMin ~/ 60} 小时左右');
    } else {
      // 2~24 小时线性衰减。
      final remain = diffMin - 120;
      score += (DuplicateWeights.timeWithin2Hours * (1 - remain / (22 * 60)))
          .clamp(0.0, 1.0);
    }

    // ---------- 3. 消费内容语义（满分 0.20）----------
    final textA = _contentText(existing);
    final textB = _contentText(draft, candidate: candidate);
    if (textA.isNotEmpty && textB.isNotEmpty) {
      final sim = _contentSimilarity(textA, textB);
      if (sim > 0.3) {
        score += DuplicateWeights.descriptionSemantic * sim;
        reasons.add('消费内容可能相关：“${_shorten(textA)}”与“${_shorten(textB)}”');
      }
    }

    // ---------- 4. 商户（满分 0.10）----------
    final merchantA = existing.merchant?.trim();
    final merchantB = candidate.merchant?.trim();
    if (merchantA != null &&
        merchantA.isNotEmpty &&
        merchantB != null &&
        merchantB.isNotEmpty) {
      if (merchantA == merchantB) {
        score += DuplicateWeights.merchantExact;
        reasons.add('商户相同');
      } else if (_sceneAffinity(merchantA, merchantB)) {
        score += DuplicateWeights.merchantRelated;
        reasons.add('商户消费场景可能相关');
      }
    }

    // ---------- 5. 分类（0.10）----------
    if (existing.categoryId != null &&
        existing.categoryId == candidate.categoryId) {
      score += DuplicateWeights.categorySame;
      reasons.add('消费分类相同');
    }

    return DuplicateMatch(
      existing: existing,
      incoming: candidate,
      score: score.clamp(0.0, 1.0),
      reasons: reasons,
    );
  }

  // ------------------------------------------------------------------
  // 文本相似度：字符二元组 Dice 系数 + 消费场景词组亲缘。
  // 离线、确定性，无 AI 依赖。
  // TODO(phase-5): AI 服务接入后可替换为 embedding 余弦相似度。
  // ------------------------------------------------------------------

  static const List<List<String>> _sceneGroups = [
    [
      '可乐',
      '饮料',
      '汽水',
      '奶茶',
      '矿泉水',
      '烟酒',
      '便利店',
      '小卖部',
      '超市',
      '全家',
      '罗森',
      '711',
      '7-11',
      '便利'
    ],
    ['咖啡', '瑞幸', '星巴克', '拿铁', '美式', '咖啡厅', '茶饮'],
    ['地铁', '公交', '交通', '出行', '滴滴', '打车', '出租', '网约车', '通勤'],
    ['饭', '餐', '外卖', '饿了么', '美团', '麦当劳', '肯德基', '食堂', '快餐', '小吃'],
    ['淘宝', '天猫', '京东', '拼多多', '购物', '电商', '订单', '网购'],
    ['房租', '水电', '燃气', '物业', '水电费', '缴费'],
    ['电影', '演出', '游戏', '会员', '视频', '音乐', '娱乐'],
  ];

  static String _contentText(
    TransactionEntity tx, {
    TransactionCandidate? candidate,
  }) {
    final merchant = tx.merchant ?? '';
    final desc = tx.description ?? '';
    return '$merchant $desc'.trim();
  }

  static String _shorten(String s) =>
      s.length > 10 ? '${s.substring(0, 10)}…' : s;

  /// 综合相似度：max（Dice 二元组，场景亲缘加成）。
  static double _contentSimilarity(String a, String b) {
    final dice = _bigramDice(a, b);
    final scene = _sceneAffinity(a, b) ? 0.55 : 0.0;
    final sim = dice > scene ? dice : scene + dice * 0.3;
    return sim.clamp(0.0, 1.0);
  }

  /// 消费场景亲缘：两段文本是否命中同一场景词组。
  static bool _sceneAffinity(String a, String b) {
    for (final group in _sceneGroups) {
      final hitA = group.any((w) => a.contains(w));
      final hitB = group.any((w) => b.contains(w));
      if (hitA && hitB) return true;
    }
    return false;
  }

  /// 字符二元组 Dice 系数（对中文短文本效果好，且与语序无关）。
  static double _bigramDice(String a, String b) {
    final cleanA = _tokenize(a);
    final cleanB = _tokenize(b);
    if (cleanA.isEmpty || cleanB.isEmpty) return 0;
    final gramsA = _bigrams(cleanA);
    final gramsB = _bigrams(cleanB);
    if (gramsA.isEmpty || gramsB.isEmpty) return 0;
    final pool = Map<String, int>.from(gramsA);
    var overlap = 0;
    gramsB.forEach((gram, count) {
      final have = pool[gram] ?? 0;
      if (have > 0) {
        overlap += have < count ? have : count;
        pool[gram] = have - count;
      }
    });
    return 2 *
        overlap /
        (gramsA.values.fold(0, (x, y) => x + y) +
            gramsB.values.fold(0, (x, y) => x + y));
  }

  /// 拆词：连续汉字整体 + 连续字母数字词。去掉空格与标点。
  static List<String> _tokenize(String input) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isNotEmpty) {
        tokens.add(buffer.toString());
        buffer.clear();
      }
    }

    for (final ch in input.runes) {
      final c = String.fromCharCode(ch);
      final isHan = ch >= 0x4E00 && ch <= 0x9FFF;
      final isAlnum = (ch >= 0x30 && ch <= 0x39) ||
          (ch >= 0x41 && ch <= 0x5A) ||
          (ch >= 0x61 && ch <= 0x7A);
      if (isHan || isAlnum) {
        buffer.write(c);
      } else {
        flush();
      }
    }
    flush();
    return tokens;
  }

  static Map<String, int> _bigrams(List<String> tokens) {
    final grams = <String, int>{};
    for (final token in tokens) {
      if (token.length == 1) {
        grams[token] = (grams[token] ?? 0) + 1;
      }
      for (var i = 0; i < token.length - 1; i++) {
        final g = token.substring(i, i + 2);
        grams[g] = (grams[g] ?? 0) + 1;
      }
    }
    return grams;
  }
}
