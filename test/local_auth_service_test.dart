import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowmoney/data/database/db_schema.dart';
import 'package:flowmoney/services/local_auth_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('注册后默认保持登录且凭据不以明文保存', () async {
    final preferences = await SharedPreferences.getInstance();
    final service = LocalAuthService(preferences, legacyDataExists: true);

    final account = await service.register('Browin', 'test-password');

    expect((await service.currentAccount())?.id, account.id);
    expect(account.databaseName, DbSchema.name);
    expect(account.settingsPrefix, isEmpty);
    final persisted = preferences
        .getKeys()
        .map((key) => preferences.get(key).toString())
        .join(' ');
    expect(persisted, isNot(contains('test-password')));
  });

  test('不同账户使用独立数据库和设置命名空间', () async {
    final preferences = await SharedPreferences.getInstance();
    final service = LocalAuthService(preferences, legacyDataExists: false);

    final first = await service.register('甲用户', 'password-a');
    await service.logout();
    final second = await service.register('乙用户', 'password-b');

    expect(first.databaseName, isNot(second.databaseName));
    expect(first.settingsPrefix, isNot(second.settingsPrefix));
    expect((await service.login('甲用户', 'password-a')).id, first.id);
    await expectLater(
      service.login('甲用户', 'wrong-password'),
      throwsA(isA<AuthException>()),
    );
  });
}
