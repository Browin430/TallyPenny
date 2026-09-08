import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../domain/repositories/settings_repository.dart';

/// 流水分析页的四位数字密码。
///
/// SharedPreferences 里只保存随机盐与迭代摘要，不保存明文密码。
class AnalysisPinService {
  AnalysisPinService(this._settings);

  final SettingsRepository _settings;

  static const _saltKey = 'analysis_pin_salt_v1';
  static const _hashKey = 'analysis_pin_hash_v1';
  static const _rounds = 12000;

  Future<bool> get isConfigured async {
    final salt = await _settings.getString(_saltKey);
    final hash = await _settings.getString(_hashKey);
    return salt?.isNotEmpty == true && hash?.isNotEmpty == true;
  }

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw const FormatException('密码必须是4位数字');
    }
    final random = Random.secure();
    final saltBytes = List<int>.generate(24, (_) => random.nextInt(256));
    final salt = base64UrlEncode(saltBytes);
    await _settings.setString(_saltKey, salt);
    await _settings.setString(_hashKey, _derive(pin, salt));
  }

  Future<bool> verify(String pin) async {
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) return false;
    final salt = await _settings.getString(_saltKey);
    final expected = await _settings.getString(_hashKey);
    if (salt == null || expected == null) return true;
    final actual = _derive(pin, salt);
    var difference = actual.length ^ expected.length;
    final limit = min(actual.length, expected.length);
    for (var i = 0; i < limit; i++) {
      difference |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return difference == 0;
  }

  Future<void> clear() async {
    await _settings.setString(_saltKey, '');
    await _settings.setString(_hashKey, '');
  }

  String _derive(String pin, String salt) {
    List<int> bytes = utf8.encode('$salt:$pin');
    for (var i = 0; i < _rounds; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64UrlEncode(bytes);
  }
}
