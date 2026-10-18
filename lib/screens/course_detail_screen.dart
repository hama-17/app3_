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
import '../main.dart';

import '../utils/term_helper.dart';
import '../utils/dummy_data_helper.dart';
import 'custom_camera_screen.dart';
import 'dart:typed_data';
import '../services/cache_manager.dart';
import '../services/auth_service.dart';

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

  final GlobalKey<_CourseMemoWidgetState> _memoKey = GlobalKey<_CourseMemoWidgetState>();

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
    widget.onScheduleOverrideChanged?.call();
  }

  void _handleExternalImagesSaved(String courseId, List<String> paths) async {
    if (paths.isEmpty) return;

    if (_memoKey.currentState != null && _memoKey.currentState!.mounted) {
      _memoKey.currentState!.appendExternalImages(paths);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final String key = 'course_memos_v2_$courseId';
    final String? data = prefs.getString(key);

    List<Map<String, dynamic>> loadedMemos = [];
    if (data != null) {
      try {
        loadedMemos = List<Map<String, dynamic>>.from(jsonDecode(data));
      } catch (_) {}
    }

    final now = DateTime.now();
    final dateStr = '${now.month.toString().padLeft(2,'0')}/${now.day.toString().padLeft(2,'0')}';
    final timeStr = "${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}";

    int todayIdx = loadedMemos.indexWhere((m) => m['title']?.toString().startsWith(dateStr) ?? false);

    if (todayIdx == -1) {
      final currentCourse = widget.courses.firstWhere((c) => c['id'].toString() == courseId, orElse: () => {});
      final cleanName = CourseTitleParser.getCleanTitle(currentCourse['name'] ?? '');
      final newTitle = cleanName.isNotEmpty ? '$dateStr $cleanName' : dateStr;

      loadedMemos.add({
        'id': now.millisecondsSinceEpoch.toString(),
        'title': newTitle,
        'items': <dynamic>[],
      });
      todayIdx = loadedMemos.length - 1; // 修正済：欠落していた引き算を復元
    }

    List<dynamic> items = List<dynamic>.from(loadedMemos[todayIdx]['items'] ?? []);
    for (var path in paths) {
      final uniqueId = (now.millisecondsSinceEpoch + paths.indexOf(path)).toString();
      items.add({
        'id': uniqueId,
        'type': 'image',
        'data': path,
        'time': timeStr
      });
    }
    loadedMemos[todayIdx]['items'] = items;

    await prefs.setString(key, jsonEncode(loadedMemos));
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex >= 0 && widget.initialIndex < widget.courses.length ? widget.initialIndex : 0;
    _currentBottomIndex = widget.isAuthenticated ? widget.initialBottomIndex : 0;

    _topPageController = PageController(initialPage: _currentIndex);
    _bottomPageController = PageController(initialPage: _currentBottomIndex);

    _loadOverrides();
    _loadTermOverrides();
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

  Color _getColorForIndex(int index) {
    final c = widget.courses[index];
    String cId = c['is_custom'] == true ? (c['raw_name'] ?? c['name'] ?? '') : c['id'].toString();

    if (widget.customCourseColors.containsKey(cId)) {
      return Color(widget.customCourseColors[cId]!);
    }

    int total = math.max(1, widget.courses.length);
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    Color lightGrey = const Color(0xFFE0E0E0);
    Color darkGrey = const Color(0xFF1A1A1A);

    if (total <= 1) {
      return isDark ? darkGrey : lightGrey;
    }

    double ratio = index / (total - 1);

    if (!isDark) {
      return Color.lerp(lightGrey, darkGrey, ratio)!;
    } else {
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
            Wrap(
                spacing: 16, runSpacing: 16,
                children: [
                  _buildColorSwatch(const Color(0xFFaed9e0), textCol, cur),
                  _buildColorSwatch(const Color(0xFF671b24), textCol, cur),
                  _buildColorSwatch(const Color(0xFF055646), textCol, cur),
                  _buildColorSwatch(const Color(0xFF034376), textCol, cur),
                  _buildColorSwatch(const Color(0xFFd8370b), textCol, cur),
                  _buildColorSwatch(const Color(0xFFf5bc64), textCol, cur),
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
                        qStates[index] = !qStates[index];
                        List<String> selectedList = [];
                        for (int i = 0; i < 4; i++) {
                          if (qStates[i]) selectedList.add(qLabels[i]);
                        }
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
          GestureDetector(
            onTap: () {
              if (_isCollapsed) setState(() => _isCollapsed = false);
            },
            onVerticalDragUpdate: (details) {
              if (details.primaryDelta! > 5 && _isCollapsed) {
                setState(() => _isCollapsed = false);
              } else if (details.primaryDelta! < -5 && !_isCollapsed) {
                setState(() => _isCollapsed = true);
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

                          return Container(
                              decoration: BoxDecoration(color: pageColor, borderRadius: BorderRadius.circular(32)),
                              child: SafeArea(
                                  bottom: false,
                                  child: Stack(children: [
                                    AnimatedPositioned(
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeOutCubic,
                                        bottom: _isCollapsed ? 5 : (206 - padTop), // 修正済：欠落していた引き算を復元
                                        left: 16,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => Navigator.pop(context),
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            child: Icon(
                                              Icons.arrow_back_ios_new,
                                              color: AppTheme.getTextColorForBackground(pageColor),
                                              size: _isCollapsed ? 18 : 20,
                                            ),
                                          ),
                                        )
                                    ),

                                    AnimatedPositioned(
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeOutCubic,
                                        top: _isCollapsed ? 20 : 16,
                                        left: 52,
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

                                    AnimatedPositioned(
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeOutCubic,
                                        bottom: _isCollapsed ? 12 : 18,
                                        left: _isCollapsed ? 52 : 24,
                                        right: _isCollapsed ? 80 : 90,
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

                                    Positioned(
                                        bottom: 12,
                                        right: 16,
                                        child: AnimatedOpacity(
                                            duration: const Duration(milliseconds: 200),
                                            opacity: _isCollapsed ? 0.0 : 1.0,
                                            child: IgnorePointer(
                                              ignoring: _isCollapsed,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  GestureDetector(
                                                    behavior: HitTestBehavior.opaque,
                                                    onTap: i > 0 ? () {
                                                      _topPageController.previousPage(
                                                        duration: const Duration(milliseconds: 300),
                                                        curve: Curves.easeOutCubic,
                                                      );
                                                    } : null,
                                                    child: Padding(
                                                      padding: const EdgeInsets.all(8.0),
                                                      child: Icon(
                                                        Icons.arrow_back,
                                                        color: AppTheme.getTextColorForBackground(pageColor)
                                                            .withOpacity(i > 0 ? 1.0 : 0.0),
                                                        size: 20,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  GestureDetector(
                                                    behavior: HitTestBehavior.opaque,
                                                    onTap: i < widget.courses.length - 1 ? () { // 修正済：欠落していた引き算を復元
                                                      _topPageController.nextPage(
                                                        duration: const Duration(milliseconds: 300),
                                                        curve: Curves.easeOutCubic,
                                                      );
                                                    } : null,
                                                    child: Padding(
                                                      padding: const EdgeInsets.all(8.0),
                                                      child: Icon(
                                                        Icons.arrow_forward,
                                                        color: AppTheme.getTextColorForBackground(pageColor)
                                                            .withOpacity(i < widget.courses.length - 1 ? 1.0 : 0), // 修正済：欠落していた引き算を復元
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

          Builder(
              builder: (context) {
                int pageCount = 0;
                List<String> pageTitlesLong = [];
                List<String> pageTitlesShort = [];

                if (isCurrentCustom) {
                  pageCount = 2;
                  pageTitlesLong = ["MEMO", "TASKS"];
                  pageTitlesShort = ["MEMO", "TASKS"];
                } else {
                  pageCount = 5;
                  pageTitlesLong = ["MEMO", "MODULES", "TASKS", "GRADES", "ANNOUNCE"];
                  pageTitlesShort = ["MEMO", "MODS", "TASKS", "GRADE", "ANN"];
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
                          width: MediaQuery.of(context).size.width * (leftFlexSum / totalFlex), // 修正済：欠落していた掛け算を復元
                          child: Container(decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.horizontal(left: Radius.circular(20), right: Radius.circular(20)))),
                        ),
                      if (safeBottomIndex < pageCount - 1)
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          top: 4, bottom: 4,
                          left: MediaQuery.of(context).size.width * ((leftFlexSum + flexes[safeBottomIndex]) / totalFlex), // 修正済：欠落していた掛け算を復元
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

          Expanded(
              child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    if (!_isCollapsed) {
                      setState(() => _isCollapsed = true);
                    }
                  },
                  onVerticalDragUpdate: (details) {
                    if (details.primaryDelta! < -3 && !_isCollapsed) {
                      setState(() => _isCollapsed = true);
                    } else if (details.primaryDelta! > 3 && _isCollapsed) {
                      setState(() => _isCollapsed = false);
                    }
                  },
                  child: NotificationListener<ScrollNotification>(
                      onNotification: (scrollNotification) {
                        if (scrollNotification.metrics.axis == Axis.vertical) {
                          if (scrollNotification is ScrollUpdateNotification) {
                            if (scrollNotification.scrollDelta != null) {
                              if (scrollNotification.scrollDelta! > 2 && !_isCollapsed) {
                                setState(() => _isCollapsed = true);
                              }
                              else if (scrollNotification.metrics.pixels <= 0 && scrollNotification.scrollDelta! < -2 && _isCollapsed) {
                                setState(() => _isCollapsed = false);
                              }
                            }
                          } else if (scrollNotification is OverscrollNotification) {
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
                                    key: _memoKey,
                                    courseId: cur['id'].toString(),
                                    courseName: cur['title'] ?? cur['name'] ?? '',
                                    bgColor: Colors.transparent,
                                    textColor: textCol,
                                    onMemoStateChanged: (isOpen) { if (mounted) setState(() => _isMemoOpen = isOpen); }
                                ),
                                Container( )
                              ];
                            } else {
                              final Function(List<String>) imgSaverUnit = (paths) async {
                                if (paths.isEmpty) return;
                                final activeCourse = widget.courses[_currentIndex];
                                final activeCourseId = activeCourse['id'];
                                final prefs = await SharedPreferences.getInstance();
                                final String dbKey = 'course_memos_v2_$activeCourseId';
                                final String? dbData = prefs.getString(dbKey);
                                List<Map<String, dynamic>> loadedMemos = [];
                                if (dbData != null) { try { final List<dynamic> decoded = jsonDecode(dbData); loadedMemos = decoded.map((e) => Map<String, dynamic>.from(e)).toList(); } catch (_) {} }
                                final now = DateTime.now();
                                final dateStr = '${now.month.toString().padLeft(2,'0')}/${now.day.toString().padLeft(2,'0')}';
                                final timeStr = "${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}";
                                int todayIdx = loadedMemos.indexWhere((m) => m['title']?.toString().startsWith(dateStr) ?? false);
                                if (todayIdx == -1) { final cleanName = CourseTitleParser.getCleanTitle(activeCourse['name'] ?? ''); final newTitle = cleanName.isNotEmpty ? '$dateStr $cleanName' : dateStr; loadedMemos.add({'id': now.millisecondsSinceEpoch.toString(), 'title': newTitle, 'items': <dynamic>[],}); todayIdx = loadedMemos.length - 1; } // 修正済：欠落していた引き算を復元
                                List<dynamic> dbItems = List<dynamic>.from(loadedMemos[todayIdx]['items'] ?? []);
                                for (var path in paths) { final uniqueId = (now.millisecondsSinceEpoch + paths.indexOf(path)).toString(); if (path.startsWith("TEXT_MEMO:")) { final actualText = path.substring(10); dbItems.add({'id': uniqueId, 'type': 'text', 'data': actualText, 'time': timeStr}); } else { dbItems.add({'id': uniqueId, 'type': 'image', 'data': path, 'time': timeStr}); } }
                                loadedMemos[todayIdx]['items'] = dbItems;
                                await prefs.setString(dbKey, jsonEncode(loadedMemos));
                                if (_memoKey.currentState != null && _memoKey.currentState!.mounted) { _memoKey.currentState!.appendExternalImages(paths); }
                              };

                              pageCount = 5;
                              // 💡 ここで onLoginRequest パラメータを子ウィジェットに伝播させています
                              pages = [
                                _CourseMemoWidget(
                                    key: _memoKey,
                                    courseId: cur['id'].toString(),
                                    courseName: cur['title'] ?? cur['name'] ?? '',
                                    bgColor: Colors.transparent,
                                    textColor: textCol,
                                    onMemoStateChanged: (isOpen) { if (mounted) setState(() => _isMemoOpen = isOpen); }
                                ),
                                _CourseDataList(courseId: cur['id'], endpointType: 'MODULES', cookie: widget.cookie, bgColor: Colors.transparent, textColor: textCol, onImagesSaved: imgSaverUnit, onLoginRequest: widget.onLoginRequest),
                                _CourseDataList(courseId: cur['id'], endpointType: 'ASSIGNMENTS', cookie: widget.cookie, bgColor: Colors.transparent, textColor: textCol, targetItemId: widget.targetTaskId, onImagesSaved: imgSaverUnit, onLoginRequest: widget.onLoginRequest),
                                _CourseDataList(courseId: cur['id'], endpointType: 'GRADES', cookie: widget.cookie, bgColor: Colors.transparent, textColor: textCol, onImagesSaved: imgSaverUnit, onLoginRequest: widget.onLoginRequest),
                                _CourseDataList(courseId: cur['id'], endpointType: 'ANNOUNCE', cookie: widget.cookie, bgColor: Colors.transparent, textColor: textCol, targetItemId: widget.targetTaskId, onImagesSaved: imgSaverUnit, onLoginRequest: widget.onLoginRequest),
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

class _CourseDataList extends StatefulWidget {
  final int courseId; final String endpointType; final String cookie; final Color bgColor; final Color textColor; final String? targetItemId;
  final Function(List<String>)? onImagesSaved;
  final VoidCallback? onLoginRequest; // 💡 追加：親への401通知用コールバック

  const _CourseDataList({required this.courseId, required this.endpointType, required this.cookie, required this.bgColor, required this.textColor, this.targetItemId, this.onImagesSaved, this.onLoginRequest});
  @override
  State<_CourseDataList> createState() => _CourseDataListState();
}

class _CourseDataListState extends State<_CourseDataList> with AutomaticKeepAliveClientMixin {
  @override bool get wantKeepAlive => true;
  List<dynamic> _data = [];
  bool _isLoading = true;
  Set<String> _expandedItems = {};

  @override void initState() {
    super.initState();
    if (widget.targetItemId != null) _expandedItems.add(widget.targetItemId!);
    _fetch();
  }

  @override void didUpdateWidget(covariant _CourseDataList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.courseId != widget.courseId) {
      _expandedItems.clear();
      if (widget.targetItemId != null) _expandedItems.add(widget.targetItemId!);
      _fetch();
    }
  }

  Future<void> _fetch() async {
    try {
      List<dynamic>? preLoadedData;

      // 💡 修正：全体同期キャッシュに加えて、詳細画面独自の「個別キャッシュ」も優先して読み込む仕様に強化しました
      if (widget.endpointType == 'ASSIGNMENTS' || widget.endpointType == 'GRADES') {
        final List<dynamic>? allTasksCache = await CacheManager.load('cached_assignments_v14_all_year');
        final List<dynamic>? courseTasksCache = await CacheManager.load('course_assignments_${widget.courseId}');
        List<dynamic> combined = [];
        if (allTasksCache != null) combined.addAll(allTasksCache.where((t) => t['course_id'] == widget.courseId));
        if (courseTasksCache != null && courseTasksCache.isNotEmpty) combined = courseTasksCache;
        preLoadedData = combined;
      } else if (widget.endpointType == 'ANNOUNCE') {
        final List<dynamic>? allMsgsCache = await CacheManager.load('cached_messages_v14_all_year');
        final List<dynamic>? courseAnnounceCache = await CacheManager.load('course_announce_${widget.courseId}');
        List<dynamic> combined = [];
        if (allMsgsCache != null) combined.addAll(allMsgsCache.where((m) => m['course_id'] == widget.courseId));
        if (courseAnnounceCache != null && courseAnnounceCache.isNotEmpty) combined = courseAnnounceCache;
        preLoadedData = combined;
      } else if (widget.endpointType == 'MODULES') {
        preLoadedData = await CacheManager.load('course_modules_${widget.courseId}');
      }

      if (preLoadedData != null && preLoadedData.isNotEmpty) {
        if (mounted) {
          setState(() {
            _data = preLoadedData!;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("詳細画面キャッシュ先行抽出エラー(安全にスルー): $e");
    }

    if (_data.isEmpty) {
      setState(() => _isLoading = true);
    }

    if (widget.cookie.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    if (widget.cookie == "dummy_test_session") {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        setState(() {
          _data = DummyDataHelper.getDetails(widget.endpointType, widget.courseId);
          _isLoading = false;
        });
      }
      return;
    }

    String url = "";
    if (widget.endpointType == 'MODULES') url = '${currentLMS.baseUrl}/api/v1/courses/${widget.courseId}/modules?per_page=50&include[]=items';
    else if (widget.endpointType == 'ASSIGNMENTS' || widget.endpointType == 'GRADES') url = '${currentLMS.baseUrl}/api/v1/courses/${widget.courseId}/assignments?per_page=50&order_by=due_at&include[]=submission';
    else url = '${currentLMS.baseUrl}/api/v1/courses/${widget.courseId}/discussion_topics?only_announcements=true&per_page=20';

    try {
      final headers = AuthService.buildHeaders(widget.cookie);
      final res = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 && mounted) {
        final List<dynamic> freshData = jsonDecode(res.body);

        setState(() {
          _data = freshData;
          _isLoading = false;
        });

        // 💡 修正：モジュールだけでなく、全ての個別取得データをキャッシュ領域へサイレント永続化保存
        if (widget.endpointType == 'MODULES') {
          await CacheManager.save('course_modules_${widget.courseId}', freshData);
        } else if (widget.endpointType == 'ASSIGNMENTS' || widget.endpointType == 'GRADES') {
          await CacheManager.save('course_assignments_${widget.courseId}', freshData);
        } else if (widget.endpointType == 'ANNOUNCE') {
          await CacheManager.save('course_announce_${widget.courseId}', freshData);
        }
      }
      // 🚨 修正：401 (セッション切れ) を検知した瞬間に親ウィジェットへ通報し、ログインボタンを赤くする
      else if (res.statusCode == 401 && mounted) {
        debugPrint("API 401 Unauthorized: Session Expired.");
        widget.onLoginRequest?.call();
      }
    } catch (e) {
      debugPrint("詳細オンラインフェッチタイムアウトまたはエラー: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("NO DATA / OFFLINE", style: TextStyle(color: widget.textColor.withOpacity(0.5), fontWeight: FontWeight.w300)),
                  if (widget.cookie.isEmpty) ...[
                    const SizedBox(height: 12),
                    Text("過去の同期ログがありません。ログインすると取得されます。", style: TextStyle(color: widget.textColor.withOpacity(0.3), fontSize: 11, fontWeight: FontWeight.w300)),
                  ]
                ],
              ),
            )
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

                  if (widget.endpointType == 'MODULES') {
                    children = (item['items'] as List? ?? []).map((si) {
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
                                      onPressed: () => openSmartUrl(
                                        context,
                                        targetUrl,
                                        widget.cookie,
                                        title: title,
                                        onImagesSaved: widget.onImagesSaved,
                                      ),
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

                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 250),
                        crossFadeState: isExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                        firstChild: Padding(
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
    super.key,
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
      _saveMemosForId(oldWidget.courseId, _memos);

      setState(() {
        _activeMemoId = null;
        _memos = [];
      });
      _loadMemos();
    }
  }

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

    int todayIdx = loadedMemos.indexWhere((m) => m['title']?.toString().startsWith(dateStr) ?? false);

    if (todayIdx == -1) {
      final filteredName = _getFilteredCourseName(widget.courseName);
      final newTitle = filteredName.isNotEmpty ? '$dateStr $filteredName' : dateStr;

      final Map<String, dynamic> newMemo = {
        'id': now.millisecondsSinceEpoch.toString(),
        'title': newTitle,
        'items': <dynamic>[],
      };
      loadedMemos.add(newMemo);
      todayIdx = loadedMemos.length - 1; // 修正済：欠落していた引き算を復元
    }

    if (mounted) {
      setState(() {
        _memos = loadedMemos;
        _activeMemoId = _memos[todayIdx]['id']?.toString();
      });
      widget.onMemoStateChanged?.call(true);
    }
  }

  Future<void> _saveMemosForId(dynamic cId, List<Map<String, dynamic>> memoList) async {
    final prefs = await SharedPreferences.getInstance();
    final realMemos = memoList.where((m) => (m['items'] as List? ?? []).isNotEmpty).toList();
    await prefs.setString('course_memos_v2_$cId', jsonEncode(realMemos));
  }

  Future<void> _saveMemos() async {
    await _saveMemosForId(widget.courseId, _memos);
  }

  void _closeMemo() {
    FocusScope.of(context).unfocus();
    setState(() {
      _activeMemoId = null;
    });
    widget.onMemoStateChanged?.call(false);
    _saveMemos();
  }

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

  String _getFilteredCourseName(String name) {
    if (name.isEmpty) return '';
    return CourseTitleParser.getCleanTitle(name);
  }

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

  Future<void> _takePhoto() async {
    try {
      globalDisableAutoCacheClear = true;
      final String? savedPath = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const CustomCameraScreen()),
      );

      if (savedPath != null && savedPath.isNotEmpty) {
        _addItemToMemo('image', savedPath);
      }
    } catch (e) {
      debugPrint("Take Photo via Custom Camera Error: $e");
    } finally {
      globalDisableAutoCacheClear = false;
    }
  }

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

  void appendExternalImages(List<String> paths) {
    if (paths.isEmpty) return;

    final now = DateTime.now();
    final dateStr = '${now.month.toString().padLeft(2,'0')}/${now.day.toString().padLeft(2,'0')}';
    final timeStr = "${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}";

    int todayIdx = _memos.indexWhere((m) => m['title']?.toString().startsWith(dateStr) ?? false);

    if (todayIdx == -1) {
      final filteredName = _getFilteredCourseName(widget.courseName);
      final newTitle = filteredName.isNotEmpty ? '$dateStr $filteredName' : dateStr;

      _memos.add({
        'id': now.millisecondsSinceEpoch.toString(),
        'title': newTitle,
        'items': <dynamic>[],
      });
      todayIdx = _memos.length - 1; // 修正済：欠落していた引き算を復元
    }

    setState(() {
      List<dynamic> items = List<dynamic>.from(_memos[todayIdx]['items'] ?? []);
      for (var path in paths) {
        final uniqueId = (now.millisecondsSinceEpoch + paths.indexOf(path)).toString();

        if (path.startsWith("TEXT_MEMO:")) {
          final actualText = path.substring(10);
          items.add({'id': uniqueId, 'type': 'text', 'data': actualText, 'time': timeStr});
        } else {
          items.add({'id': uniqueId, 'type': 'image', 'data': path, 'time': timeStr});
        }
      }
      _memos[todayIdx]['items'] = items;
    });

    _saveMemos();
  }

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
                extendBodyBehindAppBar: true,

                appBar: AppBar(
                  backgroundColor: Colors.transparent,
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

  Map<String, String> _generateDateTimeStrings(List<dynamic> items) {
    final now = DateTime.now();
    final months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

    final monthDate = "${months[now.month - 1]} ${now.day}"; // 修正済：欠落していた引き算を復元
    final year = "${now.year}";
    final weekday = weekdays[now.weekday - 1]; // 修正済：欠落していた引き算を復元

    String timeRange = "";
    if (items.isNotEmpty) {
      final first = items.first['time'] ?? '';
      final last = items.last['time'] ?? '';
      timeRange = first == last ? first : "$first - $last"; // 修正済：欠落していたハイフンを復元
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

  String _sanitizeTextForPdf(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]'), '')
        .replaceAll(RegExp(r'[\u{1F600}-\u{1F64F}]', unicode: true), '□')
        .replaceAll(RegExp(r'[\u{1F300}-\u{1F5FF}]', unicode: true), '□')
        .replaceAll(RegExp(r'[\u{1F680}-\u{1F6FF}]', unicode: true), '□')
        .replaceAll(RegExp(r'[\u{2600}-\u{26FF}]', unicode: true), '□')
        .replaceAll(RegExp(r'[\u{2700}-\u{27BF}]', unicode: true), '□');
  }

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
    final pdfResult = await _generatePdf(memoIndex);

    if (sheetContext != null && mounted) {
      Navigator.pop(sheetContext!);
    }

    if (pdfResult != null && !pdfResult.startsWith("ERROR:")) {
      final box = context.findRenderObject() as RenderBox?;
      final rect = box != null ? box.localToGlobal(Offset.zero) & box.size : null;

      await Share.shareXFiles(
        [XFile(pdfResult, mimeType: 'application/pdf')],
        sharePositionOrigin: rect,
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDFエラー: ${pdfResult?.replaceFirst("ERROR:", "") ?? "不明なエラー"}'))
      );
    }
  }

  Future<String?> _generatePdf(int memoIndex) async {
    try {
      final bool isAllCombined = memoIndex == -1;
      final pdf = pw.Document();

      List<dynamic> items = [];
      String fileSaveTitle = "";
      String documentDisplayTitle = "";
      String periodStr = "";

      if (isAllCombined) {
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

        if (items.isNotEmpty) {
          String firstDate = items.first['date_group'] ?? '';
          String lastDate = items.last['date_group'] ?? '';

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
            periodStr = "${formatDocDate(firstDate)} - ${formatDocDate(lastDate)}"; // 修正済：欠落していたハイフンを復元
          }
        }
      } else {
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
            pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(flex: 1, child: pw.SizedBox()),
                  pw.Expanded(
                      flex: 2,
                      child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: isAllCombined
                              ? [
                            pw.Text(safeDisplayTitle, style: pw.TextStyle(font: jpFont, fontSize: 40, lineSpacing: 1.2, color: PdfColors.black)),
                            pw.Text("${dateTimeInfo['year']!}", style: pw.TextStyle(font: jpFont, fontSize: 40, lineSpacing: 1.2, color: PdfColors.black)),
                            if (periodStr.isNotEmpty)
                              pw.Text(periodStr, style: pw.TextStyle(font: jpFont, fontSize: 40, lineSpacing: 1.2, color: PdfColors.black)),
                          ]
                              : [
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

            ...List.generate(items.length, (index) {
              final item = items[index];
              final bool isText = item['type'] == 'text';
              final safeData = _sanitizeTextForPdf(item['data']?.toString() ?? '');

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
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
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
                              child: imageBytesMap.containsKey(item['data'].toString())
                                  ? pw.Image(
                                pw.MemoryImage(imageBytesMap[item['data'].toString()]!),
                                fit: pw.BoxFit.contain,
                              )
                                  : pw.SizedBox(),
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
                            const SizedBox(width: 48, height: 48),
                          ]
                      )
                  ),
                ),
                Divider(color: widget.textColor.withOpacity(0.5), thickness: 0.5, height: 1),
              ],
            );
          }

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

  @override
  Widget _buildDetailView() {
    final bool isAllCombined = _activeMemoId == 'ALL_COMBINED';

    int memoIndex = -1;
    Map<String, dynamic> memo = {};
    List<dynamic> items = [];
    String displayTitle = "";
    String periodStr = "";

    List<String> allCombinedImages = [];

    if (isAllCombined) {
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

    final Widget memoContainer = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: memoBg,
        borderRadius: isAllCombined ? BorderRadius.circular(16) : null,
      ),
      child: ListView.builder(
          padding: const EdgeInsets.only(top: 16, left: 24, right: 24, bottom: 180),
          physics: const BouncingScrollPhysics(),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];

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
                  if (showDateHeader) ...[
                    if (index > 0) const SizedBox(height: 36),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14.0),
                      child: Text(
                        item['date_group'] ?? '',
                        style: TextStyle(
                          color: contentTextCol.withOpacity(0.85),
                          fontSize: 20,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                  Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                                    child: Image.file(
                                      File(item['data']),
                                      width: 180,
                                      height: 120,
                                      fit: BoxFit.cover,
                                      cacheWidth: 360,
                                      gaplessPlayback: true,
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

                  IconButton(
                      icon: Icon(Icons.share, color: widget.textColor, size: 20),
                      onPressed: () => _shareMemo(isAllCombined ? -1 : memoIndex)
                  ),
                ],
              ),
            ),

            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: 8.0, right: 8.0, bottom: 0 + bottomPadding),
                child: isAllCombined
                    ? memoContainer
                    : ClipPath(clipper: _MemoAreaClipper(), child: memoContainer),
              ),
            ),
          ],
        ),

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

class _MemoAreaClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    double r = 16.0;
    double cut = 175.0;
    double w = size.width;
    double h = size.height;

    path.moveTo(0, r);
    path.arcToPoint(Offset(r, 0), radius: Radius.circular(r));

    path.lineTo(w - r, 0);
    path.arcToPoint(Offset(w, r), radius: Radius.circular(r));

    path.lineTo(w, h - cut - r);
    path.quadraticBezierTo(w, h - cut, w - r, h - cut + r);

    path.lineTo(w - cut + r, h - r);

    path.quadraticBezierTo(w - cut, h, w - cut - r, h);

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

    double maxCardHeight = MediaQuery.of(context).size.height - topPadding - 80.0 - keyboardHeight; // 修正済：欠落していた引き算を復元

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
          ..translate(-position.dx * 1.5, -position.dy * 1.5) // 修正済：欠落していた掛け算を復元
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
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 26),
              onPressed: () => Navigator.pop(context),
            ),
          ),
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