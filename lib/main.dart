import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart'; // 🟢 追記：Workmanagerをインポート

import 'screens/dashboard_screen.dart';
import 'core/app_theme.dart';
import 'services/silent_refresh_service.dart'; // 🟢 追記：先ほどのSSO延長サービスを結線
import 'services/widget_update_service.dart';  // 🟢 追記：ウィジェット更新サービスも結線
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'services/cache_manager.dart'; // キャッシュマネージャーのパスを合わせてください
import 'utils/lms_adapter.dart';
import 'services/auth_service.dart';

bool globalDisableAutoCacheClear = false;
final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();

// ─── 🟢 決定打：スマホがスリープ中にOSから独立して呼び出されるバックグラウンド専用の無線通信Dispatcher ───
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint("💤 [Background Loop] アップル/アンドロイドのランチャー機能より巡回通信着火。");

    try {
      // ① まずは裏側でOktaを完全ステルス通過し、セッションを最新に延命！
      final bool isRefreshSuccess = await LmsSilentRefreshService.trySilentRefresh();

      if (isRefreshSuccess) {
        debugPrint("🟢 [Background Loop] サイレントログイン状態の延長に成功。データ先読みフェッチを開始します...");

        // 最新のCookieをSecureStorageからサルベージ
        final String? activeCookie = await AuthService.getSession();
        if (activeCookie != null && activeCookie.isNotEmpty) {

          // ② 【課題データの先読み直撃】全科目の課題APIを裏から叩く
          final tasksUri = Uri.tryParse('$canvasBaseUrl/api/v1/users/self/todo?per_page=100'); // 本来の課題一括取得API
          if (tasksUri != null) {
            final res = await http.get(tasksUri, headers: {'Cookie': activeCookie}).timeout(const Duration(seconds: 10));
            if (res.statusCode == 200) {
              final List<dynamic> fetchedTasks = jsonDecode(res.body);

              // 🎯 決定打：画面（UI）を一切介さず、ローカルキャッシュファイルを裏から力技で直接上書き！
              await CacheManager.save('cached_assignments_v14_all_year', fetchedTasks);
              debugPrint("📦 [Background Loop] 最新の課題データをキャッシュに直撃書き込みしました（先読み完了）");
            }
          }
        }

        // ③ データが完全に新しくなった状態で、時間割や予定ウィジェットの文字を最新状態へ焼き替える
        await WidgetUpdateService.updateHomeWidgets();
      }
    } catch (e) {
      debugPrint("❌ [Background Loop] バックグラウンド巡回中にエラーが発生: $e");
    }

    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ─── 🟢 追記：バックグラウンド巡回タスクマトリクスの初期化 ───
  await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false // ⚙️ テスト時に通知を出したい場合はここを true に切り替えてください
  );

  if (Platform.isAndroid) {
    await AndroidAlarmManager.initialize();

    // アンドロイド用の6時間おき（1日4回）の定期巡回ジョブを設定
    await Workmanager().registerPeriodicTask(
      "com.example.app3_kportal_2.silent_refresh_job", // ユニークなID
      "silentRefreshTask",
      frequency: const Duration(hours: 6), // ⏳ 6時間おき＝1日4回周期
      existingWorkPolicy: ExistingWorkPolicy.keep, // 二重登録を防止して既存のスケジュールを維持
      constraints: Constraints(
        networkType: NetworkType.connected, // 🌐 Wi-Fiまたはモバイル通信接続時のみ実行
      ),
    );
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

// （これ以降の CyberCanvasApp クラスの中身は、1文字も変更なしで完全無傷維持してください）

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