import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// 轻量提示（"✓ 已记录"）。毛玻璃底、顶部浮层、自动消失。
void showFMToast(
  BuildContext context, {
  required String message,
  IconData? icon,
  Color? iconColor,
  Duration duration = const Duration(milliseconds: 1900),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _ToastView(
      message: message,
      icon: icon,
      iconColor: iconColor,
      onDismiss: () => entry.remove(),
      duration: duration,
    ),
  );
  overlay.insert(entry);
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    required this.message,
    required this.onDismiss,
    required this.duration,
    this.icon,
    this.iconColor,
  });

  final String message;
  final VoidCallback onDismiss;
  final Duration duration;
  final IconData? icon;
  final Color? iconColor;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  void _dismiss() {
    _timer?.cancel();
    _controller.reverse().then((_) => widget.onDismiss());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Positioned(
      top: MediaQuery.paddingOf(context).top + FMSpacing.xl,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = CurvedAnimation(
              parent: _controller,
              curve: Curves.easeOutCubic,
            ).value;
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * -16),
                child: child,
              ),
            );
          },
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: FMSpacing.l,
                vertical: FMSpacing.m,
              ),
              decoration: BoxDecoration(
                color: s.navBar,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: s.ink.withValues(alpha: 0.06),
                  width: 0.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: BackdropFilter(
                  enabled: false,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(
                          widget.icon,
                          size: 17,
                          color: widget.iconColor ?? s.income,
                        ),
                        const SizedBox(width: FMSpacing.s),
                      ],
                      Text(widget.message, style: AppText.bodyStrong(s.ink)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
