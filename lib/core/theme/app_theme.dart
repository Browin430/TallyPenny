import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// 主题装配：由 [FMScheme] 生成 Material ThemeData。
/// 控件风格整体向 iOS 靠拢（Cupertino 转场、无水波纹、圆角弹层）。
class AppTheme {
  const AppTheme._();

  static ThemeData of(FMScheme s) {
    final colorScheme = ColorScheme(
      brightness: s.brightness,
      primary: s.accent,
      onPrimary: Colors.white,
      secondary: s.accent,
      onSecondary: Colors.white,
      error: s.danger,
      onError: Colors.white,
      surface: s.surface,
      onSurface: s.ink,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: s.brightness,
      scaffoldBackgroundColor: s.bg,
      colorScheme: colorScheme,
      splashFactory: InkRipple.splashFactory,
      highlightColor: s.ink.withValues(alpha: 0.05),
      splashColor: s.ink.withValues(alpha: 0.05),
      dividerColor: s.separator,
      textTheme: TextTheme(
        bodyLarge: AppText.body(s.ink),
        bodyMedium: AppText.body(s.ink),
        titleMedium: AppText.title(s.ink),
        labelLarge: AppText.bodyStrong(s.ink),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: s.ink,
        titleTextStyle: AppText.title(s.ink),
        iconTheme: IconThemeData(color: s.ink, size: 22),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: s.surface,
        modalBackgroundColor: s.surface,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(FMRadius.sheet)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: s.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: AppText.title(s.ink),
        contentTextStyle: AppText.body(s.inkSecondary),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: s.accent,
        selectionColor: s.accent.withValues(alpha: 0.25),
        selectionHandleColor: s.accent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : s.inkTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? s.income : s.separator,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
        headerForegroundColor: s.ink,
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: s.surface,
        dialBackgroundColor: s.surfaceAlt,
        hourMinuteColor: s.surfaceAlt,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: s.ink,
        contentTextStyle: AppText.bodyStrong(
          s.brightness == Brightness.dark ? s.bg : Colors.white,
        ),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FMRadius.chip)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
