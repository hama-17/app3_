import 'package:flutter/material.dart';

//app_theme.dart

final ValueNotifier<ThemeMode> appThemeNotifier = ValueNotifier(ThemeMode.system);

class AppTheme {
  static const Color accent = Color(0xFFD0312D);
  static Color bg(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? Colors.black : const Color(0xFFF2F2F2);
  static Color panel(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E1E1E) : const Color(0xFFE8E8E8);
  static Color textMain(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87;
  static Color textSub(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? Colors.white54 : Colors.black54;

  static Color getGradientColor(int index, int total) {
    if (total <= 1) return const Color(0xFF222222);
    final double t = index / (total > 15 ? 15 : total);
    final double adjustedT = (t % 1.0) * 0.85 + 0.1;
    return Color.lerp(const Color(0xFF101010), const Color(0xFFEEEEEE), adjustedT)!;
  }

  static Color getCustomCourseColor(String name) {
    int hash = name.hashCode;
    double lightness = 0.3 + (hash.abs() % 40) / 100.0;
    return HSLColor.fromAHSL(1.0, 0, 0, lightness).toColor();
  }

  static Color getTextColorForBackground(Color bg) => ThemeData.estimateBrightnessForColor(bg) == Brightness.light ? Colors.black : Colors.white;
}

