import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../services/local_auth_service.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.hasAccounts,
    required this.onLogin,
    required this.onRegister,
  });

  final bool hasAccounts;
  final Future<void> Function(String username, String password) onLogin;
  final Future<void> Function(String username, String password) onRegister;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with TickerProviderStateMixin {
  late bool _register = !widget.hasAccounts;
  late final AnimationController _entry;
  late final AnimationController _ambient;
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..forward();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _entry.dispose();
    _ambient.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final action = _register ? widget.onRegister : widget.onLogin;
      await action(_username.text, _password.text);
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) setState(() => _error = '暂时无法完成，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _switchMode() {
    setState(() {
      _register = !_register;
      _error = null;
      _password.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    final curved = CurvedAnimation(parent: _entry, curve: Curves.easeOutCubic);
    return Scaffold(
      backgroundColor: s.bg,
      body: Stack(
        children: [
          Positioned.fill(child: _AmbientBackground(animation: _ambient)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: FMSpacing.xl,
                  vertical: FMSpacing.xxl,
                ),
                child: FadeTransition(
                  opacity: curved,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.035),
                      end: Offset.zero,
                    ).animate(curved),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: s.ink,
                              borderRadius: BorderRadius.circular(21),
                              boxShadow: [
                                BoxShadow(
                                  color: s.ink.withValues(alpha: 0.16),
                                  blurRadius: 28,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: const Icon(
                              CupertinoIcons.chart_pie_fill,
                              color: Colors.white,
                              size: 31,
                            ),
                          ),
                          const SizedBox(height: FMSpacing.xl),
                          Text('FlowMoney', style: AppText.headline(s.ink)),
                          const SizedBox(height: FMSpacing.xs),
                          Text(
                            '本地，隐私的智能财务管理空间',
                            style: AppText.body(s.inkSecondary),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: FMSpacing.xxl),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                              child: Container(
                                padding: const EdgeInsets.all(FMSpacing.xl),
                                decoration: BoxDecoration(
                                  color: s.surface.withValues(alpha: 0.88),
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.65),
                                    width: 0.8,
                                  ),
                                  boxShadow: s.cardShadow,
                                ),
                                child: AnimatedSize(
                                  duration: const Duration(milliseconds: 260),
                                  curve: Curves.easeOutCubic,
                                  child: Column(
                                    children: [
                                      _AuthField(
                                        controller: _username,
                                        label: '用户名',
                                        icon: CupertinoIcons.person,
                                        textInputAction: TextInputAction.next,
                                        enabled: !_busy,
                                      ),
                                      const SizedBox(height: FMSpacing.m),
                                      _AuthField(
                                        controller: _password,
                                        label: '密码',
                                        icon: CupertinoIcons.lock,
                                        obscureText: _obscure,
                                        textInputAction: TextInputAction.done,
                                        enabled: !_busy,
                                        onSubmitted: (_) => _submit(),
                                        suffix: IconButton(
                                          onPressed: () => setState(
                                            () => _obscure = !_obscure,
                                          ),
                                          icon: Icon(
                                            _obscure
                                                ? CupertinoIcons.eye
                                                : CupertinoIcons.eye_slash,
                                            size: 19,
                                          ),
                                        ),
                                      ),
                                      if (_error != null) ...[
                                        const SizedBox(height: FMSpacing.m),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            _error!,
                                            style: AppText.caption(s.danger),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: FMSpacing.xl),
                                      SizedBox(
                                        width: double.infinity,
                                        height: 52,
                                        child: FilledButton(
                                          onPressed: _busy ? null : _submit,
                                          style: FilledButton.styleFrom(
                                            backgroundColor: s.ink,
                                            foregroundColor: s.surface,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                          ),
                                          child: AnimatedSwitcher(
                                            duration: const Duration(
                                              milliseconds: 180,
                                            ),
                                            child: _busy
                                                ? const SizedBox(
                                                    key: ValueKey('loading'),
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                                  )
                                                : Text(
                                                    _register ? '创建账户' : '登录',
                                                    key: ValueKey(_register),
                                                    style: AppText.bodyStrong(
                                                      s.surface,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: FMSpacing.m),
                                      TextButton(
                                        onPressed: _busy ? null : _switchMode,
                                        child: Text(
                                          _register ? '已有账户？登录' : '没有账户？注册',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: FMSpacing.l),
                          Text(
                            '每个账户使用独立账单空间 · 默认保持登录',
                            textAlign: TextAlign.center,
                            style: AppText.caption(s.inkTertiary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.textInputAction,
    required this.enabled,
    this.obscureText = false,
    this.suffix,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputAction textInputAction;
  final bool enabled;
  final bool obscureText;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      autocorrect: false,
      enableSuggestions: !obscureText,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: AppText.bodyStrong(s.ink),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 19),
        suffixIcon: suffix,
        filled: true,
        fillColor: s.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: s.border, width: 0.7),
        ),
      ),
    );
  }
}

class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(animation.value);
        return Stack(
          children: [
            Positioned(
              right: -90 + 24 * t,
              top: -75 + 18 * math.sin(t * math.pi),
              child: _Glow(color: s.accent, size: 245),
            ),
            Positioned(
              left: -115 + 32 * (1 - t),
              bottom: 90 + 30 * t,
              child: _Glow(color: s.income, size: 275),
            ),
          ],
        );
      },
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.13),
          ),
        ),
      );
}
