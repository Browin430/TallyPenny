import '../models/merchant_rule.dart';

abstract class MerchantRuleRepository {
  Future<List<MerchantRule>> getAll();
  Future<void> upsert(MerchantRule rule);
  Future<void> delete(String id);
  Future<void> clearAll();
}
