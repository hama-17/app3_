import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_theme.dart';
import '../services/cache_manager.dart';
import '../services/auth_service.dart';
import '../services/calendar_sync_service.dart';
import '../utils/lms_adapter.dart';
import '../utils/course_parser.dart';

import 'login_screen.dart' hide AuthService;
import 'settings_screen.dart';
import 'course_detail_screen.dart'; // 先ほど作った詳細画面
import 'media_viewers.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/app_snackbar.dart';

import 'dart:async';

import '../utils/term_helper.dart';
import 'package:flutter/services.dart';
import '../services/widget_update_service.dart';
// 🟢 既存のインポート文のすぐ下に、以下の3行を追記してシステムを認識させます
import 'package:camera/camera.dart';
import 'package:path/path.dart' show join;
import 'package:gal/gal.dart';
import '../services/live_notification_service.dart';
import '../services/p2p_sync_service.dart'; // 🟢 追記：先ほど作成したP2Pサービスを認識させる
import 'package:qr_flutter/qr_flutter.dart'; // 🟢 追記：QRコード関連のクラスを一括インポート

import '../utils/qr_payload_parser.dart'; // 🟢 追記：スキャンパーサーをダッシュボードに認識させる
//lib/screens/dashboard_screen.dartの中身です。


class MainSkeleton extends StatefulWidget { const MainSkeleton({super.key}); @override State<MainSkeleton> createState() => _MainSkeletonState(); }


class _MainSkeletonState extends State<MainSkeleton> {
  List<dynamic> _allCourses = [];
  List<dynamic> _filteredCourses = [];
  List<dynamic> _uniqueSortedCourses = [];
  bool _isLoading = true;
  bool _isAuthenticated = false;
  String _cookie = "";

  late int _selectedYear;
  late String _selectedTerm;
  Map<String, String> _courseTermOverrides = {};

  @override
  void initState() {
    super.initState();
    _initTermAndData();
  }

  // ★ 修正：起動時の初期化ロジック。手動保存を優先し、なければ自動判定。
  // lib/screens/dashboard_screen.dart 内の _initTermAndData メジットを上書き
  Future<void> _initTermAndData() async {
    final prefs = await SharedPreferences.getInstance();

    // 💡 初回起動時に「アプリにカレンダーの予定を表示」のみを自動でONにする
    if (!prefs.containsKey('calendar_sync_initialized_v10')) {
      await prefs.setBool('calendar_sync_enabled', true);         // 同期親トグルをON
      await prefs.setBool('sync_import_enabled', true);          // 「アプリに予定を表示」をON
      await prefs.setBool('sync_tasks_enabled', false);          // タスク書き出しはOFF
      await prefs.setBool('sync_schedules_enabled', false);      // 授業書き出しはOFF
      await prefs.setBool('calendar_sync_initialized_v10', true); // 初期化完了フラグ

      // 初回起動のこのタイミングで即座にOSのカレンダー権限ポップアップを自動起動
      try {
        await CalendarSyncService.requestPermissions();
      } catch (_) {}
    }

    int? savedYear = prefs.getInt('manual_year_v10');
    String? savedTerm = prefs.getString('manual_term_v10');

    final now = DateTime.now();
    int defaultYear = now.year;
    if (now.month < 4) defaultYear -= 1; // 1〜3月は前年度扱い
    String defaultTerm = TermHelper.getTermForDate(now);

    _selectedYear = savedYear ?? defaultYear;
    _selectedTerm = savedTerm ?? defaultTerm;

    final savedGradient = prefs.getString('settings_theme_mode_v10') ?? 'blue';
    appGradientThemeNotifier.value = savedGradient;

    _loadData();
  }

  void _updateUniqueSortedCourses() {
    Map<int, dynamic> uniqueMap = {};
    for (var c in _filteredCourses) {
      if (!uniqueMap.containsKey(c['id'])) { uniqueMap[c['id']] = c; }
    }
    _uniqueSortedCourses = uniqueMap.values.toList();
  }

  // ★ 修正：強制的に科目を消す古いロジックを廃止。TermHelperに完全一任。
  void _applyFilter() {
    setState(() {
      _filteredCourses = _allCourses.where((c) =>
      c['name'] != null &&
          TermHelper.shouldDisplayCourse(c, _courseTermOverrides, _selectedYear, _selectedTerm)
      ).toList();
      _updateUniqueSortedCourses();
    });
  }

  Future<void> _loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final termDataStr = prefs.getString('course_term_overrides_v10');
      if (termDataStr != null) _courseTermOverrides = Map<String, String>.from(jsonDecode(termDataStr));

      final cached = await CacheManager.load('my_course_cache_v10');
      if (cached != null) {
        _allCourses = cached;
        _applyFilter();
        if (mounted) setState(() => _isLoading = false);
      }

      _cookie = (await AuthService.getSession()) ?? "";
      if (_cookie.isEmpty) {
        if (mounted) setState(() { _isAuthenticated = false; _isLoading = false; });
        return;
      }

      // ★ 追加：テストログイン中なら、オンライン通信をスキップして即時ダミー認証化する
      if (_cookie == "dummy_test_session") {
        if (mounted) setState(() { _isAuthenticated = true; _isLoading = false; });
        return;
      }

      final uri = Uri.tryParse('$canvasBaseUrl/api/v1/courses?per_page=100&include[]=term&include[]=teachers');
      if (uri == null) return;

      final response = await http.get(uri, headers: { 'Cookie': _cookie }).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        _allCourses = jsonDecode(response.body) as List;
        await CacheManager.save('my_course_cache_v10', _allCourses);
        _applyFilter();

        // 🟢 追加：授業キャッシュが新しくなったら、即座にウィジェットへも同期
        await WidgetUpdateService.updateHomeWidgets(courses: _allCourses);

        if (mounted) setState(() { _isAuthenticated = true; _isLoading = false; });
      }
      else if (response.statusCode == 401 || response.statusCode == 403) {
        if (mounted) setState(() { _isAuthenticated = false; _isLoading = false; });
      }
      else { if (mounted) setState(() { _isLoading = false; }); }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleLogin() => Navigator.push(context, MaterialPageRoute(builder: (_) => OktaLoginScreen(onLoginSuccess: _loadData)));

  // lib/screens/dashboard_screen.dart 内の _handleLogout メソッドを上書き
  void _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();

    // 🛡️ 判定：もし現在のセッションがテスト用のダミーデータ環境だった場合
    if (_cookie == "dummy_test_session") {
      // 1. セッションの破棄
      await AuthService.clearSession();

      // 2. 設定やキャッシュキーの全消去
      await prefs.clear();

      // 3. ダミーの物理キャッシュファイルをすべて空の配列で上書き消滅させる
      await CacheManager.save('my_course_cache_v10', <dynamic>[]);
      await CacheManager.save('cached_assignments_v14_all_year', <dynamic>[]);
      await CacheManager.save('cached_messages_v14_all_year', <dynamic>[]);

      // 4. テスト中に作成されたメモの添付画像や一時ファイルをストレージから一括抹消
      try {
        final docDir = await getApplicationDocumentsDirectory();
        final memoImgDir = Directory('${docDir.path}/memo_images');
        if (await memoImgDir.exists()) {
          await memoImgDir.delete(recursive: true);
        }
        final tempDir = await getTemporaryDirectory();
        if (tempDir.existsSync()) {
          tempDir.listSync().forEach((file) {
            try { if (file is File) file.deleteSync(); } catch (_) {}
          });
        }
      } catch (e) {
        debugPrint("Test environment sandbox clear error: $e");
      }

      if (mounted) {
        // 5. 設定画面が開いていた場合は、安全に閉じて最前面のホーム（Skeleton）に視点を戻す
        Navigator.of(context).popUntil((route) => route.isFirst);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('試運転環境を終了し、すべてのテストデータを完全消去しました。')),
        );

        // 6. メモリ上の State を完全にリセットしてローディングを挟む
        setState(() {
          _allCourses = [];
          _filteredCourses = [];
          _uniqueSortedCourses = [];
          _isAuthenticated = false;
          _cookie = "";
          _isLoading = true;

        });

        // 7. 出荷状態のクリーンな状態で年度・学期の再算出へ
        _initTermAndData();
      }
      return;
    }

    // 🔒 通常のログインアカウントだった場合のログアウト処理（既存の挙動を維持）
    await AuthService.clearSession();
    if (mounted) {
      setState(() {
        _isAuthenticated = false;
        _cookie = "";
      });
      // ログアウト後の未認証データを安全にリロード
      _loadData();
    }
  }

  // lib/screens/dashboard_screen.dart 内の _openSettings メソッド
  // lib/screens/dashboard_screen.dart 内の _openSettings メソッドを修正
  void _openSettings() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(
        currentYear: _selectedYear,
        currentTerm: _selectedTerm,
        isAuthenticated: _isAuthenticated,
        onLogin: _handleLogin,
        onLogout: _handleLogout,
        onApply: (year, term) async {
          setState(() { _selectedYear = year; _selectedTerm = term; });
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('manual_year_v10', year);
          await prefs.setString('manual_term_v10', term);
          _applyFilter();
        }
    ))).then((result) {
      // 初期化の合図を受け取ったら、親クラスが持っている変数だけを綺麗にする
      if (result == 'initialized') {
        setState(() {
          _allCourses = [];
          _filteredCourses = [];
          _uniqueSortedCourses = [];
          _isAuthenticated = false;
          _cookie = "";
          _isLoading = true; // ★ これにより下位のDashboardPageが自動で解体・リセットされます！
        });
        // まっさらな状態で初期データロードを走らせる
        _initTermAndData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : DashboardPage(
          courses: _filteredCourses,
          uniqueCourses: _uniqueSortedCourses,
          allCourses: _allCourses, // ★ これを追加
          isAuthenticated: _isAuthenticated,
          onLogin: _handleLogin,
          onLogout: _handleLogout,
          onSettings: _openSettings,
          cookie: _cookie,
          currentYear: _selectedYear,
          currentTerm: _selectedTerm,
          onTermChanged: (year, term) async {
            setState(() { _selectedYear = year; _selectedTerm = term; });
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('manual_year_v10', year);
            await prefs.setString('manual_term_v10', term);
            _applyFilter();
          }
      ),
    );
  }
}


enum ViewState { home, fullTasks, fullMessages }


class DashboardPage extends StatefulWidget {
  final List<dynamic> courses;
  final List<dynamic> uniqueCourses;
  final List<dynamic> allCourses; // ★ これを追加
  final bool isAuthenticated;
  final VoidCallback onLogin;
  final VoidCallback onLogout;
  final VoidCallback onSettings;
  final String cookie;
  final int currentYear;
  final String currentTerm;
  final Function(int, String) onTermChanged;


  const DashboardPage({
    super.key,
    required this.courses,
    required this.uniqueCourses,
    required this.allCourses, // ★ これを追加
    required this.isAuthenticated,
    required this.onLogin,
    required this.onLogout,
    required this.onSettings,
    required this.cookie,
    required this.currentYear,
    required this.currentTerm,
    required this.onTermChanged
  });
  @override State<DashboardPage> createState() => _DashboardPageState();
}


class _DashboardPageState extends State<DashboardPage> with TickerProviderStateMixin, WidgetsBindingObserver {
  String _scheduleMode = 'D';
  // 🟢 追加：カメラ画面のカプセルボタン連動メモ用コンポーネント
  final TextEditingController _cameraMemoController = TextEditingController();
  final FocusNode _cameraMemoFocusNode = FocusNode();

  final GlobalKey _previewContainerKey = GlobalKey();

  late PageController _coursesWidgetController;
  late PageController _schedulePageController;
  late PageController _taskPageController;
  // 🟢 最左面用のインラインカメラ制御用ステート変数
  CameraController? _cameraController;
  List<CameraDescription> _cameraList = [];
  int _selectedCamIdx = 0;
  bool _isCamInitialized = false;
  bool _isCamInitializing = false;
  bool _isCamTakingPicture = false;
  double _camCurrentZoom = 1.0;
  double _camMinZoom = 1.0;
  double _camMaxZoom = 1.0;
  double _minZoomLevel = 1.0;
  double _maxZoomLevel = 1.0;
  double _camBaseZoom = 1.0;
  bool _camShowZoomText = false;
  // 🟢 追加：メモ入力欄が今開いているかどうかのフラグ
  bool _isMemoFieldOpen = false;
  // 🟢 追加：カメラ画面の対応メモ手動置き換え用の管理ステート
  String _cameraCourseMode = 'auto';
  Map<String, dynamic>? _cameraManualCourseObj;
  bool _isCameraPinching = false;
  // 🟢 追記：フライング誤爆を防ぐための1分猶予タイマーと確定フラグ
  Timer? _gracePeriodTimer;
  bool _shouldShowRedAlert = false;

  late AnimationController _cameraCaptureAnimController;
  String? _capturedImagePathForAnim;
  ui.Image? _capturedUiImageForAnim;
  Map<String, String> _taskDueOverrides = {};

  Timer? _autoRefreshTimer;
// 🟢 追加：最後にLMS同期（_fetchDataParallel）に成功した時刻を保持する変数
  DateTime? _lastFetchTime;



  // 🟢 独自カメラのオンデマンドライフサイクル制御
  Future<void> _prepareAvailableCameras() async {
    try { _cameraList = await availableCameras(); } catch (_) {}
  }

  Future<void> _initInlineCamera() async {
    if (_isCamInitialized || _isCamInitializing || _cameraList.isEmpty) return;

    _isCamInitializing = true;
    try {
      _cameraController = CameraController(
        _cameraList[_selectedCamIdx],
        ResolutionPreset.medium, // 🟢 修正：max から medium に引き下げて安定性を極限まで高める
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888, // 🟢 Androidなら明示的にYUVを指定
      );

      await _cameraController!.initialize();

      // 🟢 追記セクター：バックグラウンドでのQRスキャンを間引き（スロットリング）制御しながら完全実動化
      bool _isQrProcessing = false; // 内部二重発火防止フラグ

      _cameraController!.startImageStream((CameraImage availableImage) async {
        // シャッター中、またはすでに前のフレームを解析中なら、このフレームは音速でスルー（無視）する
        if (_isCamTakingPicture || _isQrProcessing || !mounted) return;

        _isQrProcessing = true; // レーダーロック（解析開始）

        try {
          // 🟢 修正：nullや空データが混ざらないようガードを強化
          if (availableImage.planes.isEmpty) return;

          final String? scannedQrText = await QrPayloadParser.parseCameraImage(
              availableImage,
              _cameraList[_selectedCamIdx]
          );
          // (以下略)

          // カメラが「kportal_p2p_v1:」から始まる暗号化QRコードを完全に捉えたら
          if (scannedQrText != null && scannedQrText.startsWith("kportal_p2p_v1:")) {
            await _cameraController!.stopImageStream(); // 迎撃レーダーを重複発火防止のために即時完全停止

            // 暗号化クッキーをWi-Fi空間へ向けてPOST射出！
            bool sendSuccess = await P2pSyncService.scanAndSendCookie(scannedQrText);

            if (sendSuccess && mounted) {
              HapticFeedback.vibrate(); // 📱 密輸成功を手のひらに伝えるバイブ演出
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('⚡ P2P Link: クッキーの暗号化密輸に成功しました。')),
              );
            }
          }
        } catch (e) {
          debugPrint("Inline QR stream parsing error: $e");
        } finally {
          _isQrProcessing = false; // レーダー解放（次のフレームの解析を許可）
        }
      });

      _camMinZoom = await _cameraController!.getMinZoomLevel();
      double deviceMax = await _cameraController!.getMaxZoomLevel();
      _camMaxZoom = math.min(20.0, deviceMax);
      _camCurrentZoom = _camMinZoom;

      if (mounted) {
        setState(() => _isCamInitialized = true);
      }
    } catch (e) {
      debugPrint("Camera Init Error: $e");
    } finally {
      _isCamInitializing = false;
    }
  }

  // 🟢 修正：赤いエラー画面を一瞬たりとも出さない、先行シャットダウン型パージロジック
  Future<void> _disposeInlineCamera() async {
    if (!_isCamInitialized) return;

    // ① 【最重要】重い非同期処理（await）を待つ前に、同期的にフラグと変数を完全パージ！
    // これにより、次の1フレーム（数ミリ秒後）の再描画で CameraPreview が呼ばれるルートを物理的に完全遮断します。
    final tempController = _cameraController;
    _cameraController = null;
    _isCamInitialized = false;

    if (mounted) {
      setState(() {}); // 👈 描画を即座に安全なインジケータ（または暗転）へ切り替え
    }

    // ② UIスレッドの描画セクターを守りきった後、裏で安全にハードウェアを解放
    if (tempController != null) {
      try {
        await tempController.dispose();
        debugPrint("Inline Camera disposed safely without red error screen.");
      } catch (e) {
        debugPrint("Camera dispose error inside background task: $e");
      }
    }
  }

  // 🟢 修正版：P2Pクッキー密輸用QRコードコンソール（ロジック完全結合版）
  // 🟢 修正版：P2Pクッキー密輸用QRコードコンソール（Material欠落＆コンテキスト競合を完全修復）
  // 🟢 リファイン完全版：ライトモード時もダーク固定 ＆ 180px対称サークルボタン ＆ 縦長インダストリアルUI
  // 🟢 リファイン確定版：完全上下対称グリッド ＆ ダーク固定 ＆ 筐体サイズ微拡大
  void _showP2pQRConnectionDialog() {
    const Color panelBg = Color(0xFF161616);
    const Color textMain = Colors.white;
    const Color textSub = Colors.white38;
    const Color borderCol = Colors.white10;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return FutureBuilder<String>(
            future: P2pSyncService.startReceiverServer(
                onSyncSuccess: () {
                  if (mounted) {
                    Navigator.pop(dialogCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('P2Pセッション同期が完了しました。時間割を復元します。')),
                    );
                    setState(() {
                      _fetchDataParallel();
                    });
                  }
                }
            ),
            builder: (futureCtx, snapshot) {
              String qrPayload = snapshot.data ?? "loading...";
              bool isServerReady = snapshot.hasData;

              return Center(
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    width: 290, // 💡 決定打①：横幅を260pxから「290px」へ微拡大し、180pxマスの質量に負けない最適な余白感を確保
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 36.0),
                    decoration: BoxDecoration(
                      color: panelBg,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: borderCol, width: 0.5),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // ① 【最上段】：固定高テキストエリア（左スワイプのカメラ誘導）
                        SizedBox(
                          height: 36, // 💡 決定打②：高さを36pxに固定し、文字数や行数のブレによる上下の非対称を物理的に完全封殺
                          child: Center(
                            child: Text(
                              "ログイン済みのアプリの\nメモカメラをかざしてください",
                              style: TextStyle(color: textSub, fontSize: 14, fontWeight: FontWeight.w300, height: 1.4),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28), // 🎯 対称マージンA（上側）

                        // ② 【中央・上】：QRコード（180pxスクエア）
                        Container(
                          width: 180,
                          height: 180,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: !isServerReady
                              ? const Center(child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                              : QrImageView(
                            data: qrPayload,
                            size: 148.0,
                          ),
                        ),
                        const SizedBox(height: 24), // 🎯 コアマージン（中央境界線）

                        // ③ 【中央・下】：手動迂回ボタン（180pxサークル）
                        GestureDetector(
                          onTap: () async {
                            await P2pSyncService.stopServer();
                            if (mounted) {
                              Navigator.pop(dialogCtx);
                              widget.onLogin();
                            }
                          },
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.black,
                              size: 40,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28), // 🎯 对称マージンA（下側）

                        // ④ 【最下段】：固定高テキストエリア（通常のログインサイト）
                        SizedBox(
                          height: 36, // 💡 決定打③：最上段と全く同じ36pxの器で包むことで、完全に計算され尽くした美しいシンメトリーを構築
                          child: Center(
                            child: Text(
                              "通常のログインサイトでログイン\n(初回ログイン)",
                              style: TextStyle(color: textSub, fontSize: 14, fontWeight: FontWeight.w300, height: 1.4),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
        );
      },
    ).then((_) async {
      await P2pSyncService.stopServer();
    });
  }

  void _switchCameraFacing() {
    if (_cameraList.length < 2 || _isCamTakingPicture) return;
    setState(() { _isCamInitialized = false; _selectedCamIdx = (_selectedCamIdx + 1) % _cameraList.length; });
    _initInlineCamera();
  }

  // 🟢 追加：永続化コピーやGal登録、授業メモ追加などの重いI/Oを「裏」で完全に非同期実行するメソッド
  // 🟢 修正：パスを外部から固定で受け取り、メインスレッドを1ミリもブロックしない非同期物理保存
  Future<void> _performBackgroundSaveTasks(String tmpPath, String permanentPath) async {
    try {
      await File(tmpPath).copy(permanentPath);
      await Gal.putImage(permanentPath);
    } catch (e) {
      debugPrint("Background save error: $e");
    }
  }

  // 🟢 修正：無音保存側も同様にディスク書き込みとGal登録のみに純化
  void _performBackgroundSilentSave(ui.Image image, String permanentPath) {
    Future(() async {
      try {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) return;

        await File(permanentPath).writeAsBytes(byteData.buffer.asUint8List());
        await Gal.putImage(permanentPath);
        debugPrint("iOS Inline 無音バックグラウンド保存完了");
      } catch (e) {
        debugPrint("Background silent save error: $e");
      }
    });
  }

  // 🟢 修正：保存完了を一切待たずに、シャッターの瞬間にアニメーションを最優先点火する爆速版
  // 🟢 修正：設定フラグに完全連動するハイブリッド無音インラインシャッター
  // 🟢 修正：レイテンシを完全消滅させ、画質を4.0へ上限突破させたインライン無音シャッター
  // 🟢 修正：20msホールド・先行メモデータ射出・最高画質4.0維持の決定版インラインシャッター
  Future<void> _takeInlineCameraPhoto() async {
    if (_cameraController == null || !_isCamInitialized || _isCamTakingPicture) return;
    setState(() => _isCamTakingPicture = true);
    try {
      // ─── 🟢 決定打①：プレビューテクスチャが完全に確定するのを20ms待機 ───
      // これにより、ビデオ描画ストリームとのラグによる「虚空（真っ黒画面）」のキャプチャを100%防ぎます
      await Future.delayed(const Duration(milliseconds: 20));

      final docDir = await getApplicationDocumentsDirectory();
      final memoImgDir = Directory('${docDir.path}/memo_images');
      if (!await memoImgDir.exists()) await memoImgDir.create(recursive: true);

      final String timeStamp = DateTime.now().millisecondsSinceEpoch.toString();

      if (Platform.isIOS) {
        final prefs = await SharedPreferences.getInstance();
        final bool isSilentMode = prefs.getBool('ios_silent_camera_v10') ?? true;

        if (isSilentMode) {
          // 🔇 【ルートA】完全無音モード（中身はPNGバイト）
          final String permanentPath = join(memoImgDir.path, 'IMG_$timeStamp.png'); // 🟢 正しく.pngで確定

          final RenderRepaintBoundary boundary = _previewContainerKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final ui.Image image = await boundary.toImage(pixelRatio: 4.0); // 画質4.0ブースト

          // ─── 🟢 決定打②：ディスクへの重い書き込みより「先に」メモリデータを更新 ───
          // これにより、撮影直後に詳細画面へジャンプしてもカメラ画像が一瞬でタイムラインに反映されます
          await _addMemoToCourse('image', permanentPath);

          // アニメーション用に生の ui.Image オブジェクトを射出
          if (mounted) {
            setState(() { _capturedUiImageForAnim = image; });
            _cameraCaptureAnimController.forward().then((_) {
              if (mounted) {
                setState(() { _capturedUiImageForAnim = null; _cameraCaptureAnimController.reset(); });
              }
            });
          }

          // 重いシリアライズは裏へ完全委譲
          _performBackgroundSilentSave(image, permanentPath);

        } else {
          // 📸 【ルートB】音あり最高物理画質モード（カメラ標準のJPEG出力）
          final String permanentPath = join(memoImgDir.path, 'IMG_$timeStamp.jpg'); // 🟢 JPGで確定

          final XFile rawImage = await _cameraController!.takePicture();
          await _addMemoToCourse('image', permanentPath); // 先行反映
          _triggerInlineAnimation(rawImage.path);
          _performBackgroundSaveTasks(rawImage.path, permanentPath);
        }
      } else {
        // ─── Android専用ルート ───
        final String permanentPath = join(memoImgDir.path, 'IMG_$timeStamp.jpg');

        final XFile rawImage = await _cameraController!.takePicture();
        await _addMemoToCourse('image', permanentPath); // 先行反映
        _triggerInlineAnimation(rawImage.path);
        _performBackgroundSaveTasks(rawImage.path, permanentPath);
      }

    } catch (e) {
      debugPrint("Take Inline Camera Photo Error: $e");
    } finally {
      if (mounted) {
        setState(() => _isCamTakingPicture = false);
      }
    }
  }

  void _triggerInlineAnimation(String path) {
    if (!mounted) return;
    setState(() { _capturedImagePathForAnim = path; });
    _cameraCaptureAnimController.forward().then((_) {
      if (mounted) {
        setState(() { _capturedImagePathForAnim = null; _cameraCaptureAnimController.reset(); });
      }
    });
  }

  // 🟢 新設：iOS無音インライン用の完全ノンブロッキング保存タスク


  // 🟢 追加：現在進行中、または直後の授業を正確に割り出すロジック
  // 🟢 修正：戻り値の型を Map<String, String>? から Map<String, dynamic>? に変更
  // これにより、Map の中に String と bool を混在させることが可能になり、エラー1が消滅します
  // 🟢 修正：10分バッファ＆24時間完全リレー型・時間割自動同期エンジン
  Map<String, dynamic>? _getCurrentOrNextCourse() {
    if (_cameraCourseMode == 'none') return null;

    if (_cameraCourseMode == 'manual' && _cameraManualCourseObj != null) {
      return _cameraManualCourseObj;
    }

    final now = DateTime.now();
    final items = _getScheduleForDate(now);

    // ① 当日のスケジュールから「有効な授業（class）」のみを抽出し、休講（status: 2）を徹底除外
    final classItems = items.where((item) => item['type'] == 'class' && item['status'] != 2).toList();
    if (classItems.isEmpty) return null; // 💡 授業が1コマもない日は、自動同期を安全に null（対応なし）にします

    // 現在時刻を「0 〜 1439分」の絶対分数にコンバート
    int nowMins = now.hour * 60 + now.minute;
    Map<String, dynamic>? targetItem;

    // ② タイムラインを隙間なくセクターに分割し、現在時刻の所属先をパズル形式で判定
    for (int i = 0; i < classItems.length; i++) {
      final current = classItems[i];
      DateTime start = current['time'];
      DateTime end = current['endTime'] ?? start.add(const Duration(hours: 1));

      int startMins = start.hour * 60 + start.minute;
      int endMins = end.hour * 60 + end.minute;

      // 【セクターの開始境界線】を算出
      int sectorStart = 0; // 最初の授業（i == 0）なら、当日の朝 0:00 から担当開始
      if (i > 0) {
        // 前の授業の終了時刻 + 10分。ただし、この授業の開始時刻を絶対に追い越さないクランプ処理
        final prev = classItems[i - 1];
        DateTime prevStart = prev['time'];
        DateTime prevEnd = prev['endTime'] ?? prevStart.add(const Duration(hours: 1));
        int prevEndMins = prevEnd.hour * 60 + prevEnd.minute;

        sectorStart = math.min(prevEndMins + 10, startMins);
      }

      // 【セクターの終了境界線】を算出
      int sectorEnd = 1440; // 一日の最後の授業（i == 末尾）なら、深夜 24:00 まで担当を維持
      if (i < classItems.length - 1) {
        // 自身の終了時刻 + 10分。ただし、次の授業の開始時刻を絶対に追い越さないクランプ処理
        final next = classItems[i + 1];
        DateTime nextStart = next['time'];
        int nextStartMins = nextStart.hour * 60 + nextStart.minute;

        sectorEnd = math.min(endMins + 10, nextStartMins);
      }

      // ③ 現在の時刻が、この授業が支配すべきセクター内にジャストミートしたか判定
      if (nowMins >= sectorStart && nowMins < sectorEnd) {
        targetItem = current;
        break;
      }
    }

    // 安全弁：境界線の極小の隙間に落ちた場合は、当日の最終授業にホールド
    targetItem ??= classItems.last;

    return {
      'courseId': targetItem['courseId'].toString(),
      'courseName': targetItem['rawName']?.toString() ?? targetItem['title']?.toString() ?? '',
      'isCustom': targetItem['isCustom'] == true,
    };
  }

  // 🟢 追加：カメラ画面のメモテキストタップ時に起動する、全授業メモ選択用の共通ボトムシート
  // 🟢 修正：背景色スイッチ・タップ挙動分離・「対応なし」「自動判定」枠を内包した決定版カード
  // 🟢 修正：赤字・アイコンの完全撤廃、文字の拡大、極細ヘッダーへのリファイン版
  // 🟢 修正：選択中（アクティブ）の項目のみを濃く、それ以外を均一に薄くフェードさせるセレクトカード
  void _showCourseSelectionBottomSheet(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color sheetBgColor = isDark ? Colors.black : AppTheme.bg(context);
    Color baseTextColor = AppTheme.textMain(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (ctx) {
        int totalItemsCount = _displayCourses.length + 2;

        return SafeArea(
          bottom: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 24.0, top: 24.0, bottom: 12.0),
                child: Text(
                  "",
                  style: TextStyle(
                    color: baseTextColor.withOpacity(0.35),
                    fontSize: 10,
                    fontWeight: FontWeight.w200,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  itemCount: totalItemsCount,
                  itemBuilder: (context, index) {

                    // ─── ケース1：自動判定 ───
                    if (index == 0) {
                      // 🟢 現在のモードが 'auto' なら選択中（不透明度1.0）、それ以外は薄く（0.35）
                      bool isSelected = _cameraCourseMode == 'auto';

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _cameraCourseMode = 'auto';
                            _cameraManualCourseObj = null;
                          });
                          Navigator.pop(ctx);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 18.0),
                          child: Text(
                            "時間割に合わせて自動で連動",
                            style: TextStyle(
                              color: baseTextColor.withOpacity(isSelected ? 1.0 : 0.35),
                              fontSize: 17,
                              fontWeight: isSelected ? FontWeight.w400 : FontWeight.w200,
                            ),
                          ),
                        ),
                      );
                    }

                    // ─── ケース2：対応なし ───
                    if (index == 1) {
                      // 🟢 現在のモードが 'none' なら選択中（不透明度1.0）、それ以外は薄く（0.35）
                      bool isSelected = _cameraCourseMode == 'none';

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _cameraCourseMode = 'none';
                            _cameraManualCourseObj = null;
                          });
                          Navigator.pop(ctx);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 18.0),
                          child: Text(
                            "メモをとらない(画像は端末にのみ保存)",
                            style: TextStyle(
                              color: baseTextColor.withOpacity(isSelected ? 1.0 : 0.35),
                              fontSize: 17,
                              fontWeight: isSelected ? FontWeight.w400 : FontWeight.w200,
                            ),
                          ),
                        ),
                      );
                    }

                    // ─── ケース3：通常の授業リスト ───
                    final course = _displayCourses[index - 2];
                    final rawName = course['name'] ?? '';
                    final cleanTitle = CourseTitleParser.getCleanTitle(rawName);

                    // 🟢 手動選択モードであり、かつIDが完全一致している項目のみを選択中（1.0）と判定
                    bool isSelected = _cameraCourseMode == 'manual' &&
                        _cameraManualCourseObj?['courseId'] == course['id'].toString();

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _cameraCourseMode = 'manual';
                                  _cameraManualCourseObj = {
                                    'courseId': course['id'].toString(),
                                    'courseName': rawName,
                                    'isCustom': course['is_custom'] == true,
                                  };
                                });
                                Navigator.pop(ctx);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 18.0),
                                child: Text(
                                  cleanTitle,
                                  style: TextStyle(
                                    color: baseTextColor.withOpacity(isSelected ? 1.0 : 0.35),
                                    fontSize: 17,
                                    fontWeight: isSelected ? FontWeight.w400 : FontWeight.w200,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),

                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              Icons.arrow_outward_rounded,
                              // 🟢 矢印の不透明度も、その授業が選択中かどうかに合わせて美しく明暗スイッチさせます
                              color: baseTextColor.withOpacity(isSelected ? 1.0 : 0.35),
                              size: 22,
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _routeToCourse(
                                course['id'].toString(),
                                course['is_custom'] == true,
                                0,
                                null,
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 🟢 追加：割り出した授業の「今日のメモタブ」にテキストや画像をねじ込むロジック
  Future<void> _addMemoToCourse(String type, String data) async {
    final target = _getCurrentOrNextCourse();
    if (target == null) {
      // 🟢 修正：対応授業がない場合はスナックバーを出さず、そのまま静かに処理を完了します
      // （※ カメラ画像自体はこれより前にスマホ本体のGalへ正常に保存されています）
      return;
    }

    final String courseId = target['courseId']!;
    final String courseName = target['courseName']!;
    final prefs = await SharedPreferences.getInstance();

    // 授業詳細画面と全く同じキーで SharedPreferences に直接アクセス
    final String key = 'course_memos_v2_$courseId';
    final String? memoData = prefs.getString(key);

    List<Map<String, dynamic>> memos = [];
    if (memoData != null) {
      try {
        final List<dynamic> decoded = jsonDecode(memoData);
        memos = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }

    final now = DateTime.now();
    final dateStr = '${now.month.toString().padLeft(2,'0')}/${now.day.toString().padLeft(2,'0')}';

    // 1日に1つまでというルールの通り、「今日の日付」で始まるタブを探す
    int todayMemoIndex = memos.indexWhere((m) => m['title'] != null && m['title'].toString().startsWith(dateStr));

    if (todayMemoIndex == -1) {
      // まだ今日のタブがなければ新規作成（授業詳細の _createNewMemoTab と完全同一仕様）
      final filteredName = CourseTitleParser.getCleanTitle(courseName);
      final newTitle = filteredName.isNotEmpty ? '$dateStr $filteredName' : dateStr;
      memos.add({
        'id': now.millisecondsSinceEpoch.toString(),
        'title': newTitle,
        'items': <dynamic>[],
      });
      todayMemoIndex = memos.length - 1;
    }

    // アイテム（テキスト or 画像パス）を追加
    final timeStr = "${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}";
    List<dynamic> items = List<dynamic>.from(memos[todayMemoIndex]['items'] ?? []);
    items.add({
      'id': now.millisecondsSinceEpoch.toString(),
      'type': type,
      'data': data,
      'time': timeStr
    });
    memos[todayMemoIndex]['items'] = items;

    // 保存
    await prefs.setString(key, jsonEncode(memos));


  }



  // ★ 追加：D/W/Mモードで表示する外部予定を保持するキャッシュ
  Map<String, List<Map<String, dynamic>>> _externalEventsCache = {};


  // ★ 修正：元のキーに戻し、キャプチャ判定用フラグを追加（_exportCalendarKeyは削除）
  final GlobalKey _calendarKey = GlobalKey();
  bool _isCapturing = false;

  // 🟢 追加：時間表示の開閉状態を管理
  bool _isTimeVisible = true;



  // ★ 追加：授業がデフォルト色かカスタム色かを判定するヘルパーメソッド
  bool _hasCustomColor(dynamic course) {
    if (course == null) return false; // 外部予定（OSカレンダー）などはfalse
    String cId = course['is_custom'] == true ? (course['raw_name'] ?? course['name'] ?? '') : course['id'].toString();
    return _customCourseColors.containsKey(cId);
  }




  double _dragPosition = 0.0;
  ViewState _currentViewState = ViewState.home;




  late ScrollController _mainScrollController;
  late ScrollController _tasksScrollController;
  double _courseScrollOffset = 0.0;
  double _tasksScrollOffset = 0.0;




  late AnimationController _dragAnimController;




  List<Map<String, dynamic>> _weeklySchedule = [];
  List<dynamic> _displayCourses = []; // ★ 新規追加: スケジュール順に統合されたリスト
  List<dynamic> _assignments = [];
  List<dynamic> _messages = [];
  List<dynamic> _customCourses = [];
  List<dynamic> _customTasks = [];
  Map<String, int> _customCourseColors = {};




  List<String> _dismissedTaskIds = [];
  List<String> _dismissedMessageIds = [];
  List<String> _completelyDeletedMessageIds = [];




  bool _isLoadingAssignments = true;
  bool _isLoadingMessages = true;
  bool _hasApiError = false;
  bool _showCompletedTasks = false;








  int _currentCourseIndex = 0;
  int _currentSchedulePage = 10000;


  // ★ 修正：白黒点滅用のアニメーション変数を追加
  late AnimationController _colorAnimController;
  late Animation<Color?> _colorTween;
  late AnimationController _errorAnimController;
  late Animation<Color?> _errorColorTween;


  late AnimationController _spinAnimController;


  late Map<int, int> _courseIndexMap;


  // ★ 追加：スケジュールの状態変更を保存するマップ
  Map<String, Map<String, int>> _courseOverrides = {};

  Map<String, String> _courseTermOverrides = {};


  final Map<int, Map<String, int>> periods = {
    0: {'start': 900, 'end': 1030}, 1: {'start': 1045, 'end': 1215}, 2: {'start': 1300, 'end': 1430},
    3: {'start': 1445, 'end': 1615}, 4: {'start': 1630, 'end': 1800}, 5: {'start': 1815, 'end': 1945}
  };


  // 🟢 新設：不具合を検知しても即座に赤くせず、1分間の猶予を耐え抜いた場合のみ点火する
  // 🟢 修正版：猶予を5秒に短縮 ＆ ガチのログアウト時のみ赤フラグを点灯させる
  void _evaluateAlertState() {
    // ① ガチのログアウト状態（未認証）かどうか
    bool isLoggedOut = !widget.isAuthenticated;

    if (isLoggedOut) {
      if (_shouldShowRedAlert || _gracePeriodTimer != null) return;

      // ⏱️ 執行猶予を「5秒」に短縮インプラント
      _gracePeriodTimer = Timer(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() => _shouldShowRedAlert = true); // 5秒経っても未認証なら「赤点滅」を確定
          _updateAlertAnimation();
        }
      });
    } else {
      // ログイン状態が維持されているなら、通信エラー（_hasApiError）があっても赤フラグは絶対に立てない
      _gracePeriodTimer?.cancel();
      _gracePeriodTimer = null;
      if (_shouldShowRedAlert) {
        setState(() => _shouldShowRedAlert = false);
        _updateAlertAnimation();
      }
    }
  }

  void _updateAlertAnimation() {
    bool isLoading = _isLoadingAssignments || _isLoadingMessages;

    // ❌ 修正前: if (!widget.isAuthenticated || _hasApiError)
    // 🟢 修正後: 1分猶予が切れて完全にエラーが確定したフラグ（_shouldShowRedAlert）のみをトリガーにする
    if (_shouldShowRedAlert) {
      if (!_errorAnimController.isAnimating) _errorAnimController.repeat(reverse: true);
      if (_colorAnimController.isAnimating) { _colorAnimController.stop(); _colorAnimController.reset(); }
      if (_spinAnimController.isAnimating) { _spinAnimController.stop(); _spinAnimController.reset(); }
    } else if (isLoading) {
      if (_errorAnimController.isAnimating) { _errorAnimController.stop(); _errorAnimController.reset(); }
      if (!_colorAnimController.isAnimating) _colorAnimController.repeat(reverse: true);
      if (!_spinAnimController.isAnimating) _spinAnimController.repeat();
    } else {
      if (_errorAnimController.isAnimating) { _errorAnimController.stop(); _errorAnimController.reset(); }
      if (_colorAnimController.isAnimating) { _colorAnimController.stop(); _colorAnimController.reset(); }
      if (_spinAnimController.isAnimating) { _spinAnimController.stop(); _spinAnimController.reset(); }
    }
  }


  // ★ 修正：エラー時/ログアウト時、および読み込み時のアニメーションを自動制御




  // ★ 高画質スクショ＆ポスター風キャンバス合成メソッド（年度右上配置版）
  Future<void> _shareCalendarImage() async {
    // 1. スクショ前に曜日のカプセルを消すための再描画
    setState(() => _isCapturing = true);
    await Future.delayed(const Duration(milliseconds: 100)); // UI反映待ち




    try {
      RenderRepaintBoundary? boundary = _calendarKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;




      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("高画質画像を生成中..."), duration: Duration(seconds: 1)));




      // 2. カレンダーをそのまま高解像度(x4)でスクショ (背景は透過のまま)
      double pixelRatio = 4.0;
      ui.Image capturedImage = await boundary.toImage(pixelRatio: pixelRatio);




      // 3. キャンバスの準備
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);




      // 色は純粋な白と黒のみ
      bool isDark = Theme.of(context).brightness == Brightness.dark;
      Color bgColor = isDark ? Colors.black : Colors.white;
      Color textColor = isDark ? Colors.white : Colors.black;




      // 学期の英語表記変換（左上に配置する2行）
      String termLine1 = "";
      String termLine2 = "";
      String rawTerm = widget.currentTerm.toUpperCase();




      if (rawTerm.contains('春') || rawTerm.contains('前期') || rawTerm.contains('SPRING')) {
        termLine1 = 'SPRING';
        termLine2 = 'SEMESTER';
      } else if (rawTerm.contains('秋') || rawTerm.contains('後期') || rawTerm.contains('FALL')) {
        termLine1 = 'FALL';
        termLine2 = 'SEMESTER';
      } else if (rawTerm.startsWith('Q')) {
        termLine1 = 'QUARTER';
        String numPart = rawTerm.replaceAll(RegExp(r'[^0-9]'), '');
        if (numPart == '1') termLine2 = 'ONE';
        else if (numPart == '2') termLine2 = 'TWO';
        else if (numPart == '3') termLine2 = 'THREE';
        else if (numPart == '4') termLine2 = 'FOUR';
        else termLine2 = numPart;
      } else {
        termLine1 = rawTerm;
        termLine2 = 'TERM';
      }




      // 日時と曜日の英語表記変換（大文字）
      final now = DateTime.now();
      final daysEn = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];
      String dateStr = "${now.year}/${now.month.toString().padLeft(2,'0')}/${now.day.toString().padLeft(2,'0')} ${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}";
      String dayStr = daysEn[now.weekday - 1];




      // サイズ計算のベース
      double captureW = capturedImage.width.toDouble();
      double captureH = capturedImage.height.toDouble();




      // 左右の余白を極限まで小さくする（幅の2%）
      double paddingX = captureW * 0.02;




      // テキストのフォントサイズ（画面幅に対してかなり大きめ）
      double headerFontSize = captureW * 0.08;
      double footerFontSize = captureW * 0.05;




      // ★ 左上：学期テキストのサイズを事前計算
      final termPainter = TextPainter(
          text: TextSpan(
              text: "$termLine1\n$termLine2",
              style: TextStyle(color: textColor, fontSize: headerFontSize, fontWeight: FontWeight.w900, height: 1.05, letterSpacing: -1.0)
          ),
          textDirection: TextDirection.ltr
      )..layout();




      // ★ 右上：年度テキストのサイズを事前計算
      final yearPainter = TextPainter(
          text: TextSpan(
              text: "(${widget.currentYear})",
              style: TextStyle(color: textColor, fontSize: headerFontSize, fontWeight: FontWeight.w900, height: 1.05, letterSpacing: -1.0)
          ),
          textDirection: TextDirection.ltr
      )..layout();




      // フッターテキストのサイズを事前計算
      final footerPainter = TextPainter(
          text: TextSpan(
              text: "SHARED ON:\n$dateStr\n$dayStr",
              style: TextStyle(color: textColor, fontSize: footerFontSize, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -0.5)
          ),
          textDirection: TextDirection.ltr
      )..layout();




      // 余白の動的計算
      double headerGap = 12.0; // 上部文字とカレンダーの隙間
      double footerGap = 80.0; // カレンダー下部と共有日時の隙間




      // ヘッダーの高さは、左上の学期テキストか右上の年度テキストの高い方を基準にする
      double maxHeaderTextHeight = math.max(termPainter.height, yearPainter.height);
      double headerH = paddingX + maxHeaderTextHeight + headerGap;
      double footerH = footerGap + footerPainter.height + paddingX;




      double totalW = captureW + paddingX * 2;
      double totalH = headerH + captureH + footerH;




      // 4. 背景全体を白か黒で塗りつぶす
      canvas.drawRect(Rect.fromLTWH(0, 0, totalW, totalH), Paint()..color = bgColor);




      // 5. ヘッダーテキスト描画
      // 左上：学期
      termPainter.paint(canvas, Offset(paddingX, paddingX));
      // 右上：年度 (右端から paddingX とテキスト幅を引いた位置)
      yearPainter.paint(canvas, Offset(totalW - paddingX - yearPainter.width, paddingX));




      // 6. 透過カレンダースクショをキャンバスに貼り付け
      canvas.drawImage(capturedImage, Offset(paddingX, headerH), Paint());




      // 7. フッターテキスト描画（左下詰め・3行）
      footerPainter.paint(canvas, Offset(paddingX, headerH + captureH + footerGap));




      // 8. 画像化して保存・共有
      final compositePicture = recorder.endRecording();
      final compositeImage = await compositePicture.toImage(totalW.toInt(), totalH.toInt());
      final byteData = await compositeImage.toByteData(format: ui.ImageByteFormat.png);




      if (byteData == null) return;
      final Uint8List pngBytes = byteData.buffer.asUint8List();




      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/calendar_export.png').create();
      await file.writeAsBytes(pngBytes);

      final box = context.findRenderObject() as RenderBox?;
      final rect = box != null ? box.localToGlobal(Offset.zero) & box.size : null;

      await Share.shareXFiles(
        [XFile(file.path)],
        text: "${widget.currentYear} $termLine1 Schedule",
        sharePositionOrigin: rect, // 👈 これでiPadでも絶対に落ちなくなります
      );
      // ★ 追加：共有ダイアログが閉じた後、一時ファイルを削除してストレージを解放
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}

    } finally {
      // 最後にカプセルを元に戻す
      if (mounted) setState(() => _isCapturing = false);
    }
  }




  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _mainScrollController = ScrollController();
    _mainScrollController.addListener(_onMainScroll);

    _tasksScrollController = ScrollController();
    _tasksScrollController.addListener(_onTasksScroll);

    _schedulePageController = PageController(initialPage: _currentSchedulePage);
    _taskPageController = PageController(initialPage: _showCompletedTasks ? 1 : 0);

    _colorAnimController = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _errorAnimController = AnimationController(duration: const Duration(milliseconds: 400), vsync: this);
    _spinAnimController = AnimationController(duration: const Duration(seconds: 1), vsync: this);

    _cameraCaptureAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // 🟢 修正：下限値を -1.0 に拡張して、左側へのカメラスワイプゾーンを確保
    _dragAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
      lowerBound: -1.0,
      upperBound: 1.0,
      value: 0.0, // 👈 この1行を確実に追加
    );

    // 🟢 修正：スワイプ位置と連動して、カメラの自動初期化 / 破棄、およびステータスバーを滑らかに隠す
    // 🟢 修正：指の移動中に、起動条件を満たしている最初の1回「だけ」安全に命令を通すようにロジックを最適化
    // 🟢 修正：伸縮アニメーションとカメラ起動を完全に分離します
    _dragAnimController.addListener(() {
      setState(() {
        _dragPosition = _dragAnimController.value;

        // 🟢 指で動かしている最中はカメラを一切動かさず、完全に左画面（-1.0）に到達した瞬間のみ起動トリガーを引く
        if (_dragPosition == -1.0) {
          if (!_isCamInitialized && !_isCamInitializing) {
            _initInlineCamera();
          }
        }
        // 中央面（0.0以上）側へ引き返し始めたら、即座にリソースを解放してホームの軽さを維持
        else if (_dragPosition >= 0.0 && (_isCamInitialized || _isCamInitializing)) {
          _disposeInlineCamera();
        }

        if (_dragPosition < -0.9) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        } else {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
      });
    });

    _loadDismissedIds(); _loadCustomData(); _buildCourseIndexMap(); _fetchDataParallel();
    _prepareAvailableCameras(); // 🟢 カメラハードウェアの事前ロード

    _startAutoRefreshTimer();

    _updateAlertAnimation();

    int initialPage = _findBestCourseIndex();
    _currentCourseIndex = initialPage;
    _coursesWidgetController = PageController(initialPage: initialPage, viewportFraction: 1.0);
  }

  @override void dispose() {
    WidgetsBinding.instance.removeObserver(this); // 🟢 解除：メモリリークを100%完全遮断
    _autoRefreshTimer?.cancel();                  // 🟢 停止：裏タイマーを安全に消滅させる
    _cameraCaptureAnimController.dispose(); // 🟢 追加：リソースの安全解放
    _cameraController?.dispose();
    _colorAnimController.dispose();
    _errorAnimController.dispose();
    _spinAnimController.dispose();
    _mainScrollController.dispose();
    _tasksScrollController.dispose();
    _dragAnimController.dispose();
    if (_schedulePageController.hasClients) { _schedulePageController.dispose(); }
    if (_taskPageController.hasClients) { _taskPageController.dispose(); }
    super.dispose();
  }










  void _onMainScroll() { if (_mainScrollController.hasClients) { setState(() { _courseScrollOffset = math.max(0.0, _mainScrollController.offset); }); } }




  void _onTasksScroll() {
    if (_dragPosition < 0.5 && _tasksScrollController.hasClients) {
      setState(() {
        _tasksScrollOffset = math.max(0.0, _tasksScrollController.offset);
      });
    }
  }




  Future<void> _loadDismissedIds() async { final prefs = await SharedPreferences.getInstance(); setState(() { _dismissedTaskIds = prefs.getStringList('dismissed_tasks_v10') ?? []; _dismissedMessageIds = prefs.getStringList('dismissed_messages_v10') ?? []; _completelyDeletedMessageIds = prefs.getStringList('deleted_messages_v10') ?? []; }); }
  // ★ 修正：_courseOverrides の読み込みを追加
  Future<void> _loadCustomData() async {
    final prefs = await SharedPreferences.getInstance();
    final cStr = prefs.getString('custom_courses_v10');
    final tStr = prefs.getString('custom_tasks_v10');
    final colStr = prefs.getString('custom_course_colors_v10');
    final overStr = prefs.getString('course_overrides_v10');
    if (cStr != null) _customCourses = jsonDecode(cStr);
    if (tStr != null) _customTasks = jsonDecode(tStr);
    if (colStr != null) _customCourseColors = Map<String, int>.from(jsonDecode(colStr));
    if (overStr != null) {
      Map<String, dynamic> decoded = jsonDecode(overStr);
      _courseOverrides = decoded.map((k, v) => MapEntry(k, Map<String, int>.from(v)));
    }

    // 👇 変数名を termDataStr2 に変更 👇
    final taskOverStr = prefs.getString('task_due_overrides_v10');
    if (taskOverStr != null) {
      _taskDueOverrides = Map<String, String>.from(jsonDecode(taskOverStr));
    }
    // 👆 追加ここまで 👆

    _generateWeeklySchedule();
  }
  Future<void> _saveCustomData() async { final prefs = await SharedPreferences.getInstance(); await prefs.setString('custom_courses_v10', jsonEncode(_customCourses)); await prefs.setString('custom_tasks_v10', jsonEncode(_customTasks)); await prefs.setString('custom_course_colors_v10', jsonEncode(_customCourseColors)); }
  Future<void> _saveDismissedTasks() async { final prefs = await SharedPreferences.getInstance(); await prefs.setStringList('dismissed_tasks_v10', _dismissedTaskIds); }
  Future<void> _saveDismissedMessages() async { final prefs = await SharedPreferences.getInstance(); await prefs.setStringList('dismissed_messages_v10', _dismissedMessageIds); await prefs.setStringList('deleted_messages_v10', _completelyDeletedMessageIds); }




  void _buildCourseIndexMap() { _courseIndexMap = {}; for (int i = 0; i < widget.courses.length; i++) { _courseIndexMap[widget.courses[i]['id']] = i; } }




  // ★ 新規追加：すべての授業（Canvas＋カスタム）を統合したリストを生成
  List<dynamic> _getAllDisplayCourses() {
    List<dynamic> list = List.from(widget.uniqueCourses);
    Map<String, dynamic> mergedMap = {};
    for (var c in _customCourses) {
      String rawName = c['name'] ?? '';
      if (!mergedMap.containsKey(rawName)) { mergedMap[rawName] = { 'id': c['id'], 'name': rawName, 'raw_name': rawName, 'is_custom': true, 'schedule_list': <String>[], 'rooms': <String>{}, }; }
      if (c['room'] != null && c['room'].toString().isNotEmpty) { mergedMap[rawName]['rooms'].add(c['room']); }
      if (c['is_weekly'] == true) { String dStr = ['MON','TUE','WED','THU','FRI','SAT'][c['day']]; String pStr = (c['period'] + 1).toString(); mergedMap[rawName]['schedule_list'].add('$dStr $pStr'); } else { DateTime d = DateTime.tryParse(c['date']) ?? DateTime.now(); String dStr = '${d.month}/${d.day}'; String pStr = (c['period'] + 1).toString(); mergedMap[rawName]['schedule_list'].add('$dStr $pStr'); }
    }
    List<dynamic> customList = mergedMap.values.map((m) { String sch = m['schedule_list'].join(' / '); String rms = m['rooms'].join(' / '); return { 'id': m['id'], 'name': '${m['name']} [$sch] ${rms.isNotEmpty ? '[$rms]' : ''}'.trim(), 'raw_name': m['name'], 'is_custom': true }; }).toList();
    list.addAll(customList);
    return list;
  }






// ★ 修正：_getAllDisplayCourses を削除し、色判定を _displayCourses の並びに完全一致させる
  // ★ 修正：ダークモード時も幅広い色域（黒から白）のグラデーションにする
  Color _getCourseColor(dynamic course) {
    if (course == null) return AppTheme.panel(context);

    // カスタム色が設定されているかチェック
    String cId = course['is_custom'] == true ? (course['raw_name'] ?? course['name'] ?? '') : course['id'].toString();
    if (_customCourseColors.containsKey(cId)) {
      return Color(_customCourseColors[cId]!);
    }

    // スケジュール順のリスト（_displayCourses）の中でのインデックスを取得
    int idx = _displayCourses.indexWhere((c) {
      String thisId = c['is_custom'] == true ? (c['raw_name'] ?? c['name'] ?? '') : c['id'].toString();
      return thisId == cId;
    });
    if (idx == -1) idx = 0;

    int total = math.max(1, _displayCourses.length);
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    // ★ 幅広いグレーの色域を定義
    Color lightGrey = const Color(0xFFE0E0E0); // ほぼ白
    Color darkGrey = const Color(0xFF1A1A1A);  // ほぼ黒

    if (total <= 1) {
      return isDark ? darkGrey : lightGrey;
    }

    double ratio = idx / (total - 1);

    if (!isDark) {
      // --- ライトモード ---
      // 白（上）から 黒（下）へ
      return Color.lerp(lightGrey, darkGrey, ratio)!;
    } else {
      // --- ダークモード ---
      // 黒（上）から 白（下）へ
      return Color.lerp(darkGrey, lightGrey, ratio)!;
    }
  }


  // ★ 修正：RefreshIndicatorで待機できるよう Future を返す非同期関数に変更
  // ─── _DashboardPageState 内の _fetchDataParallel メソッド ───

  Future<void> _fetchDataParallel() async {
    _lastFetchTime = DateTime.now();

    if (mounted) {
      setState(() {
        _hasApiError = false;
        _isLoadingAssignments = true;
        _isLoadingMessages = true;
        // ⚡ 追記：通信開始時は一旦赤点滅の確定を保留し、猶予タイマーをリセット
        _gracePeriodTimer?.cancel();
        _gracePeriodTimer = null;
        _shouldShowRedAlert = false;
      });
      _updateAlertAnimation();
    }

    // 両方の通信が終わるまで待記
    await Future.wait([
      _fetchAssignments(),
      _fetchMessages()
    ]);

    // 🟢 追記：すべての並列通信が完了したタイミングで、状態を厳密に評価して1分タイマーの判定へ回す
    if (mounted) {
      _evaluateAlertState();
    }

    try {
      await LiveNotificationService.reScheduleLiveNotifications(
        currentCourses: _displayCourses,
        currentAssignments: _assignments,
      );
      debugPrint("ライブカウントダウン通知のアラームを正常再予約しました");
    } catch (e) {
      debugPrint("ライブ通知の予約中にエラーが発生しました: $e");
    }
  }


  void _triggerErrorState() {
    if (!mounted) return;
    if (!_hasApiError) { setState(() => _hasApiError = true); _updateAlertAnimation(); }
  }
  int _findBestCourseIndex() {
    if (_weeklySchedule.isEmpty) return 0;
    final now = DateTime.now(); int currentDay = now.weekday - 1; if (currentDay > 5) currentDay = 0; int currentTime = now.hour * 100 + now.minute;
    for (int i = 0; i < _weeklySchedule.length; i++) { var item = _weeklySchedule[i]; if (item['day'] == currentDay) { var p = periods[item['period']]!; if (currentTime >= p['start']! && currentTime <= p['end']!) return i; } }
    for (int i = 0; i < _weeklySchedule.length; i++) { var item = _weeklySchedule[i]; if (item['day'] == currentDay && periods[item['period']]!['start']! > currentTime) return i; }
    for (int d = 1; d <= 7; d++) { int nextDay = (currentDay + d) % 6; for (int i = 0; i < _weeklySchedule.length; i++) { if (_weeklySchedule[i]['day'] == nextDay) return i; } }
    return 0;
  }


  void _generateWeeklySchedule() {
    List<Map<String, dynamic>> flatList = [];
    for (var course in widget.courses) {
      final name = course['name'] ?? '';
      final schedules = currentLMS.parseWeeklySchedule(name);
      for (var s in schedules) {
        flatList.add({'course': course, 'day': s['day']!, 'period': s['period']!});
      }
    }
    // （ここから下の for (var custom in _customCourses) {...} はそのまま残す）
    for (var custom in _customCourses) {
      if (custom['is_weekly'] == true) {
        String dStr = ['月','火','水','木','金','土'][custom['day']]; String pStr = (custom['period'] + 1).toString();
        flatList.add({'course': {'id': custom['id'], 'name': '${custom['name']} [$dStr$pStr] [${custom['room']}]', 'raw_name': custom['name'], 'is_custom': true}, 'day': custom['day'], 'period': custom['period']});
      }
    }
    flatList.sort((a, b) => (a['day'] as int) == (b['day'] as int) ? (a['period'] as int).compareTo(b['period'] as int) : (a['day'] as int).compareTo(b['day'] as int));


    // ★ 追加：生成したスケジュール順のリストから、カード表示用の統合リストを作成
    List<dynamic> display = [];
    Set<String> seen = {};


    for (var item in flatList) {
      var c = item['course'];
      String identifier = c['is_custom'] == true ? c['raw_name'] : c['id'].toString();
      if (!seen.contains(identifier)) {
        seen.add(identifier);
        display.add(c);
      }
    }


    // スケジュールに含まれない一般授業を追加
    for (var c in widget.uniqueCourses) {
      String identifier = c['id'].toString();
      if (!seen.contains(identifier)) {
        seen.add(identifier);
        display.add(c);
      }
    }


    // スケジュールに含まれないカスタム授業を追加
    for (var c in _customCourses) {
      String identifier = c['name'] ?? '';
      if (!seen.contains(identifier)) {
        seen.add(identifier);
        display.add({'id': c['id'], 'name': c['name'], 'raw_name': c['name'], 'is_custom': true});
      }
    }


    if (mounted) setState(() {
      _weeklySchedule = flatList;
      _displayCourses = display;
    });
    CalendarSyncService.syncSchedules(display, widget.currentYear, widget.currentTerm);

    // 🟢 追加：時間割の最終確定・並び替えが終わった瞬間にウィジェットへ射出
    WidgetUpdateService.updateHomeWidgets(courses: display);
  }


  Future<void> _fetchAssignments() async {

    try {
      // キャッシュキーを新しくし、クリーンな状態で全取得させる
      final cached = await CacheManager.load('cached_assignments_v14_all_year');
      if (cached != null && mounted) {
        setState(() {
          _assignments = cached;
        });
      }

      if (widget.cookie.isEmpty || widget.allCourses.isEmpty) return;

      // ★ 追加：テストログイン中は本番APIの走査をスキップして早期リターン
      if (widget.cookie == "dummy_test_session") {
        if (mounted) setState(() { _isLoadingAssignments = false; });
        return;
      }

      List<dynamic> tasks = [];

      // ★ 解決の鍵：Q1/Q2に関係なく、今年度のLMS授業をすべて抽出
      final thisYearCourses = widget.allCourses.where((c) {
        if (c['is_custom'] == true) return false;
        return _isCurrentYearCourse(c);
      }).toList();

      for (var course in thisYearCourses) {
        if (!mounted) return;

        final uri = Uri.tryParse('$canvasBaseUrl/api/v1/courses/${course['id']}/assignments?per_page=40&include[]=submission');
        if (uri == null) continue;

        final res = await http.get(uri, headers: {'Cookie': widget.cookie}).timeout(const Duration(seconds: 15));

        if (!mounted) return;

        if (res.statusCode == 200) {
          for (var task in jsonDecode(res.body)) {

            // ❌ 修正前: if (dueAtStr != null && dueAtStr.toString().isNotEmpty) {
            // 🟢 修正後: 条件を撤廃し、期日未定の課題もすべてサルベージします
            task['context_name'] = course['name'];
            task['course_id'] = course['id'];

            // 純正の期日をバックアップ
            task['original_due_at'] = task['due_at'];

            // 過去の上書き履歴があれば適用
            final tId = task['id']?.toString();
            if (tId != null && _taskDueOverrides.containsKey(tId)) {
              task['due_at'] = _taskDueOverrides[tId];
            }
            tasks.add(task);
          }
        } else if (res.statusCode == 403 || res.statusCode == 401) {
          // 課題機能がオフの授業や過去の授業はスルーする
          continue;
        } else if (res.statusCode == 429) {
          // リクエスト過多の場合は少し休む
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }

        await Future.delayed(const Duration(milliseconds: 150));
      }

      final Map<String, dynamic> uniqueTasks = {};
      for (var task in tasks) { uniqueTasks[task['id']?.toString() ?? task.hashCode.toString()] = task; }
      List<dynamic> finalTasks = uniqueTasks.values.toList();
      finalTasks.addAll(_customTasks);
      finalTasks.sort((a, b) => (DateTime.tryParse(a['due_at'] ?? '') ?? DateTime.now()).compareTo(DateTime.tryParse(b['due_at'] ?? '') ?? DateTime.now()));

      await CacheManager.save('cached_assignments_v14_all_year', finalTasks);
      if (mounted) setState(() { _assignments = finalTasks; });
      CalendarSyncService.syncTasks(finalTasks);

      await WidgetUpdateService.updateHomeWidgets(tasks: finalTasks);

    } catch (e) {
      debugPrint("Dashboard._fetchAssignments Error: $e");
      _triggerErrorState();
    } finally {
      if (mounted) {
        // ❌ 修正前: setState(() { _isLoadingAssignments = false; _hasApiError = false; });
        // 🟢 修正後: エラーの誤爆上書きを削除し、純粋にローディングのみを落とす
        setState(() { _isLoadingAssignments = false; });
        _updateAlertAnimation();
      }
    }
  }

  Future<void> _fetchMessages() async {
    try {
      final cached = await CacheManager.load('cached_messages_v14_all_year');
      if (cached != null && mounted) {
        setState(() {
          _messages = cached;
        });
      }

      if (widget.cookie.isEmpty || widget.allCourses.isEmpty) return;

      // ★ 追加：テストログイン中は本番APIの走査をスキップして早期リターン
      if (widget.cookie == "dummy_test_session") {
        if (mounted) setState(() { _isLoadingMessages = false; });
        return;
      }

      List<dynamic> msgs = [];

      final thisYearCourses = widget.allCourses.where((c) {
        if (c['is_custom'] == true) return false;
        return _isCurrentYearCourse(c);
      }).toList();

      for (var course in thisYearCourses) {
        if (!mounted) return;

        final uri = Uri.tryParse('$canvasBaseUrl/api/v1/courses/${course['id']}/discussion_topics?only_announcements=true&per_page=15');
        if (uri == null) continue;

        final res = await http.get(uri, headers: {'Cookie': widget.cookie}).timeout(const Duration(seconds: 15));

        if (!mounted) return;

        if (res.statusCode == 200) {
          for (var m in jsonDecode(res.body)) {
            m['context_name'] = course['name'];
            m['course_id'] = course['id'];
            msgs.add(m);
          }
        } else if (res.statusCode == 403 || res.statusCode == 401) {
          continue;
        } else if (res.statusCode == 429) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }

        await Future.delayed(const Duration(milliseconds: 150));
      }

      msgs.sort((a, b) {
        final da = DateTime.tryParse(a['posted_at'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db = DateTime.tryParse(b['posted_at'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });
      await CacheManager.save('cached_messages_v14_all_year', msgs);
      if (mounted) setState(() { _messages = msgs; });

    } catch (e) {
      debugPrint("Dashboard._fetchMessages Error: $e");
      _triggerErrorState();
    } finally {
      if (mounted) {
        // ❌ 修正前: setState(() { _isLoadingMessages = false; _hasApiError = false; });
        // 🟢 修正後: 同様に誤爆を削除
        setState(() { _isLoadingMessages = false; });
        _updateAlertAnimation();
      }
    }
  }




  Future<void> _syncCustomTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final tStr = prefs.getString('custom_tasks_v10');
    if (tStr != null) {
      try {
        _customTasks = jsonDecode(tStr);
        _assignments.removeWhere((t) => t['is_app_custom_task'] == true || t['course_id'] == 'custom_t');
        _assignments.addAll(_customTasks);
        _assignments.sort((a, b) => (DateTime.tryParse(a['due_at'] ?? '') ?? DateTime.now()).compareTo(DateTime.tryParse(b['due_at'] ?? '') ?? DateTime.now()));
        if (mounted) setState((){});
      } catch(e) {}
    }
  }


  // ★ 修正：ステータス（休講・テスト等）を判定してスケジュールを生成
  // ★ 修正：ステータス（休講・テスト等）と、月ごとの学期期間を判定してスケジュールを生成
  List<Map<String, dynamic>> _getScheduleForDate(DateTime targetDate) {
    List<Map<String, dynamic>> combined = [];
    int dayIdx = targetDate.weekday - 1;
    String dateStr = "${targetDate.year}-${targetDate.month.toString().padLeft(2,'0')}-${targetDate.day.toString().padLeft(2,'0')}";

    int month = targetDate.month;

    // ===================================
    // 1. 通常の授業
    // ===================================
    if (dayIdx <= 5) {
      final classes = _weeklySchedule.where((s) => s['day'] == dayIdx).toList();
      for (var c in classes) {
        String targetQ = TermHelper.getTermForDate(targetDate);

        int targetYear = targetDate.year;
        if (targetDate.month < 4) targetYear -= 1;

        if (!TermHelper.shouldDisplayCourse(c['course'], _courseTermOverrides, targetYear, targetQ)) {
          continue;
        }

        String cId = c['course']['is_custom'] == true ? (c['course']['raw_name'] ?? c['course']['name']) : c['course']['id'].toString();
        int status = _courseOverrides[cId]?[dateStr] ?? 0;
        if (status == 2) continue;

        int startHour = periods[c['period']]!['start']! ~/ 100;
        int startMin = periods[c['period']]!['start']! % 100;
        int endHour = periods[c['period']]!['end']! ~/ 100;
        int endMin = periods[c['period']]!['end']! % 100;

        DateTime classTime = DateTime(targetDate.year, targetDate.month, targetDate.day, startHour, startMin);
        DateTime classEndTime = DateTime(targetDate.year, targetDate.month, targetDate.day, endHour, endMin);

        combined.add({'type': 'class', 'time': classTime, 'endTime': classEndTime, 'title': currentLMS.cleanTitle(c['course']['name']), 'subtitle': currentLMS.extractRoom(c['course']['name']), 'courseId': c['course']['id'], 'isCustom': c['course']['is_custom'] == true, 'rawName': c['course']['raw_name'], 'courseObj': c['course'], 'status': status});
      }
    }

    // ===================================
    // 2. カスタム授業（単発など）
    // ===================================
    for (var cc in _customCourses.where((c) => c['is_weekly'] == false && c['date'] != null)) {
      DateTime cDate = DateTime.tryParse(cc['date']) ?? DateTime.now();
      if (cDate.year == targetDate.year && cDate.month == targetDate.month && cDate.day == targetDate.day) {
        String cId = cc['name'] ?? '';
        int status = _courseOverrides[cId]?[dateStr] ?? 0;
        if (status == 2) continue;

        int startHour = periods[cc['period']]!['start']! ~/ 100;
        int startMin = periods[cc['period']]!['start']! % 100;
        int endHour = periods[cc['period']]!['end']! ~/ 100;
        int endMin = periods[cc['period']]!['end']! % 100;

        DateTime classTime = DateTime(targetDate.year, targetDate.month, targetDate.day, startHour, startMin);
        DateTime classEndTime = DateTime(targetDate.year, targetDate.month, targetDate.day, endHour, endMin);

        combined.add({'type': 'class', 'time': classTime, 'endTime': classEndTime, 'title': cc['name'], 'subtitle': cc['room'], 'courseId': cc['id'], 'isCustom': true, 'rawName': cc['name'], 'courseObj': cc, 'status': status});
      }
    }

    // ===================================
    // 3. 課題（タスク）
    // ===================================
    // 🟢 LMS情報は元々正常なので、_filterTasks内でJST変換されたdueの年月日がページと一致するかだけで綺麗に仕分けます
    final tasksForDay = _filterTasks((due) => due.year == targetDate.year && due.month == targetDate.month && due.day == targetDate.day);

    for (var t in tasksForDay) {
      DateTime dueTime = DateTime.tryParse(t['due_at'] ?? '')?.toLocal() ?? DateTime.now();
      combined.add({
        'type': 'task',
        'time': dueTime,
        'endTime': dueTime.add(const Duration(minutes: 30)),
        'title': t['name'] ?? 'Task',
        'subtitle': currentLMS.cleanTitle(t['context_name'] ?? ''),
        'courseId': t['course_id'],
        'taskId': t['id'].toString(),
        'targetUrl': t['html_url'] ?? t['url'] ?? '',
        'courseObj': {'id': t['course_id'], 'is_custom': t['course_id'] == 'custom_t'}
      });
    }

    combined.sort((a, b) => (a['time'] as DateTime).compareTo(b['time'] as DateTime));
    return combined;
  }

  // ★ 修正：外部予定の数も含めてカレンダーの高さを正確に計算する
  double _getScheduleHeight(int pageIndex, double topPadding) {
    int offset = pageIndex - 10000;
    DateTime now = DateTime.now();

    if (_scheduleMode == 'W') {
      DateTime currentMonday = now.subtract(Duration(days: now.weekday - 1));
      DateTime targetWeek = currentMonday.add(Duration(days: offset * 7));

      int minHour = 24;
      int maxHour = 0;

      for (int i = 0; i < 7; i++) {
        DateTime d = targetWeek.add(Duration(days: i));
        List<Map<String, dynamic>> appEvents = _getScheduleForDate(d).where((item) => item['status'] != 2).toList();
        String dateKey = "${d.year}-${d.month}-${d.day}";
        List<Map<String, dynamic>> ext = _externalEventsCache[dateKey] ?? [];

        for (var item in [...appEvents, ...ext]) {
          if (item['isAllDay'] == true) continue;
          DateTime st = item['time'];
          DateTime et = item['endTime'] ?? st.add(const Duration(hours: 1));
          if (st.hour < minHour) minHour = st.hour;
          // ★ 修正：終了時間の時間を厳密に取る（分が1でもあれば次の時間まで枠を広げる）
          if (et.hour + (et.minute > 0 ? 1 : 0) > maxHour) maxHour = et.hour + (et.minute > 0 ? 1 : 0);
        }
      }

      if (minHour > maxHour) {
        minHour = 9; maxHour = 18;
      } else {
        minHour = math.max(0, minHour - 1);
        maxHour = math.min(24, maxHour + 1);
      }

      double pixelsPerMinute = 0.5;
      double timelineHeight = (maxHour - minHour) * 60 * pixelsPerMinute;
      // ★ 修正：バッファを増やして見切れを防止（+ 60.0）
      return topPadding + 48.0 + timelineHeight + 60.0;

    } else if (_scheduleMode == 'M') {
      DateTime targetMonth = DateTime(now.year, now.month + offset, 1);
      DateTime startDate = targetMonth.subtract(Duration(days: targetMonth.weekday - 1));

      int daysInMonth = DateTime(targetMonth.year, targetMonth.month + 1, 0).day;
      int numWeeks = ((targetMonth.weekday - 1 + daysInMonth) / 7.0).ceil();

      double totalWeeksHeight = 0.0;
      double headerHeight = 54.0;

      for (int weekIdx = 0; weekIdx < numWeeks; weekIdx++) {
        int maxItemsInThisWeek = 0;
        for (int dayIdx = 0; dayIdx < 7; dayIdx++) {
          DateTime currentDay = startDate.add(Duration(days: weekIdx * 7 + dayIdx));
          // ★ タスクを含めた数をカウントする
          int appItemCount = _getScheduleForDate(currentDay).where((item) => item['status'] != 2).length;

          String dateKey = "${currentDay.year}-${currentDay.month}-${currentDay.day}";
          int externalCount = (_externalEventsCache[dateKey] ?? []).length;
          if (externalCount > 3) externalCount = 3;

          if (appItemCount + externalCount > maxItemsInThisWeek) {
            maxItemsInThisWeek = appItemCount + externalCount;
          }
        }
        double dayLabelHeight = 24.0;
        double itemsHeight = maxItemsInThisWeek * 12.0;
        double weekHeight = dayLabelHeight + itemsHeight + 6.0;
        totalWeeksHeight += weekHeight;
      }
      return topPadding + 48.0 + headerHeight + totalWeeksHeight + 8.0 + 4.0;
    }

    // Dモード
    // --- メソッドの最下部、Dモードのロジック部分を以下に差し替え ---
    // Dモード
    DateTime date = now.add(Duration(days: offset));
    final items = _getScheduleForDate(date);

    // 🟢 決定打：_buildDayPageと完全に足並みを揃え、
    // 前後3日分のプールから「純粋に日本時間の当日に表示される外部予定」の正確な個数を割り出します。
    final DateTime prevDate = date.subtract(const Duration(days: 1));
    final DateTime nextDate = date.add(const Duration(days: 1));

    List<Map<String, dynamic>> rawExternalPool = [
      ...(_externalEventsCache["${prevDate.year}-${prevDate.month}-${prevDate.day}"] ?? []),
      ...(_externalEventsCache["${date.year}-${date.month}-${date.day}"] ?? []),
      ...(_externalEventsCache["${nextDate.year}-${nextDate.month}-${nextDate.day}"] ?? []),
    ];

    int correctedExternalCount = 0;
    Set<String> seenEvents = {};

    for (var item in rawExternalPool) {
      DateTime localTime = (item['time'] as DateTime).toLocal();
      if (localTime.year == date.year && localTime.month == date.month && localTime.day == date.day) {
        String eventKey = "${item['title']}_${localTime.millisecondsSinceEpoch}";
        if (!seenEvents.contains(eventKey)) {
          seenEvents.add(eventKey);
          correctedExternalCount++; // 実際にこの日に描画されるものだけをインクリメント
        }
      }
    }

    // 授業・タスク数 ＋ 厳選された外部予定数
    int totalItems = items.length + correctedExternalCount;

    double baseHeight = topPadding + 48.0 + 20.0 + 8.0;
    if (totalItems == 0) return baseHeight + 32.0;
    return baseHeight + (totalItems * 56.0);
  }

  // ★ 追加：特定の日付をタップした時にDモードへ遷移させるメソッド
  // ★ 修正：特定の日付をタップした時にDモードへ遷移させるメソッド
  void _switchToDayMode(DateTime targetDate) {
    DateTime now = DateTime.now();
    // 時分秒を無視して純粋な「日数差」を計算する
    DateTime today = DateTime.utc(now.year, now.month, now.day);
    DateTime target = DateTime.utc(targetDate.year, targetDate.month, targetDate.day);
    int diffDays = target.difference(today).inDays;

    setState(() {
      _scheduleMode = 'D';
      _currentSchedulePage = 10000 + diffDays;

      // ★ ここが解決の鍵：PageViewが再構築されるため、PageControllerも新しく作り直す
      final oldController = _schedulePageController;
      _schedulePageController = PageController(initialPage: _currentSchedulePage);
      // 古いコントローラーは安全に破棄
      Future.delayed(Duration.zero, () => oldController.dispose());

      if (_tasksScrollController.hasClients) {
        _tasksScrollController.jumpTo(0.0);
        _tasksScrollOffset = 0.0;
      }
    });
  }

  // ★ 追加：特定の日付の外部予定を非同期で取得してUIを更新する
  Future<void> _fetchExternalEventsForDate(DateTime date) async {
    String dateKey = "${date.year}-${date.month}-${date.day}";
    if (_externalEventsCache.containsKey(dateKey)) return;

    final events = await CalendarSyncService.getDeviceEventsForDate(date);
    if (mounted) {
      setState(() {
        _externalEventsCache[dateKey] = events;
      });
    }
  }

  // ★ 追加：今年度の授業かどうかを文字列から確実に判定するメソッド
  bool _isCurrentYearCourse(dynamic courseObj) {
    if (courseObj == null) return false;
    String cName = (courseObj['name'] ?? '').toString();
    String tName = (courseObj['term']?['name'] ?? '').toString();
    String combined = "$cName $tName".toUpperCase();

    // 現在の年度（例: 2026）が含まれていれば即「今年度」
    if (combined.contains(widget.currentYear.toString())) return true;

    // 過去や未来の年度が明記されている場合は弾く
    for (int y = 2020; y <= 2030; y++) {
      if (y != widget.currentYear && combined.contains(y.toString())) {
        return false;
      }
    }

    // 年度の記載がないもの（通年授業など）は今年度とみなす
    return true;
  }


  List<dynamic> _filterTasks(bool Function(DateTime due) condition, {bool wantCompleted = false}) {
    return _assignments.where((t) {
      if (_dismissedTaskIds.contains(t['id'].toString())) return false;

      bool isCompleted = false;
      bool isCustomTask = t['course_id'] == 'custom_t' || t['is_app_custom_task'] == true;

      if (isCustomTask) {
        isCompleted = t['is_completed'] == true;
      } else {
        final sub = t['submission'];
        isCompleted = sub != null && (sub['workflow_state'] == 'submitted' || sub['workflow_state'] == 'graded' || sub['workflow_state'] == 'graded_excused');
      }

      if (wantCompleted && !isCompleted) return false;
      if (!wantCompleted && isCompleted) return false;

      final dueStr = t['due_at'];
      if (dueStr == null || dueStr.toString().isEmpty) return false;
      final due = DateTime.tryParse(dueStr)?.toLocal();
      if (due == null) return false;
      if (!condition(due)) return false;

      if (!isCustomTask) {
        int courseId = t['course_id'];

        var courseObj = widget.allCourses.firstWhere(
                (c) => c['id'] == courseId,
            orElse: () => null
        );

        if (courseObj == null) return false;

        // ★ Q1/Q2に関係なく「今年度」の課題をすべて表示
        if (!_isCurrentYearCourse(courseObj)) return false;
      }

      return true;
    }).toList();
  }

  // 🟢 追加：期日の設定がない課題だけを「未提出/提出済」に分けて綺麗に抜き出す関数
  List<dynamic> _filterNoDueTasks({required bool wantCompleted}) {
    return _assignments.where((t) {
      if (_dismissedTaskIds.contains(t['id'].toString())) return false;

      // 1. 期日（due_at）が null または空文字のものだけを対象にする
      final dueStr = t['due_at'];
      if (dueStr != null && dueStr.toString().isNotEmpty) return false;

      // 2. 提出状態の判定
      bool isCompleted = false;
      if (t['course_id'] == 'custom_t' || t['is_app_custom_task'] == true) {
        isCompleted = t['is_completed'] == true;
      } else {
        final sub = t['submission'];
        isCompleted = sub != null && (sub['workflow_state'] == 'submitted' || sub['workflow_state'] == 'graded' || sub['workflow_state'] == 'graded_excused');
      }

      return wantCompleted ? isCompleted : !isCompleted;
    }).toList();
  }


  List<dynamic> _filterMessages(bool Function(dynamic msg) condition) { return _messages.where((m) { if (_completelyDeletedMessageIds.contains(m['id'].toString())) return false; return condition(m); }).toList(); }




  // ★ 修正：一貫したスケジュール順の _displayCourses を詳細画面へ渡す
  // 🟢 修正：カメラ自動パージ ＆ 復帰時ホーム強制送還シールド付き統合ルーター
  // 🟢 修正：詳細を開いた瞬間にホーム（0.0）へ位置を完全リセットする仕様
  // 🟢 修正：遷移中は -1.0 を維持し、開ききった瞬間に 0.0 へステルスリセットするルーター
  void _routeToCourse(String identifier, bool isCustom, int bottomIdx, String? taskId) {
    String heroTag = 'top_widget_hero';
    final allCourses = _displayCourses;
    int cIdx = allCourses.indexWhere((c) {
      if (isCustom) return (c['raw_name'] ?? c['name']) == identifier && c['is_custom'] == true;
      return c['id'].toString() == identifier && c['is_custom'] != true;
    });
    if (cIdx == -1) cIdx = 0;

    // 現在カメラ画面（左画面）に完全に張り付いているかの防衛線判定
    final bool cameFromCamera = _dragPosition < -0.9;

    if (cameFromCamera) {
      _disposeInlineCamera(); // ① カメラリソースを即座にパージして解放
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); // ② フルスクリーンを解除し、ステータスバーを即時復活
      // ❌ ここでの即時リセット（0.0）はパージ。遷移中の -1.0 を維持させます。
    }

    setState(() {
      final oldController = _schedulePageController;
      _schedulePageController = PageController(initialPage: _currentSchedulePage);
      Future.delayed(const Duration(seconds: 1), () {
        try { if (oldController.hasClients) oldController.dispose(); } catch (_) {}
      });
    });

    // 🟢 タイムライン制御用に遷移アニメーションの時間（500ms）を変数化
    const int pushDurationMs = 500;

    Navigator.push(context, PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: pushDurationMs),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(opacity: animation, child: CourseDetailInteractivePage(
            courses: allCourses, initialIndex: cIdx, cookie: widget.cookie, initialBottomIndex: bottomIdx, targetTaskId: taskId, isAuthenticated: widget.isAuthenticated, onLoginRequest: widget.onLogin, heroTag: heroTag, customCourseColors: _customCourseColors,
            onColorChanged: (cId, cValue) { setState(() { if (cValue == null) _customCourseColors.remove(cId); else _customCourseColors[cId] = cValue; _saveCustomData(); }); },
            onCourseEdited: (String targetName) { Navigator.pop(context); _showEditCourseDialog(targetName); },
            onCourseDeleted: (String targetName) { setState(() { _customCourses.removeWhere((c) => c['name'] == targetName); _generateWeeklySchedule(); _saveCustomData(); }); Navigator.pop(context); },
            onScheduleOverrideChanged: () async {
              await _loadCustomData();
              widget.onTermChanged(widget.currentYear, widget.currentTerm);
              if (mounted) setState((){});
            },
          ));
        }
    )).then((_) {
      if (mounted) {
        setState(() {});
      }
    });

    // 🟢 追記：遷移中（500ms）は -1.0 を絶対維持。詳細画面が開ききって背面が完全に隠れた瞬間に、裏側で位置を 0.0 へ滑り込ませます。
    if (cameFromCamera) {
      Future.delayed(const Duration(milliseconds: pushDurationMs), () {
        if (mounted) {
          setState(() {
            _dragPosition = 0.0;
            _dragAnimController.value = 0.0;
          });
          debugPrint("iOS Inline: 詳細画面が完全に開ききったため、裏側で位置をホーム(0.0)へステルスリセットしました");
        }
      });
    }
  }


  // ★ 修正：Canvas授業用の既存の呼び出しを統合ルーターへ
  void _navigateToDetail(int courseIndex, {int initialBottomIndex = 1, String? targetTaskId}) {
    if (courseIndex >= 0 && courseIndex < widget.courses.length) {
      _routeToCourse(widget.courses[courseIndex]['id'].toString(), false, initialBottomIndex, targetTaskId);
    }
  }


  // ★ 修正：カスタム授業用の既存の呼び出しを統合ルーターへ
  void _navigateToCustomDetail(dynamic customCourse) {
    String targetName = customCourse['raw_name'] ?? customCourse['name'] ?? '';
    _routeToCourse(targetName, true, 1, null);
  }


  void _showCompleteCustomTaskDialog(String taskId) {
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: Colors.white, title: const Text('Complete Task', style: TextStyle(color: Colors.black)), content: const Text('Mark this task as completed?', style: TextStyle(color: Colors.black54)), actions: [TextButton(child: const Text('Cancel', style: TextStyle(color: Colors.black54)), onPressed: () => Navigator.pop(ctx)), TextButton(child: const Text('Complete', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), onPressed: () {
      setState(() {
        // 🟢 解決の鍵：map処理を使い、変更可能な新しい箱（Map.from）にコピーしながらリストを安全に再生成します

        // 1. 保存用のカスタムタスクリストを更新
        _customTasks = _customTasks.map((t) {
          if (t['id'].toString() == taskId) {
            final writableMap = Map<String, dynamic>.from(t);
            writableMap['is_completed'] = true;
            return writableMap;
          }
          return t;
        }).toList();

        // 2. メインの課題リストも同様に更新
        _assignments = _assignments.map((t) {
          if (t['id'].toString() == taskId) {
            final writableMap = Map<String, dynamic>.from(t);
            writableMap['is_completed'] = true;
            return writableMap;
          }
          return t;
        }).toList();

        _saveCustomData();
      });
      // ★ 追加：即座にカレンダーから削除
      CalendarSyncService.deleteTaskFromCalendar(taskId);
      Navigator.pop(ctx);
    })]));
  }


  // 🟢 新設：白黒基調の期限前倒し編集ポップアップ
  // ─── 🟢 修正：白黒モノクローム ＆ 指定レイアウト特化版ポップアップ ───
  void _showDueEditDialog(Map<String, dynamic> task) {
    final String taskId = task['id'].toString();

    final String? dueStr = task['due_at'];
    final String? origDueStr = task['original_due_at'];

    final DateTime currentDue = dueStr != null ? DateTime.parse(dueStr).toLocal() : DateTime.now();
    final DateTime originalDue = origDueStr != null ? DateTime.parse(origDueStr).toLocal() : currentDue;

    // すでに前倒し上書きが実行されているかどうかの判定フラグ
    final bool hasOverride = _taskDueOverrides.containsKey(taskId);
    final bool hasDue = dueStr != null && dueStr.isNotEmpty;

    final bool hasOriginalDue = origDueStr != null && origDueStr.isNotEmpty;

    // 🪙 アプリ指定のカスタムフォントをここに定義（AppThemeに定義があればそちらに差し替えてください）
    const String customFont = 'YourCustomFontName'; // 👈 アプリでダウンロードしたフォント名に書き換えてください

    // 表示用の日時フォーマット文字列
    String formattedCurrentDue = hasDue
        ? "${currentDue.month}/${currentDue.day}  ${currentDue.hour.toString().padLeft(2, '0')}:${currentDue.minute.toString().padLeft(2, '0')}"
        : "undetermined";

    String formattedOriginalDue = origDueStr != null && origDueStr.isNotEmpty
        ? "${originalDue.month}/${originalDue.day}  ${originalDue.hour.toString().padLeft(2, '0')}:${originalDue.minute.toString().padLeft(2, '0')}"
        : "undetermined";

    showDialog(
      context: context,
      builder: (ctx) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: Colors.black, onPrimary: Colors.white, surface: Colors.white, onSurface: Colors.black),
            dialogBackgroundColor: Colors.white,
          ),
          child: AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            // ① カード上部：課題名
            title: Text(
                task['name'] ?? 'Task Title',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black, fontFamily: customFont)
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 12),

                // ② 中央揃えで大きく期日期限を表示
                Text(
                  formattedCurrentDue,
                  style: const TextStyle(
                    fontSize: 36,               // ドデカ文字サイズ
                    fontWeight: FontWeight.w100, // 無機質でシャープな極細ウェイト
                    color: Colors.black,
                    letterSpacing: -0.5,
                    fontFamily: customFont,      // 🟢 カスタムフォントを反映
                  ),
                  textAlign: TextAlign.center,
                ),

                // ③ オリジナルから変更されている場合のみ、下部に中央揃えで小さくオリジナルの期限 ＋ 横にリセットボタン
                if (hasOverride) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        "Original: $formattedOriginalDue",
                        style: TextStyle(
                            fontSize: 16,
                            color: Colors.black.withOpacity(0.9),
                            fontWeight: FontWeight.w300,
                            fontFamily: customFont // 🟢 カスタムフォントを反映
                        ),
                      ),
                      const SizedBox(width: 6),
                      // インライン設置型のミニマルなリセットボタン
                      GestureDetector(
                        onTap: () async {
                          setState(() {
                            _taskDueOverrides.remove(taskId);
                            task['due_at'] = task['original_due_at'];
                            _assignments = List.from(_assignments);
                            _assignments.sort((a, b) => (DateTime.tryParse(a['due_at'] ?? '') ?? DateTime.now()).compareTo(DateTime.tryParse(b['due_at'] ?? '') ?? DateTime.now()));
                          });
                          await WidgetUpdateService.updateHomeWidgets(tasks: _assignments);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('task_due_overrides_v10', jsonEncode(_taskDueOverrides));
                          Navigator.pop(ctx);
                        },
                        child: Icon(
                            Icons.restart_alt_rounded, // より洗練されたリセットアイコン
                            size: 18,
                            color: Colors.black.withOpacity(0.9)
                        )
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
            // ④ カードの下に配置されるアクションボタンエリア（横いっぱいに広げた編集ボタンのみ）
            actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            actions: [
              SizedBox(
                width: double.infinity, // 横幅最大化
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black, // 純黒
                    foregroundColor: Colors.white, // 純白
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                      '期限を変更',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w300, fontFamily: customFont) // 🟢 カスタムフォントを反映
                  ),
                  onPressed: () async {
                    final now = DateTime.now();

                    // 安全弁：もし元の期限がすでに過去（現在時刻より前）の場合
                    if (origDueStr != null && origDueStr.isNotEmpty && originalDue.isBefore(now)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("すでに元の期限を過ぎているため、これ以上早めることはできません。")),
                      );
                      return;
                    }

                    // 🟢 追記：デフォルト表示用日時の決定（期日ありならその期日、未定なら現在時刻）
                    final DateTime defaultDateTime = hasOriginalDue ? originalDue : now;

                    // 🗓️ 日付選択（本来の期日をデフォルト表示）
                    final pickedDate = await showDatePicker(
                      context: context,
                      initialDate: defaultDateTime, // 🟢 修正：now から変更
                      firstDate: DateTime(now.year, now.month, now.day),
                      lastDate: origDueStr != null && origDueStr.isNotEmpty ? originalDue : DateTime(2100),
                      builder: (context, child) {
                        return Theme(
                          data: ThemeData.light().copyWith(
                            colorScheme: const ColorScheme.light(
                              primary: Colors.black,
                              onPrimary: Colors.white,
                              surface: Colors.white,
                              onSurface: Colors.black,
                              secondary: Colors.black,
                            ),
                            textButtonTheme: TextButtonThemeData(
                              style: TextButton.styleFrom(foregroundColor: Colors.black),
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (pickedDate == null) return;

                    // ⏱️ 時刻選択（本来の期日の時間をデフォルト表示）
                    final pickedTime = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(defaultDateTime), // 🟢 修正：now から変更
                      builder: (context, child) {
                        return Theme(
                          data: ThemeData.light().copyWith(
                            colorScheme: const ColorScheme.light(
                              primary: Colors.black,
                              onPrimary: Colors.white,
                              surface: Colors.white,
                              onSurface: Colors.black,
                            ),
                            textButtonTheme: TextButtonThemeData(
                              style: TextButton.styleFrom(foregroundColor: Colors.black),
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (pickedTime == null) return;

                    // 結合して新しい日時を生成
                    final DateTime newDue = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);

                    // 最終防衛線：現在時刻より前の日時はリジェクト
                    if (newDue.isBefore(now)) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("現在時刻より前の日時は設定できません。")));
                      return;
                    }

                    // 既存の防衛線：元の期限より遅くなっていないかチェック
                    if (origDueStr != null && origDueStr.isNotEmpty && newDue.isAfter(originalDue)) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("元の期限より遅い日時は設定できません。")));
                      return;
                    }

                    // すべてのチェックを通過した場合のみ永続化
                    setState(() {
                      final isoStr = newDue.toIso8601String();
                      _taskDueOverrides[taskId] = isoStr;
                      task['due_at'] = isoStr;
                      _assignments = List.from(_assignments);
                      _assignments.sort((a, b) => (DateTime.tryParse(a['due_at'] ?? '') ?? DateTime.now()).compareTo(DateTime.tryParse(b['due_at'] ?? '') ?? DateTime.now()));
                    });

                    await WidgetUpdateService.updateHomeWidgets(tasks: _assignments);

                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('task_due_overrides_v10', jsonEncode(_taskDueOverrides));
                    Navigator.pop(ctx);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  void _showEditCourseDialog(String oldName) {
    var matches = _customCourses.where((c) => c['name'] == oldName).toList(); if (matches.isEmpty) return; var target = matches.first;
    String name = target['name']; String room = target['room'] ?? ''; bool isWeekly = target['is_weekly']; int selectedDay = target['day'] ?? 0; int selectedPeriod = target['period'] ?? 0; DateTime selectedDate = target['date'] != null ? DateTime.parse(target['date']) : DateTime.now();
    showDialog(context: context, builder: (context) { return StatefulBuilder(builder: (context, setState) { return AlertDialog(backgroundColor: Colors.white, title: const Text('Edit Custom Course', style: TextStyle(color: Colors.black)), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: TextEditingController(text: name), style: const TextStyle(color: Colors.black), decoration: const InputDecoration(labelText: 'Course Name', labelStyle: TextStyle(color: Colors.black54), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.black54)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.black))), onChanged: (v) => name = v), TextField(controller: TextEditingController(text: room), style: const TextStyle(color: Colors.black), decoration: const InputDecoration(labelText: 'Room (Optional)', labelStyle: TextStyle(color: Colors.black54), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.black54)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.black))), onChanged: (v) => room = v), const SizedBox(height: 16), SwitchListTile(title: const Text('Weekly Course', style: TextStyle(color: Colors.black)), activeColor: Colors.black, value: isWeekly, onChanged: (v) => setState(() => isWeekly = v)), const SizedBox(height: 16), if (isWeekly) ...[Row(children: [Expanded(child: DropdownButton<int>(isExpanded: true, dropdownColor: Colors.white, style: const TextStyle(color: Colors.black), value: selectedDay, items: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].asMap().entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(), onChanged: (v) => setState(() => selectedDay = v!))), const SizedBox(width: 16), Expanded(child: DropdownButton<int>(isExpanded: true, dropdownColor: Colors.white, style: const TextStyle(color: Colors.black), value: selectedPeriod, items: [1,2,3,4,5,6].map((e) => DropdownMenuItem(value: e-1, child: Text('Period $e'))).toList(), onChanged: (v) => setState(() => selectedPeriod = v!)))])] else ...[Row(children: [Expanded(child: TextButton(onPressed: () async { final d = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2000), lastDate: DateTime(2100), builder: (context, child) => Theme(data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: Colors.black, onPrimary: Colors.white, surface: Colors.white, onSurface: Colors.black)), child: child!)); if (d != null) setState(() => selectedDate = d); }, child: Text('${selectedDate.year}/${selectedDate.month}/${selectedDate.day}', style: const TextStyle(color: Colors.black)))), const SizedBox(width: 16), Expanded(child: DropdownButton<int>(isExpanded: true, dropdownColor: Colors.white, style: const TextStyle(color: Colors.black), value: selectedPeriod, items: [1,2,3,4,5,6].map((e) => DropdownMenuItem(value: e-1, child: Text('Period $e'))).toList(), onChanged: (v) => setState(() => selectedPeriod = v!)))])] ])), actions: [TextButton(child: const Text('Cancel', style: TextStyle(color: Colors.black54)), onPressed: () => Navigator.pop(context)), TextButton(child: const Text('Save', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), onPressed: () { if (name.isEmpty) return; this.setState(() { _customCourses.removeWhere((c) => c['name'] == oldName); _customCourses.add({'id': target['id'], 'name': name, 'room': room, 'is_weekly': isWeekly, 'day': selectedDay, 'period': selectedPeriod, 'date': selectedDate.toIso8601String()}); _generateWeeklySchedule(); _saveCustomData(); }); Navigator.pop(context); })]); }); });
  }


  void _showAddCourseDialog() {
    String name = ''; String room = ''; bool isWeekly = true; int selectedDay = 0; int selectedPeriod = 0; DateTime selectedDate = DateTime.now();
    showDialog(context: context, builder: (context) {
      return StatefulBuilder(builder: (context, setState) {
        return AlertDialog(backgroundColor: Colors.white, title: const Text('Add Custom Course', style: TextStyle(color: Colors.black)), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(style: const TextStyle(color: Colors.black), decoration: const InputDecoration(labelText: 'Course Name', labelStyle: TextStyle(color: Colors.black54), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.black54)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.black))), onChanged: (v) => name = v), TextField(style: const TextStyle(color: Colors.black), decoration: const InputDecoration(labelText: 'Room (Optional)', labelStyle: TextStyle(color: Colors.black54), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.black54)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.black))), onChanged: (v) => room = v), const SizedBox(height: 16), SwitchListTile(title: const Text('Weekly Course', style: TextStyle(color: Colors.black)), activeColor: Colors.black, value: isWeekly, onChanged: (v) => setState(() => isWeekly = v)), const SizedBox(height: 16), if (isWeekly) ...[Row(children: [Expanded(child: DropdownButton<int>(isExpanded: true, dropdownColor: Colors.white, style: const TextStyle(color: Colors.black), value: selectedDay, items: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].asMap().entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(), onChanged: (v) => setState(() => selectedDay = v!))), const SizedBox(width: 16), Expanded(child: DropdownButton<int>(isExpanded: true, dropdownColor: Colors.white, style: const TextStyle(color: Colors.black), value: selectedPeriod, items: [1,2,3,4,5,6].map((e) => DropdownMenuItem(value: e-1, child: Text('Period $e'))).toList(), onChanged: (v) => setState(() => selectedPeriod = v!)))])] else ...[Row(children: [Expanded(child: TextButton(onPressed: () async { final d = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2000), lastDate: DateTime(2100), builder: (context, child) => Theme(data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: Colors.black, onPrimary: Colors.white, surface: Colors.white, onSurface: Colors.black)), child: child!)); if (d != null) setState(() => selectedDate = d); }, child: Text('${selectedDate.year}/${selectedDate.month}/${selectedDate.day}', style: const TextStyle(color: Colors.black)))), const SizedBox(width: 16), Expanded(child: DropdownButton<int>(isExpanded: true, dropdownColor: Colors.white, style: const TextStyle(color: Colors.black), value: selectedPeriod, items: [1,2,3,4,5,6].map((e) => DropdownMenuItem(value: e-1, child: Text('Period $e'))).toList(), onChanged: (v) => setState(() => selectedPeriod = v!)))])] ])), actions: [TextButton(child: const Text('Cancel', style: TextStyle(color: Colors.black54)), onPressed: () => Navigator.pop(context)), TextButton(child: const Text('Add', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), onPressed: () { if (name.isEmpty) return; final custom = {'id': 'custom_c_${DateTime.now().millisecondsSinceEpoch}', 'name': name, 'room': room, 'is_weekly': isWeekly, 'day': selectedDay, 'period': selectedPeriod, 'date': selectedDate.toIso8601String()}; this.setState(() { _customCourses.add(custom); _generateWeeklySchedule(); _saveCustomData(); }); Navigator.pop(context); })]);
      });
    });
  }


  void _showAddTaskDialog() {
    String name = ''; DateTime due = DateTime.now();
    showDialog(context: context, builder: (context) { return StatefulBuilder(builder: (context, setState) { return AlertDialog(backgroundColor: Colors.white, title: const Text('Add Custom Task', style: TextStyle(color: Colors.black)), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(style: const TextStyle(color: Colors.black), decoration: const InputDecoration(labelText: 'Task Name', labelStyle: TextStyle(color: Colors.black54), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.black54)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.black))), onChanged: (v) => name = v), const SizedBox(height: 16), TextButton(onPressed: () async { final d = await showDatePicker(context: context, initialDate: due, firstDate: DateTime(2000), lastDate: DateTime(2100), builder: (context, child) => Theme(data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: Colors.black, onPrimary: Colors.white, surface: Colors.white, onSurface: Colors.black)), child: child!)); if (d != null) { final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(due), builder: (context, child) => Theme(data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: Colors.black, onPrimary: Colors.white, surface: Colors.white, onSurface: Colors.black)), child: child!)); if (t != null) setState(() => due = DateTime(d.year, d.month, d.day, t.hour, t.minute)); } }, child: Text('Deadline: ${due.month}/${due.day} ${due.hour.toString().padLeft(2,'0')}:${due.minute.toString().padLeft(2,'0')}', style: const TextStyle(color: Colors.black))) ]), actions: [TextButton(child: const Text('Cancel', style: TextStyle(color: Colors.black54)), onPressed: () => Navigator.pop(context)), TextButton(child: const Text('Add', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), onPressed: () { if (name.isEmpty) return; final custom = {'id': 'custom_t_${DateTime.now().millisecondsSinceEpoch}', 'name': name, 'due_at': due.toIso8601String(), 'context_name': 'Custom Task', 'course_id': 'custom_t'}; this.setState(() { _customTasks.add(custom); _assignments.add(custom); _assignments.sort((a, b) => (DateTime.tryParse(a['due_at'] ?? '') ?? DateTime.now()).compareTo(DateTime.tryParse(b['due_at'] ?? '') ?? DateTime.now())); _saveCustomData(); }); Navigator.pop(context); })]); }); });
  }


  @override void didUpdateWidget(covariant DashboardPage oldWidget) { super.didUpdateWidget(oldWidget); if (oldWidget.courses != widget.courses) { _buildCourseIndexMap(); setState(() { _generateWeeklySchedule(); _currentCourseIndex = _findBestCourseIndex(); if (_coursesWidgetController.hasClients) _coursesWidgetController.jumpToPage(_currentCourseIndex); }); _fetchDataParallel(); } }




  // ★ 修正：AppSnackBar共通クラスを使って tweaks を一元適用
  void _showUndoSnackBar(String type, String idStr) {
    AppSnackBar.showUndo(context, "$type を非表示にしました", () {
      setState(() {
        if (type == "タスク") {
          _dismissedTaskIds.remove(idStr);
          _saveDismissedTasks();
          // ★ 追加：Undoされたら再同期してカレンダーに復活させる
          CalendarSyncService.syncTasks(_assignments);
        } else {
          _completelyDeletedMessageIds.remove(idStr);
          _saveDismissedMessages();
        }
      });
    });
  }


  // 🟢 修正：AnimatedSwitcher のフェード中にコントローラが即死して赤画面になるバグを時間差パージで完全封殺
  void _handleBackNavigation() {
    // ① 古いコントローラの参照を一時退避し、新しいコントローラを先行配備
    final oldController = _schedulePageController;
    _schedulePageController = PageController(initialPage: _currentSchedulePage);

    // ② 決定打：1秒間の時間差（ディレイ）を設け、フェードアウトが100%完了した後に裏で安全に解放
    Future.delayed(const Duration(seconds: 1), () {
      try {
        oldController.dispose();
        debugPrint("Schedule PageController disposed safely after view transition.");
      } catch (_) {}
    });

    setState(() {
      _currentViewState = ViewState.home;
      _showCompletedTasks = false; // ホームに戻る時は必ず「未提出」状態にリセット
    });
  }


  Widget _buildCoursesView(double topPadding) {
    int maxPeriod = -1;
    bool hasSaturdayClasses = false; // ★ 追加：土曜授業判定
    for (var item in _weeklySchedule) {
      if (item['period'] > maxPeriod) maxPeriod = item['period'];
      if (item['day'] == 5) hasSaturdayClasses = true; // 土曜があればフラグを立てる
    }
    if (maxPeriod == -1) maxPeriod = 0;

    int displayDaysCount = hasSaturdayClasses ? 6 : 5;

    double screenWidth = MediaQuery.of(context).size.width;
    double spacing = 2.0;

    // 🟢 修正：現在の時刻ON/OFF状態に合わせてタイムカラムの幅を動的に決定
    double timeColumnWidth = _isTimeVisible ? 16.0 : 0.0;

    // 🟢 修正：時刻非表示の時は、広がったマスのサイズ（itemWidth）が計算されます
    double itemWidth = (screenWidth - 16.0 - timeColumnWidth - (spacing * (displayDaysCount - 1))) / displayDaysCount;

    // 🟢 修正：拡大された itemWidth をベースに、動的な最大・最小高さを算出
    double headerMaxHeight = topPadding + 48.0 + 24.0 + 4.0 + ((maxPeriod + 1) * itemWidth) + (maxPeriod * 2.0) + 12.0;
    double headerMinHeight = topPadding + 48.0 + ((maxPeriod + 1) * 12.0) + (maxPeriod * 2.0) + 12.0;
    double shrinkLimit = headerMaxHeight - headerMinHeight;

    return Stack(
      key: const ValueKey('course_list'),
      children: [
        CustomScrollView(
          controller: _mainScrollController,
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(
              // 🟢 headerMaxHeight が自動で増減するため、最初の空のスペースが
              // 時間割の縦幅の変化と完全にシンクロして伸縮し、カードを押し下げます
              child: SizedBox(height: headerMaxHeight + 8.0),
            ),
            SliverToBoxAdapter(
              child: _buildStackedCourseCards(headerMaxHeight, headerMinHeight, shrinkLimit),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 120.0),
            )
          ],
        ),
      ],
    );
  }


  // ★ 修正：_displayCourses を使ってカードをスケジュール順に混在描画する
  Widget _buildStackedCourseCards(double headerMaxHeight, double headerMinHeight, double shrinkLimit) {
    return LayoutBuilder(
        builder: (context, constraints) {
          double scrollBeyondHeader = math.max(0.0, _courseScrollOffset - shrinkLimit);
          double totalNaturalHeight = _displayCourses.length * (110.0 + 2.0);


          List<Widget> cardWidgets = [];
          double localYCursor = 0.0;


          for (int i = 0; i < _displayCourses.length; i++) {
            var course = _displayCourses[i];
            double minScreenY = headerMinHeight + 8.0 + i * (12.0 + 2.0);


            double currentHeaderHeight = headerMaxHeight - math.min(_courseScrollOffset, shrinkLimit);
            double naturalScreenY = currentHeaderHeight + 8.0 + localYCursor - scrollBeyondHeader;


            double actualScreenY = math.max(minScreenY, naturalScreenY);
            double overflow = math.max(0.0, minScreenY - naturalScreenY);
            double actualHeight = math.max(12.0, 110.0 - overflow);


            double sliverStartScreenY = currentHeaderHeight + 8.0 - scrollBeyondHeader;
            double actualLocalY = actualScreenY - sliverStartScreenY;


            if (actualScreenY < MediaQuery.of(context).size.height && actualScreenY + actualHeight > 0) {
              cardWidgets.add(
                  Positioned(
                      top: actualLocalY,
                      left: 0, right: 0,
                      height: actualHeight,
                      child: _buildSingleCourseCard(course, actualHeight)
                  )
              );
            }
            localYCursor += 110.0 + 2.0;
          }


          return SizedBox(
            height: totalNaturalHeight,
            child: Stack(children: cardWidgets.reversed.toList()),
          );
        }
    );
  }


  Widget _buildSingleCourseCard(dynamic course, double height) {
    final rawName = course['name'] ?? '';
    int courseIdx = _courseIndexMap[course['id']] ?? 0;

    final color = _getCourseColor(course);

    String dayPeriod = CourseScheduleParser.getDayPeriod(rawName);
    // カスタム授業の表示名から曜日時限を抽出
    if (course['is_custom'] == true) {
      final match = RegExp(r'\[(.*?)\]').firstMatch(rawName);
      if (match != null) dayPeriod = match.group(1) ?? '';
    }

    // ----------------------------------------------------
    // ★ 修正：曜日と連続する時限（例: 月1,2）を完璧にまとめる解析ロジック
    // ----------------------------------------------------
    const jpDayMap = {'月':'MON','火':'TUE','水':'WED','木':'THU','金':'FRI','土':'SAT'};

    // 全角数字を半角に変換
    String normalized = dayPeriod;
    const fullWidthNums = {'１':'1','２':'2','３':'3','４':'4','５':'5','６':'6','７':'7'};
    fullWidthNums.forEach((k, v) { normalized = normalized.replaceAll(k, v); });

    Map<String, List<String>> groupedSchedules = {};
    String currentDay = '';

    // 漢字の曜日、英語の曜日、または1〜7の数字を順番に拾い上げる
    RegExp tokenExp = RegExp(r'([月火水木金土])|(MON|TUE|WED|THU|FRI|SAT)|([1-7])', caseSensitive: false);

    for (final match in tokenExp.allMatches(normalized)) {
      if (match.group(1) != null) {
        // 漢字の曜日を見つけた場合
        currentDay = jpDayMap[match.group(1)!]!;
      } else if (match.group(2) != null) {
        // 英語の曜日を見つけた場合
        currentDay = match.group(2)!.toUpperCase();
      } else if (match.group(3) != null && currentDay.isNotEmpty) {
        // 時限の数字を見つけた場合、現在の曜日のリストに追加
        String period = match.group(3)!;
        if (!groupedSchedules.containsKey(currentDay)) groupedSchedules[currentDay] = [];
        if (!groupedSchedules[currentDay]!.contains(period)) {
          groupedSchedules[currentDay]!.add(period);
        }
      }
    }

    List<String> finalDisplayParts = [];
    // 月〜土の順番に並び替えて結合
    const dayOrder = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
    for (String day in dayOrder) {
      if (groupedSchedules.containsKey(day) && groupedSchedules[day]!.isNotEmpty) {
        List<String> periods = groupedSchedules[day]!;
        periods.sort(); // 数字を1,2の順にソート
        finalDisplayParts.add("$day ${periods.join('.')}"); // 例: MON 1.2
      }
    }

    String displayDayPeriod = finalDisplayParts.join(' / ');

    // フォールバック（うまく解析できなかったイレギュラーな文字列用）
    if (displayDayPeriod.isEmpty && dayPeriod.isNotEmpty) {
      displayDayPeriod = normalized;
      jpDayMap.forEach((k, v) { displayDayPeriod = displayDayPeriod.replaceAll(k, '$v '); });
      displayDayPeriod = displayDayPeriod.replaceAll(RegExp(r'\s+'), ' ').trim().toUpperCase();
    }
    // ----------------------------------------------------

    final textColor = AppTheme.getTextColorForBackground(color);
    double opacity = ((height - 20.0) / (110.0 - 20.0)).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: () {
        if (course['is_custom'] == true) {
          _navigateToCustomDetail(course);
        } else {
          _navigateToDetail(courseIdx);
        }
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(30)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: SizedBox(
              height: 110,
              child: Opacity(
                opacity: opacity,
                // ─── _buildSingleCourseCard メソッド内、SizedBox(height: 110) > Opacity > Padding 内部 ───

                // ─── _buildSingleCourseCard 内、SizedBox(height: 110) > Opacity > Padding 内部 ───

                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Stack(
                    children: [

                      // ① 左上：授業名 ＆ 末尾追従型の斜め矢印
                      // 🟢 解決の鍵：Text.rich を採用することで、授業名が1行でも2行でも、その文字のすぐ後ろに矢印が100%追従します。
                      // 右下のドデカ曜日（横幅）を綺麗に避けるため、右端（right）を100に制限して衝突を完全ガードしています。
                      Positioned(
                        top: 0, left: 0, right: 100,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: CourseTitleParser.getCleanTitle(rawName),
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w300, color: textColor, height: 1.1),
                              ),

                              // 🟢 矢印をインラインのスパンとして末尾にドッキング
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 6.0), // 文字とのキープディスタンス
                                  child: Icon(
                                    Icons.arrow_outward,
                                    color: textColor.withOpacity(0.5),
                                    size: 20, // テキストの高さに合わせたジャストサイズ
                                  ),
                                ),
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      // ② 🟢 復元＆移動：右下詰め ＆ 元のドデカサイズ（24px）縦引き延ばし曜日
                      if (displayDayPeriod.isNotEmpty)
                        Positioned(
                          bottom: 0, right: 0,
                          child: Transform(
                            transform: Matrix4.diagonal3Values(0.8, 1.3, 1.0),
                            alignment: Alignment.bottomRight, // 右下をアンカーにして綺麗に拡大
                            child: Text(
                              displayDayPeriod,
                              style: TextStyle(
                                color: textColor.withOpacity(0.65),
                                fontSize: 24,                 // 🟢 元のドデカサイズに完全復元
                                fontWeight: FontWeight.w100,  // ソリッドな極細ウェイト
                              ),
                            ),
                          ),
                        ),

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




  Widget _buildTasksAndMessagesColumn(List<dynamic> next7DaysTasks, List<dynamic> unreadMessages) {
    // ★ 追加：OSのライトモードなら黒、ダークモードなら白を取得
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color dynamicTextColor = isDark ? Colors.white : Colors.black;

    return Column(
      key: const ValueKey('tasks_messages'),
      children: [
        // --- TASKS セクション ---
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _currentViewState = ViewState.fullTasks),
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        "Task",
                        style: TextStyle(
                            color: dynamicTextColor,
                            fontSize: 24, // ★ 修正：20 -> 24 にサイズアップ
                            fontWeight: FontWeight.w300, // ★ 修正：w300 -> w200 でさらにスタイリッシュな極細字に
                            letterSpacing: 0.5 // ★ 追加：字間を広げてテック感を演出
                        )
                    ),
                    Icon(
                        Icons.arrow_outward, // ★ 修正：矢印を右斜め上に変更
                        color: dynamicTextColor,
                        size: 26 // ★ 修正：22 -> 26 にサイズアップ
                    )
                  ]
              )
          ),
        ),
        if (next7DaysTasks.isNotEmpty || (_isLoadingAssignments && _assignments.isEmpty))
          Padding(padding: const EdgeInsets.only(bottom: 24.0, left: 8.0, right: 8.0), child: _isLoadingAssignments && _assignments.isEmpty ? Container(height: 100, decoration: BoxDecoration(color: AppTheme.panel(context), borderRadius: BorderRadius.circular(30)), child: const Center(child: CircularProgressIndicator(color: AppTheme.accent))) : _buildGroupedTasks(next7DaysTasks))
        else const SizedBox(height: 24.0),

        // --- MESSAGES セクション ---
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _currentViewState = ViewState.fullMessages),
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        "Announce",
                        style: TextStyle(
                            color: dynamicTextColor,
                            fontSize: 24, // ★ 修正：サイズアップ
                            fontWeight: FontWeight.w300, // ★ 修正：極細字
                            letterSpacing: 0.5
                        )
                    ),
                    Icon(
                        Icons.arrow_outward, // ★ 修正：矢印を右斜め上に変更
                        color: dynamicTextColor,
                        size: 26 // ★ 修正：サイズアップ
                    )
                  ]
              )
          ),
        ),
        if (unreadMessages.isNotEmpty || (_isLoadingMessages && _messages.isEmpty))
          Padding(padding: const EdgeInsets.only(bottom: 24.0, left: 8.0, right: 8.0), child: _isLoadingMessages && _messages.isEmpty ? Container(height: 100, decoration: BoxDecoration(color: AppTheme.panel(context), borderRadius: BorderRadius.circular(30)), child: const Center(child: CircularProgressIndicator(color: AppTheme.accent))) : _buildGroupedMessages(unreadMessages, isUnread: true))
        else const SizedBox(height: 24.0),
      ],
    );
  }




  // ★ 修正：左スワイプ時に余白を赤くし、白抜きのゴミ箱アイコンを表示（角丸対応）
  // 🟢 修正：引数に enableSwipe を追加
  Widget _buildGroupedTasks(List<dynamic> tasks, {bool isOverdue = false, bool isCompletedList = false, bool enableSwipe = false}) {
    if (tasks.isEmpty) return const SizedBox();
    return Container(
        clipBehavior: Clip.antiAlias, decoration: BoxDecoration(color: AppTheme.panel(context), borderRadius: BorderRadius.circular(30)),
        child: Column(children: tasks.map((task) {

          final rawDue = task['due_at'];
          final bool isNoDue = rawDue == null || rawDue.toString().isEmpty;

          // 🟢 追記：このタスクが期限前倒しされているかの判定と純正期日のサルベージ
          final String taskIdStr = task['id'].toString();
          final bool isOverridden = _taskDueOverrides.containsKey(taskIdStr);
          final String? origDueRaw = task['original_due_at'];

          String dueStr = "";
          String weekdayStr = ""; // 🟢 追記：曜日を保持する変数
          if (!isNoDue) {
            final due = DateTime.tryParse(rawDue.toString())?.toLocal() ?? DateTime.now();
            dueStr = isOverdue ? "${due.year}/${due.month}/${due.day}  ${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}" : "${due.month}/${due.day}  ${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}";

            // 🟢 追記：パースされた確定時刻から曜日を3文字で抽出
            weekdayStr = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][due.weekday - 1];
          }

          // 🟢 追記：オリジナル期日表示用の文字列フォーマット（月/日 時:分）
          // ❌ 修正前: String origDueStr = ""; if (origDueRaw != null) { ... }
          // 🟢 修正後：本来の期日がある場合は日時をパースし、未定から変更された場合は "undetermined" を代入
          String origDueStr = "";
          if (origDueRaw != null && origDueRaw.toString().isNotEmpty) {
            final origDue = DateTime.tryParse(origDueRaw.toString())?.toLocal() ?? DateTime.now();
            origDueStr = "${origDue.month}/${origDue.day} ${origDue.hour.toString().padLeft(2, '0')}:${origDue.minute.toString().padLeft(2, '0')}";
          } else if (isOverridden) {
            // 🟢 追記：本来は期日のデータがない（未定）状態から前倒し設定された場合のスタンプ
            origDueStr = "undetermined";
          }

          String? subStr;
          if (isCompletedList && task['submission'] != null && task['submission']['submitted_at'] != null) {
            final sub = DateTime.tryParse(task['submission']['submitted_at'])?.toLocal();
            if (sub != null) {
              subStr = "提出: ${sub.month}/${sub.day} ${sub.hour.toString().padLeft(2,'0')}:${sub.minute.toString().padLeft(2,'0')}";
            }
          }

          Widget rowContent = Container(
            color: AppTheme.panel(context),
            child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (task['course_id'] == 'custom_t') {
                    _showCompleteCustomTaskDialog(task['id'].toString());
                  } else {
                    String targetUrl = task['html_url'] ?? task['url'] ?? '';
                    if (targetUrl.isNotEmpty) {
                      openSmartUrl(context, targetUrl, widget.cookie, title: task['name'] ?? 'Task');
                    } else {
                      int cIdx = _courseIndexMap[task['course_id']] ?? -1;
                      if (cIdx != -1) _navigateToDetail(cIdx, initialBottomIndex: 2, targetTaskId: task['id'].toString());
                    }
                  }
                },

                onLongPress: () {
                  // カスタムタスク（course_id == 'custom_t'）もMap構造が同じなのでそのまま編集可能です
                  // 書き換え可能なオブジェクトであることを保証するため、型をキャストして送ります
                  _showDueEditDialog(task as Map<String, dynamic>);
                },

                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Row(children: [
                      // ① 左側カラム（flex: 4）
                      Expanded(
                        flex: 4,
                        child: isNoDue
                            ? Align(
                                alignment: Alignment.center,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque, // 🟢 追記：透明な余白へのタップも100%泥棒して反応させる魔法
                                  onTap: () {
                                    _showDueEditDialog(task as Map<String, dynamic>);
                                  },
                                  // 🟢 修正：アイコンの周りに上下左右のゆったりとしたタップ座席を確保
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
                                    child: Icon(
                                      Icons.add_rounded,
                                      color: AppTheme.textMain(context).withOpacity(0.85),
                                      size: 26,
                                    ),
                                  ),
                                ),
                              )
                            : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start, // 左揃え
                          children: [
                            Transform(
                              transform: Matrix4.diagonal3Values(0.8, 1.2, 1.0),
                              alignment: Alignment.centerLeft,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(dueStr, style: TextStyle(color: AppTheme.textMain(context), fontSize: 32, fontWeight: FontWeight.w100, height: 1.0)),
                              ),
                            ),
                            // 🟢 修正：すべての課題のデカ文字下に「曜日」を常時左詰めで配置
                            Padding(
                              padding: const EdgeInsets.only(top: 3.0, left: 2.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // ① 曜日インジケータ（すべての期日あり課題で常時表示）
                                  Text(
                                    weekdayStr,
                                    style: TextStyle(
                                        color: AppTheme.textSub(context).withOpacity(0.55), // ソリッドで見やすい半透明
                                        fontSize: 9,
                                        fontWeight: FontWeight.w400, // 視認性の良いウェイト
                                        letterSpacing: -0.1
                                    ),
                                  ),

                                  // ② 変更時のみ、曜日の右隣にキープディスタンスを開けてオリジナル期日を結合
                                  if (isOverridden && origDueStr.isNotEmpty) ...[
                                    const SizedBox(width: 8), // 曜日との隙間
                                    Text(
                                      "original: $origDueStr",
                                      style: TextStyle(
                                          color: AppTheme.textSub(context).withOpacity(0.35), // 主張しない超極薄グレー
                                          fontSize: 9,
                                          fontWeight: FontWeight.w300,
                                          letterSpacing: -0.2
                                      ),
                                      maxLines: 1,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12), // 元からある行

                      Expanded(
                        flex: 5,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(task['name'] ?? 'Task', style: TextStyle(color: AppTheme.textMain(context), fontSize: 14, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(currentLMS.cleanTitle(task['context_name'] ?? ''), style: TextStyle(color: AppTheme.textSub(context), fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (subStr != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subStr, style: TextStyle(color: AppTheme.textSub(context), fontSize: 10, fontWeight: FontWeight.bold))),
                          ],
                        ),
                      ),
                    ])
                )
            ),
          );

          // 🟢 修正：enableSwipe がONの時も横2段階スライドの対象に連結
          if (isOverdue || isCompletedList || enableSwipe || isNoDue) {
            return _SwipeToDeleteWidget(
                key: ValueKey("task_${task['id'] ?? UniqueKey()}"),
                onDelete: () {
                  setState(() => _dismissedTaskIds.add(task['id'].toString()));
                  _saveDismissedTasks();
                  CalendarSyncService.deleteTaskFromCalendar(task['id'].toString());
                },
                child: rowContent
            );
          }
          return rowContent;
        }).toList())
    );
  }




  // ★ 修正：左スワイプ時に余白を赤くし、白抜きのゴミ箱アイコンを表示（角丸対応）
  Widget _buildGroupedMessages(List<dynamic> msgs, {bool isUnread = true}) {
    if (msgs.isEmpty) return const SizedBox();
    return Container(
        clipBehavior: Clip.antiAlias, decoration: BoxDecoration(color: AppTheme.panel(context), borderRadius: BorderRadius.circular(30)),
        child: Column(children: msgs.map((msg) {
          final posted = DateTime.tryParse(msg['posted_at'] ?? '')?.toLocal() ?? DateTime.now();
          String dateStr = "${posted.month}/${posted.day}"; String title = msg['title'] ?? 'Message'; String cName = CourseTitleParser.getCleanTitle(msg['context_name'] ?? '');


          Widget rowContent = Container(
            color: AppTheme.panel(context),
            child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () { if (isUnread) { setState(() { _dismissedMessageIds.add(msg['id'].toString()); }); _saveDismissedMessages(); } int cIdx = _courseIndexMap[msg['course_id']] ?? -1; if (cIdx != -1) _navigateToDetail(cIdx, initialBottomIndex: 4, targetTaskId: msg['id'].toString()); },
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [SizedBox(width: 40, child: Text(dateStr, style: TextStyle(color: AppTheme.textMain(context), fontSize: 18, fontWeight: FontWeight.w200 ,letterSpacing: -0.3,))), const SizedBox(width: 12), Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(color: AppTheme.textMain(context), fontSize: 14, fontWeight: FontWeight.w300), maxLines: 2, overflow: TextOverflow.ellipsis), const SizedBox(height: 4), Text(cName, style: TextStyle(color: AppTheme.textSub(context), fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis)]))])
                )
            ),
          );


          if (!isUnread) {
            return _SwipeToDeleteWidget(
                key: ValueKey("msg_${msg['id'] ?? UniqueKey()}"),
                onDelete: () {
                  setState(() { _completelyDeletedMessageIds.add(msg['id'].toString()); });
                  _saveDismissedMessages();
                  // ★ 修正：Undoバーの呼び出しを削除
                },
                child: rowContent
            );
          }
          return rowContent;
        }).toList())
    );
  }




  Widget _buildHomeContent() {
    final now = DateTime.now();
    final nextWeek = now.add(const Duration(days: 7));

    final overdueTasks = _filterTasks((due) => due.isBefore(now));
    final next7DaysTasks = _filterTasks((due) => due.isAfter(now) && due.isBefore(nextWeek));
    final unreadMessages = _filterMessages((m) => !_dismissedMessageIds.contains(m['id'].toString()) && (m['read_state'] == null || m['read_state'] != 'read'));

    double topPadding = MediaQuery.of(context).padding.top + 24.0;
    double scheduleHeight = _getScheduleHeight(_currentSchedulePage, topPadding);

    bool isVerticalScrolling = _courseScrollOffset > 4.0 || _tasksScrollOffset > 4.0;
    bool isTransitioning = _dragAnimController.isAnimating || (_dragPosition != 0.0 && _dragPosition != 1.0 && _dragPosition != -1.0);
    Duration animDuration = (isVerticalScrolling || isTransitioning) ? Duration.zero : const Duration(milliseconds: 300);

    double screenWidth = MediaQuery.of(context).size.width;

    return Stack(
      children: [
        Positioned.fill(
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                // 🟢 追加：カメラ画面（-1.0）に完全にいる時は、親のドラッグ処理をスキップして子（プレビュー）に権限を委譲
                if (_dragPosition < -0.99) return;

                setState(() {
                  _dragPosition -= details.delta.dx / screenWidth;
                  _dragPosition = _dragPosition.clamp(-1.0, 1.0);
                });
                _dragAnimController.value = _dragPosition;
              },
              onHorizontalDragEnd: (details) {
                // 🟢 修正：大元のスワイプは画面の切り替え（吸着）のみに専念させ、操作性の競合を排除します
                if (details.primaryVelocity != null && details.primaryVelocity!.abs() > 300) {
                  if (details.primaryVelocity! > 0) {
                    _dragPosition = _dragPosition > 0.0 ? 0.0 : -1.0;
                  } else {
                    _dragPosition = _dragPosition < 0.0 ? 0.0 : 1.0;
                  }
                } else {
                  if (_dragPosition < -0.5) _dragPosition = -1.0;
                  else if (_dragPosition > 0.5) _dragPosition = 1.0;
                  else _dragPosition = 0.0;
                }
                _dragAnimController.animateTo(_dragPosition, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
              },
              child: Stack(
                children: [
                  // ① 最左面：カメラ操作専用ベース画面
                  // 🟢 修正：ヘッダー側の camMargin = 8.0px への極細化と完全に座標計算を同期
                  // ① 最左面：カメラ操作専用ベース画面
                  // ① 最左面：カメラ操作専用ベース画面
                  // ① 最左面：カメラ操作専用ベース画面
                  // ① 最左面：カメラ操作専用ベース画面
                  // ① 最左面：カメラ操作専用ベース画面
                  Transform.translate(
                    offset: Offset((-1.0 - _dragPosition) * screenWidth, 0),
                    child: Container(
                      width: screenWidth,
                      height: double.infinity,
                      color: AppTheme.bg(context),
                      child: Column(
                        children: [
                          // プレビュー表示エリアのダミー高さを担保
                          Padding(
                            padding: EdgeInsets.zero,
                            child: Builder(
                              builder: (context) {
                                // 🟢 修正：ヘッダー側と完全に同一のクランプ計算にアップデート
                                bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
                                double camMargin = 8.0;
                                double basePreviewW = screenWidth - (camMargin * 2);

                                double maxAvailableH = MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom - 185.0;
                                double activeAspect = (_isCamInitialized && _cameraController != null) ? _cameraController!.value.aspectRatio : (16 / 9);

                                double previewH;
                                if (isLandscape) {
                                  previewH = basePreviewW / activeAspect;
                                  if (previewH > maxAvailableH) previewH = maxAvailableH;
                                } else {
                                  previewH = basePreviewW * activeAspect;
                                  if (previewH > maxAvailableH) previewH = maxAvailableH;
                                }

                                return SizedBox(height: camMargin + previewH + camMargin);
                              },
                            ),
                          ),

                          // 既存の対応メモテキストRow、Spacer、操作バーへ続く（一切変更なし）

                          // 既存の対応メモテキストRow、Spacer、操作バーへ続く（一切変更なし）

                          // 既存の対応メモテキストRow、Spacer、操作バーへ続く（一切変更なし）

                          // 既存の対応メモテキストRow、Spacer、操作バーへ続く（一切変更なし）

                          // 🟢 修正：テキストと斜め矢印をRowで並列化。判定を分離しボトムシートと直通リンクを紐づけます
                          Builder(
                              builder: (context) {
                                final target = _getCurrentOrNextCourse();
                                final now = DateTime.now();
                                final dateStr = '${now.month}/${now.day}';

                                String displayText = "対応メモなし";
                                bool hasTarget = target != null;

                                if (hasTarget) {
                                  final cleanTitle = CourseTitleParser.getCleanTitle(target['courseName'] as String);
                                  displayText = "$dateStr $cleanTitle";
                                }

                                return Padding(
                                  padding: const EdgeInsets.only(left: 20.0, top: 12.0, right: 12.0),
                                  child: Row(
                                    children: [
                                      // ① テキスト部分：タップすると下部からカードがせり上がり、他授業のメモを自由にセレクト可能
                                      Expanded(
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () {
                                            _showCourseSelectionBottomSheet(context);
                                          },
                                          child: Text(
                                            displayText,
                                            style: TextStyle(
                                              color: AppTheme.textMain(context).withOpacity(hasTarget ? 1.0 : 0.25),
                                              fontSize: 20,
                                              fontWeight: FontWeight.w200,
                                              letterSpacing: 0.5,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),

                                      // ② 矢印アイコン部分：タップで現在の対応授業詳細の「MEMOタブ」へダイレクトジャンプ
                                      IconButton(
                                        icon: Icon(
                                          Icons.arrow_outward_rounded,
                                          color: AppTheme.textMain(context).withOpacity(hasTarget ? 0.7 : 0.1),
                                          size: 22,
                                        ),
                                        onPressed: hasTarget ? () {
                                          _routeToCourse(
                                            target['courseId'] as String,
                                            target['isCustom'] as bool,
                                            0,
                                            null,
                                          );
                                        } : null, // 対応メモがない時は無効化して不透明度をミュート
                                      ),
                                    ],
                                  ),
                                );
                              }
                          ),

                          const Spacer(),

                          // ─── _buildHomeContent() メソッド内の下部操作バー周辺 ───
                          // 🟢 修正：条件式を MediaQuery から _isMemoFieldOpen に変更。
                          // メモ入力欄が開いている間、およびフェードアウト中の250msの間、操作バーを完全に消滅（shrink）させて領域を最大確保します。
                          _isMemoFieldOpen
                              ? const SizedBox.shrink()
                              : Container(
                            padding: EdgeInsets.fromLTRB(40.0, 0, 40.0, MediaQuery.of(context).padding.bottom + 24.0),
                            height: 100,
                            alignment: Alignment.center,
                            child: Builder(
                                builder: (context) {
                                  bool isDark = Theme.of(context).brightness == Brightness.dark;
                                  Color camBtnColor = isDark ? Colors.white : Colors.black;

                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      // 対応メモがない時はボタンを半透明・タップ不可にロック
                                      Builder(
                                          builder: (context) {
                                            bool hasTarget = _getCurrentOrNextCourse() != null;
                                            return IconButton(
                                              // 🟢 修正：edit_note_rounded から、より無機質でプレーンな鉛筆マークへ純化
                                              icon: Icon(
                                                Icons.create_outlined,
                                                color: hasTarget ? camBtnColor : camBtnColor.withOpacity(0.15),
                                                size: 26, // 輪郭をシャープに魅せるためサイズを26に微調整
                                              ),
                                              onPressed: hasTarget ? () {
                                                setState(() => _isMemoFieldOpen = true);
                                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                                  _cameraMemoFocusNode.requestFocus();
                                                });
                                              } : null,
                                            );
                                          }
                                      ),

                                      // 中央：タップ時にキュッと小さくなるAnimated正円シャッター
                                      GestureDetector(
                                        onTap: _takeInlineCameraPhoto,
                                        child: Container(
                                          width: 76, height: 76,
                                          alignment: Alignment.center,
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 100),
                                            curve: Curves.easeInOut,
                                            width: _isCamTakingPicture ? 52 : 72,
                                            height: _isCamTakingPicture ? 52 : 72,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: _isCamTakingPicture ? camBtnColor.withOpacity(0.5) : camBtnColor,
                                            ),
                                          ),
                                        ),
                                      ),

                                      // 右側：戻るボタン
                                      IconButton(
                                        icon: Icon(Icons.arrow_forward_rounded, color: camBtnColor, size: 28),
                                        onPressed: () {
                                          _dragAnimController.animateTo(0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
                                        },
                                      ),
                                    ],
                                  );
                                }
                            ),
                          ),


                        ],
                      ),
                    ),
                  ),

                  // ② 中央面：TASKS/MESSAGES
                  // ─── _buildHomeContent メソッド内、中央面（ListView）の children の最下部 ───

                  Transform.translate(
                      offset: Offset(-_dragPosition * screenWidth, 0),
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (info) {
                          if (info.metrics.axis == Axis.vertical) {
                            setState(() => _tasksScrollOffset = math.max(0.0, info.metrics.pixels));
                          }
                          return false;
                        },
                        child: ListView(
                          key: const ValueKey('tasks_list'),
                          controller: _tasksScrollController,
                          // 🟢 調整：ナビゲーション文字が下部バーの裏に完全に隠れてしまわないよう、
                          // ボトムパディングを 120.0 ➔ 160.0 へ僅かに拡張してスクロールの「遊び」を作ります。
                          padding: const EdgeInsets.only(bottom: 160.0),
                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                          children: [
                            AnimatedContainer(
                              duration: animDuration,
                              curve: Curves.easeOutCubic,
                              height: scheduleHeight + 24.0,
                            ),
                            _buildTasksAndMessagesColumn(next7DaysTasks, unreadMessages),

                            // -------------------------------------------------------------------
                            // 🟢 追記：最下端のミニマルなカメラ誘導インジケータ
                            // -------------------------------------------------------------------
                            const SizedBox(height: 16),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                // 🟢 解決の鍵：タップ時に大元のコントローラーを左（-1.0）へ滑らかにアニメーション駆動。
                                // これにより既存のスワイプ処理（カメラのオンデマンド起動ロジック）と100%安全に同期します。
                                _dragAnimController.animateTo(
                                    -1.0,
                                    duration: const Duration(milliseconds: 350),
                                    curve: Curves.easeOutCubic
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 24.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.arrow_back_rounded,
                                      color: AppTheme.textMain(context).withOpacity(0.8),
                                      size: 22,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "Silent Camera",
                                      style: TextStyle(
                                        color: AppTheme.textMain(context).withOpacity(1), // ノイズにならない超極薄グレー
                                        fontSize: 24,
                                        fontWeight: FontWeight.w200, // スタイリッシュな極細字
                                        letterSpacing: - 0.4,          // テック感を出す広めのカーニング
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          ],
                        ),
                      )
                  ),

                  // ③ 最右面：COURSES時間割
                  Transform.translate(
                    offset: Offset((1.0 - _dragPosition) * screenWidth, 0),
                    child: _buildCoursesView(topPadding),
                  ),
                ],
              ),
            )
        ),

        Positioned(
          top: 0.0,
          left: 0, right: 0,
          child: _buildDynamicHeaderWidget(topPadding),
        ),

        // 🟢 修正：条件式を新フラグ（_isMemoFieldOpen）基準に変更
        // 🟢 修正：カプセルボタン押下（キーボード展開時）の最前面オーバーレイ（完全リファイン版）
        // 最前面オーバーレイ（×ボタン円撤廃 ＆ テキスト量連動伸縮版）
        // 最前面オーバーレイ（4隅フィレット ＆ キーボード隙間確保版）
        // 🟢 修正：最前面オーバーレイ（左上コース名、バリデーション警告、矢印保存仕様）
        // 🟢 修正：最前面オーバーレイ（上端左詰め太字、背景0.95、未入力時の矢印ロック仕様）
        // 🟢 修正：アニメーション＆バリデーション機能を内包した新メモコンソールユニットへ移行
        if (_isMemoFieldOpen && _dragPosition < -0.99)
          _CameraMemoOverlay(
            memoTitleText: () {
              final target = _getCurrentOrNextCourse();
              final now = DateTime.now();
              final dateStr = '${now.month}/${now.day}';
              if (target != null) {
                final cleanTitle = CourseTitleParser.getCleanTitle(target['courseName'] as String);
                return "$dateStr $cleanTitle";
              }
              return "対応メモなし";
            }(),
            controller: _cameraMemoController,
            focusNode: _cameraMemoFocusNode,
            onSave: (text) => _addMemoToCourse('text', text),
            onClose: () => setState(() => _isMemoFieldOpen = false),
          ),
      ], // 既存の最外殻閉じタグ
    );
  }








  Widget _buildDynamicHeaderWidget(double topPadding) {
    // 🟢 決定打：メソッドの最外殻を ValueListenableBuilder で接続。
    // これにより、グラデーション領域のみを最軽量かつピンポイントにリアクティブ化します。
    return ValueListenableBuilder<String>(
      valueListenable: appGradientThemeNotifier,
      builder: (context, gradientMode, child) {
        bool isDark = Theme.of(context).brightness == Brightness.dark;

        // 🟢 追記：グローバルパレットから選択中のカラー定義（3色）を動的サルベージ
        final currentPalette = AppGradient.getColors(gradientMode);
        final Color defaultTopGradient = currentPalette[0];
        final Color defaultMiddleGradient = currentPalette[1];
        final Color defaultBottomGradient = currentPalette[2];

        double scheduleHeight = _getScheduleHeight(_currentSchedulePage, topPadding);
        List<Color> scheduleColors = [defaultTopGradient, defaultMiddleGradient, defaultBottomGradient];

        if (_scheduleMode == 'D') {
          DateTime date = DateTime.now().add(Duration(days: _currentSchedulePage - 10000));
          final items = _getScheduleForDate(date);
          if (items.isNotEmpty) {
            Color? customTop; Color? customMid; Color? customBot;
            for (var item in items) {
              if (_hasCustomColor(item['courseObj'])) {
                Color c = _getCourseColor(item['courseObj']);
                int hour = (item['time'] as DateTime).hour;
                if (hour < 12) customTop = c; else if (hour < 16) customMid = c; else customBot = c;
              }
            }
            scheduleColors = [customTop ?? defaultTopGradient, customMid ?? defaultMiddleGradient, customBot ?? defaultBottomGradient];
          }
        }

        List<Color> calendarColors = [defaultTopGradient, defaultMiddleGradient, defaultBottomGradient];

        double blendPos = _dragPosition.clamp(0.0, 1.0);
        Color c1 = Color.lerp(scheduleColors[0], calendarColors[0], blendPos)!;
        Color c2 = Color.lerp(scheduleColors[1], calendarColors[1], blendPos)!;
        Color c3 = Color.lerp(scheduleColors[2], calendarColors[2], blendPos)!;

        List<Color> currentGradient = [c1, c2, c3];

        int maxPeriod = -1; bool hasSaturdayClasses = false;
        for (var item in _weeklySchedule) {
          if (item['period'] > maxPeriod) maxPeriod = item['period'];
          if (item['day'] == 5) hasSaturdayClasses = true;
        }
        if (maxPeriod == -1) maxPeriod = 0;

        int displayDaysCount = hasSaturdayClasses ? 6 : 5;
        double screenWidth = MediaQuery.of(context).size.width;
        double spacing = 2.0;

        double timeColumnWidth = _isTimeVisible ? 16.0 : 0.0;
        double itemWidth = (screenWidth - 16.0 - timeColumnWidth - (spacing * (displayDaysCount - 1))) / displayDaysCount;

        double headerMaxHeight = topPadding + 48.0 + 24.0 + 4.0 + ((maxPeriod + 1) * itemWidth) + (maxPeriod * 2.0) + 12.0;
        double headerMinHeight = topPadding + 48.0 + ((maxPeriod + 1) * 12.0) + (maxPeriod * 2.0) + 12.0;
        double shrinkLimit = headerMaxHeight - headerMinHeight;

        double t = shrinkLimit > 0 ? (_courseScrollOffset  / shrinkLimit).clamp(0.0, 1.0) : 0.0;
        double calendarHeight = headerMaxHeight - t * shrinkLimit;

        double scheduleMinHeight = topPadding + 40.0;
        double activeTasksScrollOffset = 0.0;
        if (_tasksScrollController.hasClients && _tasksScrollController.position.hasContentDimensions) {
          double maxScroll = _tasksScrollController.position.maxScrollExtent;
          if (maxScroll > 0) activeTasksScrollOffset = _tasksScrollOffset;
        }

        double dynamicScheduleHeight = math.max(scheduleMinHeight, scheduleHeight - activeTasksScrollOffset);
        double taskT = (activeTasksScrollOffset / math.max(1.0, scheduleHeight - scheduleMinHeight)).clamp(0.0, 1.0);
        Color monoBg = isDark ? Colors.black : const Color(0xFFEEEEEE);
        Color monoTextColor = isDark ? Colors.white : Colors.black;

        // ─── _buildDynamicHeaderWidget() メソッド内のカメラプレビューサイズ算出周辺 ───

        // ─── _buildDynamicHeaderWidget() メソッド内のカメラプレビューサイズ算出周辺 ───

        double effectiveScheduleHeight = _dragPosition < 0.5 ? dynamicScheduleHeight : scheduleHeight;

        // ─── 🟢 サイズ計算ロジックの冒頭 ───
        // ─── 🟢 修正：画面サイズと操作バーの完全共存ロジック ───
        // ─── 🟢 修正：デバイスの回転に合わせて「縦長 ⇄ 横長」を完全自動スイッチ ───
        // ─── 🟢 修正：縦画面時の左右均一マージン完全復活ロジック ───
        bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
        bool isPad = screenWidth >= 600 || MediaQuery.of(context).size.shortestSide >= 600;
        double camMargin = 8.0;
        double basePreviewW = screenWidth - (camMargin * 2);

        // 下部操作バーと衝突しないための安全な最大縦幅（185pxの防衛線を維持）
        double maxAvailableH = MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom - 185.0;

        double activeAspect = (_isCamInitialized && _cameraController != null)
            ? _cameraController!.value.aspectRatio
            : (16 / 9);

        double previewW = basePreviewW;
        double previewH;

        if (isLandscape) {
          // 🎬 横画面：大迫力の横長シネマサイズ（これまで通り安全にホールド）
          previewH = previewW / activeAspect;
          if (previewH > maxAvailableH) {
            previewH = maxAvailableH;
            previewW = previewH * activeAspect;
          }
        } else {
          // 📱 縦画面：枠幅を均一（上下左右 8px）に保つジャストフィット思想
          // 基本は横幅いっぱいに広げ、アスペクト比を掛け算
          previewH = previewW * activeAspect;

          // 💡 決定打：もし縦が長すぎて最大高さを超えてしまう場合は、
          // プレビュー自体を縮小するのではなく、最大高さ（maxAvailableH）の枠内に
          // カメラプレビューが「はみ出さずに綺麗に収まる（Clip/補正する）」ようにホールドし、
          // 横幅（previewW）は basePreviewW のまま固定して左右のマージンが広がるのを絶対阻止します。
          if (previewH > maxAvailableH) {
            previewH = maxAvailableH;
          }
        }

        // 縦画面で最大クランプに達していない時は、常に左右マージンが「camMargin (8px)」に固定されます
        double previewLeft = (screenWidth - previewW) / 2;
        double cameraTargetHeight = camMargin + previewH + camMargin;
        // ─── 🟢 ここまで ───

        double currentHeight;
        if (_dragPosition >= 0.0) {
          currentHeight = effectiveScheduleHeight + (calendarHeight - effectiveScheduleHeight) * _dragPosition;
        } else {
          double camFactor = _dragPosition.abs();
          currentHeight = ui.lerpDouble(effectiveScheduleHeight, cameraTargetHeight, camFactor)!;
        }

        String heroTag = 'top_widget_hero';

        // 🟢 修正：白テーマ（white）の時は文字・アイコンの基本色を黒に、それ以外は白に自動反転
        Color tCol = (gradientMode == 'white') ? Colors.black87 : Colors.white;

        Color pCol = (gradientMode == 'white') ? Colors.black54 : Colors.white70; // サブテキスト用

        bool isTransitioning = _dragAnimController.isAnimating || (_dragPosition != 0.0 && _dragPosition != 1.0 && _dragPosition != -1.0);
        bool isVerticalScrolling = _courseScrollOffset > 4.0 || _tasksScrollOffset > 4.0;
        Duration animDuration = (isVerticalScrolling || isTransitioning) ? Duration.zero : const Duration(milliseconds: 300);

        return Hero(
          tag: heroTag,
          child: Material(
            type: MaterialType.transparency,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: (details) {
                if (_dragPosition > 0.5 && details.primaryVelocity != null && details.primaryVelocity!.abs() > 300) {
                  setState(() { _isTimeVisible = details.primaryVelocity! > 0; });
                }
              },
              child: AnimatedContainer(
                duration: animDuration,
                curve: Curves.easeOutCubic,
                width: double.infinity,
                height: currentHeight,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  // 💡 計算された動的補間カラー[c1, c2, c3]を展開して適用
                  gradient: LinearGradient(colors: [c1, c2, c3], begin: Alignment.topLeft, end: Alignment.bottomRight, stops: const [0.0, 0.5, 1.0]),
                  borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
                ),
                child: Stack(
                  children: [
                    // 既存の予定・カレンダー表示（そのまま維持）
                    IgnorePointer(ignoring: _dragPosition < -0.01 || _dragPosition >= 0.5, child: AnimatedOpacity(duration: const Duration(milliseconds: 150), opacity: _dragPosition >= 0.0 ? (1.0 - _dragPosition * 2).clamp(0.0, 1.0) : (1.0 - _dragPosition.abs() * 3).clamp(0.0, 1.0), child: _buildInnerSchedule(topPadding, tCol, monoBg, monoTextColor, dynamicScheduleHeight, scheduleMinHeight, scheduleHeight, taskT))),
                    IgnorePointer(ignoring: _dragPosition < 0.5, child: RepaintBoundary(key: _calendarKey, child: Opacity(opacity: ((_dragPosition - 0.5) * 2).clamp(0.0, 1.0), child: GestureDetector(behavior: HitTestBehavior.opaque, onVerticalDragUpdate: (details) { if (_mainScrollController.hasClients) { double maxScroll = _mainScrollController.position.maxScrollExtent; if (maxScroll > 0) { double newOffset = (_mainScrollController.offset - details.primaryDelta!).clamp(0.0, maxScroll); _mainScrollController.jumpTo(newOffset); } } }, child: Container(color: Colors.transparent, child: _buildInnerCalendar(topPadding + 40.0, isDark, t, itemWidth, maxPeriod, spacing, displayDaysCount)))))),

                    // カメラプレビュー領域
                    if (_dragPosition < 0.0) ...[
                      Positioned(
                        top: camMargin,
                        left: previewLeft,
                        width: previewW,
                        height: previewH,
                        child: Opacity(
                          opacity: _dragPosition.abs(),
                          child: Container(
                            clipBehavior: Clip.antiAlias,
                            decoration: const BoxDecoration(
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(32.0),
                                topRight: Radius.circular(32.0),
                                bottomLeft: Radius.circular(24.0),
                                bottomRight: Radius.circular(24.0),
                              ),
                              color: Colors.black,
                            ),
                            child: _isCamInitialized && _cameraController != null
                                ? Stack(
                              children: [
                                // 1. 【視覚ベース層】 純粋にカメラ映像を描画するだけのレイヤー（最背面）
                                Positioned.fill(
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(32.0),
                                      topRight: Radius.circular(32.0),
                                      bottomLeft: Radius.circular(24.0),
                                      bottomRight: Radius.circular(24.0),
                                    ),
                                    child: RepaintBoundary(
                                      key: _previewContainerKey,
                                      child: CameraPreview(_cameraController!),
                                    ),
                                  ),
                                ),

                                // 2. 【上部ジェスチャー専用層】 ズーム＆ホーム戻り（中間層）
                                Positioned(
                                  top: 0,
                                  bottom: isPad ? 200 : 100,
                                  left: 0,
                                  right: 0,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onScaleStart: (details) {
                                      _camBaseZoom = _camCurrentZoom;
                                      if (details.pointerCount >= 2 || _isCameraPinching) {
                                        _isCameraPinching = true;
                                        setState(() => _camShowZoomText = true);
                                      }
                                    },
                                    onScaleUpdate: (details) {
                                      if (_isCameraPinching) {
                                        if (_camMaxZoom <= _camMinZoom) return;
                                        double nz = (_camBaseZoom * details.scale).clamp(_camMinZoom, _camMaxZoom);
                                        setState(() => _camCurrentZoom = nz);
                                        _cameraController!.setZoomLevel(_camCurrentZoom);
                                      }
                                      else if (details.pointerCount == 1 && !_camShowZoomText) {
                                        double deltaX = details.focalPointDelta.dx / screenWidth;
                                        setState(() {
                                          _dragPosition = (_dragPosition + deltaX).clamp(-1.0, 0.0);
                                        });
                                        _dragAnimController.value = _dragPosition;
                                      }
                                    },
                                    onScaleEnd: (details) {
                                      _isCameraPinching = false;
                                      setState(() => _camShowZoomText = false);

                                      if (_dragPosition < 0.0) {
                                        double velocityX = details.velocity.pixelsPerSecond.dx;
                                        if (velocityX < -400 || _dragPosition > -0.5) {
                                          _dragPosition = 0.0;
                                        } else {
                                          _dragPosition = -1.0;
                                        }
                                        _dragAnimController.animateTo(
                                            _dragPosition,
                                            duration: const Duration(milliseconds: 250),
                                            curve: Curves.easeOutCubic
                                        );
                                      }
                                    },
                                    child: const SizedBox.expand(),
                                  ),
                                ),

                                Positioned(
                                  top: 12,
                                  left: 12,
                                  child: IconButton(
                                    icon: const Icon(Icons.sync_rounded, color: Colors.white, size: 28),
                                    onPressed: _switchCameraFacing,
                                  ),
                                ),

                                Positioned(
                                  bottom: isPad ? 116 : 16,
                                  left: 0, right: 0,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AnimatedOpacity(
                                        duration: const Duration(milliseconds: 200),
                                        opacity: _camShowZoomText ? 1.0 : 0.0,
                                        child: Text("${_camCurrentZoom.toStringAsFixed(1)}x", style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w200, letterSpacing: 1.0)),
                                      ),
                                      const SizedBox(height: 8),
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onHorizontalDragStart: (_) => setState(() => _camShowZoomText = true),
                                        onHorizontalDragUpdate: (details) async {
                                          if (_camMaxZoom <= _camMinZoom) return;
                                          double sensitivity = 0.04;
                                          double dz = -details.delta.dx * sensitivity;
                                          double tgt = _camCurrentZoom + dz;
                                          setState(() => _camCurrentZoom = tgt.clamp(_camMinZoom, _camMaxZoom));
                                          _cameraController!.setZoomLevel(_camCurrentZoom);
                                        },
                                        onHorizontalDragEnd: (_) => setState(() => _camShowZoomText = false),
                                        child: SizedBox(
                                          width: previewW, height: 24,
                                          child: CustomPaint(painter: _SlidingDialTicksPainter(progress: (_camCurrentZoom - _camMinZoom) / (_camMaxZoom - _camMinZoom))),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                if (_capturedImagePathForAnim != null || _capturedUiImageForAnim != null)
                                  Positioned.fill(
                                    child: AnimatedBuilder(
                                      animation: _cameraCaptureAnimController,
                                      builder: (context, child) {
                                        double v = _cameraCaptureAnimController.value;

                                        double shrinkV = CurvedAnimation(
                                          parent: _cameraCaptureAnimController,
                                          curve: const Interval(0.0, 0.4, curve: Curves.easeOutCubic),
                                        ).value;

                                        double slideV = CurvedAnimation(
                                          parent: _cameraCaptureAnimController,
                                          curve: const Interval(0.4, 1.0, curve: Curves.easeInCubic),
                                        ).value;

                                        double scale = ui.lerpDouble(1.0, 0.3, shrinkV)!;
                                        double slideX = ui.lerpDouble(0.0, screenWidth, slideV)!;
                                        double slideY = 0.0;

                                        return Transform.translate(
                                          offset: Offset(slideX, slideY),
                                          child: Transform.scale(
                                            scale: scale,
                                            alignment: Alignment.bottomRight,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                border: Border.all(color: const Color(0xFF7ebbdc), width: 8.0),
                                                borderRadius: const BorderRadius.only(
                                                  topLeft: Radius.circular(32.0),
                                                  topRight: Radius.circular(32.0),
                                                  bottomLeft: Radius.circular(24.0),
                                                  bottomRight: Radius.circular(24.0),
                                                ),
                                              ),
                                              child: ClipRRect(
                                                borderRadius: const BorderRadius.only(
                                                  topLeft: Radius.circular(28.0),
                                                  topRight: Radius.circular(28.0),
                                                  bottomLeft: Radius.circular(20.0),
                                                  bottomRight: Radius.circular(20.0),
                                                ),
                                                child: _capturedUiImageForAnim != null
                                                    ? RawImage(
                                                  image: _capturedUiImageForAnim,
                                                  fit: BoxFit.cover,
                                                )
                                                    : (_capturedImagePathForAnim != null
                                                    ? Image.file(
                                                  File(_capturedImagePathForAnim!),
                                                  fit: BoxFit.cover,
                                                  gaplessPlayback: true,
                                                )
                                                    : const SizedBox()),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),

                              ],
                            )
                                : const Center(child: CircularProgressIndicator(color: Colors.white)),
                          ),
                        ),
                      ),
                    ],

                    // 左上：学期タイトル
                    Positioned(
                      top: topPadding - 20,
                      left: 8.0,
                      child: IgnorePointer(
                        ignoring: _dragPosition < 0.5,
                        child: Opacity(
                          opacity: ((_dragPosition - 0.5) * 2).clamp(0.0, 1.0),
                          child: Builder(
                              builder: (context) {
                                String term = widget.currentTerm.toUpperCase();
                                String line1 = term; String line2 = "";
                                if (term.contains('春') || term.contains('前期') || term.contains('SPRING')) { line1 = "Spring"; line2 = "Semester"; }
                                else if (term.contains('秋') || term.contains('後期') || term.contains('FALL')) { line1 = "Fall"; line2 = "Semester"; }
                                else if (term.startsWith('Q')) { line1 = "Quarter"; String n = term.replaceAll(RegExp(r'[^0-9]'), ''); line2 = n == '1' ? "One" : n == '2' ? "Two" : n == '3' ? "Three" : n == '4' ? "Four" : n; }
                                return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(line1, style: TextStyle(color: tCol, fontSize: 20, fontWeight: FontWeight.w300, height: 1.1, letterSpacing: 1.5)),
                                      if (line2.isNotEmpty) Text(line2, style: TextStyle(color: tCol, fontSize: 20, fontWeight: FontWeight.w300, height: 1.1, letterSpacing: 1.5)),
                                      Text("(${widget.currentYear})", style: TextStyle(color: tCol, fontSize: 20, fontWeight: FontWeight.w300, height: 1.1, letterSpacing: 1.5))
                                    ]
                                );
                              }
                          ),
                        ),
                      ),
                    ),

                    // 右上：各種コントロールボタン
                    Positioned(
                      top: topPadding - 32,
                      right: 16,
                      child: IgnorePointer(
                        ignoring: _dragPosition < 0.5,
                        child: Opacity(
                          opacity: ((_dragPosition - 0.5) * 2).clamp(0.0, 1.0),
                          child: Row(
                            children: [
                              if (_dragPosition > 0.95)
                                IconButton(
                                  icon: Icon(Icons.share, color: tCol, size: 22),
                                  onPressed: _shareCalendarImage,
                                ),
                              IconButton(
                                icon: Icon(Icons.add, color: tCol, size: 24),
                                onPressed: _showAddCourseDialog,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }




  // ★ 引数に縮小割合(t)を追加
  // ★ 引数に縮小割合(t)を追加
  Widget _buildInnerSchedule(double topPadding, Color tCol, Color btnBg, Color btnIconColor, double dynHeight, double minH, double maxH, double taskT) {
    // ★ スクロール半分で中身が綺麗にフェードアウトする
    double contentOpacity = (1.0 - taskT * 2.0).clamp(0.0, 1.0);

    return Stack(
      key: const ValueKey('schedule'),
      children: [
        Opacity(
          opacity: contentOpacity, // 中身全体を透過
          child: OverflowBox(
            minHeight: maxH,
            maxHeight: maxH,
            alignment: Alignment.bottomCenter,
            child: PageView.builder(
                key: ValueKey('schedule_page_view_$_scheduleMode'),
                controller: _schedulePageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentSchedulePage = index;
                    if (_tasksScrollController.hasClients) {
                      _tasksScrollController.jumpTo(0.0);
                      _tasksScrollOffset = 0.0;
                    }
                  });
                },
                physics: const BouncingScrollPhysics(),
                itemBuilder: (context, index) {
                  DateTime now = DateTime.now();
                  int offsetDays = index - 10000;

                  if (_scheduleMode == 'W') {
                    DateTime currentMonday = now.subtract(Duration(days: now.weekday - 1));
                    DateTime targetWeek = currentMonday.add(Duration(days: offsetDays * 7));
                    for(int i = 0; i < 7; i++) { _fetchExternalEventsForDate(targetWeek.add(Duration(days: i))); }
                    return _buildWeekPage(targetWeek, topPadding, tCol);
                  } else if (_scheduleMode == 'M') {
                    DateTime targetMonth = DateTime(now.year, now.month + offsetDays, 1);
                    DateTime startDate = targetMonth.subtract(Duration(days: targetMonth.weekday - 1));
                    int daysInMonth = DateTime(targetMonth.year, targetMonth.month + 1, 0).day;
                    int numWeeks = ((targetMonth.weekday - 1 + daysInMonth) / 7.0).ceil();
                    for(int i = 0; i < numWeeks * 7; i++) { _fetchExternalEventsForDate(startDate.add(Duration(days: i))); }
                    return _buildMonthPage(targetMonth, topPadding, tCol);
                  }

                  // --- 既存のWモード・Mモードの分岐のすぐ下、Dモードの処理部分 ---
                  DateTime pageDate = now.add(Duration(days: offsetDays));

                  // 🟢 決定打：_buildDayPageの3日分プール結合を100%機能させるため、
                  // 前後の日付の外部予定もバックグラウンドで同時に先読み（事前ロード）させます。
                  _fetchExternalEventsForDate(pageDate.subtract(const Duration(days: 1)));
                  _fetchExternalEventsForDate(pageDate);
                  _fetchExternalEventsForDate(pageDate.add(const Duration(days: 1)));

                  return _buildDayPage(pageDate, index, topPadding, tCol);
                }
            ),
          ),
        ),

        Positioned(
          top: topPadding - 6.0,
          left: 0, right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildModeButton('D', tCol),
              Text(' / ', style: TextStyle(color: tCol.withOpacity(0.2), fontSize: 24, fontWeight: FontWeight.w200)),
              _buildModeButton('W', tCol),
              Text(' / ', style: TextStyle(color: tCol.withOpacity(0.2), fontSize: 24, fontWeight: FontWeight.w200)),
              _buildModeButton('M', tCol),
            ],
          ),
        ),

        if (_currentSchedulePage != 10000)
          Positioned(
              top: topPadding - 2.0,
              right: 16,
              child: Opacity(
                opacity: contentOpacity,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _currentSchedulePage = 10000);
                    if (_schedulePageController.hasClients) {
                      _schedulePageController.animateToPage(10000, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
                    }
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                      child: Builder(
                          builder: (context) {
                            // 🟢 追記：現在のグラデーション状態を読み込み、パーツ色を動的にスイッチ
                            final String gradientMode = appGradientThemeNotifier.value;
                            final bool isWhiteTheme = gradientMode == 'white';

                            final Color btnElementColor = isWhiteTheme ? Colors.black87 : Colors.white;
                            final Color btnBgColor = isWhiteTheme ? Colors.black.withOpacity(0) : Colors.white.withOpacity(0);

                            return Container(
                              height: 28,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                  color: btnBgColor, // 🟢 修正
                                  borderRadius: BorderRadius.circular(14)
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: _currentSchedulePage > 10000
                                    ? [
                                  Icon(Icons.arrow_back_ios_new, size: 10, color: btnElementColor), // 🟢 修正
                                  const SizedBox(width: 4),
                                  Text("${DateTime.now().month}/${DateTime.now().day}", style: TextStyle(color: btnElementColor, fontSize: 16, fontWeight: FontWeight.w300)) // 🟢 修正
                                ]
                                    : [
                                  Text("${DateTime.now().month}/${DateTime.now().day}", style: TextStyle(color: btnElementColor, fontSize: 16, fontWeight: FontWeight.w300)), // 🟢 修正
                                  const SizedBox(width: 4),
                                  Icon(Icons.arrow_forward_ios, size: 10, color: btnElementColor) // 🟢 修正
                                ],
                              ),
                            );
                          }
                      ),
                    ),
                  ),
                ),
              )
          )
      ],
    );
  }
  // トグルボタン用ヘルパーメソッド
  Widget _buildModeButton(String mode, Color tCol) {
    bool isSel = _scheduleMode == mode;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_scheduleMode != mode) {
          setState(() {
            _scheduleMode = mode;
            _currentSchedulePage = 10000; // モードを変えたら「今」に戻す

            // ★ 修正：モード切替時もPageControllerを初期位置(10000)で新しく作り直す
            final oldController = _schedulePageController;
            _schedulePageController = PageController(initialPage: 10000);
            Future.delayed(Duration.zero, () => oldController.dispose());

            if (_tasksScrollController.hasClients) _tasksScrollController.jumpTo(0.0);
            _tasksScrollOffset = 0.0;
          });
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Text(
          mode,
          style: TextStyle(
            color: tCol.withOpacity(isSel ? 1.0 : 0.3),
            fontSize: 24,
            fontWeight: isSel ? FontWeight.w400 : FontWeight.w200,
          ),
        ),
      ),
    );
  }
  // === 以下、新規追加する描画用ヘルパーメソッド3種 ===

  Widget _buildDayPage(DateTime pageDate, int index, double topPadding, Color tCol) {
    final pageItems = _getScheduleForDate(pageDate);

    // 🟢 決定打：OSカレンダー（UTC起因）の「朝9時の呪い」を完全に粉砕する結合＆再仕分けロジック
    final DateTime prevDate = pageDate.subtract(const Duration(days: 1));
    final DateTime nextDate = pageDate.add(const Duration(days: 1));

    // 前日・当日・翌日のキャッシュをごっそり1つのプールにまとめる（9時間のズレによる漏れをここで全回収）
    List<Map<String, dynamic>> rawExternalPool = [
      ...(_externalEventsCache["${prevDate.year}-${prevDate.month}-${prevDate.day}"] ?? []),
      ...(_externalEventsCache["${pageDate.year}-${pageDate.month}-${pageDate.day}"] ?? []),
      ...(_externalEventsCache["${nextDate.year}-${nextDate.month}-${nextDate.day}"] ?? []),
    ];

    List<Map<String, dynamic>> correctedExternal = [];
    Set<String> seenEvents = {};

    for (var item in rawExternalPool) {
      // 全イベントの時間を100%ピュアな日本ローカル時間（JST）へ強制変換
      DateTime localTime = (item['time'] as DateTime).toLocal();
      DateTime localEndTime = item['endTime'] != null
          ? (item['endTime'] as DateTime).toLocal()
          : localTime.add(const Duration(hours: 1));

      // 🟢 純粋に日本時間基準で「今日（pageDate）」の年月日と完全一致するものだけを厳選ホールド
      if (localTime.year == pageDate.year && localTime.month == pageDate.month && localTime.day == pageDate.day) {
        String eventKey = "${item['title']}_${localTime.millisecondsSinceEpoch}";
        // 重複して結合されるのを防止
        if (!seenEvents.contains(eventKey)) {
          seenEvents.add(eventKey);

          Map<String, dynamic> correctedItem = Map.from(item);
          correctedItem['time'] = localTime;
          correctedItem['endTime'] = localEndTime;
          correctedExternal.add(correctedItem);
        }
      }
    }

    // 日本時間で綺麗に整列し直した外部イベントを授業データとマージ
    // 日本時間で綺麗に整列し直した外部イベントを授業データとマージ
    List<Map<String, dynamic>> allItems = List.from(pageItems)..addAll(correctedExternal);

    // ─── 🟢 修正①：同時刻の場合のみ、課題（task）を最優先で上にする高剛性ソート ───
    allItems.sort((a, b) {
      int cmp = (a['time'] as DateTime).compareTo(b['time'] as DateTime);
      if (cmp != 0) return cmp; // 時間が違うなら時系列順

      // 同時刻の場合、aがtaskなら上(-1)、bがtaskなら下(1)へスライド
      if (a['type'] == 'task' && b['type'] != 'task') return -1;
      if (a['type'] != 'task' && b['type'] == 'task') return 1;
      return 0;
    });

    final daysEn = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    String dayStr = daysEn[pageDate.weekday - 1];
    String dateAndDay = "${pageDate.month}/${pageDate.day} $dayStr";

    String? relativeLabel;
    if (index == 10000) relativeLabel = "TODAY";
    else if (index == 9999) relativeLabel = "YESTERDAY";
    else if (index == 10001) relativeLabel = "TOMORROW";

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: topPadding + 24.0, bottom: 8.0),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: (details) {
            if (_tasksScrollController.hasClients) {
              double maxScroll = _tasksScrollController.position.maxScrollExtent;
              if (maxScroll > 0) {
                double newOffset = (_tasksScrollController.offset - details.primaryDelta!).clamp(0.0, maxScroll);
                _tasksScrollController.jumpTo(newOffset);
              }
            }
          },
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 36,
                    child: Stack(
                      children: [
                        Positioned(
                          top: 0, left: 0,
                          child: Text(
                            relativeLabel ?? '',
                            style: TextStyle(
                              color: tCol.withOpacity(0.6),
                              fontSize: 10,
                              fontWeight: FontWeight.w300,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0, left: 0,
                          child: Text(
                            dateAndDay,
                            style: TextStyle(
                              color: tCol.withOpacity(0.9),
                              fontSize: 18,
                              fontWeight: FontWeight.w300,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (allItems.isNotEmpty)
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // ① 極細の縦直線
                        Positioned(
                          top: 12.0,
                          bottom: 0,
                          left: 51.0,
                          child: Container(
                            width: 0.5,
                            color: tCol.withOpacity(0.95),
                          ),
                        ),

                        // ② 現在時刻のインジケータ極細横直線
                        if (index == 10000)
                          Builder(
                            builder: (context) {
                              if (allItems.isEmpty) return const SizedBox();

                              final now = DateTime.now();
                              int nowMins = now.hour * 60 + now.minute;
                              double? lineY;

                              DateTime firstStart = allItems.first['time'];
                              int firstStartMins = firstStart.hour * 60 + firstStart.minute;
                              DateTime lastEnd = allItems.last['endTime'] ?? allItems.last['time'].add(const Duration(hours: 1));
                              int lastEndMins = lastEnd.hour * 60 + lastEnd.minute;

                              // 最初の予定より前：タイムラインの上部にホールド
                              if (nowMins < firstStartMins) {
                                lineY = 12.0;
                              }
                              // すべての予定が終わった後：最終アイテムの時刻の間にホールド
                              else if (nowMins > lastEndMins) {
                                int i = allItems.length - 1;
                                // 56.0 を掛けることで、最後の授業カードの完全に「下側の境界線上」へ横線を追い出します
                                lineY = (i + 1) * 56.0;
                              }
                              // 進行中の時間帯
                              else {
                                for (int i = 0; i < allItems.length; i++) {
                                  final item = allItems[i];
                                  DateTime start = item['time'];
                                  DateTime end = item['endTime'] ?? start.add(const Duration(hours: 1));
                                  int startMins = start.hour * 60 + start.minute;
                                  int endMins = end.hour * 60 + end.minute;

                                  // 🟢 修正：現在進行中のアイテム内部。開始時刻と終了時刻（または空枠）のジャスト中間に線を引く
                                  if (nowMins >= startMins && nowMins <= endMins) {
                                    lineY = i * 56.0 + 37.5;
                                    break;
                                  }

                                  // 🟢 修正：アイテムとアイテムの間の隙間（コマ間）にいる時
                                  if (i < allItems.length - 1) {
                                    final nextItem = allItems[i + 1];
                                    DateTime nextStart = nextItem['time'];
                                    int nextStartMins = nextStart.hour * 60 + nextStart.minute;

                                    if (nowMins > endMins && nowMins < nextStartMins) {
                                      lineY = i * 56.0 + 64.0;
                                      break;
                                    }
                                  }
                                }
                              }

                              if (lineY == null) return const SizedBox();

                              return Positioned(
                                top: lineY,
                                left: 0,
                                width: 51.0,
                                child: Container(
                                  height: 0.5,
                                  color: tCol.withOpacity(1),
                                ),
                              );
                            },
                          ),

                        // ③ 元の予定リスト本体
                        Column(
                          children: allItems.map((item) {
                            bool isTask = item['type'] == 'task';
                            bool isExternal = item['type'] == 'external_event';

                            DateTime time = item['time'];
                            String startTimeStr = "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";

                            String endTimeStr = "";
                            DateTime endTime = item['endTime'] ?? time.add(const Duration(hours: 1));
                            if (item['endTime'] != null) {
                              endTimeStr = "${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}";
                            } else {
                              endTimeStr = "${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}";
                            }

                            if (isExternal && item['isAllDay'] == true) {
                              startTimeStr = "ALL";
                              endTimeStr = "DAY";
                            }

                            int status = item['status'] ?? 0;
                            double itemOpacity = 1.0;
                            Color subTextColor = tCol.withOpacity(0.7);
                            String subText = item['subtitle']?.toString() ?? '';

                            if (!isTask && !isExternal) {
                              if (status == 1) { subText = "Ondemand"; itemOpacity = 0.4; }
                              else if (status == 3) { subText = "Exam"; }
                            }

                            // ─── 🟢 変更①：時限文字列の生成（タイトルとは分離して保持） ───
                            String periodStr = "";
                            if (item['type'] == 'class') {
                              int startMins = time.hour * 100 + time.minute;
                              if (startMins == 900) periodStr = "1．";
                              else if (startMins == 1045) periodStr = "2．";
                              else if (startMins == 1300) periodStr = "3．";
                              else if (startMins == 1445) periodStr = "4．";
                              else if (startMins == 1630) periodStr = "5．";
                              else if (startMins == 1815) periodStr = "6．";
                            }

                            // ─── 🟢 変更②：太さ（FontWeight）の主律リバランス ───
                            FontWeight titleWeight = FontWeight.w400; // 通常の講義（座学）は w300 をホールド

                            if (isExternal) {
                              // 🟢 カレンダー同期の文字のみ、さらにミニマルで無機質な w200 へピンポイントコンバート
                              titleWeight = FontWeight.w200;
                            } else {
                              // タイトルに「演習」が含まれる授業、または課題予定（Task）のみを w600 へ引き上げ
                              bool isPracticeClass = item['type'] == 'class' && item['title'].toString().contains('演習');
                              if (isTask || isPracticeClass) {
                                titleWeight = FontWeight.w600;
                              }
                            }

                            // 終了した予定のフェード処理
                            if (endTime.isBefore(DateTime.now()) && !(isExternal && item['isAllDay'] == true)) {
                              itemOpacity *= 0.35;
                            }

                            return SizedBox(
                                height: 56,
                                child: Opacity(
                                  opacity: itemOpacity,
                                  child: Padding(
                                      padding: const EdgeInsets.only(top: 16.0),
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          if (isExternal) return;
                                          if (isTask) {
                                            if (item['courseId'] == 'custom_t') {
                                              _showCompleteCustomTaskDialog(item['taskId']);
                                            } else {
                                              String url = item['targetUrl'] ?? '';
                                              if (url.isNotEmpty) openSmartUrl(context, url, widget.cookie, title: item['title']);
                                              else {
                                                int cIdx = _courseIndexMap[item['courseId']] ?? -1;
                                                if (cIdx != -1) _navigateToDetail(cIdx, initialBottomIndex: 2, targetTaskId: item['taskId']);
                                              }
                                            }
                                          } else if (item['isCustom'] == true) {
                                            _navigateToCustomDetail(item['courseObj']);
                                          } else {
                                            int cIdx = _courseIndexMap[item['courseId']] ?? -1;
                                            if (cIdx != -1) _navigateToDetail(cIdx, initialBottomIndex: 1);
                                          }
                                        },
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center, // 56pxの枠内で全体を美しく縦中央寄せ
                                          children: [
                                            // ─── 🟢 1行目：開始時刻、アイコン、タイトル文字を同じRowに並べる ───
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.center, // ✨ これで手動パディングなしで「文字の目線」が全自動で100%揃います！
                                              children: [
                                                SizedBox(
                                                  width: 45,
                                                  child: Text(startTimeStr, style: TextStyle(color: tCol, fontSize: 14, fontWeight: FontWeight.w400, height: 1.0)),
                                                ),
                                                const SizedBox(width: 12),
                                                if (isTask) ...[Icon(Icons.assignment_late, size: 18, color: tCol), const SizedBox(width: 4)],
                                                if (isExternal) ...[Icon(Icons.event, size: 16, color: tCol), const SizedBox(width: 4)],

                                                Expanded(
                                                  child: Text.rich(
                                                    TextSpan(
                                                      style: TextStyle(color: tCol, fontSize: 14, height: 1.0),
                                                      children: [
                                                        if (periodStr.isNotEmpty)
                                                          TextSpan(
                                                            text: periodStr,
                                                            style: const TextStyle(fontWeight: FontWeight.w900),
                                                          ),
                                                        TextSpan(
                                                          text: item['title'],
                                                          style: TextStyle(fontWeight: titleWeight),
                                                        ),
                                                      ],
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),

                                            const SizedBox(height: 2), // 1行目と2行目の等間隔キープディスタンス

                                            // ─── 🟢 2行目：終了時刻（授業のみ）とサブテキストのラインを揃える ───
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                SizedBox(
                                                  width: 45,
                                                  // 💡 課題（Task）の時は終了時刻が消え、空の45px幅だけが残るため、右のsubTextの開始位置が上のタイトルと綺麗に揃います
                                                  child: !isTask
                                                      ? Text(endTimeStr, style: TextStyle(color: tCol.withOpacity(0.75), fontSize: 11, fontWeight: FontWeight.w300, height: 1.0))
                                                      : const SizedBox(),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(subText, style: TextStyle(color: subTextColor, fontSize: 10, height: 1.0), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      )
                                  ),
                                )
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeekPage(DateTime startOfWeek, double topPadding, Color tCol) {
    final daysEn = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final monthsEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    String monthLabel = monthsEn[startOfWeek.month - 1];

    int minHour = 24;
    int maxHour = 0;
    for (int i = 0; i < 7; i++) {
      DateTime d = startOfWeek.add(Duration(days: i));
      List<Map<String, dynamic>> appEvents = _getScheduleForDate(d).where((item) => item['status'] != 2).toList();
      String dateKey = "${d.year}-${d.month}-${d.day}";
      List<Map<String, dynamic>> ext = _externalEventsCache[dateKey] ?? [];
      for (var item in [...appEvents, ...ext]) {
        if (item['isAllDay'] == true) continue;
        DateTime st = item['time'];
        DateTime et = item['endTime'] ?? st.add(const Duration(hours: 1));
        if (st.hour < minHour) minHour = st.hour;
        if (et.hour > maxHour) maxHour = et.hour + (et.minute > 0 ? 1 : 0);
      }
    }

    if (minHour > maxHour) { minHour = 9; maxHour = 18; }
    else { minHour = math.max(0, minHour - 1); maxHour = math.min(24, maxHour + 1); }

    final double pixelsPerMinute = 0.5;
    final double timelineHeight = (maxHour - minHour) * 60 * pixelsPerMinute;

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: topPadding + 48.0, bottom: 8.0),
        // ★ 修正：Dモード同様に、縦スワイプをタスクリストのスクロールに流し込む
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: (details) {
            if (_tasksScrollController.hasClients) {
              double maxScroll = _tasksScrollController.position.maxScrollExtent;
              if (maxScroll > 0) {
                double newOffset = (_tasksScrollController.offset - details.primaryDelta!).clamp(0.0, maxScroll);
                _tasksScrollController.jumpTo(newOffset);
              }
            }
          },
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                  child: SizedBox(
                    height: 28,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(monthLabel, style: TextStyle(color: tCol.withOpacity(0.9), fontSize: 22, fontWeight: FontWeight.w200, letterSpacing: 1.2)),
                        const SizedBox(width: 8),
                        Text("${minHour}:00 - ${maxHour}:00", style: TextStyle(color: tCol.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.w400)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(7, (i) {
                    DateTime currentDay = startOfWeek.add(Duration(days: i));
                    bool isToday = currentDay.year == DateTime.now().year && currentDay.month == DateTime.now().month && currentDay.day == DateTime.now().day;

                    List<Map<String, dynamic>> appEvents = _getScheduleForDate(currentDay).where((item) => item['status'] != 2).toList();
                    String dateKey = "${currentDay.year}-${currentDay.month}-${currentDay.day}";
                    List<Map<String, dynamic>> externalEvents = _externalEventsCache[dateKey] ?? [];

                    List<Map<String, dynamic>> dailyEvents = [...appEvents, ...externalEvents];
                    dailyEvents.sort((a, b) => (a['time'] as DateTime).compareTo(b['time'] as DateTime));

                    List<Widget> eventWidgets = [];

                    for (var event in dailyEvents) {
                      bool isExternal = event['type'] == 'external_event';
                      bool isTask = event['type'] == 'task';
                      DateTime startTime = event['time'];
                      DateTime endTime = event['endTime'] ?? startTime.add(const Duration(hours: 1));

                      double topOffset;
                      double height;

                      if (isExternal && event['isAllDay'] == true) {
                        topOffset = 0.0;
                        height = 12.0;
                      } else {
                        int startMinTotal = startTime.hour * 60 + startTime.minute;
                        int endMinTotal = endTime.hour * 60 + endTime.minute;

                        if (startMinTotal < minHour * 60) startMinTotal = minHour * 60;
                        if (endMinTotal > maxHour * 60) endMinTotal = maxHour * 60;

                        int durationMin = endMinTotal - startMinTotal;
                        if (durationMin < 20) durationMin = 20;

                        topOffset = (startMinTotal - minHour * 60) * pixelsPerMinute;
                        height = durationMin * pixelsPerMinute;
                      }

                      Color bgColor = !isExternal ? _getCourseColor(event['courseObj']) : tCol.withOpacity(0.15);
                      Color txtColor = !isExternal ? AppTheme.getTextColorForBackground(bgColor) : tCol;

                      if (isTask) {
                        bgColor = bgColor.withOpacity(0.8);
                      } else if (!isExternal && event['status'] == 1) {
                        bgColor = bgColor.withOpacity(0.3);
                        txtColor = txtColor.withOpacity(0.5);
                      }

                      String title = event['title'] ?? '';

                      eventWidgets.add(
                          Positioned(
                            top: topOffset,
                            left: 0,
                            right: 0,
                            height: height,
                            child: GestureDetector(
                              onTap: () {
                                if (isTask) {
                                  if (event['courseId'] == 'custom_t') _showCompleteCustomTaskDialog(event['taskId']);
                                  else {
                                    String url = event['targetUrl'] ?? '';
                                    if (url.isNotEmpty) openSmartUrl(context, url, widget.cookie, title: event['title']);
                                    else {
                                      int cIdx = _courseIndexMap[event['courseId']] ?? -1;
                                      if (cIdx != -1) _navigateToDetail(cIdx, initialBottomIndex: 2, targetTaskId: event['taskId']);
                                    }
                                  }
                                } else if (!isExternal) {
                                  if (event['isCustom'] == true) _navigateToCustomDetail(event['courseObj']);
                                  else {
                                    int cIdx = _courseIndexMap[event['courseId']] ?? -1;
                                    if (cIdx != -1) _navigateToDetail(cIdx, initialBottomIndex: 1);
                                  }
                                }
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 1.0, right: 1.0),
                                padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 2.0),
                                decoration: BoxDecoration(
                                  color: bgColor,
                                  // ★ 修正：角の丸みを4から6へ少し大きく
                                  borderRadius: BorderRadius.circular(6),
                                  // ★ 修正：授業(!isTask && !isExternal)なら枠線なし、それ以外は枠線を残す
                                  border: (!isTask && !isExternal)
                                      ? null
                                      : Border.all(color: AppTheme.bg(context).withOpacity(isTask ? 0.8 : 0.4), width: isTask ? 1.0 : 0.5),
                                ),
                                child: Text(
                                  title,
                                  style: TextStyle(color: txtColor, fontSize: 7, fontWeight: FontWeight.w600, height: 1.1),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: math.max(1, (height / 10).floor()),
                                ),
                              ),
                            ),
                          )
                      );
                    }

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.0),
                        child: Column(
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _switchToDayMode(currentDay),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                child: Column(
                                  children: [
                                    Text(daysEn[i][0], style: TextStyle(color: tCol.withOpacity(isToday ? 1.0 : 0.5), fontSize: 10, fontWeight: isToday ? FontWeight.bold : FontWeight.w300)),
                                    Text("${currentDay.day}", style: TextStyle(color: tCol.withOpacity(isToday ? 1.0 : 0.5), fontSize: 14, fontWeight: isToday ? FontWeight.bold : FontWeight.w300)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                                height: timelineHeight,
                                width: double.infinity,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: eventWidgets,
                                )
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthPage(DateTime pageDate, double topPadding, Color tCol) {
    DateTime firstDayOfMonth = DateTime(pageDate.year, pageDate.month, 1);
    DateTime startDate = firstDayOfMonth.subtract(Duration(days: firstDayOfMonth.weekday - 1));
    final monthsEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    String monthLabel = monthsEn[pageDate.month - 1];

    int daysInMonth = DateTime(pageDate.year, pageDate.month + 1, 0).day;
    int numWeeks = ((firstDayOfMonth.weekday - 1 + daysInMonth) / 7.0).ceil();

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: topPadding + 48.0, bottom: 8.0),
        // ★ 修正：Dモード同様に、縦スワイプをタスクリストのスクロールに流し込む
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: (details) {
            if (_tasksScrollController.hasClients) {
              double maxScroll = _tasksScrollController.position.maxScrollExtent;
              if (maxScroll > 0) {
                double newOffset = (_tasksScrollController.offset - details.primaryDelta!).clamp(0.0, maxScroll);
                _tasksScrollController.jumpTo(newOffset);
              }
            }
          },
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: SizedBox(
                    height: 28,
                    child: Text(monthLabel, style: TextStyle(color: tCol.withOpacity(0.9), fontSize: 22, fontWeight: FontWeight.w200, letterSpacing: 1.2)),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((d) =>
                      Expanded(child: Center(child: Text(d, style: TextStyle(color: tCol.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.w300))))
                  ).toList(),
                ),
                const SizedBox(height: 8),

                ...List.generate(numWeeks, (weekIdx) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(7, (dayIdx) {
                        DateTime currentDay = startDate.add(Duration(days: weekIdx * 7 + dayIdx));
                        bool isCurrentMonth = currentDay.month == pageDate.month;
                        bool isToday = currentDay.year == DateTime.now().year && currentDay.month == DateTime.now().month && currentDay.day == DateTime.now().day;

                        List<Map<String, dynamic>> appEvents = _getScheduleForDate(currentDay).where((item) => item['status'] != 2).toList();
                        String dateKey = "${currentDay.year}-${currentDay.month}-${currentDay.day}";
                        List<Map<String, dynamic>> externalEvents = _externalEventsCache[dateKey] ?? [];

                        return Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _switchToDayMode(currentDay),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                                    child: Text(
                                        "${currentDay.day}",
                                        style: TextStyle(
                                            color: tCol.withOpacity(isToday ? 1.0 : (isCurrentMonth ? 0.7 : 0.2)),
                                            fontSize: 10,
                                            fontWeight: isToday ? FontWeight.bold : FontWeight.w300
                                        )
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),

                                ...appEvents.map((c) {
                                  bool isTask = c['type'] == 'task';
                                  Color cColor = _getCourseColor(c['courseObj']);
                                  bool isOndemand = c['status'] == 1;

                                  return GestureDetector(
                                    onTap: () {
                                      if (isTask) {
                                        if (c['courseId'] == 'custom_t') {
                                          _showCompleteCustomTaskDialog(c['taskId']);
                                        } else {
                                          String url = c['targetUrl'] ?? '';
                                          if (url.isNotEmpty) openSmartUrl(context, url, widget.cookie, title: c['title']);
                                          else {
                                            int cIdx = _courseIndexMap[c['courseId']] ?? -1;
                                            if (cIdx != -1) _navigateToDetail(cIdx, initialBottomIndex: 2, targetTaskId: c['taskId']);
                                          }
                                        }
                                      } else {
                                        if (c['isCustom'] == true) _navigateToCustomDetail(c['courseObj']);
                                        else {
                                          int cIdx = _courseIndexMap[c['courseId']] ?? -1;
                                          if (cIdx != -1) _navigateToDetail(cIdx, initialBottomIndex: 1);
                                        }
                                      }
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 2),
                                      height: isTask ? 6 : 10,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: isTask ? cColor.withOpacity(0.9) : cColor.withOpacity(isOndemand ? 0.3 : 0.8),
                                        borderRadius: BorderRadius.circular(isTask ? 3 : 5),
                                        border: isTask ? Border.all(color: tCol.withOpacity(0.4), width: 0.5) : null,
                                      ),
                                    ),
                                  );
                                }).toList(),

                                ...externalEvents.take(3).map((e) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 2),
                                    height: 3,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: tCol.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(1.5),
                                    ),
                                  );
                                }).toList(),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ★ 修正：引数に displayDaysCount を追加
  // ★ 修正：引数に displayDaysCount を追加
  // ★ 修正：引数に displayDaysCount を追加
  Widget _buildInnerCalendar(double topPadding, bool isDark, double t, double baseItemWidth, int maxPeriod, double baseSpacing, int displayDaysCount) {
    // 🟢 追記：現在のグラデーションテーマの状態をスキャン
    final String gradientMode = appGradientThemeNotifier.value;
    final bool isWhiteTheme = gradientMode == 'white';

    // テーマに応じたベース文字色とアクティブ背景色を定義
    final Color calTextColor = isWhiteTheme ? Colors.black87 : Colors.white;
    final Color calSubTextColor = isWhiteTheme ? Colors.black54 : Colors.white70;
    final Color activeCapsuleBg = isWhiteTheme ? Colors.black.withOpacity(0.08) : Colors.white.withOpacity(0.95);
    final Color activeCapsuleText = isWhiteTheme ? Colors.black : Colors.black;
    double currentItemHeight = baseItemWidth - t * (baseItemWidth - 12.0);
    double currentSpacing = 1.0;
    double textOpacity = math.max(0.0, 1.0 - t * 3.0);

    // 時刻列のON/OFFを動的に反映
    double timeColumnWidth = _isTimeVisible ? 16.0 : 0.0;

    final bool isPad = MediaQuery.of(context).size.shortestSide >= 600;

    return Container(
        key: const ValueKey('calendar'),
        width: double.infinity,
        // paddingのトップ位置を固定し、上部への突き抜けを防止
        padding: EdgeInsets.only(top: topPadding + 8.0, bottom: 12.0, left: 8.0, right: 8.0),
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          // 🟢 Align で包むことで上詰め（トップ基準）のアンカーに固定し、下向きに拡大させます
          child: Align(
            alignment: Alignment.topCenter,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (textOpacity > 0)
                    Opacity(
                      opacity: textOpacity,
                      child: SizedBox(
                        height: 24.0 * textOpacity,
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              SizedBox(width: timeColumnWidth), // 時刻の有無で動的に伸縮
                              ...['MON','TUE','WED','THU','FRI','SAT'].take(displayDaysCount).toList().asMap().entries.map((entry) {
                                int idx = entry.key; bool isToday = (DateTime.now().weekday - 1) == idx;

                                Widget content = Container(
                                  width: baseItemWidth,
                                  decoration: (isToday && !_isCapturing)
                                      ? BoxDecoration(
                                      color: Colors.white.withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(12)
                                  )
                                      : null,
                                  alignment: Alignment.center,
                                  child: Text(
                                      entry.value,
                                      style: TextStyle(
                                          color: (isToday && !_isCapturing)
                                              ? (isWhiteTheme ? Colors.white : Colors.black) // 今日かつ白テーマなら文字を白に
                                              : (_isCapturing && !isDark ? Colors.black : calTextColor), // 通常時の曜日文字色
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold
                                      )
                                  ),
                                );

                                return Padding(
                                  padding: EdgeInsets.only(right: entry.key == displayDaysCount - 1 ? 0 : baseSpacing),
                                  child: isToday && !_isCapturing
                                      ? ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: BackdropFilter(
                                      filter: ui.ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                                      child: content,
                                    ),
                                  )
                                      : content,
                                );
                              }).toList()
                            ]
                        ),
                      ),
                    ),
                  if (textOpacity > 0)
                    SizedBox(height: 4.0 * textOpacity),
                  ...List.generate(maxPeriod + 1, (periodIndex) {

                    String startStr = "";
                    String endStr = "";
                    final pData = periods[periodIndex];
                    if (pData != null) {
                      int start = pData['start']!;
                      int end = pData['end']!;
                      startStr = "${start ~/ 100}:${(start % 100).toString().padLeft(2, '0')}";
                      endStr = "${end ~/ 100}:${(end % 100).toString().padLeft(2, '0')}";
                    }

                    // ─── _buildInnerCalendar メソッド内の List.generate(maxPeriod + 1, ...) 内部 ───

                    // ─── _buildInnerCalendar メソッド内の List.generate(maxPeriod + 1, ...) 内部 ───

                    // ─── _buildInnerCalendar メソッド内の List.generate(maxPeriod + 1, ...) 内部 ───

                    return Padding(
                      padding: EdgeInsets.only(bottom: periodIndex == maxPeriod ? 0 : currentSpacing),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [

                          // -------------------------------------------------------------------
                          // 🟢 修正：カプセル幅14 / 隙間2 の黄金比率 ＆ 非アクティブ文字の拡大
                          // -------------------------------------------------------------------
                          // ─── _buildInnerCalendar 内、List.generate(maxPeriod + 1, ...) の Row 内部 ───

                          if (timeColumnWidth > 0)
                            Opacity(
                              opacity: textOpacity,
                              child: Builder(
                                builder: (context) {
                                  final now = DateTime.now();
                                  bool isDisplayDayActive = now.weekday <= displayDaysCount;

                                  bool isCurrentPeriod = false;
                                  if (!_isCapturing && pData != null) {
                                    int nowMins = now.hour * 100 + now.minute;
                                    if (isDisplayDayActive && nowMins >= pData['start']! && nowMins <= pData['end']!) {
                                      isCurrentPeriod = true;
                                    }
                                  }

                                  // 🟢 修正：iPad（Pad環境）の文字サイズをさらに1〜2段階大きくスケールアップ
                                  double activeFontSize = isPad ? 14.5 : 10.5;
                                  double inactiveFontSize = isPad ? 16.5 : 12.0;



                                  return SizedBox(
                                    width: timeColumnWidth, // 16px固定
                                    height: currentItemHeight,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.start,
                                      children: [

                                        // ① カプセル・時刻テキスト本体（アクティブ時）
                                        if (isCurrentPeriod)
                                          Container(
                                            width: 14.0,
                                            height: currentItemHeight,
                                            decoration: BoxDecoration(
                                              color: activeCapsuleBg, // 動的カプセル背景
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                                              child: FittedBox(
                                                fit: BoxFit.contain,
                                                child: RotatedBox(
                                                  quarterTurns: 1,
                                                  child: SizedBox(
                                                    width: currentItemHeight, // 物理的な縦幅をマスの高さに完全ロック
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.max,
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween, // マスの中で限界まで等間隔に引き伸ばす
                                                      children: [
                                                        // 🟢 修正：中略（...）を完全にパージし、本来のスタイルプロパティを完全結合
                                                        Text(startStr, style: TextStyle(color: activeCapsuleText, fontSize: activeFontSize, fontWeight: FontWeight.w300, letterSpacing: 0.1)),
                                                        Text("-", style: TextStyle(color: activeCapsuleText.withOpacity(0.4), fontSize: activeFontSize - 1)),
                                                        Text(endStr, style: TextStyle(color: activeCapsuleText, fontSize: activeFontSize, fontWeight: FontWeight.w300, letterSpacing: 0.1)),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          )
                                        else
                                        // ② 時刻テキスト本体（通常時 / 非アクティブ時）
                                          SizedBox(
                                            width: 14.0,
                                            height: currentItemHeight,
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                                              child: FittedBox(
                                                fit: BoxFit.contain,
                                                child: RotatedBox(
                                                  quarterTurns: 1,
                                                  child: SizedBox(
                                                    width: currentItemHeight,
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.max,
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        // 🟢 修正：通常時の時限テキスト色
                                                        Text(startStr, style: TextStyle(color: (_isCapturing && !isDark) ? Colors.black : calTextColor, fontSize: inactiveFontSize, fontWeight: FontWeight.w300)),
                                                        Text("-", style: TextStyle(color: (_isCapturing && !isDark) ? Colors.black : calTextColor, fontSize: inactiveFontSize, fontWeight: FontWeight.w200)),
                                                        Text(endStr, style: TextStyle(color: (_isCapturing && !isDark) ? Colors.black : calTextColor, fontSize: inactiveFontSize, fontWeight: FontWeight.w300)),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),

                                        const SizedBox(width: 2.0), // カプセルとマスの隙間
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),

                          // 💡 右隣の授業マス（...List.generate(displayDaysCount, ...）へと続きます

                          // 💡 右隣の授業マス（...List.generate(displayDaysCount, ...）へと美しく続きます

                          // 💡 この右隣に並ぶ「授業マス目自動等分生成ロジック（...List.generate(displayDaysCount, ...）」へとそのまま続きます

                          // 授業マス目自動等分生成ロジック
                          ...List.generate(displayDaysCount, (dayIndex) {
                            final matches = _weeklySchedule.where((s) => s['day'] == dayIndex && s['period'] == periodIndex).toList();

                            Widget buildCell(Map<String, dynamic> match, double height, bool isHalf) {
                              Color color = _getCourseColor(match['course']);
                              bool isPad = MediaQuery.of(context).size.shortestSide >= 600;
                              String rawName = match['course']['raw_name'] ?? match['course']['name'] ?? '';
                              String courseName = CourseTitleParser.getCleanTitle(rawName);
                              String roomName = match['course']['is_custom'] == true ? (match['course']['room'] ?? '') : CourseScheduleParser.getRoomNumber(rawName);

                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  if (match['course']['is_custom'] == true) {
                                    _navigateToCustomDetail(match['course']);
                                  } else {
                                    int courseIdx = _courseIndexMap[match['course']['id']] ?? -1;
                                    if (courseIdx != -1) _navigateToDetail(courseIdx);
                                  }
                                },
                                child: Container(
                                  width: baseItemWidth,
                                  height: height,
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                  padding: EdgeInsets.all(isHalf ? 2.0 : 4.0),
                                  child: Opacity(
                                    opacity: textOpacity,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Align(
                                            alignment: Alignment.topCenter,
                                            child: Text(
                                                courseName,
                                                style: TextStyle(
                                                    color: AppTheme.getTextColorForBackground(color),
                                                    fontSize: isHalf ? (isPad ? 16.0 : 8.0) : (isPad ? 20.0 : 10.0),
                                                    fontWeight: FontWeight.w400,
                                                    height: 1.1
                                                ),
                                                textAlign: TextAlign.center,
                                                maxLines: isHalf ? 1 : 3,
                                                overflow: TextOverflow.ellipsis
                                            ),
                                          ),
                                        ),
                                        if (roomName.isNotEmpty)
                                          Text(
                                              roomName,
                                              style: TextStyle(
                                                  color: AppTheme.getTextColorForBackground(color).withOpacity(0.8),
                                                  fontSize: isHalf ? (isPad ? 10.0 : 6.5) : (isPad ? 12.0 : 8.0),
                                                  fontWeight: FontWeight.w300,
                                                  height: 1.1
                                              ),
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }

                            Widget currentCell;
                            if (matches.isEmpty) {
                              currentCell = SizedBox(width: baseItemWidth, height: currentItemHeight);
                            } else if (matches.length == 1) {
                              currentCell = buildCell(matches.first, currentItemHeight, false);
                            } else {
                              Map<String, dynamic>? firstHalfMatch;
                              Map<String, dynamic>? secondHalfMatch;

                              for (var m in matches) {
                                String rawName = m['course']['raw_name'] ?? m['course']['name'] ?? '';
                                String termName = m['course']['term']?['name'] ?? '';
                                String combined = "$rawName $termName".toUpperCase();

                                bool isQ2 = combined.contains("Q2") || combined.contains("2Q") || combined.contains("第2クォーター") || combined.contains("春学期後半");
                                bool isQ4 = combined.contains("Q4") || combined.contains("4Q") || combined.contains("第4クォーター") || combined.contains("秋学期後半");
                                bool isLate = combined.contains("後半") || combined.contains("後期");

                                if (isQ2 || isQ4 || isLate) {
                                  secondHalfMatch ??= m;
                                } else {
                                  firstHalfMatch ??= m;
                                }
                              }

                              if (firstHalfMatch == null) firstHalfMatch = matches[0];
                              if (secondHalfMatch == null) secondHalfMatch = matches[1];
                              if (firstHalfMatch == secondHalfMatch) secondHalfMatch = matches[1];

                              double halfHeight = (currentItemHeight - baseSpacing) / 2.0;

                              currentCell = SizedBox(
                                  width: baseItemWidth,
                                  height: currentItemHeight,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      buildCell(firstHalfMatch, halfHeight, true),
                                      buildCell(secondHalfMatch, halfHeight, true),
                                    ],
                                  )
                              );
                            }

                            return Padding(
                              padding: EdgeInsets.only(right: dayIndex == displayDaysCount - 1 ? 0 : baseSpacing),
                              child: currentCell,
                            );
                          }),
                        ],
                      ),
                    );
                  }),
                ]
            ),
          ),
        )
    );
  }// ★ 修正：バグの原因となっていた自前のスワイプ判定を削除し、データフィルタリングを固定
  // ★ 修正：＋ボタンの常時表示と、スワイプ物理特性の最適化
  Widget _buildFullTasksContent() {
    final now = DateTime.now();
    final nextWeek = now.add(const Duration(days: 7));

    // ★ 修正：ignoreTerm を削除
    // 左側：PENDING用データ
    final overdueTasks = _filterTasks((due) => due.isBefore(now), wantCompleted: false);
    final next7DaysTasks = _filterTasks((due) => due.isAfter(now) && due.isBefore(nextWeek), wantCompleted: false);
    final futureTasks = _filterTasks((due) => due.isAfter(nextWeek) || due.isAtSameMomentAs(nextWeek), wantCompleted: false);

    final noDuePendingTasks = _filterNoDueTasks(wantCompleted: false);



    // ★ 修正：ignoreTerm を削除
    // 右側：COMPLETED用データ
    List<dynamic> allCompletedTasks = _filterTasks((due) => true, wantCompleted: true);
    final noDueCompletedTasks = _filterNoDueTasks(wantCompleted: true);
    allCompletedTasks.addAll(noDueCompletedTasks);

    // 提出日時（submitted_at）の新しい順に1つのタイムラインとしてソート
    allCompletedTasks.sort((a, b) {
      DateTime timeA = DateTime.tryParse(a['submission']?['submitted_at'] ?? a['due_at'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      DateTime timeB = DateTime.tryParse(b['submission']?['submitted_at'] ?? b['due_at'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return timeB.compareTo(timeA);
    });

    bool isDark = Theme.of(context).brightness == Brightness.dark;
    // ... 以下そのまま

    // トグルカプセル用の色（ライト: 黒カプセル/白文字、ダーク: 白カプセル/黒文字）
    // トグルカプセル用の色（ライト: 黒カプセル/白文字、ダーク: 白カプセル/黒文字）
    Color activeCapsuleColor = isDark ? Colors.white : Colors.black;
    Color activeTextColor = isDark ? Colors.black : Colors.white;

    // ★ 修正：非選択の文字色を半透明(opacity)にせず、くっきりした黒（ダークモード時は白）にする
    Color inactiveTextColor = isDark ? Colors.white : Colors.black;

    double topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      body: Stack(
        children: [
          // -------------------------------------------------------------------
          // 1. タスクリスト領域
          // -------------------------------------------------------------------
          Positioned.fill(
            child: PageView(
              controller: _taskPageController,
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              onPageChanged: (i) => setState(() => _showCompletedTasks = i == 1),
              children: [
                // --- PENDING リスト ---
                ListView(
                  // ★ 修正：カプセル直下（112px付近）に合わせたパディング
                  padding: EdgeInsets.only(
                      top: topPadding + 112.0,
                      left: 16.0,
                      right: 16.0,
                      bottom: MediaQuery.of(context).padding.bottom + 120.0
                  ),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    if (next7DaysTasks.isNotEmpty) ...[
                      Padding(padding: const EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text("next 7 days", style: TextStyle(color: AppTheme.textSub(context), fontSize: 18, fontWeight: FontWeight.w300))),
                      _buildGroupedTasks(next7DaysTasks, isCompletedList: false),
                      const SizedBox(height: 24),
                    ],
                    if (overdueTasks.isNotEmpty) ...[
                      Padding(padding: const EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text("overdue", style: TextStyle(color: AppTheme.textSub(context), fontSize: 18, fontWeight: FontWeight.w300))),
                      _buildGroupedTasks(overdueTasks, isOverdue: true, isCompletedList: false),
                      const SizedBox(height: 24),
                    ],
                    if (futureTasks.isNotEmpty) ...[
                      Padding(padding: const EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text("future tasks", style: TextStyle(color: AppTheme.textSub(context), fontSize: 18, fontWeight: FontWeight.w300))),
                      _buildGroupedTasks(futureTasks, isCompletedList: false),
                      const SizedBox(height: 24), // 👈 追記
                    ],
                    // 🟢 追記：未提出の期日未定セクション
                    // 🟢 修正：ダミー生成マップを完全パージし、スワイプを許可
                    if (noDuePendingTasks.isNotEmpty) ...[
                      Padding(padding: const EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text("undetermined", style: TextStyle(color: AppTheme.textSub(context), fontSize: 18, fontWeight: FontWeight.w300))),
                      _buildGroupedTasks(noDuePendingTasks, enableSwipe: true),
                    ],
                  ],
                ),
                // --- COMPLETED リスト ---
                // --- COMPLETED リスト ---
                ListView(
                  padding: EdgeInsets.only(
                      top: topPadding + 112.0,
                      left: 16.0,
                      right: 16.0,
                      bottom: MediaQuery.of(context).padding.bottom + 120.0
                  ),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    // 🟢 修正：期日未定も提出日時順で完全にマージされた美しい一本のリストを射出
                    if (allCompletedTasks.isNotEmpty)
                      _buildGroupedTasks(allCompletedTasks, isCompletedList: true),
                  ],
                )
              ],
            ),
          ),

          // -------------------------------------------------------------------
          // 2. カプセル直下でスッと消えるグラデーションマスク
          // -------------------------------------------------------------------
          Positioned(
            top: 0, left: 0, right: 0,
            // ★ 修正：高さを抑え、カプセル下端に合わせる
            height: topPadding + 112.0,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AppTheme.bg(context).withOpacity(0.00),
                      AppTheme.bg(context).withOpacity(0.20),
                      AppTheme.bg(context).withOpacity(0.50),
                      AppTheme.bg(context).withOpacity(0.80),
                      AppTheme.bg(context), // カプセル裏付近で不透明に
                      AppTheme.bg(context), // ヘッダー裏は完全に不透明
                    ],
                    // ★ 修正：下の少しの領域（約16px分）だけで急速にフェードアウトさせる
                    stops: const [0.0, 0.04, 0.08, 0.12, 0.16, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // -------------------------------------------------------------------
          // 3. 固定ヘッダー（戻るボタン、タイトル、追加ボタン）
          // -------------------------------------------------------------------
          Positioned(
            top: topPadding + 16.0,
            left: 16.0,
            right: 16.0,
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _handleBackNavigation,
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back_ios, color: AppTheme.textMain(context), size: 20),
                          const SizedBox(width: 8),
                          Text("Tasks", style: TextStyle(color: AppTheme.textMain(context), fontSize: 24, fontWeight: FontWeight.w300, letterSpacing: 0)),
                        ]
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _showAddTaskDialog,
                    child: Icon(Icons.add, color: isDark ? Colors.white : Colors.black, size: 28),
                  ),
                ]
            ),
          ),

          // -------------------------------------------------------------------
          // 4. スライド移動するミニマルトグルバー
          // -------------------------------------------------------------------
          Positioned(
            top: topPadding + 64.0, // ヘッダーと少し近づける
            left: 16.0,
            right: 16.0,
            child: Container(
              height: 32, // ★ 修正：高さを抑えて細身のスリムなカプセルに
              width: double.infinity,
              color: Colors.transparent, // 背景（レール）は完全に透明で枠なし
              child: AnimatedBuilder(
                  animation: _taskPageController,
                  builder: (context, child) {
                    // 現在のページ位置 (0.0=PENDING, 1.0=COMPLETED)
                    double page = 0.0;
                    if (_taskPageController.hasClients && _taskPageController.position.haveDimensions) {
                      page = _taskPageController.page ?? (_showCompletedTasks ? 1.0 : 0.0);
                    } else {
                      page = _showCompletedTasks ? 1.0 : 0.0;
                    }

                    // 文字色のクロスフェード
                    Color pendingTxtColor = Color.lerp(activeTextColor, inactiveTextColor, page)!;
                    Color completedTxtColor = Color.lerp(inactiveTextColor, activeTextColor, page)!;

                    return Stack(
                      children: [
                        // --- 物理的にスライド移動するカプセル ---
                        Align(
                          // page が 0 のときは左端(-1.0)、1 のときは右端(1.0)へ移動
                          alignment: Alignment(page * 2 - 1, 0),
                          child: FractionallySizedBox(
                            widthFactor: 0.5, // ちょうど半分の幅
                            heightFactor: 1.0,
                            child: Container(
                              decoration: BoxDecoration(
                                color: activeCapsuleColor,
                                borderRadius: BorderRadius.circular(16), // 細身に合わせた角丸
                              ),
                            ),
                          ),
                        ),

                        // --- 前面のテキスト配置 ---
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  _taskPageController.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
                                },
                                child: Center(
                                    child: Text(
                                        "Pending",
                                        style: TextStyle(
                                            color: pendingTxtColor,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w300,
                                            letterSpacing: 0
                                        )
                                    )
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  _taskPageController.animateToPage(1, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
                                },
                                child: Center(
                                    child: Text(
                                        "Completes",
                                        style: TextStyle(
                                            color: completedTxtColor,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w300,
                                            letterSpacing: 0
                                        )
                                    )
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  }
              ),
            ),
          ),
        ],
      ),
    );
  }




  Widget _buildFullMessagesContent() {
    // 未読・既読メッセージのフィルタリング
    final unreadMessages = _filterMessages((m) => !_dismissedMessageIds.contains(m['id'].toString()) && (m['read_state'] == null || m['read_state'] != 'read'));
    final readMessages = _filterMessages((m) => _dismissedMessageIds.contains(m['id'].toString()) || (m['read_state'] != null && m['read_state'] == 'read'));

    double topPadding = MediaQuery.of(context).padding.top;
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      body: Stack(
        children: [
          // -------------------------------------------------------------------
          // 1. メッセージリスト領域
          // -------------------------------------------------------------------
          Positioned.fill(
            child: ListView(
              padding: EdgeInsets.only(
                  top: topPadding + 88.0, // ヘッダーとグラデーション分を考慮
                  left: 16.0,
                  right: 16.0,
                  bottom: MediaQuery.of(context).padding.bottom + 120.0
              ),
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              children: [
                if (unreadMessages.isNotEmpty) ...[
                  Padding(padding: const EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text("unread", style: TextStyle(color: AppTheme.textSub(context), fontSize: 18, fontWeight: FontWeight.w300))),
                  _buildGroupedMessages(unreadMessages, isUnread: true),
                  const SizedBox(height: 24),
                ],
                if (readMessages.isNotEmpty) ...[
                  Padding(padding: const EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text("read", style: TextStyle(color: AppTheme.textSub(context), fontSize: 18, fontWeight: FontWeight.w300))),
                  Opacity(
                      opacity: 0.5,
                      child: _buildGroupedMessages(readMessages, isUnread: false)
                  ),
                ],
              ],
            ),
          ),

          // -------------------------------------------------------------------
          // 2. フェードアウト用グラデーションマスク
          // -------------------------------------------------------------------
          Positioned(
            top: 0, left: 0, right: 0,
            height: topPadding + 88.0,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AppTheme.bg(context).withOpacity(0.00),
                      AppTheme.bg(context).withOpacity(0.20),
                      AppTheme.bg(context).withOpacity(0.50),
                      AppTheme.bg(context).withOpacity(0.80),
                      AppTheme.bg(context),
                      AppTheme.bg(context),
                    ],
                    stops: const [0.0, 0.10, 0.20, 0.30, 0.40, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // -------------------------------------------------------------------
          // 3. 固定ヘッダー（戻るボタン ＋ タイトル）
          // -------------------------------------------------------------------
          Positioned(
            top: topPadding + 16.0,
            left: 16.0,
            right: 16.0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleBackNavigation,
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_ios, color: AppTheme.textMain(context), size: 20),
                    const SizedBox(width: 8),
                    Text(
                        "All Announcements",
                        style: TextStyle(
                            color: AppTheme.textMain(context),
                            fontSize: 24,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 0
                        )
                    ),
                  ]
              ),
            ),
          ),
        ],
      ),
    );
  }




  // 🟢 修正：カメラ側のマイナス値（-1.0〜0.0）を安全に遮断し、左はみ出しを防止する決定版
  // 🟢 修正完全版：古いログイン画面へのダイレクト遷移をパージし、P2Pポップアップへ完全結線
  Widget _buildBottomNavigation() {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    // 🟢 下部バーの内部レイアウト計算用に、0.0〜1.0の範囲に美しくクランプした安全な位置変数を定義します
    final double safePos = _dragPosition.clamp(0.0, 1.0);

    int leftFlex = (80 - safePos * 60).toInt();
    int rightFlex = (20 + safePos * 60).toInt();

    Color baseBgColor = isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0);
    Color toggleColor = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5);
    Color textColor = AppTheme.textMain(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(8.0, 0, 8.0, MediaQuery.of(context).padding.bottom + 16.0),
      child: Row(
        children: [
          // -------------------------------------------------------------------
          // 【左側】：P2Pコンソール起動 ＆ 同期 ＆ 赤点滅パルスボタン
          // -------------------------------------------------------------------
          AnimatedBuilder(
              animation: Listenable.merge([_colorAnimController, _errorAnimController, _spinAnimController]),
              builder: (context, child) {
                Color bg;
                IconData iconData;
                bool isLoading = _isLoadingAssignments || _isLoadingMessages;
                Color appBgColor = AppTheme.bg(context);

                // ❌ 修正前: if (!widget.isAuthenticated || _hasApiError)
                // 🟢 修正後: 1分間の執行猶予を耐え抜いて、本当にログインが死んでいる時だけ赤点滅させる
                // 🟢 修正版：ガチのログアウト（赤点滅）と単なる通信不通（オレンジ）を完全分離
                if (_shouldShowRedAlert) {
                  // 🚨 5秒以上本当にログアウトしている：激しい警告赤でパルス点滅
                  bg = Color.lerp(const Color(0xFF1A1A1A), const Color(0xFFD0312D), _errorAnimController.value) ?? const Color(0xFFD0312D);
                  iconData = Icons.login_rounded;
                } else if (_hasApiError) {
                  // ⚠️ セッションは生きてるが通信がコケただけ：警告オレンジ（点滅はせず静かにアピール）
                  bg = const Color(0xFFE67E22);
                  iconData = Icons.sync_problem_rounded;
                } else if (isLoading) {
                  bg = _colorAnimController.value == 0.0
                      ? baseBgColor
                      : (Color.lerp(Colors.black, Colors.white, _colorAnimController.value) ?? Colors.black);
                  iconData = Icons.sync;
                } else {
                  bg = baseBgColor;
                  iconData = Icons.sync;
                }

                Widget iconWidget = Icon(iconData, color: textColor);
                if (isLoading) {
                  iconWidget = Transform.rotate(
                    angle: _spinAnimController.value * 2.0 * math.pi,
                    child: iconWidget,
                  );
                }

                return GestureDetector(
                  onTap: () {
                    if (_shouldShowRedAlert) {
                      // 🟢 本物のログアウト時のみ、満を持してP2P接続（QR）を要求
                      _showP2pQRConnectionDialog();
                    } else {
                      // 🟢 通常時、および「単なる通信エラー（オレンジ）」の時は、ボタンを押せば普通にリトライ通信を執行！
                      // これにより、手動でOkta画面にログインしに行く無駄足が完全にゼロになります。
                      _fetchDataParallel();
                    }
                  },
                  child: Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                      color: bg,
                      shape: BoxShape.circle,
                      boxShadow: (!widget.isAuthenticated || _hasApiError) ? [
                        BoxShadow(
                          color: const Color(0xFFD0312D).withOpacity(0.3 * _errorAnimController.value),
                          blurRadius: 12,
                          spreadRadius: 4 * _errorAnimController.value,
                        )
                      ] : null,
                    ),
                    child: iconWidget,
                  ),
                );
              }
          ),
          const SizedBox(width: 8),

          // -------------------------------------------------------------------
          // 【中央】：TO DO ⇄ COURSES メインスライドトグルバー
          // -------------------------------------------------------------------
          Expanded(
            child: LayoutBuilder(
                builder: (context, constraints) {
                  final double toggleWidth = constraints.maxWidth;
                  return GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _dragPosition += details.delta.dx / (toggleWidth * 0.4);
                        _dragPosition = _dragPosition.clamp(0.0, 1.0);
                      });
                    },
                    onHorizontalDragEnd: (details) {
                      double targetPosition;
                      if (details.primaryVelocity != null && details.primaryVelocity!.abs() > 300) {
                        targetPosition = details.primaryVelocity! > 0 ? 0.0 : 1.0;
                      } else {
                        targetPosition = _dragPosition > 0.5 ? 1.0 : 0.0;
                      }

                      _dragAnimController.value = _dragPosition;
                      _dragAnimController.animateTo(targetPosition, duration: const Duration(milliseconds: 150), curve: Curves.easeOutCubic);
                    },
                    child: Container(
                      height: 60,
                      decoration: BoxDecoration(color: baseBgColor, borderRadius: BorderRadius.circular(30)),
                      padding: const EdgeInsets.all(4.0),
                      child: Stack(
                        children: [
                          AnimatedAlign(
                            duration: const Duration(milliseconds: 150),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment(safePos * 2 - 1, 0),
                            child: FractionallySizedBox(
                              widthFactor: 0.8,
                              heightFactor: 1.0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: toggleColor,
                                  borderRadius: BorderRadius.circular(26),
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                flex: leftFlex,
                                child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      _dragAnimController.animateTo(0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
                                      if (_currentViewState != ViewState.home) _handleBackNavigation();
                                    },
                                    child: Center(
                                        child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.view_agenda_rounded, color: textColor, size: 20),
                                              if (safePos < 0.5) ...[
                                                const SizedBox(width: 6),
                                                Flexible(child: Text("TO DO", style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w300, letterSpacing: 0.5), overflow: TextOverflow.clip))
                                              ]
                                            ]
                                        )
                                    )
                                ),
                              ),
                              Expanded(
                                flex: rightFlex,
                                child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      _dragAnimController.animateTo(1.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
                                      if (_currentViewState != ViewState.home) _handleBackNavigation();
                                    },
                                    child: Center(
                                        child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.apps_rounded, color: textColor, size: 20),
                                              if (safePos >= 0.5) ...[
                                                const SizedBox(width: 6),
                                                Flexible(child: Text("COURSES", style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w300, letterSpacing: 0.5), overflow: TextOverflow.clip))
                                              ]
                                            ]
                                        )
                                    )
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }
            ),
          ),
          const SizedBox(width: 8),

          // -------------------------------------------------------------------
          // 【右側】：設定画面（Settings）起動サークルボタン
          // -------------------------------------------------------------------
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(color: baseBgColor, shape: BoxShape.circle),
            child: IconButton(
              icon: Icon(Icons.settings, color: textColor),
              onPressed: widget.onSettings,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 🟢 追加：ライフサイクルチェンジャー ───
  // ─── 🟢 修正：バックグラウンド暴発を100%封殺するライフサイクルチェンジャー ───
  // ─── 🟢 修正：ただ裏から戻っただけの自動同期をパージ ───
  // ─── 🟢 修正：1時間（60分）の絶対経過時間監視スタビライザー ───
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 📱 最前面に戻ってきたとき：バックグラウンド中に1時間以上が経過していたか判定
      if (_lastFetchTime != null) {
        final passedTime = DateTime.now().difference(_lastFetchTime!);

        if (passedTime.inHours >= 1) {
          debugPrint("バックグラウンド経由で1時間以上経過したため復帰時自動同期（経過: ${passedTime.inMinutes}分）");
          _fetchDataParallel();
        } else {
          debugPrint("1時間未満の復帰のため通信をスキップ（経過: ${passedTime.inMinutes}分）");
        }
      } else {
        // 初回など、スタンプがなければ同期
        _fetchDataParallel();
      }

      // 1分周期の経過時間監視タイマーを再始動
      _startAutoRefreshTimer();

    } else {
      // 💤 バックグラウンドに回った瞬間：無駄なタイマーを完全に抹殺
      _autoRefreshTimer?.cancel();
      _autoRefreshTimer = null;
    }
  }

  // ─── 🟢 修正：30分タイマーを完全廃止し、1分精度の経過時間チェッカーへ変更 ───
  void _startAutoRefreshTimer() {
    _autoRefreshTimer?.cancel(); // 二重起動防止のクリーンアップ

    // ⏱️ 1分（60秒）に1回、時計の針をチェックする超軽量な監視レール
    _autoRefreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted && widget.isAuthenticated && _lastFetchTime != null) {
        final passedTime = DateTime.now().difference(_lastFetchTime!);

        // アプリを開いたまま放置され、前回の同期から「1時間（60分）」が経過した瞬間をピンポイント検知
        if (passedTime.inHours >= 1) {
          debugPrint("フォアグラウンド放置状態で1時間以上経過したため自動同期します");
          _fetchDataParallel();
        }
      }
    });
  }




  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    // 🟢 決定打：最外殻を ValueListenableBuilder で包み、白テーマ時のステータスバー文字反転をリアルタイム同期
    return ValueListenableBuilder<String>(
      valueListenable: appGradientThemeNotifier,
      builder: (context, gradientMode, child) {

        // ホーム画面かつ白テーマ（white）の時だけ、ステータスバー文字を専用の「黒（dark）」にスイッチ
        SystemUiOverlayStyle overlayStyle = _currentViewState == ViewState.home
            ? (gradientMode == 'white' ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light)
            : (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark);

        // 🟢 修正：左画面にスワイプする時（_dragPosition < 0）のみ、下部バー群がホーム画面と同期して右側に「すーっ」と掃ける
        double leftSwipeOffset = _dragPosition < 0.0 ? -_dragPosition * MediaQuery.of(context).size.width : 0.0;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyle,
          child: PopScope(
            // 🟢 修正：無地画面のときは、戻るボタン（またはスワイプ戻り）で中央面へ引き返せるようにガード
            canPop: _currentViewState == ViewState.home && _dragPosition == 0.0,
            onPopInvoked: (didPop) {
              if (didPop) return;
              if (_dragPosition < 0.0) {
                _dragAnimController.animateTo(0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
              } else if (_currentViewState != ViewState.home) {
                _handleBackNavigation();
              }
            },
            child: Stack(
              children: [
                Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _currentViewState == ViewState.home
                          ? _buildHomeContent()
                          : _currentViewState == ViewState.fullTasks
                          ? _buildFullTasksContent()
                          : _buildFullMessagesContent(),
                    )
                ),

                // 下部かすみ用グラデーションマスク
                Positioned(
                  bottom: 0,
                  left: leftSwipeOffset, // 👈 🟢 追従オフセットを適用
                  right: -leftSwipeOffset, // 👈 🟢 追従オフセットを適用
                  height: 140.0 + MediaQuery.of(context).padding.bottom + 16.0,
                  child: IgnorePointer(
                    child: Column(
                      children: [
                        Container(
                          height: 140.0,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                AppTheme.bg(context).withOpacity(0.00),
                                AppTheme.bg(context).withOpacity(0.02),
                                AppTheme.bg(context).withOpacity(0.06),
                                AppTheme.bg(context).withOpacity(0.12),
                                AppTheme.bg(context).withOpacity(0.22),
                                AppTheme.bg(context).withOpacity(0.35),
                                AppTheme.bg(context).withOpacity(0.52),
                                AppTheme.bg(context).withOpacity(0.72),
                                AppTheme.bg(context).withOpacity(0.88),
                                AppTheme.bg(context).withOpacity(0.97),
                                AppTheme.bg(context),
                              ],
                              stops: const [0.0, 0.10, 0.20, 0.30, 0.40, 0.50, 0.60, 0.75, 0.88, 0.96, 1.0],
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            color: AppTheme.bg(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 下部ナビゲーションユニット本体
                Positioned(
                    bottom: 0,
                    left: leftSwipeOffset, // 👈 🟢 追従オフセットを適用
                    right: -leftSwipeOffset, // 👈 🟢 追従オフセットを適用
                    child: _buildBottomNavigation()
                )
              ],
            ),
          ),
        );
      },
    );
  }
}


// ★ 追加：1/2スワイプで止まり、再度スワイプで消えるカスタムウィジェット
class _SwipeToDeleteWidget extends StatefulWidget {
  final Widget child;
  final VoidCallback onDelete;


  const _SwipeToDeleteWidget({super.key, required this.child, required this.onDelete});


  @override
  State<_SwipeToDeleteWidget> createState() => _SwipeToDeleteWidgetState();
}


class _SwipeToDeleteWidgetState extends State<_SwipeToDeleteWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _dragOffset = 0.0;
  bool _isHalfOpen = false;


  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _animation = Tween<double>(begin: 0, end: 0).animate(_controller);
    _controller.addListener(() {
      setState(() {
        _dragOffset = _animation.value;
      });
    });
  }


  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }


  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset -= details.delta.dx;
      if (_dragOffset < 0) _dragOffset = 0;
    });
  }


  void _handleDragEnd(DragEndDetails details) {
    double maxOffset = MediaQuery.of(context).size.width;
    double halfOffset = maxOffset * 0.5; // ★ 1/2の位置


    if (!_isHalfOpen) {
      // 最初のスワイプ：1/2を超えたか、勢いよく左にスワイプされたら半分開く
      if (_dragOffset > halfOffset * 0.5 || (details.primaryVelocity != null && details.primaryVelocity! < -300)) {
        _openHalf(halfOffset);
      } else {
        _close();
      }
    } else {
      // 半分開いている状態からのスワイプ
      if (_dragOffset > halfOffset + 40.0 || (details.primaryVelocity != null && details.primaryVelocity! < -300)) {
        _delete(maxOffset);
      } else if (_dragOffset < halfOffset - 40.0 || (details.primaryVelocity != null && details.primaryVelocity! > 300)) {
        _close();
      } else {
        _openHalf(halfOffset); // 少し動かしただけなら半分の状態に戻る
      }
    }
  }


  void _openHalf(double halfOffset) {
    _isHalfOpen = true;
    _animation = Tween<double>(begin: _dragOffset, end: halfOffset).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward(from: 0);
  }


  void _close() {
    _isHalfOpen = false;
    _animation = Tween<double>(begin: _dragOffset, end: 0.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward(from: 0);
  }


  void _delete(double maxOffset) {
    _animation = Tween<double>(begin: _dragOffset, end: maxOffset).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward(from: 0).then((_) {
      widget.onDelete();
    });
  }


  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 32),
              // ★ 修正：角丸指定を削除し、親のウィジェット形状（カードの枠）に依存させる
              color: const Color(0xFFD0312D),
              child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
            ),
          ),
          Transform.translate(
            offset: Offset(-_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

// 🟢 ファイル最末尾に追記：中央基準で目盛りが左右に流れるインライン用ダイヤルペインター
// ─── ファイル下部にある _SlidingDialTicksPainter を丸ごと上書き ───
class _SlidingDialTicksPainter extends CustomPainter {
  final double progress;
  _SlidingDialTicksPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final double centerX = size.width / 2;

    // 🟢 密度の調教：トータルの目盛り数を160本に倍増させ、隙間を 14.0 ➔ 7.0px へハーフ化して高密度に並べます
    const int totalTicks = 160;
    const double tickSpacing = 7.0;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    double activeOffset = progress * totalTicks * tickSpacing;

    for (int i = 0; i <= totalTicks; i++) {
      double x = centerX + (i * tickSpacing) - activeOffset;

      // 画面外の見えない目盛りは計算をスキップ
      if (x < 0 || x > size.width) continue;

      // 画面中央（現在のズーム位置）からの物理的な距離を測定
      double dist = (x - centerX).abs();

      // 左右にフェードアウトしていくお馴染みの超極細透過エフェクト
      double opacity = (1.0 - (dist / centerX)).clamp(0.0, 1.0);
      opacity = math.pow(opacity, 2.5).toDouble();
      if (opacity <= 0.02) continue;

      paint.color = Colors.white.withOpacity(opacity);

      // 🟢 形状の調教：基本の長さはすべて均一（高さの30%）に整列
      double th = size.height * 0.3;

      // 🎯 選択中央イージング：中央から「前後3.5本分」の狭いエリアだけ、中央に近づくほど段階的に膨らませます
      double maxInfluenceDist = tickSpacing * 3.5;
      if (dist < maxInfluenceDist) {
        // 中央ジャストで1.0、離れると0.0になる減衰係数
        double factor = (1.0 - (dist / maxInfluenceDist)).clamp(0.0, 1.0);

        // 中央に向かって最大で高さの50%分、段階的に「じんわり」と縦線を引き伸ばします
        th += size.height * 0.5 * factor;
      }

      // 縦線が常にコンテナの上下中央（センターライン）を基準に上下に等しく伸びるように描画
      double topY = (size.height - th) / 2;
      canvas.drawLine(Offset(x, topY), Offset(x, topY + th), paint);
    }

    // 🟢 物理パージ：不要になった「三角の指示器」の描画ロジック（Path）は跡形もなく完全抹消しました
  }

  @override
  bool shouldRepaint(covariant _SlidingDialTicksPainter old) => old.progress != progress;
}

// 🟢 ファイル最末尾に追記：縮小・右スライドアウト物理モーションを制御する特化型コンソール
class _CameraMemoOverlay extends StatefulWidget {
  final String memoTitleText;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Function(String) onSave;
  final VoidCallback onClose;

  const _CameraMemoOverlay({
    required this.memoTitleText,
    required this.controller,
    required this.focusNode,
    required this.onSave,
    required this.onClose,
  });

  @override
  State<_CameraMemoOverlay> createState() => _CameraMemoOverlayState();
}

// ─── ファイル最末尾の _CameraMemoOverlayState 内 ───
// ─── ファイル最末尾の _CameraMemoOverlayState 内を丸ごと上書き ───
class _CameraMemoOverlayState extends State<_CameraMemoOverlay> with TickerProviderStateMixin { // 🟢 修正：2つのコントローラーを扱うため TickerProviderStateMixin へ変更
  late AnimationController _animController; // 物理スライドアウト用 (550ms)
  late AnimationController _fadeController; // 🟢 追加：じんわりフェードイン/アウト用 (250ms)
  bool _hasText = false;
  bool _isSaving = false; // 🟢 追加：矢印保存ボタンが押されたかを識別するフラグ

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _fadeController = AnimationController( // 🟢 追加：ユーザー指定の250msでフェードを制御
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_onTextChanged);

    // 🟢 起動の瞬間に、背景もテキスト四角もまとめて一斉にじんわりフェードイン点火
    _fadeController.forward();
  }

  void _onTextChanged() {
    if (mounted) {
      setState(() => _hasText = widget.controller.text.trim().isNotEmpty);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _animController.dispose();
    _fadeController.dispose(); // 🟢 追加
    super.dispose();
  }

  // 🟢 追加：キャンセル（背景タップ・×ボタン）時のじんわりフェードアウト共通ロジック
  // 🟢 キャンセル（背景タップ・×ボタン）時のじんわりフェードアウト共通ロジック
  Future<void> _closeWithFade() async {
    widget.focusNode.unfocus();      // ① キーボードを閉じ始める（ここから250msのカウント開始）
    await _fadeController.reverse(); // ② 250ms かけて背景とタイトルを滑らかにフェードアウト

    // 🟢 決定打：OS側のキーボード格納アニメーションが完全に終了するまでのわずかなタイムラグ（約50ms）を確実に吸収します。
    // これにより、閉じ始めてから「ジャスト300ms後」の完璧にフラットになった画面へシャッターボタン群を安全に呼び戻します。
    await Future.delayed(const Duration(milliseconds: 50));

    widget.onClose(); // ③ 親のフラグを false に戻し、満を持して操作バーを無傷で復活させます
  }

  void _handlePublish() {
    if (!_hasText || _animController.isAnimating) return;
    final text = widget.controller.text.trim();
    widget.focusNode.unfocus();

    setState(() => _isSaving = true); // 🟢 追加：保存演出が始まった瞬間にフラグをロック

    // 保存時は、四角が右へ掃けていく動き(550ms)と並行して、背景グラデーションも550msかけてじんわり消去します
    _fadeController.animateTo(0.0, duration: const Duration(milliseconds: 550));

    _animController.forward().then((_) {
      widget.onSave(text);
      widget.controller.clear();
      widget.onClose();
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color circleBgColor = isDark ? Colors.white : Colors.black;
    Color circleIconColor = isDark ? Colors.black : Colors.white;
    double screenWidth = MediaQuery.of(context).size.width;

    // 🟢 決定打：背景とインプラントを ValueListenableBuilder で包み、電線と直結同期
    return ValueListenableBuilder<String>(
      valueListenable: appGradientThemeNotifier,
      builder: (context, gradientMode, child) {
        // 現在選択されているテーマの3色パレットを動的に取得
        final currentPalette = AppGradient.getColors(gradientMode);

        return Stack(
          children: [
            // 🟢 ① 背景グラデーションだけを 250ms のじんわりフェードに個別バインド
            Positioned.fill(
              child: FadeTransition(
                opacity: _fadeController,
                child: GestureDetector(
                  onTap: _closeWithFade,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(1),
                          currentPalette[0], // 🟢 動的パレット（Top）を注入
                          currentPalette[1], // 🟢 動的パレット（Mid）を注入
                          currentPalette[2], // 🟢 動的パレット（Bot）を注入
                        ],
                        stops: const [0.0, 0.26, 0.63, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 🟢 ② 左上の大きめタイトルも 250ms のじんわりフェードに個別バインド
            Positioned(
              top: MediaQuery.of(context).padding.top + 20,
              left: 20, right: 20,
              child: FadeTransition(
                opacity: _fadeController,
                child: Text(
                  widget.memoTitleText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            // 🟢 ③ メモの四角（コンソール外殻）はフェードから完全に解放！
            Positioned(
              bottom: 8, left: 8, right: 8,
              child: AnimatedBuilder(
                animation: Listenable.merge([_animController, _fadeController]),
                builder: (context, child) {
                  double scale = ui.lerpDouble(1.0, 0.75, Curves.easeOutCubic.transform(_animController.value))!;
                  double slideX = ui.lerpDouble(0.0, screenWidth * 1.3, Curves.easeInOutCubic.transform(_animController.value))!;

                  // 起動時・キャンセル時は滑らかにフェードし、矢印保存時のみフェードアウトを1.0で完全ロック
                  double boxOpacity = _isSaving ? 1.0 : _fadeController.value;

                  return Transform.translate(
                    offset: Offset(slideX, 0),
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment.center,
                      child: Opacity(
                        opacity: boxOpacity,
                        child: child,
                      ),
                    ),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ×マーク（角丸四角のすぐ左上）
                    Padding(
                      padding: const EdgeInsets.only(left: 12.0, bottom: 4.0),
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                        onPressed: _closeWithFade,
                      ),
                    ),

                    // メモ四角（R30フィレット）
                    Container(
                      padding: const EdgeInsets.all(20.0),
                      decoration: BoxDecoration(
                        color: AppTheme.panel(context),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 32.0),
                            child: TextField(
                              controller: widget.controller,
                              focusNode: widget.focusNode,
                              minLines: 3,
                              maxLines: null,
                              cursorColor: isDark ? Colors.white : Colors.black,
                              style: TextStyle(color: AppTheme.textMain(context), fontSize: 18, height: 1.4),
                              decoration: InputDecoration(
                                hintText: "メモを追加",
                                hintStyle: TextStyle(color: AppTheme.textSub(context).withOpacity(0.4), fontSize: 18),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),

                          // 右下の矢印ボタン
                          GestureDetector(
                            onTap: _hasText ? _handlePublish : null,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 150),
                              opacity: _hasText ? 1.0 : 0.15,
                              child: Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: circleBgColor,
                                ),
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  color: circleIconColor,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}