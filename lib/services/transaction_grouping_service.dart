import '../domain/models/transaction.dart';
import '../core/utils/settlement_policy.dart';

enum TransactionGroupKind { merchant, category, company, timeline }

class TransactionDisplayGroup {
  const TransactionDisplayGroup({
    required this.kind,
    required this.key,
    required this.title,
    required this.transactions,
    this.categoryId,
  });

  final TransactionGroupKind kind;
  final String key;
  final String title;
  final String? categoryId;
  final List<TransactionEntity> transactions;

  int get expenseCents => transactions
      .where((transaction) => !transaction.isIncome)
      .fold(0, (sum, transaction) => sum + transaction.amountCents);

  int get incomeCents => transactions
      .where((transaction) => transaction.isIncome)
      .fold(0, (sum, transaction) => sum + transaction.amountCents);

  int get totalCents => expenseCents + incomeCents;
}

class TransactionGroupingResult {
  const TransactionGroupingResult({
    required this.merchants,
    required this.scatteredCategories,
    required this.company,
  });

  final List<TransactionDisplayGroup> merchants;
  final List<TransactionDisplayGroup> scatteredCategories;
  final TransactionDisplayGroup? company;
}

class TransactionGroupingService {
  const TransactionGroupingService._();

  static TransactionGroupingResult group(
    List<TransactionEntity> transactions, {
    int merchantFoldThreshold = 3,
  }) {
    final byMerchant = <String, List<TransactionEntity>>{};
    final merchantTitles = <String, String>{};
    final withoutMerchant = <TransactionEntity>[];
    final companyTransactions = <TransactionEntity>[];

    for (final transaction in transactions) {
      if (SettlementPolicy.isCompany(transaction)) {
        companyTransactions.add(transaction);
        continue;
      }
      final merchant = transaction.merchant?.trim() ?? '';
      if (merchant.isEmpty) {
        withoutMerchant.add(transaction);
        continue;
      }
      final key = _normalizeMerchant(merchant);
      byMerchant.putIfAbsent(key, () => []).add(transaction);
      merchantTitles.putIfAbsent(key, () => merchant);
    }

    final merchantGroups = <TransactionDisplayGroup>[];
    final scattered = <TransactionEntity>[...withoutMerchant];
    for (final entry in byMerchant.entries) {
      if (entry.value.length >= merchantFoldThreshold) {
        merchantGroups.add(TransactionDisplayGroup(
          kind: TransactionGroupKind.merchant,
          key: entry.key,
          title: merchantTitles[entry.key]!,
          transactions: _sortedTransactions(entry.value),
        ));
      } else {
        scattered.addAll(entry.value);
      }
    }

    final byCategory = <String, List<TransactionEntity>>{};
    for (final transaction in scattered) {
      final key = transaction.categoryId ?? '__uncategorized__';
      byCategory.putIfAbsent(key, () => []).add(transaction);
    }
    final categoryGroups = byCategory.entries
        .map((entry) => TransactionDisplayGroup(
              kind: TransactionGroupKind.category,
              key: entry.key,
              title: entry.key,
              categoryId: entry.key == '__uncategorized__' ? null : entry.key,
              transactions: _sortedTransactions(entry.value),
            ))
        .toList();

    void sortGroups(List<TransactionDisplayGroup> groups) {
      groups.sort((a, b) {
        final byAmount = b.totalCents.compareTo(a.totalCents);
        return byAmount != 0 ? byAmount : a.title.compareTo(b.title);
      });
    }

    sortGroups(merchantGroups);
    sortGroups(categoryGroups);
    return TransactionGroupingResult(
      merchants: merchantGroups,
      scatteredCategories: categoryGroups,
      company: companyTransactions.isEmpty
          ? null
          : TransactionDisplayGroup(
              kind: TransactionGroupKind.company,
              key: '__company__',
              title: '公司账单',
              transactions: _sortedTransactions(companyTransactions),
            ),
    );
  }

  /// 时间模式按日期从新到旧分段，段内按具体时间从新到旧排列。
  static List<TransactionDisplayGroup> timeline(
    List<TransactionEntity> transactions,
  ) {
    final byDate = <DateTime, List<TransactionEntity>>{};
    for (final transaction in transactions) {
      final time = transaction.transactionTime;
      final date = DateTime(time.year, time.month, time.day);
      byDate.putIfAbsent(date, () => []).add(transaction);
    }
    final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final date in dates)
        TransactionDisplayGroup(
          kind: TransactionGroupKind.timeline,
          key: '${date.year}-${date.month}-${date.day}',
          title: '${date.month}月${date.day}日',
          transactions: _sortedByTime(byDate[date]!),
        ),
    ];
  }

  static List<TransactionEntity> _sortedTransactions(
    List<TransactionEntity> source,
  ) {
    final result = [...source];
    result.sort((a, b) {
      final byAmount = b.amountCents.compareTo(a.amountCents);
      return byAmount != 0
          ? byAmount
          : b.transactionTime.compareTo(a.transactionTime);
    });
    return result;
  }

  static List<TransactionEntity> _sortedByTime(
    List<TransactionEntity> source,
  ) {
    final result = [...source];
    result.sort((a, b) => b.transactionTime.compareTo(a.transactionTime));
    return result;
  }

  static String _normalizeMerchant(String merchant) =>
      merchant.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}
