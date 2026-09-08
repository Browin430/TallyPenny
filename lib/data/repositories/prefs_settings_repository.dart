import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/repositories/settings_repository.dart';

/// shared_preferences 实现（移动端与 Web 通用）。
class PrefsSettingsRepository implements SettingsRepository {
  PrefsSettingsRepository(this._prefs, {this.prefix = ''});

  final SharedPreferences _prefs;
  final String prefix;

  String _key(String key) => '$prefix$key';

  @override
  Future<String?> getString(String key) async => _prefs.getString(_key(key));

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(_key(key), value);

  @override
  Future<int?> getInt(String key) async => _prefs.getInt(_key(key));

  @override
  Future<void> setInt(String key, int value) => _prefs.setInt(_key(key), value);

  @override
  Future<bool> getBool(String key, {bool fallback = false}) async =>
      _prefs.getBool(_key(key)) ?? fallback;

  @override
  Future<void> setBool(String key, bool value) =>
      _prefs.setBool(_key(key), value);
}
