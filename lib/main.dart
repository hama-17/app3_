import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
// ─── 🟢 追記：ウィジェット連携パッケージをインポート ───
import 'package:home_widget/home_widget.dart';

import 'screens/dashboard_screen.dart';
import 'core/app_theme.dart';

bool globalDisableAutoCacheClear = false;

// ─── 🟢 決定打1：MaterialAppの外側からでも安全に画面遷移をブチ抜くグローバルキー ───
final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid) {
    await AndroidAlarmManager.initialize();
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final prefs = await SharedPreferences.getInstance();

  final savedTheme = prefs.getString('app_theme_mode');
  if (savedTheme == 'light') {
    appThemeNotifier.value = ThemeMode.light;
  } else if (savedTheme == 'dark') {
    appThemeNotifier.value = ThemeMode.dark;
  }

  runApp(const CyberCanvasApp());
}

class CyberCanvasApp extends StatefulWidget {
  const CyberCanvasApp({super.key});

  @override
  State<CyberCanvasApp> createState() => _CyberCanvasAppState();
}

class _CyberCanvasAppState extends State<CyberCanvasApp> with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clearAppCache();

    // ─── 🟢 決定打2：アプリ起動の瞬間から、ウィジェットによるジャンプ命令の監視を開始 ───
    _initWidgetNavigation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ─── 🟢 修正版：ネイティブから飛んできたURLの捕獲エンジン ───
  void _initWidgetNavigation() {
    // 📥 パターンA: アプリが「完全に終了」していた状態から起動した場合
    HomeWidget.initiallyLaunchedFromHomeWidget().then((Uri? uri) {
      if (uri != null) _handleWidgetRoute(uri);
    });

    // 📥 🎯 修正：launchedFromHomeWidget を widgetClicked に変更してエラーを根治
    HomeWidget.widgetClicked.listen((Uri? uri) {
      if (uri != null) _handleWidgetRoute(uri);
    });
  }

  // ─── 🟢 修正版：届いた指令を解析し、魔法の合鍵で強制送還するハンドラー ───
  // ─── 🟢 最終進化版：パラメータ解析付き遷移ハンドラー ───
  // ─── 🟢 最終進化版：ダッシュボードへ直通信号を送るハンドラー ───
  void _handleWidgetRoute(Uri uri) {
    final String page = uri.pathSegments.last;
    final String? targetId = uri.queryParameters['id'];

    debugPrint("🛸 ウィジェット指令受信 ➔ ページ: $page, 対象ID: $targetId");

    Future.delayed(const Duration(milliseconds: 100), () {
      if (page == 'main' || targetId == null || targetId.isEmpty) {
        debugPrint("➔ 通常起動のため、トップ画面のまま維持します");
        return;
      }

      // ─── 🟢 決定打3：Dashboardに直通の電線へ信号を送るだけ！ ───
      // これにより、データが完全に揃った状態のダッシュボードが自律的に詳細画面を展開します。
      globalWidgetRouteNotifier.value = WidgetRouteData(page, targetId);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      if (globalDisableAutoCacheClear) {
        debugPrint("Auto Cache Clear Skipped (Camera in use)");
        return;
      }
      _clearAppCache();
    }
  }

  Future<void> _clearAppCache() async {
    if (globalDisableAutoCacheClear) return;
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        tempDir.listSync().forEach((file) {
          try {
            if (file is File) {
              file.deleteSync();
            }
          } catch (_) {}
        });
      }
    } catch (e) {
      debugPrint("Auto Cache Clear Error (Temp files): $e");
    }
    debugPrint("✨ Auto App Cache Cleared (Storage optimized, Session kept)");
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
        valueListenable: appThemeNotifier,
        builder: (_, currentMode, __) {
          return MaterialApp(
              title: 'k.portal',
              debugShowCheckedModeBanner: false,
              themeMode: currentMode,

              // ─── 🟢 決定打5：魔法の合鍵をマテリアルアプリに結線（これがないとジャンプできません） ───
              navigatorKey: globalNavigatorKey,

              theme: ThemeData(
                  brightness: Brightness.light,
                  fontFamily: 'GenInterfaceJP',
                  scaffoldBackgroundColor: const Color(0xFFF5F5F7)),
              darkTheme: ThemeData(
                  brightness: Brightness.dark,
                  fontFamily: 'GenInterfaceJP',
                  scaffoldBackgroundColor: Colors.black),
              home: const MainSkeleton());
        });
  }
}