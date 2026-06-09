import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_calendar/device_calendar.dart' as dc;
import 'dart:math' as math;

import '../core/app_theme.dart';
import '../services/calendar_sync_service.dart';
import 'media_viewers.dart'; // フィードバックのWebViewで使う
import 'info_screens.dart';  // ガイドや規約画面への遷移で使う
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../utils/dummy_data_helper.dart';
import '../services/cache_manager.dart';
import '../services/auth_service.dart';
import 'package:url_launcher/url_launcher.dart'; // 👈 設定画面へジャンプするために追加

class TermCirclePainter extends CustomPainter {
  final bool q1Active;
  final bool q2Active;
  final bool q3Active;
  final bool q4Active;
  final Color activeColor;
  final Color inactiveColor;


  TermCirclePainter(this.q1Active, this.q2Active, this.q3Active, this.q4Active, this.activeColor, this.inactiveColor);


  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 // 極細の円環
      ..strokeCap = StrokeCap.round;


    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    final double gap = 0.2;
    final double sweep = (math.pi / 2) - gap;


    // Q1 (右下)
    paint.color = q1Active ? activeColor : inactiveColor;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), gap / 2, sweep, false, paint);


    // Q2 (左下)
    paint.color = q2Active ? activeColor : inactiveColor;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), math.pi / 2 + gap / 2, sweep, false, paint);


    // Q3 (左上)
    paint.color = q3Active ? activeColor : inactiveColor;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), math.pi + gap / 2, sweep, false, paint);


    // Q4 (右上)
    paint.color = q4Active ? activeColor : inactiveColor;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), 3 * math.pi / 2 + gap / 2, sweep, false, paint);
  }


  @override
  bool shouldRepaint(covariant TermCirclePainter oldDelegate) {
    return oldDelegate.q1Active != q1Active ||
        oldDelegate.q2Active != q2Active ||
        oldDelegate.q3Active != q3Active ||
        oldDelegate.q4Active != q4Active;
  }
}


class YearCirclePainter extends CustomPainter {
  final double pulseValue;
  final bool isClockwise;
  final Color activeColor;
  final Color inactiveColor;


  YearCirclePainter(this.pulseValue, this.isClockwise, this.activeColor, this.inactiveColor);


  @override
  void paint(Canvas canvas, Size size) {
    final Paint basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 // 極細線
      ..color = inactiveColor
      ..strokeCap = StrokeCap.round;


    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;


    // 分割のない1周のベースライン
    canvas.drawCircle(center, radius, basePaint);


    // パルスアニメーション (0.0 〜 1.0 で1周)
    if (pulseValue > 0.0 && pulseValue < 1.0) {
      canvas.save();
      canvas.translate(center.dx, center.dy);


      // アニメーションの進行に合わせてキャンバスを回転
      double currentAngle = -math.pi / 2 + (isClockwise ? pulseValue * 2 * math.pi : -pulseValue * 2 * math.pi);
      canvas.rotate(currentAngle);


      final Rect localRect = Rect.fromCircle(center: Offset.zero, radius: radius);


      // サイン波でフェードイン・フェードアウトする不透明度
      final double opacity = math.sin(pulseValue * math.pi);


      // 美しいグラデーションの尾を引くパルス
      final Gradient gradient = SweepGradient(
        colors: isClockwise
            ? [activeColor.withOpacity(0.0), activeColor.withOpacity(0.0), activeColor.withOpacity(opacity)]
            : [activeColor.withOpacity(opacity), activeColor.withOpacity(0.0), activeColor.withOpacity(0.0)],
        stops: const [0.0, 0.5, 1.0],
      );


      final Paint pulsePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..shader = gradient.createShader(localRect)
        ..strokeCap = StrokeCap.round;


      // 回転したキャンバス上に円を描画することで、グラデーションが回っているように見せる
      canvas.drawCircle(Offset.zero, radius, pulsePaint);
      canvas.restore();
    }
  }


  @override
  bool shouldRepaint(covariant YearCirclePainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue || oldDelegate.isClockwise != isClockwise;
  }
}


class SettingsScreen extends StatefulWidget {
  final int currentYear;
  final String currentTerm;
  final bool isAuthenticated;
  final VoidCallback onLogin;
  final VoidCallback onLogout;
  final Function(int, String) onApply;

  const SettingsScreen({super.key, required this.currentYear, required this.currentTerm, required this.isAuthenticated, required this.onLogin, required this.onLogout, required this.onApply});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}


class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late int tempYear;
  late String tempTerm;
  late bool _isAuthenticated;

  late AnimationController _pulseController;
  bool _isClockwise = true;

  // スクロール検知用コントローラー
  late ScrollController _scrollController;

  // カレンダー同期用ステート
  bool _isSyncEnabled = false;
  String? _targetCalendarId;
  List<dc.Calendar> _availableCalendars = [];

  bool _syncTasksEnabled = false;
  bool _syncSchedulesEnabled = false;
  bool _importEventsEnabled = false;

  @override
  void initState() {
    super.initState();
    tempYear = widget.currentYear;
    tempTerm = widget.currentTerm;
    _isAuthenticated = widget.isAuthenticated;

    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

    _scrollController = ScrollController();
    _scrollController.addListener(() {
      setState(() {});
    });

    _loadSyncSettings();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSyncSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isSyncEnabled = prefs.getBool('calendar_sync_enabled') ?? false;
      _targetCalendarId = prefs.getString('calendar_sync_target_id');
      _syncTasksEnabled = prefs.getBool('sync_tasks_enabled') ?? false;
      _syncSchedulesEnabled = prefs.getBool('sync_schedules_enabled') ?? false;
      _importEventsEnabled = prefs.getBool('sync_import_enabled') ?? false;
    });
    if (_isSyncEnabled) {
      await _fetchCalendars();
    }
  }

  Future<void> _fetchCalendars() async {
    final cals = await CalendarSyncService.getWritableCalendars();
    setState(() {
      _availableCalendars = cals;
      if (_targetCalendarId != null && !_availableCalendars.any((c) => c.id == _targetCalendarId)) {
        _targetCalendarId = null;
      }
    });
  }

  Future<void> _toggleSyncTasks(bool value) async {
    setState(() => _syncTasksEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_tasks_enabled', value);
    if (!value) await CalendarSyncService.disableTaskSync();
  }

  Future<void> _toggleSyncSchedules(bool value) async {
    setState(() => _syncSchedulesEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_schedules_enabled', value);
    if (!value) await CalendarSyncService.disableScheduleSync();
  }

  Future<void> _toggleImportEvents(bool value) async {
    setState(() => _importEventsEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_import_enabled', value);
  }

  // lib/screens/settings_screen.dart 内の _toggleSync メソッドを上書き
  Future<void> _toggleSync(bool value) async {
    if (value) {
      bool granted = await CalendarSyncService.requestPermissions();
      if (!granted) {
        // ★ 修正：一度不許可にされている場合、ユーザーが端末の設定から直接変更できるように誘導ダイアログを起動
        _showPermissionGuideDialog();
        return;
      }
      await _fetchCalendars();
    }

    setState(() {
      _isSyncEnabled = value;
      if (!value) {
        _targetCalendarId = null;
        _syncTasksEnabled = false;
        _syncSchedulesEnabled = false;
        _importEventsEnabled = false;
      }
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('calendar_sync_enabled', _isSyncEnabled);
    if (!value) {
      await prefs.remove('calendar_sync_target_id');
      await prefs.setBool('sync_tasks_enabled', false);
      await prefs.setBool('sync_schedules_enabled', false);
      await prefs.setBool('sync_import_enabled', false);
      await CalendarSyncService.disableTaskSync();
      await CalendarSyncService.disableScheduleSync();
    }
  }

  // ★ 新設：拒否状態のテスターを端末の設定画面へワンタップで飛ばすソリッドな案内ダイアログ
  void _showPermissionGuideDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('カレンダー権限が必要です', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        content: const Text(
          '一度カレンダーへのアクセスが拒否されたため、アプリ内からダイアログを再表示できません。\n\n同期機能を利用するには、下の「設定を開く」から端末の設定アプリへ移動し、アクセス権限を許可に変更してください。',
          style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            child: const Text('キャンセル', style: TextStyle(color: Colors.black54)),
            onPressed: () => Navigator.pop(ctx),
          ),
          TextButton(
            child: const Text('設定を開く', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                // iOS / Androidシステム共通の「このアプリのシステム設定画面」を直接開くディープリンクを発火
                final Uri settingUri = Uri.parse('app-settings:');
                if (await canLaunchUrl(settingUri)) {
                  await launchUrl(settingUri);
                }
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('端末の設定アプリ > 本アプリ > カレンダー から許可してください。')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _selectTargetCalendar(String? calId) async {
    if (calId == null) return;
    setState(() => _targetCalendarId = calId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('calendar_sync_target_id', calId);
  }

  bool get q1 => tempTerm.contains('春') || tempTerm.contains('Q1') || tempTerm.contains('通年');
  bool get q2 => tempTerm.contains('春') || tempTerm.contains('Q2') || tempTerm.contains('通年');
  bool get q3 => tempTerm.contains('秋') || tempTerm.contains('Q3') || tempTerm.contains('通年');
  bool get q4 => tempTerm.contains('秋') || tempTerm.contains('Q4') || tempTerm.contains('通年');

  void _update() { widget.onApply(tempYear, tempTerm); }

  Future<void> _clearAppCache() async {
    try {} catch (e) { debugPrint("Manual Cache Clear Error (WebView): $e"); }
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        tempDir.listSync().forEach((file) {
          try { if (file is File) file.deleteSync(); } catch (_) {}
        });
      }
    } catch (e) {
      debugPrint("Manual Cache Clear Error (Temp files): $e");
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('キャッシュをクリアしました（空き容量を確保しました）'))
      );
    }
  }

  void _animateYear(bool increase) {
    setState(() { if (increase) { tempYear++; _isClockwise = true; } else { tempYear--; _isClockwise = false; } _update(); });
    _pulseController.forward(from: 0.0);
  }

  void _handleCircleTap(Offset localPosition, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final angle = math.atan2(localPosition.dy - center.dy, localPosition.dx - center.dx);
    bool nq1 = q1, nq2 = q2, nq3 = q3, nq4 = q4;
    setState(() {
      if (angle >= 0 && angle < math.pi / 2) nq1 = !nq1;
      else if (angle >= math.pi / 2 && angle <= math.pi) nq2 = !nq2;
      else if (angle >= -math.pi && angle < -math.pi / 2) nq3 = !nq3;
      else nq4 = !nq4;
      if (nq1 && nq2 && nq3 && nq4) tempTerm = "通年";
      else if (nq1 && nq2 && !nq3 && !nq4) tempTerm = "春学期";
      else if (!nq1 && !nq2 && nq3 && nq4) tempTerm = "秋学期";
      else {
        List<String> parts = [];
        if (nq1) parts.add("Q1"); if (nq2) parts.add("Q2"); if (nq3) parts.add("Q3"); if (nq4) parts.add("Q4");
        tempTerm = parts.isEmpty ? "未選択" : parts.join(".");
      }
      _update();
    });
  }

  Widget _buildSyncSubToggle(String title, bool value, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(color: AppTheme.textMain(context), fontSize: 13, fontWeight: FontWeight.w300)),
          SizedBox(
            height: 20,
            child: Transform.scale(
              scale: 0.75,
              child: Switch(
                value: value,
                onChanged: (v) {
                  if (_targetCalendarId == null && title.contains('Export')) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a target calendar first.')));
                    return;
                  }
                  onChanged(v);
                },
                activeColor: AppTheme.textMain(context),
                activeTrackColor: AppTheme.textMain(context).withOpacity(0.5),
                inactiveThumbColor: AppTheme.textSub(context),
                inactiveTrackColor: Colors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    double topPadding = MediaQuery.of(context).padding.top;
    double minHeaderHeight = topPadding + 56.0;
    double maxHeaderHeight = topPadding + 310.0;
    double shrinkLimit = maxHeaderHeight - minHeaderHeight;

    double scrollOffset = _scrollController.hasClients ? math.max(0.0, _scrollController.offset) : 0.0;
    double currentHeaderHeight = math.max(minHeaderHeight, maxHeaderHeight - scrollOffset);

    double t = (scrollOffset / shrinkLimit).clamp(0.0, 1.0);
    double contentOpacity = math.max(0.0, 1.0 - t * 2.0);

    return Scaffold(
        backgroundColor: AppTheme.bg(context),
        body: Stack(
            children: [
              // ----------------------------------------------------
              // 1. スクロールするリストコンテンツ（下部）
              // ----------------------------------------------------
              ListView(
                  controller: _scrollController,
                  padding: EdgeInsets.only(top: maxHeaderHeight + 34.0, bottom: 100.0 + MediaQuery.of(context).padding.bottom),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    // カレンダー同期ウィジェット
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Container(
                        decoration: BoxDecoration(color: AppTheme.panel(context), borderRadius: BorderRadius.circular(30)),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text("カレンダー同期", style: TextStyle(color: AppTheme.textMain(context), fontWeight: FontWeight.w300)),
                                  SizedBox(
                                    height: 20,
                                    child: Transform.scale(
                                      scale: 0.75,
                                      child: Switch(
                                        value: _isSyncEnabled,
                                        onChanged: _toggleSync,
                                        activeColor: AppTheme.textMain(context),
                                        activeTrackColor: AppTheme.textMain(context).withOpacity(0.5),
                                        inactiveThumbColor: AppTheme.textSub(context),
                                        inactiveTrackColor: Colors.transparent,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              child: _isSyncEnabled
                                  ? Column(
                                children: [
                                  Divider(height: 1, color: AppTheme.bg(context)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text("アカウントの選択", style: TextStyle(color: AppTheme.textMain(context), fontWeight: FontWeight.w300)),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Align(
                                            alignment: Alignment.centerRight,
                                            child: _availableCalendars.isEmpty
                                                ? Text("No Calendars Found", style: TextStyle(color: AppTheme.textSub(context), fontSize: 12))
                                                : Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: AppTheme.textMain(context).withOpacity(0.05),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: DropdownButtonHideUnderline(
                                                child: DropdownButton<String>(
                                                  value: _targetCalendarId,
                                                  hint: Text("Select...", style: TextStyle(color: AppTheme.textSub(context), fontSize: 13)),
                                                  icon: Icon(Icons.arrow_drop_down, color: AppTheme.textSub(context), size: 20),
                                                  dropdownColor: AppTheme.panel(context),
                                                  elevation: 0,
                                                  borderRadius: BorderRadius.circular(20),
                                                  style: TextStyle(color: AppTheme.textMain(context), fontSize: 13, fontWeight: FontWeight.w300),
                                                  isDense: true,
                                                  onChanged: _selectTargetCalendar,
                                                  items: _availableCalendars.map((c) {
                                                    String name = c.name ?? 'Unknown';
                                                    if (name.length > 18) name = "${name.substring(0, 16)}...";
                                                    return DropdownMenuItem<String>(value: c.id, child: Text(name));
                                                  }).toList(),
                                                ),
                                              ),
                                            ),
                                          ),
                                        )
                                      ],
                                    ),
                                  ),
                                  if (_targetCalendarId != null) ...[
                                    Divider(height: 1, color: AppTheme.bg(context)),
                                    _buildSyncSubToggle("タスクをカレンダーに追加", _syncTasksEnabled, _toggleSyncTasks),
                                    _buildSyncSubToggle("授業予定をカレンダーに追加", _syncSchedulesEnabled, _toggleSyncSchedules),
                                    _buildSyncSubToggle("アプリにカレンダーの予定を表示", _importEventsEnabled, _toggleImportEvents),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 20.0, right: 20.0, bottom: 20.0, top: 12.0),
                                      child: Text("次回の再起動時に変更が反映されます", style: TextStyle(color: AppTheme.textSub(context).withOpacity(0.5), fontSize: 10, height: 1.4)),
                                    )
                                  ] else const SizedBox(height: 8)
                                ],
                              ) : const SizedBox(width: double.infinity, height: 0),
                            )
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ガイド / バージョン / キャッシュクリア
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Container(
                          decoration: BoxDecoration(color: AppTheme.panel(context), borderRadius: BorderRadius.circular(30)),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                              children: [
                                _buildCustomListItem("Guide", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GuideScreen()))),
                                Divider(height: 1, color: AppTheme.bg(context)),
                                _buildCustomListItem("Version", trailingText: "1.0.2", onTap: () {}),
                                Divider(height: 1, color: AppTheme.bg(context)),
                                _buildCustomListItem("Clear Cache (Free up space)", onTap: _clearAppCache, hideArrow: true),
                              ]
                          )
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ----------------------------------------------------
                    // ★ 修正：プライバシー / 利用規約 / ライセンス の統合外部化
                    // ----------------------------------------------------
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Container(
                          decoration: BoxDecoration(color: AppTheme.panel(context), borderRadius: BorderRadius.circular(30)),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                              children: [
                                // Privacy Policy（プライバシーポリシー）
                                _buildCustomListItem("Privacy Policy", onTap: () {
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsWebBrowserScreen(url: "https://sites.google.com/view/kportal-app/en", title: 'Privacy Policy')));
                                }),
                                Divider(height: 1, color: AppTheme.bg(context)),

                                // Terms of Use（利用規約：プライバシーポリシーと同じ外部URLへリダイレクト）
                                _buildCustomListItem("Terms of Use", onTap: () {
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsWebBrowserScreen(url: "https://sites.google.com/view/kportal-app/en", title: 'Terms of Use')));
                                }),
                                Divider(height: 1, color: AppTheme.bg(context)),

                                // Open Source Libraries
                                _buildCustomListItem("Open Source Libraries", onTap: () {
                                  showLicensePage(context: context, applicationVersion: '1.0.2', applicationLegalese: '© 2026 Developer');
                                }),
                              ]
                          )
                      ),
                    ),

                    // settings_screen.dart 内の ListView の最下部付近
                    // プライバシーや利用規約のコンテナの下に追記します

                    if (!_isAuthenticated) ...[
                      const SizedBox(height: 32),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppTheme.panel(context),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _buildCustomListItem(
                            "Test login",
                            hideArrow: false,
                            onTap: () async {
                              // 1. ダミーデータを最新の選択年度に合わせてキャッシュに直接注入
                              final dummyCourses = DummyDataHelper.getCourses(tempYear);
                              final dummyAssignments = DummyDataHelper.getDummyAssignments(tempYear);
                              final dummyMessages = DummyDataHelper.getDummyMessages();

                              await CacheManager.save('my_course_cache_v10', dummyCourses);
                              await CacheManager.save('cached_assignments_v14_all_year', dummyAssignments);
                              await CacheManager.save('cached_messages_v14_all_year', dummyMessages);

                              // 2. セッション情報を特別な文字列でダミー偽装保存
                              await AuthService.saveSession("dummy_test_session");

                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('テスト用ダミーデータをロードしました。アプリを再起動してくさだい。')),
                                );
                                Navigator.pop(context);
                                // メイン画面側に更新通知をトス（これでホームが自動でリロードされます）
                                widget.onApply(tempYear, tempTerm);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                    // 🛠️ 先ほど追加したテストログインのブロックの「すぐ下」に追記します
                    const SizedBox(height: 32),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.panel(context),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _buildCustomListItem(
                          "アプリを完全に初期状態に戻す",
                          hideArrow: true,
                          onTap: () {
                            // 安全のため、全消去の前に確認ダイアログを挟む
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: Colors.white,
                                title: const Text('データの完全初期化', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                content: const Text(
                                  '保存されているすべての授業データ、時間割、課題、お知らせ、ローカルのメモ、および写真ファイルが完全に削除されます。\n\nこの操作は取り消せません。よろしいですか？',
                                  style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.4),
                                ),
                                actions: [
                                  TextButton(
                                    child: const Text('キャンセル', style: TextStyle(color: Colors.black54)),
                                    onPressed: () => Navigator.pop(ctx),
                                  ),
                                  TextButton(
                                    child: const Text('すべて削除する', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold)),
                                    // settings_screen.dart 内の「すべて削除する」ボタンの onPressed 内部
                                    onPressed: () async {
                                      Navigator.pop(ctx); // ダイアログを閉じる

                                      // 1. セッション（SecureStorage等）の完全破棄
                                      await AuthService.clearSession();

                                      // 2. SharedPreferencesの完全消去
                                      final prefs = await SharedPreferences.getInstance();
                                      await prefs.clear();

                                      try {
                                        await CookieManager.instance().deleteAllCookies();
                                      } catch (e) {
                                        debugPrint("Settings clear cookies error: $e");
                                      }

                                      // 3. 【最重要】CacheManagerの物理ファイルを空の配列で上書きして消滅させる
                                      await CacheManager.save('my_course_cache_v10', <dynamic>[]);
                                      await CacheManager.save('cached_assignments_v14_all_year', <dynamic>[]);
                                      await CacheManager.save('cached_messages_v14_all_year', <dynamic>[]);

                                      // 4. ローカルの添付画像やTemp内ファイルの一括削除
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
                                        debugPrint("File systems clear error: $e");
                                      }

                                      // 5. 完了通知を出し、上位のSkeletonへ「initialized」の合図を投げて画面を閉じる
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('すべてのデータを削除し、初期状態にリセットしました。アプリを再起動してください。')),
                                        );
                                        // ★ 変更：合図（result）を渡して設定画面を閉じる
                                        Navigator.pop(context, 'initialized');
                                      }
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ]
              ),

              // ----------------------------------------------------
              // 2. スクロールで縮むグラデーションヘッダー（上部）
              // ----------------------------------------------------
              Positioned(
                  top: 0, left: 0, right: 0,
                  height: currentHeaderHeight,
                  child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          // 👇 ここを3色のグラデーションに変更 👇
                          colors: [
                            Color(0xFF020403), // トップ
                            Color(0xFF2c4f5f), // ミドル
                            Color(0xFFa8ccdc), // ボトム
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(32),
                          bottomRight: Radius.circular(32),
                        ),
                      ),
                      child: SafeArea(
                          bottom: false,
                          child: Column(
                              children: [
                                // --- 戻るボタン ＆ ログアウトボタン領域 ---
                                Container(
                                    height: 56.0,
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                    child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () => Navigator.pop(context),
                                              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                                                Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                                                SizedBox(width: 8),
                                                // ★ 修正：SETTINGS の文字を細字 (w300) に変更
                                                Text("SETTINGS", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w300, letterSpacing: 1.0)),
                                              ])
                                          ),
                                          GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () {
                                              if (_isAuthenticated) { widget.onLogout(); setState(() => _isAuthenticated = false); }
                                              else { Navigator.pop(context); widget.onLogin(); }
                                            },
                                            child: Icon(_isAuthenticated ? Icons.logout_rounded : Icons.login_rounded, color: Colors.white, size: 24),
                                          )
                                        ]
                                    )
                                ),

                                // lib/screens/settings_screen.dart 内の build メソッド中盤
                                // --- 学期・年度の輪っか ＆ テーマ変更ウィジェット ---
                                if (contentOpacity > 0)
                                  Expanded(
                                    child: SingleChildScrollView(
                                      physics: const NeverScrollableScrollPhysics(),
                                      child: Opacity(
                                        opacity: contentOpacity,
                                        child: Column(
                                          children: [
                                            // ★ 修正：iPadの大画面で円が巨大化してはみ出るのを防ぐため、Center と ConstrainedBox で最大横幅を 380px に美しく制限
                                            Padding(
                                                padding: const EdgeInsets.only(left: 32.0, right: 32.0, bottom: 8.0, top: 4.0),
                                                child: Center(
                                                  child: ConstrainedBox(
                                                    constraints: const BoxConstraints(maxWidth: 380),
                                                    child: Row(children: [
                                                      // 左：年度（Year）
                                                      Expanded(
                                                          flex: 1,
                                                          child: LayoutBuilder(builder: (context, constraints) {
                                                            return AspectRatio(
                                                                aspectRatio: 1.0,
                                                                child: Stack(
                                                                  alignment: Alignment.center,
                                                                  children: [
                                                                    SizedBox(
                                                                      width: constraints.maxWidth, height: constraints.maxWidth,
                                                                      child: AnimatedBuilder(
                                                                        animation: _pulseController,
                                                                        builder: (context, child) => CustomPaint(painter: YearCirclePainter(_pulseController.value, _isClockwise, Colors.white, Colors.white.withOpacity(0.2))),
                                                                      ),
                                                                    ),
                                                                    Column(
                                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                                      children: [
                                                                        _buildArrowBtn(Icons.keyboard_arrow_up, () => _animateYear(true), Colors.white),
                                                                        Text(tempYear.toString(), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w200, letterSpacing: 2.0, height: 1.0)),
                                                                        _buildArrowBtn(Icons.keyboard_arrow_down, () => _animateYear(false), Colors.white),
                                                                      ],
                                                                    )
                                                                  ],
                                                                ));
                                                          })
                                                      ),
                                                      const SizedBox(width: 32),
                                                      // 右：学期（Term）
                                                      Expanded(
                                                          flex: 1,
                                                          child: LayoutBuilder(builder: (context, constraints) {
                                                            return GestureDetector(
                                                                onTapDown: (details) => _handleCircleTap(details.localPosition, Size(constraints.maxWidth, constraints.maxWidth)),
                                                                child: AspectRatio(
                                                                    aspectRatio: 1.0,
                                                                    child: Stack(
                                                                      alignment: Alignment.center,
                                                                      children: [
                                                                        SizedBox(
                                                                          width: constraints.maxWidth, height: constraints.maxWidth,
                                                                          child: CustomPaint(painter: TermCirclePainter(q1, q2, q3, q4, Colors.white, Colors.white.withOpacity(0.2))),
                                                                        ),
                                                                        Padding(
                                                                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                                                          child: Text(tempTerm, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w300), maxLines: 2, overflow: TextOverflow.ellipsis),
                                                                        ),
                                                                      ],
                                                                    )));
                                                          })
                                                      ),
                                                    ]),
                                                  ),
                                                )
                                            ),

                                            const SizedBox(height: 8),

                                            // ★ 修正：テーマ変更カプセルも、iPadで横に間伸びしないように最大横幅を円と同期（380px）させて美しく中央配置
                                            Padding(
                                              padding: const EdgeInsets.only(left: 24.0, right: 24.0, bottom: 16.0),
                                              child: Center(
                                                child: ConstrainedBox(
                                                  constraints: const BoxConstraints(maxWidth: 380),
                                                  child: Container(
                                                      decoration: BoxDecoration(
                                                        color: Colors.white.withOpacity(0.15),
                                                        borderRadius: BorderRadius.circular(30),
                                                      ),
                                                      padding: const EdgeInsets.all(4.0),
                                                      child: Row(
                                                          children: [
                                                            _buildThemeSegment("System", ThemeMode.system),
                                                            _buildThemeSegment("Light", ThemeMode.light),
                                                            _buildThemeSegment("Dark", ThemeMode.dark),
                                                          ]
                                                      )
                                                  ),
                                                ),
                                              ),
                                            )
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                              ]
                          )
                      )
                  )
              ),

              // ----------------------------------------------------
              // 3. フィードバックボタンの真ん中より下を隠す背景
              // ----------------------------------------------------
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                // ★ 修正：FEEDBACKボタンの高さ(60)の半分(30) ＋ 下部余白(16) ＋ OSの底面余白 分をベタ塗り
                height: 30.0 + 16.0 + MediaQuery.of(context).padding.bottom,
                child: IgnorePointer(
                  child: Container(
                    color: AppTheme.bg(context),
                  ),
                ),
              ),

              // ----------------------------------------------------
              // 4. 画面下部に完全固定されるフィードバックボタン
              // ----------------------------------------------------
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(8.0, 0, 8.0, MediaQuery.of(context).padding.bottom + 16.0),
                  child: Container(
                    decoration: BoxDecoration(color: isDark ? Colors.white : Colors.black, borderRadius: BorderRadius.circular(30)),
                    clipBehavior: Clip.antiAlias,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsWebBrowserScreen(url: "https://docs.google.com/forms/d/e/1FAIpQLSeQMBcpW781ng45wNbGJKqBIqq492AnmMMie5-9ihkGg1eAkw/viewform?usp=header/viewform", title: 'Feedback')));
                        },
                        child: SizedBox(
                          height: 60,
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.mode_comment_outlined, color: isDark ? Colors.black : Colors.white, size: 18),
                                const SizedBox(width: 12),
                                Text("FEEDBACK", style: TextStyle(color: isDark ? Colors.black : Colors.white, fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 2.0)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            ]
        )
    );
  }

  Widget _buildArrowBtn(IconData icon, VoidCallback onTap, [Color? iconColor]) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 0.0),
        child: Icon(icon, size: 28, color: (iconColor ?? AppTheme.textMain(context)).withOpacity(0.5)),
      ),
    );
  }

  Widget _buildCustomListItem(String title, {String? trailingText, VoidCallback? onTap, bool hideArrow = false}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: TextStyle(color: AppTheme.textMain(context), fontWeight: FontWeight.w300)),
            if (trailingText != null)
              Text(trailingText, style: TextStyle(color: AppTheme.textSub(context), fontWeight: FontWeight.w300, fontSize: 14))
            else if (onTap != null && !hideArrow)
              Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textSub(context)),
          ],
        ),
      ),
    );
  }


  // ★ テーマ変更カプセルのトグル色をモードに合わせて動的に変更
  Widget _buildThemeSegment(String title, ThemeMode mode) {
    bool isSelected = appThemeNotifier.value == mode;
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    // ★ 修正：ダークモード時の選択色は真っ黒ではなく「濃い灰色 (0xFF333333)」
    Color activeBgColor = isDark ? const Color(0xFF222222) : Colors.white;

    return Expanded(
        child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              appThemeNotifier.value = mode;
              final prefs = await SharedPreferences.getInstance();
              if (mode == ThemeMode.system) {
                prefs.remove('app_theme_mode');
              } else {
                prefs.setString('app_theme_mode', mode == ThemeMode.light ? 'light' : 'dark');
              }
              setState(() {});
            },
            child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                    color: isSelected ? activeBgColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(26)
                ),
                child: Center(
                  child: Text(title, style: TextStyle(
                      color: isSelected
                          ? (isDark ? Colors.white : Colors.black)
                          : Colors.white.withOpacity(0.8),
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w400
                  )),
                )
            )
        )
    );
  }
}



// ★ settings_screen.dart の一番下に追加したクラスを以下に差し替えてください ★
class SettingsWebBrowserScreen extends StatefulWidget {
  final String url;
  final String title; // 呼び出し側でのエラーを防ぐため変数は残しておきます

  const SettingsWebBrowserScreen({super.key, required this.url, required this.title});

  @override
  State<SettingsWebBrowserScreen> createState() => _SettingsWebBrowserScreenState();
}

class _SettingsWebBrowserScreenState extends State<SettingsWebBrowserScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ★ 最小限のヘッダー：ステータスバー（時計や電池残量の裏側）の背景色のみ指定
      backgroundColor: AppTheme.panel(context),
      body: SafeArea(
        // ★ 最小限のフッター：iOSのホームバーやAndroidのシステムバーへの被りだけを防ぐ
        top: true,
        bottom: true,
        child: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(widget.url)),
        ),
      ),
    );
  }
}

