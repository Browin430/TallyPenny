import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bootstrap.dart';
import 'data/database/app_database.dart';
import 'services/local_auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final auth = LocalAuthService(
    prefs,
    legacyDataExists: await AppDatabase.legacyHasData(),
  );
  final account = await auth.bootstrapLegacyAccount();
  final hasAccounts = (await auth.accounts()).isNotEmpty;
  runApp(TallyPennyBootstrap(
    preferences: prefs,
    auth: auth,
    initialAccount: account,
    hasAccounts: hasAccounts,
  ));
}
