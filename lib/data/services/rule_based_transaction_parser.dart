import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/models/enums.dart';
import '../../domain/models/transaction_candidate.dart';
import '../../domain/services/ai_services.dart';

/// 规则解析器 —— Phase 1 的确定性 Mock AI（离线、无网络依赖）。
///
/// TODO(phase-3): 语音链路换为 SpeechRecognitionService(真实 ASR) + LLM 解析。
/// TODO(phase-5): 本类保留为"端侧预解析器"，LLM 结果与其融合以提高准确率。
class RuleBasedTransactionParser implements AITransactionParser {
  @override
  Future<TransactionCandidate> parseFromText(
    String text, {
    DateTime? referenceTime,
    SourceType sourceType = SourceType.voice,
  }) async {
    final now = referenceTime ?? DateTime.now();
    final warnings = <String>[];
    var confidence = 0.92;

    // ---- 金额 ----
    final amounts = extractAmounts(text);
    int? amountCents;
    if (amounts.isEmpty) {
      warnings.add('未识别到金额');
      confidence -= 0.4;
    } else {
      if (amounts.length > 1) {
        warnings.add('识别到多个金额，已取第一个');
        confidence -= 0.15;
      }
      amountCents = (amounts.first * 100).round();
    }

    // ---- 收支方向 ----
    final isIncome = _incomeKeywords.any(text.contains);

    // ---- 时间 ----
    final time = _extractTime(text, now);
    if (!time.$2) {
      warnings.add('时间不明确，按当前时间记录');
      confidence -= 0.08;
    }

    // ---- 分类 / 商户 / 描述 ----
    final category = classify(text, isIncome: isIncome);
    if (category == null) {
      warnings.add('类别不确定，归入"其他"');
      confidence -= 0.12;
    }
    final merchant = extractMerchant(text);
    final item = extractItem(text);
    final description = item ?? (merchant != null ? '在$merchant消费' : null);

    return TransactionCandidate(
      sourceType: sourceType,
      confidence: confidence.clamp(0.3, 1.0),
      type: isIncome ? TransactionType.income : TransactionType.expense,
      amountCents: amountCents,
      categoryId: category?.$1,
      subcategory: category?.$2,
      merchant: merchant,
      description: description ?? _cleanText(text),
      transactionTime: time.$1,
      timeConfident: time.$2,
      parseWarnings: warnings,
      sourceRecords: [
        SourceRecordDraft(
          sourceType: sourceType,
          rawText: text,
          aiParseResultJson: jsonEncode({
            'engine': 'rule_based_v1',
            'amount': amountCents,
            'income': isIncome,
            'category': category?.$1,
            'merchant': merchant,
            'warnings': warnings,
          }),
        ),
      ],
    );
  }

  @override
  Future<TransactionCandidate> parseFromOcr(OcrResult ocr) async {
    final warnings = <String>[];
    if (ocr.amountCents == null) warnings.add('未识别到金额');
    final now = DateTime.now();
    final textProbe =
        '${ocr.merchant ?? ''} ${ocr.rawText.length > 60 ? ocr.rawText.substring(0, 60) : ocr.rawText}';
    final category = classify(textProbe, isIncome: ocr.isIncome == true);

    return TransactionCandidate(
      sourceType: SourceType.screenshot,
      confidence: ocr.confidence.clamp(0.4, 0.95),
      type: ocr.isIncome == true
          ? TransactionType.income
          : TransactionType.expense,
      amountCents: ocr.amountCents,
      categoryId: category?.$1,
      subcategory: category?.$2,
      merchant: ocr.merchant,
      transactionTime: ocr.paidAt ?? now,
      timeConfident: ocr.paidAt != null,
      paymentMethod: _platformToPayment(ocr.platform),
      parseWarnings: warnings,
      sourceRecords: [
        SourceRecordDraft(
          sourceType: SourceType.screenshot,
          rawText: ocr.rawText,
          ocrResultJson: jsonEncode({
            'platform': ocr.platform,
            'merchant': ocr.merchant,
            'amountCents': ocr.amountCents,
            'orderNo': ocr.orderNo,
            'confidence': ocr.confidence,
          }),
        ),
      ],
    );
  }

  PaymentMethod? _platformToPayment(String? platform) => switch (platform) {
        'alipay' => PaymentMethod.alipay,
        'wechat' => PaymentMethod.wechat,
        'bank' => PaymentMethod.bankCard,
        _ => null,
      };

  // =====================================================================
  // 金额提取
  // =====================================================================

  /// 返回识别到的金额列表（元），优先带单位的形式。
  @visibleForTesting
  static List<double> extractAmounts(String text) {
    final results = <double>[];

    // 1) 数字 + 块/元，支持 "28块5" "3.5元"。
    final unitRe = RegExp(
        r'([0-9]+(?:\.[0-9]+)?|[零一二两三四五六七八九十百千]+)(?:块|元)钱?\s*(?:([0-9])|([一二三四五六七八九]))?');
    for (final m in unitRe.allMatches(text)) {
      final whole = _parseNumberToken(m.group(1)!);
      final frac = m.group(2) ?? m.group(3);
      if (whole != null) {
        results.add(whole + (frac != null ? _digitValue(frac) * 0.1 : 0));
      }
    }
    if (results.isNotEmpty) return results;

    // 2) 动词 + 纯数字（"花了15000" "到账 3200.5" "收到工资15000"）。
    final verbRe =
        RegExp(r'(?:花了|消费了?|支付了?|付了|到账|收入|发了|收到)\D{0,4}?([0-9]+(?:\.[0-9]+)?)');
    for (final m in verbRe.allMatches(text)) {
      final v = double.tryParse(m.group(1)!);
      if (v != null) results.add(v);
    }
    if (results.isNotEmpty) return results;

    // 3) 带小数点的数字（"-3.00" "15,000.00"）。
    final decimalRe =
        RegExp(r'[0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]+)?|[0-9]+\.[0-9]{1,2}');
    for (final m in decimalRe.allMatches(text)) {
      final v = double.tryParse(m.group(0)!.replaceAll(',', ''));
      if (v != null) results.add(v);
    }
    return results;
  }

  static int _digitValue(String digit) {
    final ascii = int.tryParse(digit);
    if (ascii != null) return ascii;
    return const {
          '一': 1,
          '二': 2,
          '两': 2,
          '三': 3,
          '四': 4,
          '五': 5,
          '六': 6,
          '七': 7,
          '八': 8,
          '九': 9
        }[digit] ??
        0;
  }

  /// 解析 "1500" / "三十五" / "三百五" / "两千" 等数字 token。
  static double? _parseNumberToken(String token) {
    final asDouble = double.tryParse(token);
    if (asDouble != null) return asDouble;
    return _parseChineseNumber(token);
  }

  static double? _parseChineseNumber(String s) {
    if (s.isEmpty) return null;
    var total = 0;
    var section = 0; // 当前"万"以下段
    var current = 0;
    var hasDigit = false;
    for (final ch in s.runes) {
      final c = String.fromCharCode(ch);
      final digit = _digitValue(c);
      if (c == '零') continue;
      if (digit > 0) {
        current = digit;
        hasDigit = true;
      } else if (c == '十') {
        section += (current == 0 ? 1 : current) * 10;
        current = 0;
      } else if (c == '百') {
        section += (current == 0 ? 1 : current) * 100;
        current = 0;
      } else if (c == '千') {
        section += (current == 0 ? 1 : current) * 1000;
        current = 0;
      } else {
        return null;
      }
    }
    total = section + current;
    if (!hasDigit || total <= 0) return null;
    return total.toDouble();
  }

  // =====================================================================
  // 时间提取
  // =====================================================================

  static (DateTime, bool) _extractTime(String text, DateTime now) {
    var day = DateTime(now.year, now.month, now.day);
    var confident = false;

    if (text.contains('昨天') || text.contains('昨晚')) {
      day = day.subtract(const Duration(days: 1));
      confident = true;
    } else if (text.contains('今天') || text.contains('今晚')) {
      confident = true;
    } else if (text.contains('刚刚') ||
        text.contains('刚才') ||
        text.contains('刚')) {
      return (now, true);
    } else if (text.contains('前天')) {
      day = day.subtract(const Duration(days: 2));
      confident = true;
    }

    // 时段 + 钟点："早上九点" "下午3点半" "晚上 21 点"。
    final timeRe = RegExp(
      r'(凌晨|早上|上午|中午|下午|晚上)?\s*([0-9]+|[一二三四五六七八九十]+)\s*[点时:：]\s*(?:(半)|([0-9]+|[一二三四五六七八九十]+)分?)?',
    );
    final m = timeRe.firstMatch(text);
    if (m != null) {
      final period = m.group(1);
      var hour = _parseNumberToken(m.group(2)!)?.toInt() ?? 0;
      var minute = 0;
      if (m.group(3) == '半') {
        minute = 30;
      } else if (m.group(4) != null) {
        minute = _parseNumberToken(m.group(4)!)?.toInt() ?? 0;
      }
      if (period == '下午' || period == '晚上') {
        if (hour < 12) hour += 12;
      } else if (period == '中午') {
        hour = hour < 12 ? 12 : hour;
      } else if (period == '凌晨') {
        // 保持 0-5。
      }
      if (hour >= 0 && hour <= 23 && minute <= 59) {
        confident = true;
        return (
          DateTime(day.year, day.month, day.day, hour, minute),
          confident
        );
      }
    }

    // 只有时段没有钟点。
    if (text.contains('凌晨')) return (day.add(const Duration(hours: 5)), true);
    if (text.contains('早上') || text.contains('上午')) {
      return (day.add(const Duration(hours: 8)), true);
    }
    if (text.contains('中午')) return (day.add(const Duration(hours: 12)), true);
    if (text.contains('下午')) return (day.add(const Duration(hours: 15)), true);
    if (text.contains('晚上') || text.contains('今晚')) {
      return (day.add(const Duration(hours: 19)), true);
    }

    return (day.add(Duration(hours: now.hour, minutes: now.minute)), confident);
  }

  // =====================================================================
  // 分类 / 商户 / 提取
  // =====================================================================

  static const _incomeKeywords = [
    '到账',
    '工资',
    '收入',
    '奖金',
    '红包',
    '退款',
    '报销',
    '兼职收入',
    '收益',
    '发了'
  ];

  /// (categoryId, subcategory)。null 表示不确定。
  static (String, String?)? classify(String text, {required bool isIncome}) {
    if (!isIncome && text.contains('小遛')) {
      return ('transport', 'shared_bike');
    }
    if (!isIncome && _hardwareKeywords.any(text.contains)) {
      return ('shopping', 'hardware');
    }
    if (!isIncome && _foodMerchantKeywords.any(text.contains)) {
      return ('food', 'meal');
    }
    for (final rule in _categoryRules) {
      for (final kw in rule.keywords) {
        if (text.contains(kw)) {
          if (isIncome && rule.category == 'food') continue; // "收到咖啡红包"之类的歧义兜底
          return (rule.category, rule.sub);
        }
      }
    }
    return null;
  }

  /// 常见餐饮商户名称。覆盖“品牌名 + 品类”而不仅依赖平台交易分类。
  static const _foodMerchantKeywords = [
    '餐饮',
    '餐厅',
    '餐馆',
    '饭店',
    '酒楼',
    '食府',
    '菜馆',
    '私房菜',
    '小吃',
    '快餐',
    '便当',
    '食堂',
    '早餐',
    '夜宵',
    '重庆小面',
    '小面',
    '面馆',
    '拉面',
    '牛肉面',
    '刀削面',
    '米线',
    '米粉',
    '螺蛳粉',
    '酸辣粉',
    '麻辣烫',
    '冒菜',
    '火锅',
    '串串',
    '烧烤',
    '烤肉',
    '烤鱼',
    '酸菜鱼',
    '馄饨',
    '云吞',
    '饺子',
    '包子',
    '粥铺',
    '盖饭',
    '炒饭',
    '汉堡',
    '炸鸡',
    '披萨',
    '寿司',
    '料理',
    '咖啡',
    '奶茶',
    '茶饮',
    '果汁',
    '鲜榨',
    '饮品',
    '烘焙',
    '蛋糕',
    '甜品',
    '面包店',
  ];

  static const _hardwareKeywords = [
    '螺丝钉',
    '螺丝刀',
    '螺丝',
    '螺母',
    '垫片',
    '紧固件',
    '五金',
    '扳手',
    '钳子',
    '钻头',
  ];

  static const _categoryRules = [
    (
      keywords: ['小遛', '共享电动车', '共享单车'],
      category: 'transport',
      sub: 'shared_bike'
    ),
    (keywords: ['地铁', '公交', '地铁卡'], category: 'transport', sub: 'subway'),
    (keywords: ['打车', '滴滴', '出租', '网约车'], category: 'transport', sub: 'taxi'),
    (keywords: ['加油', '停车', '洗车', '保养'], category: 'car', sub: null),
    (
      keywords: ['咖啡', '星巴克', '瑞幸', '拿铁', '美式'],
      category: 'food',
      sub: 'coffee'
    ),
    (
      keywords: ['奶茶', '喜茶', '蜜雪', '果汁', '鲜榨', '茶'],
      category: 'food',
      sub: 'drink'
    ),
    (
      keywords: ['麦当劳', '肯德基', '外卖', '饿了么', '美团', '餐厅', '餐馆'],
      category: 'food',
      sub: 'meal'
    ),
    (
      keywords: ['可乐', '雪碧', '饮料', '矿泉水', '烟酒', '便利店'],
      category: 'food',
      sub: 'drink'
    ),
    (
      keywords: ['饭', '餐', '吃', '食堂', '面馆', '米线', '麻辣烫', '火锅', '烧烤'],
      category: 'food',
      sub: 'meal'
    ),
    (keywords: ['水费', '电费', '燃气', '水电气'], category: 'utilities', sub: null),
    (keywords: ['话费', '流量', '宽带'], category: 'telecom', sub: null),
    (keywords: ['房租', '房贷', '物业'], category: 'housing', sub: 'rent'),
    (
      keywords: ['淘宝', '天猫', '京东', '拼多多', '网购'],
      category: 'shopping',
      sub: 'online'
    ),
    (keywords: ['衣服', '裤子', '鞋', '裙子'], category: 'shopping', sub: 'clothing'),
    (keywords: ['电影', '游戏', '演出', 'KTV'], category: 'entertainment', sub: null),
    (
      keywords: ['爱奇艺', '腾讯视频', '网飞', 'Netflix', '会员', '订阅'],
      category: 'subscription',
      sub: null
    ),
    (keywords: ['医院', '挂号', '药', '看病'], category: 'medical', sub: null),
    (keywords: ['学费', '课程', '培训', '书'], category: 'education', sub: null),
    (keywords: ['机票', '酒店', '火车票', '旅行', '旅游'], category: 'travel', sub: null),
    (keywords: ['猫粮', '狗粮', '宠物', '疫苗'], category: 'pet', sub: null),
    (keywords: ['健身', '运动', '游泳'], category: 'entertainment', sub: 'sport'),
    (keywords: ['工资', '薪资'], category: 'salary', sub: null),
    (keywords: ['奖金', '年终奖'], category: 'bonus', sub: null),
    (keywords: ['红包'], category: 'redpacket', sub: null),
    (keywords: ['退款', '退货'], category: 'refund', sub: null),
    (keywords: ['兼职'], category: 'parttime', sub: null),
    (keywords: ['理财', '基金', '股票', '收益'], category: 'invest_return', sub: null),
    (keywords: ['礼物', '礼品'], category: 'gift', sub: null),
    (keywords: ['保险'], category: 'insurance', sub: null),
  ];

  @visibleForTesting
  static String? extractMerchant(String text) {
    final m = RegExp(r'在\s*(.{1,12}?)\s*(?:买了|买|点了|点|消费|吃了|吃|花了|加满)')
        .firstMatch(text);
    if (m != null) return m.group(1)!.trim();
    return null;
  }

  @visibleForTesting
  static String? extractItem(String text) {
    final m = RegExp(r'(?:买了?|点了?|吃了?)\s*(.{1,10}?)\s*(?:花了|花|用了|用|，|,|$)')
        .firstMatch(text);
    if (m != null) {
      final item = m.group(1)!.trim();
      if (item.isNotEmpty) return item;
    }
    return null;
  }

  static String _cleanText(String text) {
    var t = text.trim();
    for (final w in ['今天', '昨天', '刚刚', '早上', '中午', '下午', '晚上']) {
      t = t.replaceAll(w, '');
    }
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
