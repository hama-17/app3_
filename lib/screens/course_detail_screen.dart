import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'dart:math' as math;

import '../core/app_theme.dart';
import '../utils/lms_adapter.dart';
import '../utils/course_parser.dart';
import 'media_viewers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_snackbar.dart';
import '../main.dart'; // ★ globalDisableAutoCacheClear を読み込むために必要

import '../utils/term_helper.dart'; // パスは適宜合わせてください
import '../utils/dummy_data_helper.dart';
import 'custom_camera_screen.dart';
import 'dart:typed_data'; // 🟢 追記：これを入れることで Uint8List のエラーが消滅します

//lib/screens/course_detail_screen.dartの中身です。


class CourseDetailInteractivePage extends StatefulWidget {
  final List<dynamic> courses; final int initialIndex; final String cookie; final int initialBottomIndex; final String? targetTaskId;
  final bool isAuthenticated; final VoidCallback onLoginRequest; final String heroTag;
  final Map<String, int> customCourseColors;
  final Function(String, int?)? onColorChanged;
  final Function(String)? onCourseEdited;
  final Function(String)? onCourseDeleted;
  final VoidCallback? onScheduleOverrideChanged;


  const CourseDetailInteractivePage({super.key, required this.courses, required this.initialIndex, required this.cookie, this.initialBottomIndex = 0, this.targetTaskId, required this.isAuthenticated, required this.onLoginRequest, required this.heroTag, required this.customCourseColors, this.onColorChanged, this.onCourseEdited, this.onCourseDeleted, this.onScheduleOverrideChanged});
  @override
  State<CourseDetailInteractivePage> createState() => _CourseDetailInteractivePageState();
}


class _CourseDetailInteractivePageState extends State<CourseDetailInteractivePage> {
  late PageController _topPageController; late PageController _bottomPageController;
  int _currentIndex = 0;
  int _currentBottomIndex = 0;
  bool _isMenuMode = false;
  bool _isMemoOpen = false;
  bool _isCollapsed = false;
  Map<String, Map<String, int>> _courseOverrides = {};
  Map<String, String> _courseTermOverrides = {};

  // ─── 🔑 新設：MEMOタブのStateを別タブからダイレクトにハック・同期するためのGlobalKey ───
  final GlobalKey<_CourseMemoWidgetState> _memoKey = GlobalKey<_CourseMemoWidgetState>();



  // initState の中に `_loadTermOverrides();` を追記してください

  Future<void> _loadTermOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('course_term_overrides_v10');
    if (str != null) {
      setState(() {
        _courseTermOverrides = Map<String, String>.from(jsonDecode(str));
      });
    }
  }

  Future<void> _saveTermOverride(String cId, String termStr) async {
    _courseTermOverrides[cId] = termStr;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('course_term_overrides_v10', jsonEncode(_courseTermOverrides));
    setState(() {});
    widget.onScheduleOverrideChanged?.call(); // ホーム画面の時間割フィルターを即座に再適用させる
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex >= 0 && widget.initialIndex < widget.courses.length ? widget.initialIndex : 0;

    // ★ 修正：未ログイン時は下部カードの初期インデックスを強制的に「0 (MEMO)」にする
    _currentBottomIndex = widget.isAuthenticated ? widget.initialBottomIndex : 0;

    _topPageController = PageController(initialPage: _currentIndex);
    _bottomPageController = PageController(initialPage: _currentBottomIndex);

    // ★ 修正：既存の上書き情報と、学期属性（Q1~Q4）の上書き情報を両方とも初期化時にロードする
    _loadOverrides();
    _loadTermOverrides(); // 👈 ここを追加！
  }








  @override
  void dispose() { _topPageController.dispose(); _bottomPageController.dispose(); super.dispose(); }


  Future<void> _loadOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('course_overrides_v10');
    if (str != null) {
      Map<String, dynamic> dec = jsonDecode(str);
      setState(() {
        _courseOverrides = dec.map((k, v) => MapEntry(k, Map<String, int>.from(v)));
      });
    }
  }


  Future<void> _setOverride(String dateStr, int status, String cId) async {
    if (_courseOverrides[cId] == null) _courseOverrides[cId] = {};
    _courseOverrides[cId]![dateStr] = status;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('course_overrides_v10', jsonEncode(_courseOverrides));
    setState((){});
    widget.onScheduleOverrideChanged?.call();
  }


  // ★ 修正：ホーム画面と同じ「幅広いグレーの色域」を詳細画面にも適用
  Color _getColorForIndex(int index) {
    final c = widget.courses[index];
    String cId = c['is_custom'] == true ? (c['raw_name'] ?? c['name'] ?? '') : c['id'].toString();

    // カスタムカラーが設定されていれば優先
    if (widget.customCourseColors.containsKey(cId)) {
      return Color(widget.customCourseColors[cId]!);
    }

    int total = math.max(1, widget.courses.length);
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    // ★ ホーム画面と同じ幅広いグレーの色域を定義
    Color lightGrey = const Color(0xFFE0E0E0); // ほぼ白
    Color darkGrey = const Color(0xFF1A1A1A);  // ほぼ黒

    if (total <= 1) {
      return isDark ? darkGrey : lightGrey;
    }

    double ratio = index / (total - 1);

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


  List<DateTime> _generateCourseDates(dynamic course) {
    String rawName = course['name'] ?? '';
    String dayPeriod = CourseScheduleParser.getDayPeriod(rawName);
    if (course['is_custom'] == true) {
      final match = RegExp(r'\[(.*?)\]').firstMatch(rawName);
      if (match != null) dayPeriod = match.group(1) ?? '';
    }
    List<int> targetWeekdays = [];
    if (dayPeriod.contains('月') || dayPeriod.contains('MON')) targetWeekdays.add(DateTime.monday);
    if (dayPeriod.contains('火') || dayPeriod.contains('TUE')) targetWeekdays.add(DateTime.tuesday);
    if (dayPeriod.contains('水') || dayPeriod.contains('WED')) targetWeekdays.add(DateTime.wednesday);
    if (dayPeriod.contains('木') || dayPeriod.contains('THU')) targetWeekdays.add(DateTime.thursday);
    if (dayPeriod.contains('金') || dayPeriod.contains('FRI')) targetWeekdays.add(DateTime.friday);
    if (dayPeriod.contains('土') || dayPeriod.contains('SAT')) targetWeekdays.add(DateTime.saturday);


    if (targetWeekdays.isEmpty) targetWeekdays.add(DateTime.monday);


    DateTime now = DateTime.now();
    bool isSpring = currentLMS.isSpringSemester(now);
    DateTime start = currentLMS.getSemesterStartDate(now, isSpring);
    DateTime end = currentLMS.getSemesterEndDate(now, isSpring);


    List<DateTime> dates = [];
    for (DateTime d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
      if (targetWeekdays.contains(d.weekday)) {
        dates.add(d);
      }
    }
    return dates;
  }


  Widget _buildMenuContent(Color textCol, dynamic cur) {
    bool isCurrentCustom = cur['is_custom'] == true;
    Color defaultColor = isCurrentCustom ? AppTheme.getCustomCourseColor(cur['raw_name'] ?? cur['name'] ?? '') : AppTheme.getGradientColor(_currentIndex, widget.courses.length);
    List<DateTime> dates = _generateCourseDates(cur);
    String cId = isCurrentCustom ? (cur['raw_name'] ?? cur['name'] ?? '') : cur['id'].toString();

    // -------------------------------------------------------------------
    // ★ 修正：TermHelper を使って現在の真の学期属性をスマートに取得
    // -------------------------------------------------------------------
    List<String> activeTerms = TermHelper.getCourseTerms(cur, _courseTermOverrides);

    List<String> qLabels = ["Q1", "Q2", "Q3", "Q4"];
    List<bool> qStates = [
      activeTerms.contains("Q1"),
      activeTerms.contains("Q2"),
      activeTerms.contains("Q3"),
      activeTerms.contains("Q4"),
    ];

    return Container(
        width: double.infinity,
        decoration: BoxDecoration(color: _getColorForIndex(_currentIndex), borderRadius: BorderRadius.circular(32)),
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ★ COURSE MENU の文字タイトルは削除してここから Wrap を開始
            Wrap(
                spacing: 16, runSpacing: 16,
                children: [
                  // ★ 修正：ソリッド＆サイバーテイストに映える洗練されたカラーに一新
                  _buildColorSwatch(const Color(0xFFaed9e0), textCol, cur), // ネオンシアン
                  _buildColorSwatch(const Color(0xFF671b24), textCol, cur), // ネオンマゼンタ
                  _buildColorSwatch(const Color(0xFF055646), textCol, cur), // ネオンライム
                  _buildColorSwatch(const Color(0xFF034376), textCol, cur), // エレクトリックブルー
                  _buildColorSwatch(const Color(0xFFd8370b), textCol, cur), // ブライトアンバー
                  _buildColorSwatch(const Color(0xFFf5bc64), textCol, cur), // インオーガニックグレー
                  GestureDetector(
                    onTap: () {
                      widget.onColorChanged?.call(cId, null);
                      setState((){});
                    },
                    child: Container(width: 36, height: 36, decoration: BoxDecoration(color: defaultColor, shape: BoxShape.circle, border: Border.all(color: textCol.withOpacity(0.5), width: 1)), child: Icon(Icons.refresh, color: AppTheme.getTextColorForBackground(defaultColor).withOpacity(0.8), size: 20)),
                  )
                ]
            ),
            const SizedBox(height: 32),

            // -------------------------------------------------------------------
            // ★ 新設：学期属性変更トグルバー（複数選択可能なカプセルバー）
            // -------------------------------------------------------------------
            Text("学期属性のカスタマイズ (複数選択可)", style: TextStyle(color: textCol.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              height: 36,
              decoration: BoxDecoration(
                color: textCol.withOpacity(0.1),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: List.generate(4, (index) {
                  bool isSelected = qStates[index];
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        // タップされた位置の状態を反転
                        qStates[index] = !qStates[index];

                        // 有効なQを文字列にまとめる (例: "Q1.Q2")
                        List<String> selectedList = [];
                        for (int i = 0; i < 4; i++) {
                          if (qStates[i]) selectedList.add(qLabels[i]);
                        }
                        // すべて外れた場合は空文字、選択があれば結合
                        String updatedTermStr = selectedList.isEmpty ? "未選択" : selectedList.join(".");
                        _saveTermOverride(cId, updatedTermStr);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: isSelected ? textCol : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            qLabels[index],
                            style: TextStyle(
                              color: isSelected ? AppTheme.getTextColorForBackground(textCol) : textCol.withOpacity(0.6),
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w300,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 32),

            if (isCurrentCustom) ...[
              Text("Manage Custom Course", style: TextStyle(color: textCol.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => widget.onCourseEdited?.call(cur['raw_name'] ?? cur['name']),
                      child: Container(padding: const EdgeInsets.symmetric(vertical: 16), decoration: BoxDecoration(color: textCol.withOpacity(0.1), borderRadius: BorderRadius.circular(16)), child: Center(child: Text("EDIT", style: TextStyle(color: textCol, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)))),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => widget.onCourseDeleted?.call(cur['raw_name'] ?? cur['name']),
                      child: Container(padding: const EdgeInsets.symmetric(vertical: 16), decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(16)), child: const Center(child: Text("DELETE", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)))),
                    ),
                  )
                ],
              ),
              const SizedBox(height: 32),
            ],
            Text("学期スケジュール", style: TextStyle(color: textCol.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(
                child: ListView.builder(
                    padding: EdgeInsets.zero,
                    physics: const BouncingScrollPhysics(),
                    itemCount: dates.length,
                    itemBuilder: (ctx, i) {
                      DateTime d = dates[i];
                      String dateStr = "${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}";
                      String displayDate = "${d.month}/${d.day}";
                      int status = _courseOverrides[cId]?[dateStr] ?? 0;
                      List<String> labels = ["通常", "ｵﾝﾃﾞﾏﾝﾄﾞ", "休講", "テスト"];

                      return Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Row(
                              children: [
                                SizedBox(width: 45, child: Text(displayDate, style: TextStyle(color: textCol, fontSize: 14, fontWeight: FontWeight.bold))),
                                Expanded(
                                    child: Container(
                                        height: 30,
                                        decoration: BoxDecoration(
                                          color: textCol.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(15),
                                        ),
                                        child: Row(
                                            children: [0, 1, 2, 3].map((val) {
                                              bool isSel = status == val;
                                              return Expanded(
                                                  child: GestureDetector(
                                                      behavior: HitTestBehavior.opaque,
                                                      onTap: () => _setOverride(dateStr, val, cId),
                                                      child: Container(
                                                        alignment: Alignment.center,
                                                        decoration: BoxDecoration(
                                                          color: isSel ? textCol : Colors.transparent,
                                                          borderRadius: BorderRadius.circular(15),
                                                          boxShadow: isSel ? [const BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))] : [],
                                                        ),
                                                        child: FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          child: Padding(
                                                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                                            child: Text(
                                                                labels[val],
                                                                style: TextStyle(
                                                                    color: isSel ? AppTheme.getTextColorForBackground(textCol) : textCol.withOpacity(0.6),
                                                                    fontSize: 10,
                                                                    fontWeight: isSel ? FontWeight.bold : FontWeight.w500
                                                                )
                                                            ),
                                                          ),
                                                        ),
                                                      )
                                                  )
                                              );
                                            }).toList()
                                        )
                                    )
                                )
                              ]
                          )
                      );
                    }
                )
            )
          ],
        )
    );
  }


  Widget _buildColorSwatch(Color c, Color textCol, dynamic cur) {
    return GestureDetector(
        onTap: () {
          String cId = cur['is_custom'] == true ? (cur['raw_name'] ?? cur['name'] ?? '') : cur['id'].toString();
          widget.onColorChanged?.call(cId, c.value);
          setState((){});
        },
        child: Container(width: 36, height: 36, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 1)))
    );
  }


  @override
  Widget build(BuildContext context) {
    if (widget.courses.isEmpty || _currentIndex < 0 || _currentIndex >= widget.courses.length) {
      return Scaffold(backgroundColor: AppTheme.bg(context), body: const Center(child: Text("Error: Course not found")));
    }
    final cur = widget.courses[_currentIndex];

    final color = _getColorForIndex(_currentIndex);
    final textCol = AppTheme.getTextColorForBackground(color);
    bool isCurrentCustom = cur['is_custom'] == true;
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
        backgroundColor: AppTheme.bg(context),
        body: Column(children: [
          // -------------------------------------------------------------------
          // ★ 上部カード（スワイプや下部のスクロール押し下げで伸縮する）
          // -------------------------------------------------------------------
          GestureDetector(
            onTap: () {
              if (_isCollapsed) setState(() => _isCollapsed = false);
            },
            onVerticalDragUpdate: (details) {
              if (details.primaryDelta! > 5 && _isCollapsed) {
                setState(() => _isCollapsed = false); // 下スワイプで広げる
              } else if (details.primaryDelta! < -5 && !_isCollapsed) {
                setState(() => _isCollapsed = true);  // 上スワイプで縮める
              }
            },
            onVerticalDragEnd: (details) {
              if (details.primaryVelocity != null && details.primaryVelocity! > 300 && !_isCollapsed) {
                Navigator.pop(context);
              }
            },
            child: Hero(
              tag: widget.heroTag,
              child: Material(
                type: MaterialType.transparency,
                child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    height: _isCollapsed ? 100 : 260,
                    child: PageView.builder(
                        controller: _topPageController,
                        itemCount: widget.courses.length,
                        onPageChanged: (i) {
                          setState(() {
                            _currentIndex = i;
                            _isMemoOpen = false;
                          });
                        },
                        itemBuilder: (context, i) {
                          final c = widget.courses[i]; final name = c['name'] ?? '';
                          bool isThisCustom = c['is_custom'] == true;
                          Color pageColor = _getColorForIndex(i);
                          final double padTop = MediaQuery.of(context).padding.top;

                          // --- 曜日・時限パース処理 ---
                          String rawDayStr = "";
                          if (isThisCustom) {
                            final match = RegExp(r'\[(.*?)\]').firstMatch(name);
                            if (match != null) rawDayStr = match.group(1) ?? '';
                          } else {
                            rawDayStr = CourseScheduleParser.getDayPeriod(name);
                          }

                          const numMap = {'１':'1','２':'2','３':'3','４':'4','５':'5','６':'6','７':'7'};
                          numMap.forEach((k, v) { rawDayStr = rawDayStr.replaceAll(k, v); });
                          const dayMap = {'月':'MON','火':'TUE','水':'WED','木':'THU','金':'FRI','土':'SAT','日':'SUN'};
                          dayMap.forEach((k, v) { rawDayStr = rawDayStr.replaceAll(k, v); });
                          rawDayStr = rawDayStr.toUpperCase();

                          Map<String, Set<int>> dayToPeriods = {};
                          String currentDay = "";
                          final regex = RegExp(r'(MON|TUE|WED|THU|FRI|SAT|SUN)?\s*(\d)');
                          final matches = regex.allMatches(rawDayStr);

                          for (var m in matches) {
                            String? day = m.group(1);
                            int period = int.parse(m.group(2)!);
                            if (day != null) currentDay = day;
                            if (currentDay.isNotEmpty) {
                              dayToPeriods.putIfAbsent(currentDay, () => {}).add(period);
                            }
                          }

                          String dayText = "";
                          if (dayToPeriods.isNotEmpty) {
                            List<String> parts = [];
                            dayToPeriods.forEach((day, periods) {
                              List<int> pList = periods.toList()..sort();
                              parts.add("$day${pList.join('.')}");
                            });
                            dayText = parts.join(' / ');
                          } else {
                            dayText = rawDayStr.trim();
                          }
                          dayText = dayText.toUpperCase();

                          String instructor = isThisCustom ? '' : CourseInstructorParser.getInstructorName(c);
                          String roomName = isThisCustom
                              ? (name.split('[').length > 2 ? name.split('[')[2].replaceAll(']', '').trim() : '')
                              : CourseScheduleParser.getRoomNumber(name);

                          int totalCourses = widget.courses.length;
                          int dotCount = totalCourses < 5 ? totalCourses : 5;
                          int activeDot = 0;
                          if (totalCourses <= 5) {
                            activeDot = i;
                          } else {
                            if (i == 0) activeDot = 0;
                            else if (i == 1) activeDot = 1;
                            else if (i == totalCourses - 2) activeDot = 3;
                            else if (i == totalCourses - 1) activeDot = 4;
                            else activeDot = 2;
                          }

                          // lib/screens/course_detail_screen.dart 内の PageView.builder > itemBuilder 戻り値の Stack内部

                          // lib/screens/course_detail_screen.dart 内の PageView.builder > itemBuilder 内の Stack 直下

                          return Container(
                              decoration: BoxDecoration(color: pageColor, borderRadius: BorderRadius.circular(32)),
                              child: SafeArea(
                                  bottom: false,
                                  child: Stack(children: [

                                    // 🟢 ① 修正：縮小時に、教科名テキストの左隣に回り込むよう座標（left / top）を動的シフト
                                    // lib/screens/course_detail_screen.dart 内の 戻る矢印ボタン部分

                                    // 🟢 修正：縮小時、上へ這い上がる教科名（fontSize 16）の高さラインにぴったり揃うよう、topを「16」から「46」へシフト
                                    AnimatedPositioned(
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeOutCubic,
                                        bottom: _isCollapsed ? 5 : (206 - padTop), // 260px(全高) - 18px(上余白) - 36px(ボタン高) = 206px
                                        left: 16,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => Navigator.pop(context),
                                          child: Container(
                                            padding: const EdgeInsets.all(8), // 横幅は 20 + 8*2 = 36px
                                            child: Icon(
                                              Icons.arrow_back_ios_new,
                                              color: AppTheme.getTextColorForBackground(pageColor),
                                              size: _isCollapsed ? 18 : 20,
                                            ),
                                          ),
                                        )
                                    ),

                                    // 3点メニューボタン（通常時のみアクティブ）
                                    AnimatedPositioned(
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeOutCubic,
                                        top: _isCollapsed ? 20 : 16,
                                        left: 52, // 通常時は戻るボタンのすぐ右隣
                                        child: AnimatedOpacity(
                                          duration: const Duration(milliseconds: 200),
                                          opacity: _isCollapsed ? 0.0 : 1.0,
                                          child: IgnorePointer(
                                            ignoring: _isCollapsed,
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () => setState(() => _isMenuMode = !_isMenuMode),
                                              child: Container(
                                                padding: const EdgeInsets.all(8),
                                                child: Icon(_isMenuMode ? Icons.close : Icons.more_vert, color: AppTheme.getTextColorForBackground(pageColor), size: 24),
                                              ),
                                            ),
                                          ),
                                        )
                                    ),

                                    Positioned(
                                        top: 0, right: 24,
                                        child: AnimatedOpacity(
                                            duration: const Duration(milliseconds: 200),
                                            opacity: _isCollapsed ? 0.0 : 1.0,
                                            child: Transform(transform: Matrix4.diagonal3Values(0.8, 1.3, 1.0), alignment: Alignment.topRight, child: Text(dayText, style: TextStyle(color: AppTheme.getTextColorForBackground(pageColor).withOpacity(0.8), fontSize: 36, fontWeight: FontWeight.w100), textAlign: TextAlign.right))
                                        )
                                    ),

                                    // 🟢 ② 修正：縮小時に、左に回り込んできた矢印ボタンの幅(56px分)を確保して綺麗に並ぶよう left を調整
                                    AnimatedPositioned(
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeOutCubic,
                                        bottom: _isCollapsed ? 12 : 18,
                                        left: _isCollapsed ? 52 : 24, // 👈 縮小時は戻るボタンの真右から1ミリの狂いもなく開始
                                        right: _isCollapsed ? 80 : 90, // 右側の左右矢印コントローラーを綺麗に避ける幅
                                        child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              AnimatedDefaultTextStyle(
                                                duration: const Duration(milliseconds: 300),
                                                style: TextStyle(
                                                    fontSize: _isCollapsed ? 16 : 24,
                                                    fontWeight: FontWeight.w300,
                                                    color: AppTheme.getTextColorForBackground(pageColor),
                                                    height: 1.2
                                                ),
                                                child: Text(
                                                    CourseTitleParser.getCleanTitle(name),
                                                    maxLines: _isCollapsed ? 1 : 2,
                                                    overflow: TextOverflow.ellipsis
                                                ),
                                              ),
                                              AnimatedCrossFade(
                                                duration: const Duration(milliseconds: 200),
                                                crossFadeState: _isCollapsed ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                                                firstChild: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    if (instructor.isNotEmpty || roomName.isNotEmpty) const SizedBox(height: 12),
                                                    if (instructor.isNotEmpty) Text(instructor, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w300, color: AppTheme.getTextColorForBackground(pageColor))),
                                                    if (roomName.isNotEmpty) Text(roomName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w300, color: AppTheme.getTextColorForBackground(pageColor)))
                                                  ],
                                                ),
                                                secondChild: const SizedBox(width: double.infinity, height: 0),
                                              )
                                            ]
                                        )
                                    ),

                                    // 🟢 変更：5点ドットを廃止し、次の授業へスライドするミニマルな右矢印を配置
                                    // 🟢 変更：5点ドットを廃止し、左右の「矢印型」ソリッドボタンでページ送り・戻りを可能に
                                    Positioned(
                                        bottom: 12, // 2つのボタンが並ぶため、下端の目線を整えるよう16➔12へ微調整
                                        right: 16,
                                        child: AnimatedOpacity(
                                            duration: const Duration(milliseconds: 200),
                                            opacity: _isCollapsed ? 0.0 : 1.0,
                                            child: IgnorePointer(
                                              ignoring: _isCollapsed,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [

                                                  // ◀️ 左向き矢印（前の授業へ）
                                                  GestureDetector(
                                                    behavior: HitTestBehavior.opaque,
                                                    onTap: i > 0 ? () {
                                                      _topPageController.previousPage(
                                                        duration: const Duration(milliseconds: 300),
                                                        curve: Curves.easeOutCubic,
                                                      );
                                                    } : null, // 最初のページではタップを完全遮断
                                                    child: Padding(
                                                      padding: const EdgeInsets.all(8.0), // タップ判定の拡張
                                                      child: Icon(
                                                        Icons.arrow_back,
                                                        color: AppTheme.getTextColorForBackground(pageColor)
                                                            .withOpacity(i > 0 ? 1.0 : 0.0), // 押せない時は不透明度を下げて無機質に固定
                                                        size: 20,
                                                      ),
                                                    ),
                                                  ),

                                                  const SizedBox(width: 4), // 矢印ボタン同士のミニマルな間隔

                                                  // ▶️ 右向き矢印（次の授業へ）
                                                  GestureDetector(
                                                    behavior: HitTestBehavior.opaque,
                                                    onTap: i < widget.courses.length - 1 ? () {
                                                      _topPageController.nextPage(
                                                        duration: const Duration(milliseconds: 300),
                                                        curve: Curves.easeOutCubic,
                                                      );
                                                    } : null, // 最後のページではタップを完全遮断
                                                    child: Padding(
                                                      padding: const EdgeInsets.all(8.0),
                                                      child: Icon(
                                                        Icons.arrow_forward,
                                                        color: AppTheme.getTextColorForBackground(pageColor)
                                                            .withOpacity(i < widget.courses.length - 1 ? 1.0 : 0),
                                                        size: 20,
                                                      ),
                                                    ),
                                                  ),

                                                ],
                                              ),
                                            )
                                        )
                                    )
                                  ])));
                        })),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // -------------------------------------------------------------------
          // ★ スライドするタブ型メニュー
          // -------------------------------------------------------------------
          Builder(
              builder: (context) {
                int pageCount = 0;
                List<String> pageTitlesLong = [];
                List<String> pageTitlesShort = [];

                if (isCurrentCustom) {
                  pageCount = 2;
                  pageTitlesLong = ["MEMO", "TASKS"];
                  pageTitlesShort = ["MEMO", "TASKS"];
                } else if (widget.isAuthenticated) {
                  pageCount = 5;
                  pageTitlesLong = ["MEMO", "MODULES", "TASKS", "GRADES", "ANNOUNCE"];
                  pageTitlesShort = ["MEMO", "MODS", "TASKS", "GRADE", "ANN"];
                } else {
                  pageCount = 2;
                  pageTitlesLong = ["MEMO", "LOGIN"];
                  pageTitlesShort = ["MEMO", "LOGIN"];
                }

                int safeBottomIndex = _currentBottomIndex;
                if (safeBottomIndex >= pageCount) safeBottomIndex = pageCount - 1;
                if (safeBottomIndex < 0) safeBottomIndex = 0;

                List<int> flexes = List.generate(pageCount, (i) => i == safeBottomIndex ? 4 : 2);
                int totalFlex = flexes.fold(0, (sum, flex) => sum + flex);

                int leftFlexSum = 0;
                for (int i = 0; i < safeBottomIndex; i++) { leftFlexSum += flexes[i]; }

                return Container(
                  height: 48,
                  width: double.infinity,
                  color: Colors.transparent,
                  child: Stack(
                    children: [
                      if (safeBottomIndex > 0)
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          top: 4, bottom: 4, left: 0,
                          width: MediaQuery.of(context).size.width * (leftFlexSum / totalFlex),
                          child: Container(decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.horizontal(left: Radius.circular(20), right: Radius.circular(20)))),
                        ),
                      if (safeBottomIndex < pageCount - 1)
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          top: 4, bottom: 4,
                          left: MediaQuery.of(context).size.width * ((leftFlexSum + flexes[safeBottomIndex]) / totalFlex),
                          right: 0,
                          child: Container(decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.horizontal(left: Radius.circular(20), right: Radius.circular(20)))),
                        ),
                      Row(
                        children: List.generate(pageCount, (index) {
                          bool isSelected = safeBottomIndex == index;
                          return Expanded(
                            flex: flexes[index],
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                setState(() => _currentBottomIndex = index);
                                if (_bottomPageController.hasClients) {
                                  _bottomPageController.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
                                }
                              },
                              child: Center(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 300),
                                  style: TextStyle(
                                    color: isSelected ? (isDark ? Colors.white : Colors.black) : textCol,
                                    fontSize: 13, fontWeight: FontWeight.w300, letterSpacing: 1.0,
                                  ),
                                  child: Text(isSelected ? pageTitlesLong[index] : pageTitlesShort[index], maxLines: 1, overflow: TextOverflow.clip),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                );
              }
          ),
          const SizedBox(height: 4),

          // -------------------------------------------------------------------
          // ★ 下部カード領域（横スライド・縦スクロールの挙動一元化）
          // -------------------------------------------------------------------
          // -------------------------------------------------------------------
          // ★ 下部カード領域（横スライド・縦スクロールの挙動一元化）
          // -------------------------------------------------------------------
          Expanded(
            // 👇 新設：項目が少ないときのドラッグや、純粋な「タップ（触る）」を検知する
              child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  // ① 空白部分を「触ったりしたら」縮小する
                  onTap: () {
                    if (!_isCollapsed) {
                      setState(() => _isCollapsed = true);
                    }
                  },
                  // ② 項目が少なくスクロールしない時の「押し上げ」「押し下げ」を検知
                  onVerticalDragUpdate: (details) {
                    if (details.primaryDelta! < -3 && !_isCollapsed) {
                      setState(() => _isCollapsed = true);  // 上スワイプ -> 縮小
                    } else if (details.primaryDelta! > 3 && _isCollapsed) {
                      setState(() => _isCollapsed = false); // 下スワイプ -> 拡大
                    }
                  },
                  child: NotificationListener<ScrollNotification>(
                      onNotification: (scrollNotification) {
                        // 横スワイプ（タブ切り替え）での誤作動を防ぐため、縦スクロールのみ処理
                        if (scrollNotification.metrics.axis == Axis.vertical) {
                          if (scrollNotification is ScrollUpdateNotification) {
                            if (scrollNotification.scrollDelta != null) {
                              // ③ 長いリストを上にスクロール（押し上げ）した時
                              if (scrollNotification.scrollDelta! > 2 && !_isCollapsed) {
                                setState(() => _isCollapsed = true);
                              }
                              // ④ 長いリストが「最上部」にある状態で、さらに下に押し下げた時
                              else if (scrollNotification.metrics.pixels <= 0 && scrollNotification.scrollDelta! < -2 && _isCollapsed) {
                                setState(() => _isCollapsed = false);
                              }
                            }
                          } else if (scrollNotification is OverscrollNotification) {
                            // iOSなどのバウンス（引っ張り）領域での検知
                            if (scrollNotification.overscroll < -2 && _isCollapsed) {
                              setState(() => _isCollapsed = false);
                            } else if (scrollNotification.overscroll > 2 && !_isCollapsed) {
                              setState(() => _isCollapsed = true);
                            }
                          }
                        }
                        return false;
                      },
                      child: Builder(
                          builder: (context) {
                            final route = ModalRoute.of(context);
                            final animation = route?.animation ?? const AlwaysStoppedAnimation(1.0);

                            int pageCount = 0;
                            List<Widget> pages = [];

                            if (isCurrentCustom) {
                              pageCount = 2;
                              pages = [
                                _CourseMemoWidget(
                                    key: _memoKey, // 👈 🔑 鍵を装着してロックオン
                                    courseId: cur['id'].toString(),
                                    courseName: cur['title'] ?? cur['name'] ?? '',
                                    bgColor: Colors.transparent,
                                    textColor: textCol,
                                    onMemoStateChanged: (isOpen) { if (mounted) setState(() => _isMemoOpen = isOpen); }
                                ),
                                Container( /* ...カスタム授業用タスク画面... */ )
                              ];
                            } else if (widget.isAuthenticated) {
                              pageCount = 5;
                              pages = [
                                _CourseMemoWidget(
                                    key: _memoKey, // 👈 🔑 鍵を装着してロックオン
                                    courseId: cur['id'].toString(),
                                    courseName: cur['title'] ?? cur['name'] ?? '',
                                    bgColor: Colors.transparent,
                                    textColor: textCol,
                                    onMemoStateChanged: (isOpen) { if (mounted) setState(() => _isMemoOpen = isOpen); }
                                ),
                                // 🟢 修正：すべてのデータリストの背後に、MEMOへの直撃ルートを結合
                                _CourseDataList(courseId: cur['id'], endpointType: 'MODULES', cookie: widget.cookie, bgColor: Colors.transparent, textColor: textCol, onImagesSaved: (paths) => _memoKey.currentState?.appendExternalImages(paths)),
                                _CourseDataList(courseId: cur['id'], endpointType: 'ASSIGNMENTS', cookie: widget.cookie, bgColor: Colors.transparent, textColor: textCol, targetItemId: widget.targetTaskId, onImagesSaved: (paths) => _memoKey.currentState?.appendExternalImages(paths)),
                                _CourseDataList(courseId: cur['id'], endpointType: 'GRADES', cookie: widget.cookie, bgColor: Colors.transparent, textColor: textCol, onImagesSaved: (paths) => _memoKey.currentState?.appendExternalImages(paths)),
                                _CourseDataList(courseId: cur['id'], endpointType: 'ANNOUNCE', cookie: widget.cookie, bgColor: Colors.transparent, textColor: textCol, targetItemId: widget.targetTaskId, onImagesSaved: (paths) => _memoKey.currentState?.appendExternalImages(paths)),
                              ];
                            } else {
                              pageCount = 2;
                              pages = [
                                _CourseMemoWidget(
                                    courseId: cur['id'].toString(),
                                    courseName: cur['title'] ?? cur['name'] ?? '',
                                    bgColor: Colors.transparent,
                                    textColor: textCol,
                                    onMemoStateChanged: (isOpen) { if (mounted) setState(() => _isMemoOpen = isOpen); }
                                ),
                                Container(
                                    width: double.infinity,
                                    color: Colors.transparent,
                                    child: Center(
                                        child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [

                                              GestureDetector(
                                                onTap: () {
                                                  Navigator.pop(context);
                                                  widget.onLoginRequest();
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                                  decoration: BoxDecoration(color: textCol, borderRadius: BorderRadius.circular(30)),
                                                  child: Text("LOGIN", style: TextStyle(color: color, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                                                ),
                                              )
                                            ]
                                        )
                                    )
                                )
                              ];
                            }

                            int safeBottomIndex = _currentBottomIndex;
                            if (safeBottomIndex >= pageCount) safeBottomIndex = pageCount - 1;
                            if (safeBottomIndex < 0) safeBottomIndex = 0;

                            List<Widget> wrappedPages = pages.map((page) {
                              return Container(
                                width: double.infinity,
                                height: double.infinity,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(32),
                                ),
                                child: page,
                              );
                            }).toList();

                            return SlideTransition(
                              position: Tween<Offset>(begin: const Offset(0, 1.0), end: Offset.zero).animate(
                                  CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)
                              ),
                              child: FadeTransition(
                                  opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
                                  child: _isMenuMode
                                      ? _buildMenuContent(textCol, cur)
                                      : Container(
                                      width: double.infinity,
                                      color: Colors.transparent,
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: PageView(
                                              controller: _bottomPageController,
                                              onPageChanged: (i) => setState(() => _currentBottomIndex = i),
                                              children: wrappedPages,
                                            ),
                                          ),
                                        ],
                                      )
                                  )
                              ),
                            );
                          }
                      )
                  )
              )
          )
        ])
    );
  }
}

// （以下、_CourseDataList、_CourseMemoWidget、_TextInputOverlay、_FullScreenImageGallery は変更なし）
class _CourseDataList extends StatefulWidget {
  final int courseId; final String endpointType; final String cookie; final Color bgColor; final Color textColor; final String? targetItemId;
  final Function(List<String>)? onImagesSaved; // 🟢 追記：画像が保存されたことを親画面に中継するコールバック

  // 🟢 修正：コンストラクタに onImagesSaved を追加
  const _CourseDataList({required this.courseId, required this.endpointType, required this.cookie, required this.bgColor, required this.textColor, this.targetItemId, this.onImagesSaved});
  @override
  State<_CourseDataList> createState() => _CourseDataListState();
}


class _CourseDataListState extends State<_CourseDataList> with AutomaticKeepAliveClientMixin {
  @override bool get wantKeepAlive => true;
  List<dynamic> _data = [];
  bool _isLoading = true;
  Set<String> _expandedItems = {}; // ★ 展開状態を記憶するセット

  @override void initState() {
    super.initState();
    if (widget.targetItemId != null) _expandedItems.add(widget.targetItemId!);
    _fetch();
  }

  @override void didUpdateWidget(covariant _CourseDataList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.courseId != widget.courseId) {
      _expandedItems.clear(); // 授業が変わったらリセット
      if (widget.targetItemId != null) _expandedItems.add(widget.targetItemId!);
      _fetch();
    }
  }

  // lib/screens/course_detail_screen.dart 内の _CourseDataListState._fetch() メソッド
  Future<void> _fetch() async {
    setState(() => _isLoading = true);

    // ★ 修正：テストログイン中の場合はオンラインへのHTTP通信を遮断し、ダミーを流し込む
    if (widget.cookie == "dummy_test_session") {
      await Future.delayed(const Duration(milliseconds: 300)); // リアルなロード感
      if (mounted) {
        setState(() {
          // 👇 ★ 変更：第二引数として「widget.courseId」を確実に流し込む！
          _data = DummyDataHelper.getDetails(widget.endpointType, widget.courseId);
          _isLoading = false;
        });
      }
      return;
    }

    String url = "";
    // ...（以降の既存の本番用通信コードは一切変更なしでOKです）...
    if (widget.endpointType == 'MODULES') url = '${currentLMS.baseUrl}/api/v1/courses/${widget.courseId}/modules?per_page=50&include[]=items';
    // ... 以降、元の既存通信コードが続く
    else if (widget.endpointType == 'ASSIGNMENTS' || widget.endpointType == 'GRADES') url = '${currentLMS.baseUrl}/api/v1/courses/${widget.courseId}/assignments?per_page=50&order_by=due_at&include[]=submission';
    else url = '${currentLMS.baseUrl}/api/v1/courses/${widget.courseId}/discussion_topics?only_announcements=true&per_page=20';
    try { // 修正前： final res = await http.get(Uri.parse(url), headers: {'Cookie': widget.cookie});
      final res = await http.get(Uri.parse(url), headers: {'Cookie': widget.cookie}).timeout(const Duration(seconds: 10)); if (res.statusCode == 200 && mounted) setState(() { _data = jsonDecode(res.body); _isLoading = false; }); } catch (_) { if (mounted) setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    double bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
        width: double.infinity,
        decoration: BoxDecoration(color: widget.bgColor, borderRadius: BorderRadius.circular(32)),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: widget.textColor))
                : _data.isEmpty
                ? Center(child: Text("NO DATA / OFFLINE", style: TextStyle(color: widget.textColor.withOpacity(0.5), fontWeight: FontWeight.w300)))
                : ListView.builder(
                padding: EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 24 + bottomPadding),
                itemCount: _data.length,
                itemBuilder: (context, i) {
                  final item = _data[i];
                  String itemId = item['id']?.toString() ?? i.toString();
                  String title = item['name'] ?? item['title'] ?? 'No Title';
                  String subtitle = "";
                  String rightText = "";
                  bool isExpanded = _expandedItems.contains(itemId);
                  List<Widget> children = [];
                  String largeDueStr = "";

                  // --- MODULES ---
                  if (widget.endpointType == 'MODULES') {
                    children = (item['items'] as List? ?? []).map((si) {
                      // 🎯 大切な変数定義をしっかり保持
                      String subTitle = si['title'] ?? 'Unknown';
                      String type = si['type'] ?? '';
                      IconData icon;
                      switch(type) {
                        case 'File': icon = Icons.description; break;
                        case 'Page': icon = Icons.article; break;
                        case 'Assignment': icon = Icons.assignment; break;
                        case 'Quiz': icon = Icons.quiz; break;
                        case 'ExternalUrl': icon = Icons.link; break;
                        default: icon = Icons.circle; break;
                      }
                      return InkWell(
                          onTap: () {
                            // 🚀 コールバックを安全に最深部へパススルー
                            openSmartUrl(
                              context,
                              si['html_url'] ?? si['url'] ?? '',
                              widget.cookie,
                              title: subTitle,
                              onImagesSaved: widget.onImagesSaved,
                            );
                          },
                          child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              child: Row(
                                  children: [
                                    Icon(icon, size: 16, color: widget.textColor.withOpacity(0.7)),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text(subTitle, style: TextStyle(color: widget.textColor.withOpacity(0.9), fontSize: 13)))
                                  ]
                              )
                          )
                      );
                    }).toList();
                    if (children.isEmpty) {
                      children = [Padding(padding: const EdgeInsets.all(16.0), child: Text("No items in this module", style: TextStyle(color: widget.textColor.withOpacity(0.5), fontSize: 12)))];
                    }
                  }
                  // --- ASSIGNMENTS / GRADES / ANNOUNCE ---
                  else if (widget.endpointType == 'ASSIGNMENTS' || widget.endpointType == 'GRADES' || widget.endpointType == 'ANNOUNCE') {
                    if (widget.endpointType == 'ASSIGNMENTS' || widget.endpointType == 'GRADES') {
                      String dueStrRaw = item['due_at'] ?? '';
                      if (dueStrRaw.isNotEmpty) {
                        DateTime? dueAt = DateTime.tryParse(dueStrRaw)?.toLocal();
                        if (dueAt != null) {
                          subtitle = "Due: ${dueAt.month}/${dueAt.day} ${dueAt.hour.toString().padLeft(2,'0')}:${dueAt.minute.toString().padLeft(2,'0')}";
                          largeDueStr = "${dueAt.month}/${dueAt.day}  ${dueAt.hour.toString().padLeft(2,'0')}:${dueAt.minute.toString().padLeft(2,'0')}";
                        }
                      }

                      if (widget.endpointType == 'GRADES') {
                        final submission = item['submission'];
                        final score = submission != null ? submission['score'] : null;
                        final points = item['points_possible'];
                        rightText = score != null ? "$score / $points" : "- / $points";
                      }
                      else {
                        final points = item['points_possible'];
                        rightText = points != null ? "$points pts" : "";
                      }

                      List<String> subTypes = (item['submission_types'] as List?)?.map((e) => e.toString()).toList() ?? [];
                      String subTypeStr = subTypes.join(', ');
                      List<String> allowedExt = (item['allowed_extensions'] as List?)?.map((e) => e.toString()).toList() ?? [];
                      String allowedExtStr = allowedExt.isNotEmpty ? allowedExt.join(', ') : 'Not specified';

                      children.add(
                          Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(title, style: TextStyle(color: widget.textColor, fontSize: 16, fontWeight: FontWeight.w400, height: 1.3)),
                                    const SizedBox(height: 12),
                                    Text("Submission Type: $subTypeStr", style: TextStyle(color: widget.textColor.withOpacity(0.8), fontSize: 12)),
                                    const SizedBox(height: 4),
                                    Text("Allowed Formats: $allowedExtStr", style: TextStyle(color: widget.textColor.withOpacity(0.8), fontSize: 12))
                                  ]
                              )
                          )
                      );
                    } else if (widget.endpointType == 'ANNOUNCE') {
                      String posted = item['posted_at'] ?? '';
                      if (posted.length > 10) posted = posted.substring(0, 10);
                      subtitle = posted;
                      String message = item['message'] ?? 'No content';
                      message = message.replaceAll(RegExp(r'<[^>]*>'), '');
                      children.add(
                          Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                              child: Text(
                                  message.trim(),
                                  style: TextStyle(color: widget.textColor.withOpacity(0.8), fontSize: 13, height: 1.4)
                              )
                          )
                      );
                    }

                    String targetUrl = item['html_url'] ?? item['url'] ?? '';
                    if (targetUrl.isNotEmpty) {
                      Color btnBgColor = widget.textColor;
                      Color btnTextColor = AppTheme.getTextColorForBackground(btnBgColor);

                      children.add(
                          Padding(
                              padding: const EdgeInsets.only(left: 8.0, bottom: 8.0, top: 8.0),
                              child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                      onPressed: () => openSmartUrl(context, targetUrl, widget.cookie, title: title),

                                      label: Text("OPEN LINK", style: TextStyle(color: btnTextColor, fontWeight: FontWeight.w500, letterSpacing: 1.0)),
                                      style: TextButton.styleFrom(
                                          backgroundColor: btnBgColor,
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))
                                      )
                                  )
                              )
                          )
                      );
                    }
                  }

                  // ★ ヘッダーコンテンツの生成
                  Widget headerContent;
                  if ((widget.endpointType == 'ASSIGNMENTS' || widget.endpointType == 'GRADES') && isExpanded && largeDueStr.isNotEmpty) {
                    headerContent = Text(largeDueStr, style: TextStyle(color: widget.textColor, fontSize: 26, fontWeight: FontWeight.w200, height: 1.1));
                  } else {
                    headerContent = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              title,
                              style: TextStyle(color: widget.textColor, fontSize: 14, fontWeight: FontWeight.w500, height: 1.3),
                              maxLines: isExpanded ? null : 1,
                              overflow: isExpanded ? null : TextOverflow.ellipsis
                          ),
                          if (subtitle.isNotEmpty)
                            Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(subtitle, style: TextStyle(color: widget.textColor.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.w300))
                            )
                        ]
                    );
                  }

                  return Column(
                    children: [
                      // 各項目の上部に細い線を描画（一番上の項目以外）
                      if (i > 0)
                        Divider(color: widget.textColor.withOpacity(0.5), thickness: 0.5, height: 1),

                      Theme(
                        data: Theme.of(context).copyWith(
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                        ),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              if (isExpanded) _expandedItems.remove(itemId);
                              else _expandedItems.add(itemId);
                            });
                          },
                          child: Padding(
                            // ★ 修正：上パンディングは狭く(12)、下の余白は広く(展開時はコンテンツの繋がりを意識して16、閉じている時は40)
                            padding: EdgeInsets.only(top: 12.0, bottom: isExpanded ? 16.0 : 40.0),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 200),
                                        child: Align(
                                            key: ValueKey(isExpanded),
                                            alignment: Alignment.centerLeft,
                                            child: headerContent
                                        ),
                                      )
                                  ),
                                  if (rightText.isNotEmpty)
                                    Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                                        child: Text(rightText, style: TextStyle(color: widget.textColor, fontSize: 16, fontWeight: FontWeight.w400))
                                    ),
                                  Icon(
                                      isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                      color: widget.textColor.withOpacity(0.5),
                                      size: 24
                                  ),
                                ]
                            ),
                          ),
                        ),
                      ),

                      // ★ 展開時のコンテンツ
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 250),
                        crossFadeState: isExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                        firstChild: Padding(
                          // ★ 展開時はコンテンツの下に大きな余白(40)を作り、次の区切り線との距離を保つ
                          padding: const EdgeInsets.only(bottom: 40.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: children,
                          ),
                        ),
                        secondChild: const SizedBox(width: double.infinity, height: 0),
                      ),
                    ],
                  );
                }
            )
        )
    );
  }
}


class _CourseMemoWidget extends StatefulWidget {
  final dynamic courseId;
  final String courseName;
  final Color bgColor;
  final Color textColor;
  final ValueChanged<bool>? onMemoStateChanged;

  const _CourseMemoWidget({
    super.key, // 🎯 修正：これを取り込むことで、外部からの GlobalKey バインディングが可能になります
    required this.courseId,
    this.courseName = '',
    required this.bgColor,
    required this.textColor,
    this.onMemoStateChanged,
  });

  @override
  State<_CourseMemoWidget> createState() => _CourseMemoWidgetState();
}


class _CourseMemoWidgetState extends State<_CourseMemoWidget> with AutomaticKeepAliveClientMixin {
  @override bool get wantKeepAlive => true;

  List<Map<String, dynamic>> _memos = [];
  String? _activeMemoId;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadMemos();
  }

  @override
  void didUpdateWidget(covariant _CourseMemoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.courseId != widget.courseId) {
      // 左右スワイプで授業が切り替わる直前、古い授業から空の仮メモを除外して確定保存
      _saveMemosForId(oldWidget.courseId, _memos);

      setState(() {
        _activeMemoId = null;
        _memos = [];
      });
      _loadMemos();
    }
  }

  // 🟢 起動時・授業切り替え時に今日のメモを自動展開するコア
  Future<void> _loadMemos() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('course_memos_v2_${widget.courseId}');

    List<Map<String, dynamic>> loadedMemos = [];
    if (data != null) {
      try {
        final List<dynamic> decoded = jsonDecode(data);
        loadedMemos = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch(e) {}
    }

    final now = DateTime.now();
    final dateStr = '${now.month.toString().padLeft(2,'0')}/${now.day.toString().padLeft(2,'0')}';

    // すでに今日の日付のメモが存在するかスキャン
    int todayIdx = loadedMemos.indexWhere((m) => m['title']?.toString().startsWith(dateStr) ?? false);

    if (todayIdx == -1) {
      // なければ「中身が空の今日の仮メモ」を配列に仕込む
      final filteredName = _getFilteredCourseName(widget.courseName);
      final newTitle = filteredName.isNotEmpty ? '$dateStr $filteredName' : dateStr;

      final Map<String, dynamic> newMemo = {
        'id': now.millisecondsSinceEpoch.toString(),
        'title': newTitle,
        'items': <dynamic>[],
      };
      loadedMemos.add(newMemo);
      todayIdx = loadedMemos.length - 1;
    }

    if (mounted) {
      setState(() {
        _memos = loadedMemos;
        // 起動・切り替えの瞬間、100%確実に今日のメモ（詳細ビュー）へダイレクトジャンプ
        _activeMemoId = _memos[todayIdx]['id']?.toString();
      });
      widget.onMemoStateChanged?.call(true);
    }
  }

  // 🟢 特定の授業IDに対して、空メモを除外してクリーン保存する防波堤
  Future<void> _saveMemosForId(dynamic cId, List<Map<String, dynamic>> memoList) async {
    final prefs = await SharedPreferences.getInstance();
    final realMemos = memoList.where((m) => (m['items'] as List? ?? []).isNotEmpty).toList();
    await prefs.setString('course_memos_v2_$cId', jsonEncode(realMemos));
  }

  // 🟢 現在の授業のローカル保存
  Future<void> _saveMemos() async {
    await _saveMemosForId(widget.courseId, _memos);
  }

  // 🟢 一覧へ視点を戻す（メモリ上では空でも今日の項目を仮維持）
  void _closeMemo() {
    FocusScope.of(context).unfocus();
    setState(() {
      _activeMemoId = null;
    });
    widget.onMemoStateChanged?.call(false);
    _saveMemos();
  }

  // 🟢 一時キャッシュの画像を安全な領域（Documents）にコピーして永続化する
  Future<String> _saveImageToLocal(String tempPath) async {
    final directory = await getApplicationDocumentsDirectory();
    final memoDirPath = '${directory.path}/memo_images';
    final memoDir = Directory(memoDirPath);
    if (!await memoDir.exists()) {
      await memoDir.create(recursive: true);
    }
    final fileName = 'memo_img_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final savedImage = await File(tempPath).copy('$memoDirPath/$fileName');
    return savedImage.path;
  }

  // 🟢 Undoを考慮した画像の遅延削除
  void _scheduleFileDeletion(String path) {
    Future.delayed(const Duration(seconds: 6), () {
      bool isStillInUse = false;
      for (var memo in _memos) {
        final items = memo['items'] as List<dynamic>? ?? [];
        for (var item in items) {
          if (item['type'] == 'image' && item['data'] == path) {
            isStillInUse = true;
            break;
          }
        }
      }
      if (!isStillInUse) {
        try {
          final file = File(path);
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
      }
    });
  }

  // 🟢 教科名のクリーンフィルター
  String _getFilteredCourseName(String name) {
    if (name.isEmpty) return '';
    return CourseTitleParser.getCleanTitle(name);
  }

  // 🟢 メモへアイテム（テキスト・画像）をドッキング
  void _addItemToMemo(String type, String data) {
    if (_activeMemoId == null) return;
    final index = _memos.indexWhere((m) => m['id']?.toString() == _activeMemoId);
    if (index != -1) {
      final now = DateTime.now();
      final timeStr = "${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}";
      setState(() {
        List<dynamic> items = List<dynamic>.from(_memos[index]['items'] ?? []);
        items.add({'id': now.millisecondsSinceEpoch.toString(), 'type': type, 'data': data, 'time': timeStr});
        _memos[index]['items'] = items;
      });
      _saveMemos();
    }
  }

  // 🟢 メモ内アイテムの削除（Undoスナックバー連動）
  void _deleteItem(int memoIndex, int itemIndex) {
    final deletedItem = _memos[memoIndex]['items'][itemIndex];
    final currentCourseId = widget.courseId;
    final currentMemoId = _memos[memoIndex]['id'];

    setState(() {
      List<dynamic> items = List<dynamic>.from(_memos[memoIndex]['items'] ?? []);
      items.removeAt(itemIndex);
      _memos[memoIndex]['items'] = items;
    });
    _saveMemos();

    AppSnackBar.showUndo(context, "メモを削除しました", () {
      if (widget.courseId != currentCourseId) return;
      setState(() {
        final targetIndex = _memos.indexWhere((m) => m['id'] == currentMemoId);
        if (targetIndex != -1) {
          List<dynamic> items = List<dynamic>.from(_memos[targetIndex]['items'] ?? []);
          if (itemIndex <= items.length) items.insert(itemIndex, deletedItem);
          else items.add(deletedItem);
          _memos[targetIndex]['items'] = items;
        }
      });
      _saveMemos();
    });
    if (deletedItem['type'] == 'image') {
      _scheduleFileDeletion(deletedItem['data']);
    }
  }

  // 🟢 過去ログから特定のメモシートを削除（Undoスナックバー連動）
  void _deleteMemoTab(int index) {
    final deletedMemo = _memos[index];
    final currentCourseId = widget.courseId;

    setState(() {
      _memos.removeAt(index);
      if (_activeMemoId == deletedMemo['id']?.toString()) {
        _activeMemoId = null;
        widget.onMemoStateChanged?.call(false);
      }
    });
    _saveMemos();

    AppSnackBar.showUndo(context, "メモタブを削除しました", () {
      if (widget.courseId != currentCourseId) return;
      setState(() {
        if (index <= _memos.length) _memos.insert(index, deletedMemo);
        else _memos.add(deletedMemo);
      });
      _saveMemos();
    });
    final items = deletedMemo['items'] as List<dynamic>? ?? [];
    for (var item in items) {
      if (item['type'] == 'image') {
        _scheduleFileDeletion(item['data']);
      }
    }
  }

  // 🟢 タブ名（タイトル）編集モーダル
  void _editTitleDialog(String currentTitle, int index) {
    String newTitle = currentTitle;
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Edit Tab Name', style: TextStyle(color: Colors.black)),
          content: TextField(
            controller: TextEditingController(text: currentTitle),
            style: const TextStyle(color: Colors.black),
            decoration: const InputDecoration(focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.black))),
            onChanged: (v) => newTitle = v,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.black54))),
            TextButton(onPressed: () { setState(() => _memos[index]['title'] = newTitle); _saveMemos(); Navigator.pop(ctx); }, child: const Text('Save', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
          ],
        )
    );
  }

  // 🟢 内製カスタムカメラルーティング（インターロック完備）
  // 🟢 確認：course_detail_screen.dart 側の _takePhoto メソッド
  Future<void> _takePhoto() async {
    try {
      globalDisableAutoCacheClear = true;
      final String? savedPath = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const CustomCameraScreen()),
      );

      // 💡 CameraScreenから正真正銘の「.png」パスが返ってくるため、
      // cacheWidth 制限サムネイルが詰まることなく一瞬で点灯するようになります！
      if (savedPath != null && savedPath.isNotEmpty) {
        _addItemToMemo('image', savedPath);
      }
    } catch (e) {
      debugPrint("Take Photo via Custom Camera Error: $e");
    } finally {
      globalDisableAutoCacheClear = false;
    }
  }

  // 🟢 ギャラリーから複数画像インポート（インターロック完備）
  Future<void> _pickFile() async {
    try {
      globalDisableAutoCacheClear = true;
      final List<XFile> files = await _picker.pickMultiImage(imageQuality: 80, maxWidth: 2400);
      if (files.isNotEmpty) {
        for (var file in files) {
          final savedPath = await _saveImageToLocal(file.path);
          _addItemToMemo('image', savedPath);
        }
      }
    } catch (e) {
      debugPrint("Pick File Error: $e");
    } finally {
      globalDisableAutoCacheClear = false;
    }
  }

  // 🎯 完全リファイン：現在の画面表示状態に関わらず、今日のメモシートを強制スキャンして100%確実に画像をねじ込む防衛エンジン
  void appendExternalImages(List<String> paths) {
    if (paths.isEmpty) return;

    final now = DateTime.now();
    final dateStr = '${now.month.toString().padLeft(2,'0')}/${now.day.toString().padLeft(2,'0')}';
    final timeStr = "${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}";

    // 🟢 画面表示が null や別モードであっても、メモリ内の _memos ログから「今日のシート」のインデックスを直接ハック
    int todayIdx = _memos.indexWhere((m) => m['title']?.toString().startsWith(dateStr) ?? false);

    // 万が一今日のシートがまだ生成されていなければ、その場で強制緊急生成
    if (todayIdx == -1) {
      final filteredName = _getFilteredCourseName(widget.courseName);
      final newTitle = filteredName.isNotEmpty ? '$dateStr $filteredName' : dateStr;

      _memos.add({
        'id': now.millisecondsSinceEpoch.toString(),
        'title': newTitle,
        'items': <dynamic>[],
      });
      todayIdx = _memos.length - 1;
    }

    setState(() {
      List<dynamic> items = List<dynamic>.from(_memos[todayIdx]['items'] ?? []);
      for (var path in paths) {
        final uniqueId = (now.millisecondsSinceEpoch + paths.indexOf(path)).toString();
        items.add({
          'id': uniqueId,
          'type': 'image',
          'data': path,
          'time': timeStr
        });
      }
      _memos[todayIdx]['items'] = items;
    });

    _saveMemos(); // 🚀 バックグラウンドの SharedPreferences へ即座に確定永続化
  }

  // 🟢 タイポグラフィテキスト入力オーバーレイ起動
  void _openTextInput() {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color inputBg = isDark ? const Color(0xFF222222) : const Color(0xFFEEEEEE);
    Color inputCol = isDark ? Colors.white : Colors.black;

    Navigator.push(context, PageRouteBuilder(
        opaque: false, barrierColor: Colors.black.withOpacity(0.95), barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: _TextInputOverlay(bgColor: inputBg, textColor: inputCol, onSubmitted: (text) => _addItemToMemo('text', text)),
          );
        }
    ));
  }

  // 🟢 フルスクリーンイメージギャラリー（InteractiveViewer搭載）
  void _showFullScreenImage(int memoIndex, String initialPath) {
    final memo = _memos[memoIndex];
    final items = memo['items'] as List<dynamic>? ?? [];
    final imageItems = items.where((item) => item['type'] == 'image').toList();
    final initialIndex = imageItems.indexWhere((item) => item['data']?.toString() == initialPath);

    Navigator.push(context, PageRouteBuilder(
        opaque: false, barrierColor: Colors.black,
        pageBuilder: (context, _, __) => _FullScreenImageGallery(imageItems: imageItems, initialIndex: initialIndex != -1 ? initialIndex : 0)
    ));
  }

  // 🟢 新設：日付をまたいで全板書画像を爆速スワイプ＆ピンチズームできる黒色空間
  // 🟢 修正：全画像スライダー内に、現在表示中の画像を個別共有できるダイレクトシェア機能をインプラント
  // 🟢 修正：境界ノイズ（黒帯）の完全パージ ＆ 視覚的アッパーセンター配置スライダー
  void _showAllImagesSlider(List<String> imagePaths, int initialIndex) {
    if (imagePaths.isEmpty) return;

    int currentIndex = initialIndex;
    final PageController pageController = PageController(initialPage: initialIndex);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StatefulBuilder(
            builder: (context, setModalState) {
              return Scaffold(
                backgroundColor: Colors.black,
                // ─── 🟢 決定打①：AppBarの後ろまでボディを全画面拡張 ───
                // これにより、AppBarが確保していた上部の不自然なレイアウトの「ハコ感（黒帯）」が跡形もなく消滅します
                extendBodyBehindAppBar: true,

                appBar: AppBar(
                  backgroundColor: Colors.transparent, // 空間に完全に溶け込ませる
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 24),
                    onPressed: () => Navigator.pop(context),
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.share, color: Colors.white, size: 22),
                      onPressed: () async {
                        final box = context.findRenderObject() as RenderBox?;
                        final rect = box != null ? box.localToGlobal(Offset.zero) & box.size : null;

                        await Share.shareXFiles(
                          [XFile(imagePaths[currentIndex])],
                          sharePositionOrigin: rect,
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                body: PageView.builder(
                  itemCount: imagePaths.length,
                  controller: pageController,
                  physics: const BouncingScrollPhysics(),
                  onPageChanged: (index) {
                    setModalState(() {
                      currentIndex = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    return SizedBox.expand(
                      child: InteractiveViewer(
                        clipBehavior: Clip.none,
                        minScale: 1.0,
                        maxScale: 5.0,

                        // ─── 🟢 決定打②：Centerをパージし、上方オフセットをかけたAlignへ換装 ───
                        // 横方向は完全に「中心にそろえ」つつ、縦位置を少し上（-0.15）へ吊り上げ、人間の目に最も美しい「視覚的センター」へ調教します
                        child: Align(
                          alignment: const Alignment(0, 0),
                          child: Image.file(
                            File(imagePaths[index]),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            }
        ),
      ),
    );
  }

  // 🟢 PDFジェネレータ用日時整形ラッパー
  Map<String, String> _generateDateTimeStrings(List<dynamic> items) {
    final now = DateTime.now();
    final months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

    final monthDate = "${months[now.month - 1]} ${now.day}";
    final year = "${now.year}";
    final weekday = weekdays[now.weekday - 1];

    String timeRange = "";
    if (items.isNotEmpty) {
      final first = items.first['time'] ?? '';
      final last = items.last['time'] ?? '';
      timeRange = first == last ? first : "$first - $last";
    } else {
      timeRange = "${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}";
    }

    return {
      "monthDate": monthDate,
      "year": year,
      "weekday": weekday,
      "time": timeRange
    };
  }

  // 🟢 サニタイズ（PDF制御コード・絵文字クラッシュ防止ガード）
  String _sanitizeTextForPdf(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]'), '')
        .replaceAll(RegExp(r'[\u{1F600}-\u{1F64F}]', unicode: true), '□')
        .replaceAll(RegExp(r'[\u{1F300}-\u{1F5FF}]', unicode: true), '□')
        .replaceAll(RegExp(r'[\u{1F680}-\u{1F6FF}]', unicode: true), '□')
        .replaceAll(RegExp(r'[\u{2600}-\u{26FF}]', unicode: true), '□')
        .replaceAll(RegExp(r'[\u{2700}-\u{27BF}]', unicode: true), '□');
  }

  // 🟢 共有ダイアログ（iPadOS位置追従ポップオーバー完備）
  // 🟢 修正：全体メモ（-1）の着信をインターロックする統合エクスポートプロセッサ
  Future<void> _shareMemo(int memoIndex) async {
    final bool isAllCombined = memoIndex == -1;
    BuildContext? sheetContext;
    showModalBottomSheet(
        context: context,
        backgroundColor: widget.bgColor,
        isDismissible: false,
        enableDrag: false,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        builder: (ctx) {
          sheetContext = ctx;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 48.0),
            child: SizedBox(
              height: 64,
              child: Center(child: CircularProgressIndicator(color: widget.textColor)),
            ),
          );
        }
    );

    await Future.delayed(const Duration(milliseconds: 350));
    final pdfResult = await _generatePdf(memoIndex); // 👈 -1 のままPDFコンパイラへ突入

    if (sheetContext != null && mounted) {
      Navigator.pop(sheetContext!);
    }

    if (pdfResult != null && !pdfResult.startsWith("ERROR:")) {
      final box = context.findRenderObject() as RenderBox?;
      final rect = box != null ? box.localToGlobal(Offset.zero) & box.size : null;

      // 🟢 修正：XFileにMIMEタイプをインプラントし、iOSのテキスト2重生成バグを完全パージ
      await Share.shareXFiles(
        [XFile(pdfResult, mimeType: 'application/pdf')], // 👈 mimeType を明示
        // ❌ 削除: text: isAllCombined ? "授業全体メモ" : _memos[memoIndex]['title'],
        // 💡 ファイルとテキストの同時共有はiOSでは厳禁のため、潔く text 引数はパージします
        sharePositionOrigin: rect,
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDFエラー: ${pdfResult?.replaceFirst("ERROR:", "") ?? "不明なエラー"}'))
      );
    }
  }

  // 🟢 日本語マルチページ対応PDFコンパイルエンジン
  // 🟢 修正：単発メモ ⇄ 過去ログ全統合タイムラインを自動スイッチする高剛性PDFコンパイルエンジン
  // 🟢 修正：通常PDFを100%ホールドし、全体まとめPDFだけを表紙特化仕様へ調教
  Future<String?> _generatePdf(int memoIndex) async {
    try {
      final bool isAllCombined = memoIndex == -1;
      final pdf = pw.Document();

      List<dynamic> items = [];
      String fileSaveTitle = "";
      String documentDisplayTitle = "";
      String periodStr = ""; // 🟢 追記：全体メモの「〇月〇日 - 〇月〇日」を格納するハック変数

      if (isAllCombined) {
        // 🔲 【ルートA】授業全体メモのデータソースコンパイル
        // 🟢 修正：最上部のタイトルを「全体メモ」ではなく、純粋な「授業名」に直撃換装
        documentDisplayTitle = _getFilteredCourseName(widget.courseName);
        fileSaveTitle = "授業全体メモ_${documentDisplayTitle}";

        List<dynamic> combinedList = [];
        for (var m in _memos) {
          String rawTitle = m['title']?.toString() ?? '';
          String datePrefix = rawTitle.length >= 5 ? rawTitle.substring(0, 5) : rawTitle;

          final mItems = m['items'] as List<dynamic>? ?? [];
          for (var item in mItems) {
            final newItem = Map<String, dynamic>.from(item);
            newItem['date_group'] = datePrefix;
            newItem['parent_memo_id'] = m['id'];
            combinedList.add(newItem);
          }
        }
        items = combinedList;

        // 🟢 追記：全ログから「最初のメモの日付」と「最後のメモの日付」を自動抽出し、期間文字列を生成
        if (items.isNotEmpty) {
          String firstDate = items.first['date_group'] ?? '';
          String lastDate = items.last['date_group'] ?? '';

          // "06/15" を "6月15日" に美しくパースする内部フィルター
          String formatDocDate(String md) {
            if (md.contains('/')) {
              final parts = md.split('/');
              try {
                int m = int.parse(parts[0]);
                int d = int.parse(parts[1]);
                return "${m}/${d}";
              } catch(_) {}
            }
            return md;
          }

          if (firstDate == lastDate) {
            periodStr = formatDocDate(firstDate);
          } else if (firstDate.isNotEmpty && lastDate.isNotEmpty) {
            periodStr = "${formatDocDate(firstDate)} - ${formatDocDate(lastDate)}";
          }
        }
      } else {
        // ⬠ 【ルートB】通常の単発日付メモの処理（1ミリも変更なし）
        final memo = _memos[memoIndex];
        items = memo['items'] ?? [];
        String rawTitle = memo['title']?.toString() ?? 'Untitled';
        documentDisplayTitle = rawTitle;
        fileSaveTitle = rawTitle;

        final defaultDatePattern = RegExp(r'^(\d{2})/(\d{2})\s+(.+)$');
        final match = defaultDatePattern.firstMatch(rawTitle);
        if (match != null) {
          documentDisplayTitle = match.group(3)!.trim();
          fileSaveTitle = documentDisplayTitle + "_" + match.group(1)! + "-" + match.group(2)!;
        } else {
          final dateOnlyPattern = RegExp(r'^(\d{2})/(\d{2})$');
          final matchDateOnly = dateOnlyPattern.firstMatch(rawTitle);
          if (matchDateOnly != null) {
            documentDisplayTitle = rawTitle;
            fileSaveTitle = matchDateOnly.group(1)! + "-" + matchDateOnly.group(2)!;
          }
        }
      }

      final dateTimeInfo = _generateDateTimeStrings(items);
      final fontData = await rootBundle.load('assets/fonts/ZenKakuGothicNew-Regular.ttf');
      final jpFont = pw.Font.ttf(fontData);
      final safeDisplayTitle = _sanitizeTextForPdf(documentDisplayTitle);
      final Map<String, Uint8List> imageBytesMap = {};
      for (var item in items) {
        if (item['type'] != 'text') {
          final String path = item['data'].toString();
          if (await File(path).exists()) {
            // 同期(Sync)ではなく、非同期(await)でバックグラウンドから安全にバイトを吸い出します
            imageBytesMap[path] = await File(path).readAsBytes();
          }
        }
      }

      pdf.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            margin: const pw.EdgeInsets.all(48),
            theme: pw.ThemeData.withFont(base: jpFont),
          ),
          build: (pw.Context context) => [
            // ─── 表紙・大判タイポグラフィセクター ───
            // タイポグラフィ表紙ヘッダー
            pw.Row(
              // ❌ 修正前: crossAxisAlignment: CrossAxisAlignment.start,
              // 🟢 修正後：頭に pw. を付けてPDF純正パーツであることを明示
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(flex: 1, child: pw.SizedBox()),
                  pw.Expanded(
                      flex: 2,
                      child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: isAllCombined
                              ? [
                            // 🟢 全体まとめ専用：ノイズを削ぎ落とした3行のシンプリシティ構成
                            pw.Text(safeDisplayTitle, style: pw.TextStyle(font: jpFont, fontSize: 40, lineSpacing: 1.2, color: PdfColors.black)),
                            pw.Text("${dateTimeInfo['year']!}", style: pw.TextStyle(font: jpFont, fontSize: 40, lineSpacing: 1.2, color: PdfColors.black)),
                            if (periodStr.isNotEmpty)
                              pw.Text(periodStr, style: pw.TextStyle(font: jpFont, fontSize: 40, lineSpacing: 1.2, color: PdfColors.black)),
                          ]
                              : [
                            // 🔴 通常メモ用：以前の5行スタイルを【完全無傷で100%維持】
                            pw.Text(safeDisplayTitle, style: pw.TextStyle(font: jpFont, fontSize: 40, lineSpacing: 1.2, color: PdfColors.black)),
                            pw.Text(dateTimeInfo['monthDate']!, style: pw.TextStyle(font: jpFont, fontSize: 40, lineSpacing: 1.2, color: PdfColors.black)),
                            pw.Text(dateTimeInfo['year']!, style: pw.TextStyle(font: jpFont, fontSize: 40, lineSpacing: 1.2, color: PdfColors.black)),
                            pw.Text(dateTimeInfo['weekday']!, style: pw.TextStyle(font: jpFont, fontSize: 40, lineSpacing: 1.2, color: PdfColors.black)),
                            pw.Text(dateTimeInfo['time']!, style: pw.TextStyle(font: jpFont, fontSize: 40, lineSpacing: 1.2, color: PdfColors.black)),
                          ]
                      )
                  ),
                ]
            ),
            pw.SizedBox(height: 64),

            // ...（以降のタイムライン生成ループ部分コードは一切変更なし）...

            // タイムラインの構築
            ...List.generate(items.length, (index) {
              final item = items[index];
              final bool isText = item['type'] == 'text';
              final safeData = _sanitizeTextForPdf(item['data']?.toString() ?? '');

              // 🟢 PDF内での日付ヘッダーの動的挿入判定
              bool showDateHeader = false;
              if (isAllCombined) {
                if (index == 0) {
                  showDateHeader = true;
                } else {
                  final prevItem = items[index - 1];
                  if (prevItem['date_group'] != item['date_group']) {
                    showDateHeader = true;
                  }
                }
              }

              return pw.Column(
                // ❌ 修正前: crossAxisAlignment: CrossAxisAlignment.start,
                // 🟢 修正後：ここも頭に pw. を補填
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // 日付ヘッダー描画
                  if (showDateHeader) ...[
                    if (index > 0) pw.SizedBox(height: 28),
                    pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 14),
                      child: pw.Text(
                        item['date_group'] ?? '',
                        style: pw.TextStyle(
                          font: jpFont,
                          fontSize: 19,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                    ),
                  ],
                  pw.Container(
                    margin: const pw.EdgeInsets.symmetric(vertical: 8),
                    child: pw.Row(
                      // ❌ 修正前: crossAxisAlignment: CrossAxisAlignment.start,
                      // 🟢 修正後：ここにも頭に pw. を補填してPDFエンジン専用の型へ統一します
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                            flex: 1,
                            child: pw.Text(item['time']?.toString() ?? '', style: pw.TextStyle(font: jpFont, fontSize: 14, color: PdfColors.black))
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: isText
                              ? pw.Text(safeData, style: pw.TextStyle(font: jpFont, fontSize: 14, lineSpacing: 1.5, color: PdfColors.black))
                              : pw.ConstrainedBox(
                            constraints: const pw.BoxConstraints(maxHeight: 340),
                            child: pw.ClipRRect(
                              horizontalRadius: 8,
                              verticalRadius: 8,
                              // ─── 🟢 ここを重い Sync から、軽量なプリロードマップ参照へ換装 ───
                              child: imageBytesMap.containsKey(item['data'].toString())
                                  ? pw.Image(
                                pw.MemoryImage(imageBytesMap[item['data'].toString()]!),
                                fit: pw.BoxFit.contain,
                              )
                                  : pw.SizedBox(), // 万が一画像ファイルが壊れて消失していてもクラッシュさせない防衛線
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      );

      final output = await getTemporaryDirectory();
      final fileSafeName = fileSaveTitle.replaceAll(RegExp(r'[\\/:*?"<>|\r\n]'), '_');
      final fileName = fileSafeName.trim().isEmpty ? "Memo_All" : fileSafeName;
      final file = File("${output.path}/$fileName.pdf");
      await file.writeAsBytes(await pdf.save());
      return file.path;
    } catch (e) {
      debugPrint("PDF Export Error: $e");
      return "ERROR: $e";
    }
  }

  // 🟢 メモ一覧（インデックスシートビュー）
  // 🟢 メモ一覧（インデックスシートビュー）
  // 🟢 修正：囲いをパージし、極細ラインで美しく整地したミニマルインデックスビュー
  // 🟢 修正：左アイコンをパージし、MODULESと完全同一の境界線をインプラントした一覧ビュー
  // 🟢 修正：最上部に日付なしの「授業全体メモ」を完全インプラント
  // 🟢 修正：最上部タイトルの動的化 ＆ 100%等間隔ワイヤーフレームグリッド
  // 🟢 修正：ゴミ箱の有無による高さを完全相殺した、絶対等間隔タイムライン
  @override
  Widget _buildListView() {
    double bottomPadding = MediaQuery.of(context).padding.bottom;
    final now = DateTime.now();
    final dateStr = '${now.month.toString().padLeft(2,'0')}/${now.day.toString().padLeft(2,'0')}';

    final cleanCourseName = _getFilteredCourseName(widget.courseName);
    final combinedTitle = cleanCourseName.isNotEmpty ? "$cleanCourseName まとめ" : "まとめ";

    return ListView.builder(
        padding: EdgeInsets.only(top: 8, left: 16, right: 16, bottom: 24 + bottomPadding),
        itemCount: _memos.length + 1,
        itemBuilder: (context, index) {

          // ✨ 【セクターA】最上部に固定出現する「授業名 ＋ まとめ」
          if (index == 0) {
            return Column(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() => _activeMemoId = 'ALL_COMBINED');
                    widget.onMemoStateChanged?.call(true);
                  },
                  child: Container(
                      padding: const EdgeInsets.only(top: 12.0, bottom: 40.0),
                      color: Colors.transparent,
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                                child: Text(
                                  combinedTitle,
                                  style: TextStyle(color: widget.textColor, fontSize: 14, fontWeight: FontWeight.bold),
                                )
                            ),
                            // 🟢 修正：通常行と高さをミリ単位で一致させるため、48x48の固定ボックスを配置
                            const SizedBox(width: 48, height: 48),
                          ]
                      )
                  ),
                ),
                Divider(color: widget.textColor.withOpacity(0.5), thickness: 0.5, height: 1),
              ],
            );
          }

          // ✨ 【セクターB】通常の各日付メモ
          final i = index - 1;
          final memo = _memos[i];
          final String title = memo['title']?.toString() ?? 'Untitled';
          final bool isToday = title.startsWith(dateStr);

          return Column(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() => _activeMemoId = memo['id']?.toString());
                  widget.onMemoStateChanged?.call(true);
                },
                child: Container(
                    padding: const EdgeInsets.only(top: 12.0, bottom: 40.0),
                    color: Colors.transparent,
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                              child: Text(
                                  title,
                                  style: TextStyle(color: widget.textColor, fontSize: 14, fontWeight: FontWeight.w500),
                                  maxLines: 1, overflow: TextOverflow.ellipsis
                              )
                          ),

                          // 🟢 修正：ゴミ箱の有無にかかわらず、外殻を「48x48」の同じコンテナで完全拘束。
                          // これにより、Rowの高さ計算が100%同一になり、上下の余白がガチッと等間隔に揃います。
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: !isToday
                                ? Center(
                              child: IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: Icon(Icons.delete, size: 18, color: widget.textColor.withOpacity(0.3)),
                                  onPressed: () => _deleteMemoTab(i)
                              ),
                            )
                                : const SizedBox(),
                          ),
                        ]
                    )
                ),
              ),
              Divider(color: widget.textColor.withOpacity(0.5), thickness: 0.5, height: 1),
            ],
          );
        }
    );
  }
  // 🟢 メモ詳細（エディタ・撮影・キャンバスビュー）
  // 🟢 修正：全体まとめビューの動的コンパイル＆閲覧特化ハック
  // 🟢 修正：全体メモ時は4角形長方形化 ＆ 日付セクター自動リレー型タイムライン
  @override
  Widget _buildDetailView() {
    final bool isAllCombined = _activeMemoId == 'ALL_COMBINED';

    int memoIndex = -1;
    Map<String, dynamic> memo = {};
    List<dynamic> items = [];
    String displayTitle = "";
    String periodStr = "";

    // ─── 🟢 追記：全体メモ内のすべての画像パスを直列に束ねるコンパイラ配列 ───
    List<String> allCombinedImages = [];

    if (isAllCombined) {
      // 🟢 修正：固定文字をパージし、「教科名 ＋ まとめ」のソリッドなタイトルへ動的ハック
      final cleanCourseName = _getFilteredCourseName(widget.courseName);
      displayTitle = cleanCourseName.isNotEmpty ? "$cleanCourseName まとめ" : "まとめ";

      List<dynamic> combinedList = [];
      for (var m in _memos) {
        String rawTitle = m['title']?.toString() ?? '';
        String datePrefix = rawTitle.length >= 5 ? rawTitle.substring(0, 5) : rawTitle;

        final mItems = m['items'] as List<dynamic>? ?? [];
        for (var item in mItems) {
          final newItem = Map<String, dynamic>.from(item);
          newItem['date_group'] = datePrefix;
          newItem['parent_memo_id'] = m['id'];
          combinedList.add(newItem);
          if (item['type'] != 'text') {
            allCombinedImages.add(item['data'].toString());
          }
        }
      }
      items = combinedList;
    } else {
      memoIndex = _memos.indexWhere((m) => m['id']?.toString() == _activeMemoId);
      if (memoIndex == -1) return const SizedBox();
      memo = _memos[memoIndex];
      items = memo['items'] ?? [];
      displayTitle = memo['title']?.toString() ?? 'Untitled';
    }

    Color solidBtnBg = widget.textColor;
    Color solidIconCol = AppTheme.getTextColorForBackground(solidBtnBg);
    double bottomPadding = MediaQuery.of(context).padding.bottom;

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color memoBg = isDark ? Colors.black : const Color(0xFFF5F7F8);
    final Color contentTextCol = isDark ? Colors.white : Colors.black;
    final Color timeTextCol = isDark ? Colors.white54 : Colors.black45;
    final Color deleteIconCol = isDark ? Colors.white30 : Colors.black26;

    final Color roundBtnBg = isDark ? Colors.black : const Color(0xFFF5F7F8);
    final Color roundBtnIconCol = isDark ? Colors.white : Colors.black;

    // ─── 🟢 共通コンテナエンジンの定義（コード重複のパージ） ───
    final Widget memoContainer = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: memoBg,
        // 🟢 全体メモモードの時だけ、5角形ではなく「4角形の通常の長方形（16px角丸）」へトランスフォーム
        borderRadius: isAllCombined ? BorderRadius.circular(16) : null,
      ),
      child: ListView.builder(
          padding: const EdgeInsets.only(top: 16, left: 24, right: 24, bottom: 180),
          physics: const BouncingScrollPhysics(),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];

            // 🟢 ② 日付が変わった境界のフレームを動的検知
            bool showDateHeader = false;
            if (isAllCombined) {
              if (index == 0) {
                showDateHeader = true;
              } else {
                final prevItem = items[index - 1];
                if (prevItem['date_group'] != item['date_group']) {
                  showDateHeader = true;
                }
              }
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🟢 ③ 日付ごとに隙間を開けてインダストリアルな日付ヘッダーをインプラント
                  // 🟢 ③ 日付ごとに隙間を開けてインダストリアルな日付ヘッダーをインプラント
                  if (showDateHeader) ...[
                    if (index > 0) const SizedBox(height: 36), // 上のセクターとの隙間を32➔36へわずかに拡大
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14.0),
                      child: Text(
                        item['date_group'] ?? '',
                        style: TextStyle(
                          color: contentTextCol.withOpacity(0.85), // 馴染みの良いメカニカルグレー
                          // ❌ 修正前: fontSize: 12, fontWeight: FontWeight.bold,
                          // 🟢 修正後：サイズを 18 へスケールアップし、細字（w300）でエッジを立てる
                          fontSize: 20,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 0, // 🟢 文字間隔を 2.0 ➔ 3.0 へ広げ、洗練された空間を演出
                        ),
                      ),
                    ),
                  ],
                  Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 🟢 ④ 通常メモと同じ「時刻のみ」の表示に戻すため、幅はスマートに「40」のままホールド！
                        SizedBox(
                            width: 40,
                            child: Text(
                                item['time'] ?? '',
                                style: TextStyle(color: timeTextCol, fontSize: 10, fontWeight: FontWeight.bold)
                            )
                        ),
                        Expanded(
                          child: item['type'] == 'text'
                              ? Text(item['data'] ?? '', style: TextStyle(color: contentTextCol, fontSize: 16, height: 1.4))
                              : Align(
                              alignment: Alignment.centerLeft,
                              child: GestureDetector(
                                  onTap: () {
                                    if (isAllCombined) {
                                      final currentPath = item['data'].toString();
                                      final int initialIdx = allCombinedImages.indexOf(currentPath);
                                      _showAllImagesSlider(allCombinedImages, initialIdx);
                                    } else {
                                      _showFullScreenImage(memoIndex, item['data']);
                                    }
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    // ─── 🟢 修正：オリジナル高画質はそのまま、デコード負荷のみを1/100へパージ ───
                                    child: Image.file(
                                      File(item['data']),
                                      width: 180,
                                      height: 120,
                                      fit: BoxFit.cover,

                                      // 💡 コアハック：メモリに展開するサイズを表示枠の2倍（Retinaディスプレイ等の高精細対応）に完全制限！
                                      cacheWidth: 360,  // 180 * 2
                                      //cacheHeight: 240, // 120 * 2

                                      gaplessPlayback: true, // 状態更新時の画像のチラつきをハードウェア側で防止

                                      // スナップ撮影直後やファイル書き込みの超微細なラグによる一瞬の不発をガード
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(
                                          width: 180, height: 120,
                                          decoration: BoxDecoration(
                                            color: contentTextCol.withOpacity(0.05),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(Icons.broken_image, color: deleteIconCol, size: 20),
                                        );
                                      },
                                    ),
                                  )
                              )
                          ),
                        ),
                        if (!isAllCombined)
                          IconButton(icon: Icon(Icons.delete, size: 16, color: deleteIconCol), onPressed: () => _deleteItem(memoIndex, index))
                        else
                          const SizedBox(width: 48),
                      ]
                  ),
                ],
              ),
            );
          }
      ),
    );

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── 上部ヘッダーセクター ───
            Padding(
              padding: const EdgeInsets.only(top: 8.0, left: 16.0, right: 16.0, bottom: 4.0),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque, onTap: _closeMemo,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: isDark ? Colors.black : Colors.white, shape: BoxShape.circle),
                      child: Icon(Icons.arrow_back_ios_new, color: isDark ? Colors.white : Colors.black, size: 15),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: isAllCombined ? null : () => _editTitleDialog(memo['title']?.toString() ?? '', memoIndex),
                      child: Text(displayTitle, style: TextStyle(color: widget.textColor, fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),

                  // 🟢 修正：if (!isAllCombined) のガードを完全にパージ！
                  // これにより、全体まとめ画面でも共有ボタン（Icons.share）が100%常時出現します
                  IconButton(
                      icon: Icon(Icons.share, color: widget.textColor, size: 20),
                      onPressed: () => _shareMemo(isAllCombined ? -1 : memoIndex)
                  ),
                ],
              ),
            ),

            // ─── 🟢 ⑤ 最外殻での条件分岐（4角形 ⇄ 5角形クリッパー） ───
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: 8.0, right: 8.0, bottom: 0 + bottomPadding),
                child: isAllCombined
                    ? memoContainer // 🔲 日付なし全体メモ：4角形の通常の長方形
                    : ClipPath(clipper: _MemoAreaClipper(), child: memoContainer), // ⬠ 日付あり通常メモ：5角形斜めカット
              ),
            ),
          ],
        ),

        // 右下の入力丸ボタン3種（全体まとめ時は非表示）
        if (!isAllCombined) ...[
          Positioned(
            bottom: 0 + bottomPadding, right: 8,
            child: _buildRoundBtn(Icons.photo_library, roundBtnBg, roundBtnIconCol, _pickFile),
          ),
          Positioned(
            bottom: 0 + bottomPadding, right: 8 + 56 + 12,
            child: _buildRoundBtn(Icons.camera_alt, roundBtnBg, roundBtnIconCol, _takePhoto),
          ),
          Positioned(
            bottom: 0 + 56 + 12 + bottomPadding, right: 8,
            child: _buildRoundBtn(Icons.edit, roundBtnBg, roundBtnIconCol, _openTextInput),
          ),
        ],
      ],
    );
  }

  @override
  Widget _buildRoundBtn(IconData icon, Color bg, Color iconCol, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56, height: 56,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, color: iconCol, size: 24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      width: double.infinity,
      color: widget.bgColor,
      child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _activeMemoId == null ? _buildListView() : _buildDetailView()
      ),
    );
  }
}


// ★ 修正：すべての角をフィレットした完全な5角形クリッパー
class _MemoAreaClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    double r = 16.0;
    double cut = 175.0;
    double w = size.width;
    double h = size.height;


    // 左上角から開始
    path.moveTo(0, r);
    path.arcToPoint(Offset(r, 0), radius: Radius.circular(r));


    // 右上角
    path.lineTo(w - r, 0);
    path.arcToPoint(Offset(w, r), radius: Radius.circular(r));


    // 右下の斜めカット開始角 (フィレット)
    path.lineTo(w, h - cut - r);
    path.quadraticBezierTo(w, h - cut, w - r, h - cut + r);


    // 斜め線
    path.lineTo(w - cut + r, h - r);


    // 右下の斜めカット終了角 (フィレット)
    path.quadraticBezierTo(w - cut, h, w - cut - r, h);


    // 左下角
    path.lineTo(r, h);
    path.arcToPoint(Offset(0, h - r), radius: Radius.circular(r));


    path.close();
    return path;
  }


  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}


class _TextInputOverlay extends StatefulWidget {
  final Function(String) onSubmitted;
  final Color bgColor;
  final Color textColor;




  const _TextInputOverlay({required this.onSubmitted, required this.bgColor, required this.textColor});




  @override
  State<_TextInputOverlay> createState() => _TextInputOverlayState();
}


class _TextInputOverlayState extends State<_TextInputOverlay> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;




  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {
        _hasText = _controller.text.trim().isNotEmpty;
      });
    });
  }




  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }




  @override
  Widget build(BuildContext context) {
    double topPadding = MediaQuery.of(context).padding.top;
    double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;




    double maxCardHeight = MediaQuery.of(context).size.height - topPadding - 80.0 - keyboardHeight;
    if (maxCardHeight < 100) maxCardHeight = 100;




    return Stack(
      children: [
        Positioned(
          top: topPadding + 16.0,
          left: 16.0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(context),
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(Icons.close, color: Colors.white, size: 28),
            ),
          ),
        ),




        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: keyboardHeight + 8.0,
            ),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              builder: (context, val, child) {
                return Transform.scale(
                  scale: val,
                  alignment: const Alignment(0.8, 1.0),
                  child: Opacity(opacity: val, child: child),
                );
              },
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: maxCardHeight,
                ),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: widget.bgColor,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding: const EdgeInsets.only(left: 24, right: 16, top: 16, bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          autofocus: true,
                          minLines: 4,
                          maxLines: null,
                          cursorColor: widget.textColor,
                          style: TextStyle(color: widget.textColor, fontSize: 16, height: 1.4),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _hasText ? () {
                          widget.onSubmitted(_controller.text.trim());
                          Navigator.pop(context);
                        } : null,
                        child: Container(
                          width: 40, height: 40,
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: _hasText ? widget.textColor : widget.textColor.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.arrow_forward, color: widget.bgColor, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}


class _FullScreenImageGallery extends StatefulWidget {
  final List<dynamic> imageItems;
  final int initialIndex;




  const _FullScreenImageGallery({required this.imageItems, required this.initialIndex});




  @override
  State<_FullScreenImageGallery> createState() => _FullScreenImageGalleryState();
}


class _FullScreenImageGalleryState extends State<_FullScreenImageGallery> {
  late PageController _pageController;
  late List<TransformationController> _transformationControllers;
  bool _isZoomed = false;
  TapDownDetails? _doubleTapDetails;
  late int _currentIndex;




  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _transformationControllers = List.generate(
        widget.imageItems.length,
            (_) => TransformationController()..addListener(_onTransformationChange)
    );
  }




  void _onTransformationChange() {
    final currentPage = _pageController.page?.round() ?? widget.initialIndex;
    if (currentPage >= 0 && currentPage < _transformationControllers.length) {
      final scale = _transformationControllers[currentPage].value.getMaxScaleOnAxis();
      final isCurrentlyZoomed = scale > 1.01;
      if (_isZoomed != isCurrentlyZoomed) {
        setState(() {
          _isZoomed = isCurrentlyZoomed;
        });
      }
    }
  }




  @override
  void dispose() {
    _pageController.dispose();
    for (var controller in _transformationControllers) {
      controller.dispose();
    }
    super.dispose();
  }




  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }




  void _handleDoubleTap(int index) {
    final controller = _transformationControllers[index];
    if (controller.value.getMaxScaleOnAxis() > 1.0) {
      controller.value = Matrix4.identity();
    } else {
      if (_doubleTapDetails != null) {
        final position = _doubleTapDetails!.localPosition;
        controller.value = Matrix4.identity()
          ..translate(-position.dx * 1.5, -position.dy * 1.5)
          ..scale(2.5);
      }
    }
  }




  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            physics: _isZoomed ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
            itemCount: widget.imageItems.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
              for (int i = 0; i < _transformationControllers.length; i++) {
                if (i != index) {
                  _transformationControllers[i].value = Matrix4.identity();
                }
              }
            },
            itemBuilder: (context, index) {
              final path = widget.imageItems[index]['data']?.toString() ?? '';
              return GestureDetector(
                onDoubleTapDown: _handleDoubleTapDown,
                onDoubleTap: () => _handleDoubleTap(index),
                child: InteractiveViewer(
                  transformationController: _transformationControllers[index],
                  minScale: 1.0,
                  maxScale: 5.0,
                  child: Center(
                    child: Image.file(
                      File(path),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              );
            },
          ),
          // ★ 左上に×（閉じる）ボタンを配置
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 26),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          // ★ 右上にダウンロード（共有）ボタンを配置（三角の共有マーク）
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.share, color: Colors.white, size: 26),
              onPressed: () async {
                final path = widget.imageItems[_currentIndex]['data']?.toString() ?? '';
                if (path.isNotEmpty) {
                  await Share.shareXFiles([XFile(path)], text: 'Memo Image');
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}


