/// 键值设置仓库抽象（shared_preferences 实现）。
abstract class SettingsRepository {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);

  Future<int?> getInt(String key);
  Future<void> setInt(String key, int value);

  Future<bool> getBool(String key, {bool fallback = false});
  Future<void> setBool(String key, bool value);
}
