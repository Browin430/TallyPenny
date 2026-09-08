import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'presentation/navigation/app_shell.dart';
import 'state/app_providers.dart';

/// 应用根。产品名未定稿：这里使用中性描述，正式名确定后仅改此处与平台清单。
class MoneyApp extends ConsumerStatefulWidget {
  const MoneyApp({super.key});

  @override
  ConsumerState<MoneyApp> createState() => _MoneyAppState();
}

class _MoneyAppState extends ConsumerState<MoneyApp>
    with WidgetsBindingObserver {
  static const _pendingJobPollInterval = Duration(seconds: 4);

  bool _syncingPendingJobs = false;
  Timer? _pendingJobPollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startPendingJobPolling();
    });
  }

  @override
  void dispose() {
    _pendingJobPollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPendingJobPolling();
    } else {
      _pendingJobPollTimer?.cancel();
      _pendingJobPollTimer = null;
    }
  }

  void _startPendingJobPolling() {
    _pendingJobPollTimer?.cancel();
    unawaited(_syncPendingJobs());
    _pendingJobPollTimer = Timer.periodic(
      _pendingJobPollInterval,
      (_) => unawaited(_syncPendingJobs()),
    );
  }

  Future<void> _syncPendingJobs() async {
    if (_syncingPendingJobs) return;
    final remote = ref.read(backgroundJobServiceProvider);
    if (remote == null) return;
    _syncingPendingJobs = true;
    try {
      final result = await ref.read(pendingAiJobServiceProvider).sync(remote);
      if (result.imported > 0 && mounted) {
        ref.read(dataVersionProvider.notifier).state++;
      }
    } on Object {
      // 网络暂不可用时保留任务，前台轮询或下次恢复时继续检查。
    } finally {
      _syncingPendingJobs = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: '智账',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.of(FMScheme.light),
      darkTheme: AppTheme.of(FMScheme.dark),
      themeMode: themeMode,
      home: const AppShell(),
    );
  }
}
