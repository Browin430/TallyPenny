import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../state/app_providers.dart';

Future<String?> showFourDigitPinDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmText = '确定',
  bool verify = false,
}) async {
  final controller = TextEditingController();
  String? error;
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: !verify,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message != null) ...[
              Text(message, style: AppText.body(context.colors.inkSecondary)),
              const SizedBox(height: FMSpacing.l),
            ],
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              obscuringCharacter: '●',
              maxLength: 4,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: AppText.title(context.colors.ink).copyWith(
                letterSpacing: 12,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: InputDecoration(
                hintText: '••••',
                errorText: error,
                counterText: '',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                if (value.length == 4) Navigator.of(dialogContext).pop(value);
              },
              onChanged: (_) {
                if (error != null) setDialogState(() => error = null);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.length != 4) {
                setDialogState(() => error = '请输入4位数字密码');
                return;
              }
              Navigator.of(dialogContext).pop(controller.text);
            },
            child: Text(confirmText),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}

/// 进入流水或分析页前验证；未设置密码时直接通过。
Future<bool> requestFinancialDataAccess(
  BuildContext context,
  WidgetRef ref,
) async {
  final configured = await ref.read(analysisPinProvider.future);
  if (!configured || !context.mounted) return true;

  while (context.mounted) {
    final pin = await showFourDigitPinDialog(
      context,
      title: '解锁流水与分析',
      message: '请输入4位数密码',
      confirmText: '解锁',
      verify: true,
    );
    if (pin == null || !context.mounted) return false;
    final ok = await ref.read(analysisPinProvider.notifier).verify(pin);
    if (ok) return true;
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('密码错误，请重试')));
  }
  return false;
}
