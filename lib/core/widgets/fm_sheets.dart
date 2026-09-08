import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// 统一的底部弹层容器：圆角、安全区、键盘避让、拖拽把手。
Future<T?> showFMSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    enableDrag: enableDrag,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: _SheetChrome(child: Builder(builder: builder)),
    ),
  );
}

class _SheetChrome extends StatelessWidget {
  const _SheetChrome({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(FMRadius.sheet),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: s.ink.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// iOS 风格确认对话框，返回是否确认。
Future<bool> showFMConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmText = '确认',
  String cancelText = '取消',
  bool destructive = false,
}) async {
  final s = context.colors;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title, style: AppText.title(s.ink)),
      content: message == null
          ? null
          : Text(message, style: AppText.body(s.inkSecondary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelText, style: AppText.bodyStrong(s.inkSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(
            confirmText,
            style: AppText.bodyStrong(destructive ? s.danger : s.accent),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
