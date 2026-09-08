import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/fm_sheets.dart';
import '../analysis/analysis_page.dart';
import '../entry/entry_mode_sheet.dart';
import '../entry/voice_entry_page.dart';
import '../home/home_page.dart';
import '../profile/profile_page.dart';
import '../privacy/analysis_pin_dialog.dart';
import '../transactions/transactions_page.dart';

/// 当前选中的 Tab（全局，供跨页跳转使用）。
final shellTabIndexProvider = StateProvider<int>((ref) => 0);

/// 四 Tab 壳：首页 / 流水 / 【+】 / 分析 / 我的。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _widgetChannel = MethodChannel('dev.flowmoney.flowmoney/widget');
  bool _openingVoice = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _widgetChannel.setMethodCallHandler((call) async {
        if (call.method == 'openVoice') await _openVoice();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _consumeWidgetOpen());
    }
  }

  Future<void> _consumeWidgetOpen() async {
    try {
      final requested = await _widgetChannel
              .invokeMethod<bool>('consumeInitialVoiceRequest') ??
          false;
      if (requested) await _openVoice();
    } on MissingPluginException {
      // 非 Android 平台或热重载期间没有原生通道时忽略。
    } on PlatformException {
      // 桌面入口不可用不应影响 App 正常启动。
    }
  }

  Future<void> _openVoice() async {
    if (!mounted || _openingVoice) return;
    _openingVoice = true;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const VoiceEntryPage()),
    );
    _openingVoice = false;
  }

  @override
  void dispose() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _widgetChannel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final index = ref.watch(shellTabIndexProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: index,
              children: [
                const HomePage(),
                const TransactionsPage(),
                AnalysisPage(active: index == 2),
                const ProfilePage(),
              ],
            ),
          ),
          Positioned(
            left: FMSpacing.m,
            right: FMSpacing.m,
            bottom: math.max(bottomInset, FMSpacing.s),
            child: _TabBar(
              currentIndex: index,
              onTap: (i) async {
                if ((i == 1 || i == 2) && index != i) {
                  final allowed =
                      await requestFinancialDataAccess(context, ref);
                  if (!allowed || !context.mounted) return;
                }
                ref.read(shellTabIndexProvider.notifier).state = i;
              },
              onPlus: () => showFMSheet(
                context,
                builder: (_) => const EntryModeSheet(),
              ),
              ink: s.ink,
              inkSecondary: s.inkSecondary,
              accent: s.accent,
              barColor: s.navBar,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.currentIndex,
    required this.onTap,
    required this.onPlus,
    required this.ink,
    required this.inkSecondary,
    required this.accent,
    required this.barColor,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onPlus;
  final Color ink;
  final Color inkSecondary;
  final Color accent;
  final Color barColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: ink.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: FMSpacing.s),
            child: Row(
              children: [
                _TabItem(
                  icon: FMIcons.home,
                  label: '首页',
                  selected: currentIndex == 0,
                  color: currentIndex == 0 ? accent : inkSecondary,
                  onTap: () => onTap(0),
                ),
                _TabItem(
                  icon: FMIcons.list,
                  label: '流水',
                  selected: currentIndex == 1,
                  color: currentIndex == 1 ? accent : inkSecondary,
                  onTap: () => onTap(1),
                ),
                Expanded(
                  child: Center(
                    child: Semantics(
                      button: true,
                      label: '快速记账',
                      child: Material(
                        color: accent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onPlus,
                          child: const SizedBox(
                            width: 50,
                            height: 50,
                            child: Icon(
                              FMIcons.plus,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _TabItem(
                  icon: FMIcons.analysis,
                  label: '分析',
                  selected: currentIndex == 2,
                  color: currentIndex == 2 ? accent : inkSecondary,
                  onTap: () => onTap(2),
                ),
                _TabItem(
                  icon: FMIcons.person,
                  label: '我的',
                  selected: currentIndex == 3,
                  color: currentIndex == 3 ? accent : inkSecondary,
                  onTap: () => onTap(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: selected ? 1.04 : 1,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: AppText.micro(color).copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
