import 'package:flutter/material.dart';

//app_theme.dart

final ValueNotifier<ThemeMode> appThemeNotifier = ValueNotifier(ThemeMode.system);

// 🟢 app_theme.dart の ValueNotifier のすぐ下あたりに追記
final ValueNotifier<String> appGradientThemeNotifier = ValueNotifier('blue');

// 🟢 app_theme.dart の AppGradient クラスを以下に差し替え
// 🟢 app_theme.dart の AppGradient クラスを以下に差し替え
class AppGradient {
  static const List<Color> blue = [Color(0xFF73a0fe), Color(0xFF96a9f9), Color(0xFFf6c0e7)];
  static const List<Color> green = [Color(0xFF161616), Color(0xFF455451), Color(0xFFABBBB1)];
  static const List<Color> black = [Color(0xFF000000), Color(0xFF1A1A1A), Color(0xFF2D2D2C)];
  static const List<Color> white = [Color(0xFFDCDCDC), Color(0xFFF5F5F5), Color(0xFFFFFFFF)];
  static const List<Color> purple = [Color(0xFF020304), Color(0xFF174a69), Color(0xFF7ebbdc)]; // 💡 新設：未来感パステルパープル

  static List<Color> getColors(String mode) {
    switch (mode) {
      case 'green': return green;
      case 'black': return black;
      case 'white': return white;
      case 'purple': return purple; // 💡 追記：パープルフローを通す
      case 'blue':
      default:
        return blue;
    }
  }
}

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

