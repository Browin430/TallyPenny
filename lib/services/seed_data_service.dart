import 'dart:math';

import '../core/utils/id_gen.dart';
import '../domain/models/category.dart';
import '../domain/models/enums.dart';
import '../domain/models/transaction.dart';
import '../domain/models/transaction_candidate.dart';
import '../domain/repositories/category_repository.dart';
import '../domain/repositories/settings_repository.dart';
import '../domain/repositories/transaction_repository.dart';

/// 默认分类与中文演示数据。
/// 演示数据使用固定随机种子，每次生成完全一致（可复现的测试集）。
class SeedDataService {
  SeedDataService({
    required TransactionRepository transactionRepository,
    required CategoryRepository categoryRepository,
    required SettingsRepository settingsRepository,
  })  : _transactions = transactionRepository,
        _categories = categoryRepository,
        _settings = settingsRepository;

  static const _seededKey = 'seeded_v1';

  final TransactionRepository _transactions;
  final CategoryRepository _categories;
  final SettingsRepository _settings;

  /// 默认分类（产品需求定义的 18 支出 + 7 收入）。
  static List<Category> defaultCategories() => const [
        // ---- 支出 ----
        Category(
            id: 'food',
            name: '餐饮',
            iconCode: 'food',
            colorValue: 0xFFFF9500,
            type: TransactionType.expense,
            sortOrder: 1,
            isSystem: true),
        Category(
            id: 'transport',
            name: '交通',
            iconCode: 'transport',
            colorValue: 0xFF3E7BFA,
            type: TransactionType.expense,
            sortOrder: 2,
            isSystem: true),
        Category(
            id: 'shopping',
            name: '购物',
            iconCode: 'shopping',
            colorValue: 0xFFA855F7,
            type: TransactionType.expense,
            sortOrder: 3,
            isSystem: true),
        Category(
            id: 'housing',
            name: '住房',
            iconCode: 'housing',
            colorValue: 0xFFF76E6C,
            type: TransactionType.expense,
            sortOrder: 4,
            isSystem: true),
        Category(
            id: 'entertainment',
            name: '娱乐',
            iconCode: 'entertainment',
            colorValue: 0xFFEC4899,
            type: TransactionType.expense,
            sortOrder: 5,
            isSystem: true),
        Category(
            id: 'medical',
            name: '医疗',
            iconCode: 'medical',
            colorValue: 0xFFEF4444,
            type: TransactionType.expense,
            sortOrder: 6,
            isSystem: true),
        Category(
            id: 'education',
            name: '教育',
            iconCode: 'education',
            colorValue: 0xFF14B8A6,
            type: TransactionType.expense,
            sortOrder: 7,
            isSystem: true),
        Category(
            id: 'travel',
            name: '旅行',
            iconCode: 'travel',
            colorValue: 0xFF06B6D4,
            type: TransactionType.expense,
            sortOrder: 8,
            isSystem: true),
        Category(
            id: 'pet',
            name: '宠物',
            iconCode: 'pet',
            colorValue: 0xFFF59E0B,
            type: TransactionType.expense,
            sortOrder: 9,
            isSystem: true),
        Category(
            id: 'telecom',
            name: '通讯',
            iconCode: 'telecom',
            colorValue: 0xFF64748B,
            type: TransactionType.expense,
            sortOrder: 10,
            isSystem: true),
        Category(
            id: 'utilities',
            name: '水电燃气',
            iconCode: 'utilities',
            colorValue: 0xFFFBBF24,
            type: TransactionType.expense,
            sortOrder: 11,
            isSystem: true),
        Category(
            id: 'subscription',
            name: '订阅服务',
            iconCode: 'subscription',
            colorValue: 0xFF8B5CF6,
            type: TransactionType.expense,
            sortOrder: 12,
            isSystem: true),
        Category(
            id: 'insurance',
            name: '保险',
            iconCode: 'insurance',
            colorValue: 0xFF10B981,
            type: TransactionType.expense,
            sortOrder: 13,
            isSystem: true),
        Category(
            id: 'car',
            name: '汽车',
            iconCode: 'car',
            colorValue: 0xFF7A8AA0,
            type: TransactionType.expense,
            sortOrder: 14,
            isSystem: true),
        Category(
            id: 'gift',
            name: '礼物',
            iconCode: 'gift',
            colorValue: 0xFFF472B6,
            type: TransactionType.expense,
            sortOrder: 15,
            isSystem: true),
        Category(
            id: 'social',
            name: '人情',
            iconCode: 'social',
            colorValue: 0xFFFB7185,
            type: TransactionType.expense,
            sortOrder: 16,
            isSystem: true),
        Category(
            id: 'investment',
            name: '投资',
            iconCode: 'investment',
            colorValue: 0xFF22C55E,
            type: TransactionType.expense,
            sortOrder: 17,
            isSystem: true),
        Category(
            id: 'other',
            name: '其他',
            iconCode: 'other',
            colorValue: 0xFF98A2B3,
            type: TransactionType.expense,
            sortOrder: 18,
            isSystem: true),
        // ---- 收入 ----
        Category(
            id: 'salary',
            name: '工资',
            iconCode: 'salary',
            colorValue: 0xFF30A46C,
            type: TransactionType.income,
            sortOrder: 1,
            isSystem: true),
        Category(
            id: 'bonus',
            name: '奖金',
            iconCode: 'bonus',
            colorValue: 0xFF4ADE80,
            type: TransactionType.income,
            sortOrder: 2,
            isSystem: true),
        Category(
            id: 'parttime',
            name: '兼职',
            iconCode: 'parttime',
            colorValue: 0xFF34D399,
            type: TransactionType.income,
            sortOrder: 3,
            isSystem: true),
        Category(
            id: 'invest_return',
            name: '投资收益',
            iconCode: 'invest_return',
            colorValue: 0xFF10B981,
            type: TransactionType.income,
            sortOrder: 4,
            isSystem: true),
        Category(
            id: 'refund',
            name: '退款',
            iconCode: 'refund',
            colorValue: 0xFF2DD4BF,
            type: TransactionType.income,
            sortOrder: 5,
            isSystem: true),
        Category(
            id: 'redpacket',
            name: '红包',
            iconCode: 'redpacket',
            colorValue: 0xFFF0655A,
            type: TransactionType.income,
            sortOrder: 6,
            isSystem: true),
        Category(
            id: 'other_income',
            name: '其他收入',
            iconCode: 'other_income',
            colorValue: 0xFF86EFAC,
            type: TransactionType.income,
            sortOrder: 7,
            isSystem: true),
      ];

  Future<void> seedIfNeeded({bool includeDemo = true}) async {
    if (await _settings.getBool(_seededKey)) return;
    await _categories.upsertAll(defaultCategories());
    if (includeDemo) await generateDemoTransactions();
    await _settings.setBool(_seededKey, true);
  }

  /// 重新生成演示数据（"我的"页开发工具）。
  Future<void> regenerateDemo() async {
    await _categories.upsertAll(defaultCategories());
    await _transactions.clearAll();
    await generateDemoTransactions();
  }

  Future<void> generateDemoTransactions() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final rnd = Random(20260828);

    for (var back = 5; back >= 0; back--) {
      final monthRef = DateTime(now.year, now.month - back, 1);
      final daysInMonth = DateTime(monthRef.year, monthRef.month + 1, 0).day;
      final lastDay = back == 0 ? today.day : daysInMonth;

      if (back == 0) {
        await _seedCurrentMonth(today);
        continue;
      }

      for (var day = 1; day <= lastDay; day++) {
        final date = DateTime(monthRef.year, monthRef.month, day);
        final isWeekend = date.weekday == DateTime.saturday ||
            date.weekday == DateTime.sunday;

        // ---- 固定周期项 ----
        if (day == 1) {
          await _add(
            date,
            9,
            0,
            'housing',
            '房租',
            -300000,
            recurring: true,
          );
        }
        // ---- 固定收入与订阅 ----
        const salaryDay = 15;
        if (day == salaryDay) {
          await _add(date, 9, 0, 'salary', '工资', 1500000,
              income: true, recurring: true);
        }
        if (day == 20) {
          await _add(date, 10, 0, 'subscription', 'Netflix', -6800,
              recurring: true);
        }

        // ---- 历史日期（固定种子伪随机）----
        if (!isWeekend) {
          await _add(date, 8, 58, 'transport', '地铁', -300,
              sub: 'subway', recurring: true);
          if (rnd.nextDouble() < 0.4) {
            await _add(date, 9, 32, 'food', '全家便利店', -1250, sub: 'drink');
          }
          final lunches = const ['麦当劳', '兰州拉面', '沙县小吃', '公司食堂'];
          final prices = const [-3200, -2200, -1600, -1800];
          final i = rnd.nextInt(lunches.length);
          await _add(date, 12, 18, 'food', lunches[i], prices[i], sub: 'meal');
          if (rnd.nextDouble() < 0.25) {
            await _add(date, 15, 22, 'food', '瑞幸咖啡', -1600, sub: 'coffee');
          }
          if (rnd.nextDouble() < 0.3) {
            await _add(date, 18, 36, 'transport', '滴滴出行', -2800, sub: 'taxi');
          }
        } else {
          if (rnd.nextDouble() < 0.45) {
            await _add(date, 10, 23, 'food', '星巴克', -3600, sub: 'coffee');
          }
          if (rnd.nextDouble() < 0.3) {
            await _addTaobao(date, 21, 14, -(9900 + rnd.nextInt(25) * 1000));
          }
          if (rnd.nextDouble() < 0.2) {
            await _add(date, 19, 30, 'entertainment', '万达影城', -8000);
          }
          if (rnd.nextDouble() < 0.25) {
            await _add(date, 17, 40, 'food', '盒马鲜生', -15800, sub: 'meal');
          }
        }
      }
    }
  }

  /// 产品稿的标准当月数据：收入 ¥15,000、支出 ¥6,380、结余 ¥8,620。
  Future<void> _seedCurrentMonth(DateTime today) async {
    DateTime earlier(int days) =>
        DateTime(today.year, today.month, max(1, today.day - days));

    await _add(today, 9, 0, 'salary', '工资', 1500000,
        income: true, recurring: true);
    await _add(today, 8, 58, 'transport', '地铁', -300,
        sub: 'subway', recurring: true);
    await _add(today, 9, 32, 'food', '全家便利店', -1250, sub: 'drink');
    await _add(today, 10, 26, 'food', '瑞幸咖啡', -1600, sub: 'coffee');
    await _add(today, 12, 18, 'food', '麦当劳', -3200, sub: 'meal');
    await _add(today, 18, 36, 'transport', '滴滴出行', -2800, sub: 'taxi');
    await _addTaobao(today, 21, 14, 29900);

    // 六个聚合账单稳定形成分析页的 28/22/20/10/8/12 消费结构。
    await _add(earlier(24), 9, 0, 'housing', '房租与居住', -127600, recurring: true);
    await _add(earlier(20), 12, 30, 'food', '餐饮消费', -172550);
    await _addTaobao(earlier(16), 20, 10, 110400);
    await _add(earlier(12), 8, 30, 'transport', '通勤出行', -60700);
    await _add(earlier(8), 19, 30, 'entertainment', '休闲娱乐', -51040);
    await _add(earlier(4), 17, 20, 'other', '其他生活支出', -76660);
  }

  Future<void> _addTaobao(DateTime date, int h, int m, int cents) async {
    await _add(date, h, m, 'shopping', '淘宝', cents,
        sub: 'online', source: SourceType.screenshot);
  }

  Future<void> _add(
    DateTime date,
    int hour,
    int minute,
    String categoryId,
    String? merchant,
    int signedCents, {
    bool income = false,
    bool recurring = false,
    String? sub,
    SourceType source = SourceType.manual,
  }) async {
    final time = DateTime(date.year, date.month, date.day, hour, minute);
    final tx = TransactionEntity(
      id: IdGen.newId(),
      userId: 'local',
      type: income ? TransactionType.income : TransactionType.expense,
      amountCents: signedCents.abs(),
      currency: 'CNY',
      categoryId: categoryId,
      subcategory: sub,
      merchant: merchant,
      transactionTime: time,
      createdAt: time,
      updatedAt: time,
      sourceType: source,
      confidence: 1.0,
      status: TxStatus.confirmed,
      isRecurring: recurring,
      paymentMethod:
          source == SourceType.screenshot ? PaymentMethod.alipay : null,
    );
    await _transactions.insert(tx);
    if (source == SourceType.screenshot) {
      await _transactions.attachSource(
        SourceRecordDraft(
          sourceType: SourceType.screenshot,
          rawText:
              '支付宝\n交易成功\n$merchant\n-${(signedCents.abs() / 100).toStringAsFixed(2)}\n演示账单截图',
          imageReference: null,
        ),
        transactionId: tx.id,
      );
    }
  }
}
