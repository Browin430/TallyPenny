import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database/db_schema.dart';
import '../domain/models/local_account.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
}

/// 设备本地账户。账单按账户使用独立 SQLite 文件，凭据仅保存加盐派生值。
class LocalAuthService {
  LocalAuthService(this._prefs, {required bool legacyDataExists})
      : _legacyDataExists = legacyDataExists;

  static const _accountsKey = 'local_auth_accounts_v1';
  static const _sessionKey = 'local_auth_session_v1';
  static const _initialUsername = String.fromEnvironment('FM_INITIAL_USERNAME');
  static const _initialPasswordSalt =
      String.fromEnvironment('FM_INITIAL_PASSWORD_SALT');
  static const _initialPasswordHash =
      String.fromEnvironment('FM_INITIAL_PASSWORD_HASH');

  final SharedPreferences _prefs;
  final bool _legacyDataExists;

  Future<List<LocalAccount>> accounts() async {
    final raw = _prefs.getString(_accountsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(LocalAccount.fromJson)
          .toList();
    } on Object {
      return const [];
    }
  }

  Future<LocalAccount?> currentAccount() async {
    final id = _prefs.getString(_sessionKey);
    if (id == null) return null;
    for (final account in await accounts()) {
      if (account.id == id) return account;
    }
    await _prefs.remove(_sessionKey);
    return null;
  }

  /// 旧版已有账单时，用构建期注入的一次性凭据建立首个账户。
  Future<LocalAccount?> bootstrapLegacyAccount() async {
    final existing = await accounts();
    if (existing.isNotEmpty ||
        !_legacyDataExists ||
        _initialUsername.trim().isEmpty ||
        _initialPasswordSalt.isEmpty ||
        _initialPasswordHash.isEmpty) {
      return currentAccount();
    }
    final id = _newId();
    final account = LocalAccount(
      id: id,
      username: _initialUsername.trim(),
      passwordSalt: _initialPasswordSalt,
      passwordHash: _initialPasswordHash,
      databaseName: DbSchema.name,
      settingsPrefix: '',
      createdAt: DateTime.now(),
    );
    await _saveAccounts([account]);
    await _prefs.setString(_sessionKey, account.id);
    return account;
  }

  Future<LocalAccount> register(String username, String password) async {
    final clean = _validate(username, password);
    final existing = await accounts();
    if (existing
        .any((item) => item.username.toLowerCase() == clean.toLowerCase())) {
      throw const AuthException('该用户名已经存在');
    }

    final isLegacy = existing.isEmpty && _legacyDataExists;
    final id = _newId();
    final salt = _randomToken(18);
    final hash = await _derivePassword(password, salt);
    final account = LocalAccount(
      id: id,
      username: clean,
      passwordSalt: salt,
      passwordHash: hash,
      databaseName: isLegacy ? DbSchema.name : 'flowmoney_$id.db',
      settingsPrefix: isLegacy ? '' : 'account_${id}_',
      createdAt: DateTime.now(),
    );
    await _saveAccounts([...existing, account]);
    await _prefs.setString(_sessionKey, account.id);
    return account;
  }

  Future<LocalAccount> login(String username, String password) async {
    final clean = username.trim();
    LocalAccount? match;
    for (final account in await accounts()) {
      if (account.username.toLowerCase() == clean.toLowerCase()) {
        match = account;
        break;
      }
    }
    if (match == null) throw const AuthException('用户名或密码不正确');
    final hash = await _derivePassword(password, match.passwordSalt);
    if (!_constantTimeEquals(hash, match.passwordHash)) {
      throw const AuthException('用户名或密码不正确');
    }
    await _prefs.setString(_sessionKey, match.id);
    return match;
  }

  Future<void> logout() => _prefs.remove(_sessionKey);

  Future<void> _saveAccounts(List<LocalAccount> accounts) => _prefs.setString(
        _accountsKey,
        jsonEncode(accounts.map((item) => item.toJson()).toList()),
      );

  String _validate(String username, String password) {
    final clean = username.trim();
    if (clean.length < 2 || clean.length > 24) {
      throw const AuthException('用户名请输入 2–24 个字符');
    }
    if (password.length < 6 || password.length > 64) {
      throw const AuthException('密码请输入 6–64 个字符');
    }
    return clean;
  }

  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_randomToken(5)}';

  static String _randomToken(int bytes) {
    final random = Random.secure();
    return base64UrlEncode(
            List<int>.generate(bytes, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }
}

Future<String> _derivePassword(String password, String salt) => Isolate.run(
      () => _pbkdf2(password, salt),
    );

String _pbkdf2(String password, String salt) {
  const iterations = 40000;
  final hmac = Hmac(sha256, utf8.encode(password));
  var block = hmac.convert([
    ...utf8.encode(salt),
    0,
    0,
    0,
    1,
  ]).bytes;
  final result = List<int>.from(block);
  for (var round = 1; round < iterations; round++) {
    block = hmac.convert(block).bytes;
    for (var i = 0; i < result.length; i++) {
      result[i] ^= block[i];
    }
  }
  return base64UrlEncode(result);
}

bool _constantTimeEquals(String left, String right) {
  final a = utf8.encode(left);
  final b = utf8.encode(right);
  var difference = a.length ^ b.length;
  final length = min(a.length, b.length);
  for (var i = 0; i < length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}
