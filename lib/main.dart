import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

import 'screens/dashboard_screen.dart';
import 'core/app_theme.dart';
//main.dart

bool globalDisableAutoCacheClear = false;
// ─── main.dart の最上部周辺 ───

// ─── lib/main.dart ───

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🟢 解決の鍵：iOS環境での暴走を物理的に完全ブロック！
  // Androidの時はしっかりと叩き起こし、iOSの時は何事もなかったかのようにスルーさせます。
  // これにより、起動0秒目にMissingPluginExceptionでアプリが即死するルートを永久に封殺します。
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

// ★ 修正：StatefulWidgetに変更し、ライフサイクル（アプリの状態）を監視できるようにする
class CyberCanvasApp extends StatefulWidget {
  const CyberCanvasApp({super.key});

  @override
  State<CyberCanvasApp> createState() => _CyberCanvasAppState();
}

// ★ WidgetsBindingObserver を追加して、バックグラウンド移行を検知する
class _CyberCanvasAppState extends State<CyberCanvasApp> with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    // アプリ起動時に監視を開始
    WidgetsBinding.instance.addObserver(this);
    // 起動時にも念のため一度お掃除
    _clearAppCache();
  }

  @override
  void dispose() {
    // アプリ終了時に監視を解除
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ★ ここが検知メソッド：「アプリが見えなくなった」等で呼ばれる
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      // ★ 修正：カメラ起動中などでフラグが立っていれば、お掃除をスキップして終了する
      if (globalDisableAutoCacheClear) {
        debugPrint("Auto Cache Clear Skipped (Camera in use)");
        return;
      }

      _clearAppCache();
    }
  }

  // ★ バックグラウンドで実行される自動お掃除メソッド
  // ★ 修正：バックグラウンドで実行される自動お掃除メソッド
  Future<void> _clearAppCache() async {
    if (globalDisableAutoCacheClear) return;
    // ----------------------------------------------------
    // 【削除】
    // 以下の2行を実行するとCanvasのSessionStorageが消え、
    // Oktaでいちいちログインを求められるため削除しました。
    // final webStorageManager = WebStorageManager.instance();
    // await webStorageManager.deleteAllData();
    // ----------------------------------------------------

    try {
      // OSの一時ディレクトリ（Temp）にある不要なファイルを一掃
      // 動画バッファや画像の残骸（1GBの元凶）はこれで確実に消えます
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

              // 🟢 ライトモードのテーマ設定にフォントを追加
              theme: ThemeData(
                  brightness: Brightness.light,
                  fontFamily: 'GenInterfaceJP', // 👈 追記
                  scaffoldBackgroundColor: const Color(0xFFF5F5F7)),

              // 🟢 ダークモードのテーマ設定にフォントを追加
              darkTheme: ThemeData(
                  brightness: Brightness.dark,
                  fontFamily: 'GenInterfaceJP', // 👈 追記
                  scaffoldBackgroundColor: Colors.black),

              home: const MainSkeleton());
        });
  }
}


