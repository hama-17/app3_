import 'dart:convert';
import 'dart:io';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../utils/lms_adapter.dart';
import 'cache_manager.dart';
import 'calendar_sync_service.dart';
import 'package:app3_kportal_2/core/app_theme.dart';
import 'dart:math' as math;

class WidgetUpdateService {
  static Future<void> updateHomeWidgets({
    List<dynamic>? tasks,
    List<dynamic>? courses,
  }) async {
    if (!Platform.isAndroid) return;

    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    int? savedYear = prefs.getInt('manual_year_v10');
    String? savedTerm = prefs.getString('manual_term_v10');

    int defaultYear = now.year;
    if (now.month < 4) defaultYear -= 1;

    int selectedYear = savedYear ?? defaultYear;
    String selectedTerm = savedTerm ?? (now.month >= 4 && now.month <= 8 ? "春学期" : "秋学期");

    final List<dynamic> finalTasks = tasks ?? await CacheManager.load('cached_assignments_v14_all_year') ?? [];
    final List<dynamic> finalCourses = courses ?? await CacheManager.load('my_course_cache_v10') ?? [];

    // ─── 🟢 修正の決定打：スコープエラーを破壊するため、テーマ変数を最上部に引き揚げ ───
    final String gradientMode = appGradientThemeNotifier.value;
    final List<Color> currentPalette = AppGradient.getColors(gradientMode);
    bool isDark = gradientMode != 'white';

    final termOverridesStr = prefs.getString('course_term_overrides_v10') ?? '{}';
    final Map<String, dynamic> termOverrides = jsonDecode(termOverridesStr);

    // 🎯 詳細画面と100%シンクロするカラー計算内部ブレイン（上部に移動したため安全に参照可能）
    String getCourseColorHex(int index, dynamic c) {
      String cId = c['is_custom'] == true ? (c['raw_name'] ?? c['name'] ?? '') : c['id'].toString();

      final String customColorKey = 'custom_color_$cId';
      if (prefs.containsKey(customColorKey)) {
        int? colorVal = prefs.getInt(customColorKey);
        if (colorVal != null) {
          return '#${(colorVal & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
        }
      }

      int total = math.max(1, finalCourses.length);
      if (total <= 1) return isDark ? '#1A1A1A' : '#E0E0E0';

      double ratio = index / (total - 1);
      if (!isDark) {
        int r = (0xE0 + (0x1A - 0xE0) * ratio).round();
        return '#${r.toRadixString(16).padLeft(2, '0') * 3}';
      } else {
        int r = (0x1A + (0xE0 - 0x1A) * ratio).round();
        return '#${r.toRadixString(16).padLeft(2, '0') * 3}';
      }
    }

    // 🎯 Q2限定フィルター
    bool isTargetQuarter(dynamic c) {
      String cId = c['is_custom'] == true ? (c['raw_name'] ?? c['name'] ?? '') : c['id'].toString();

      if (termOverrides.containsKey(cId)) {
        String overrideStr = termOverrides[cId]?.toString() ?? '';
        if (overrideStr == "未選択") return false;
        return overrideStr.contains("Q2");
      }

      String name = (c['name'] ?? '').toString();
      String semester = (c['semester'] ?? c['term'] ?? '').toString();
      if (name.contains("Q2") || semester.contains("Q2")) return true;
      if (name.contains("Q1") || semester.contains("Q1")) return false;

      if (semester.contains("春学期") || semester.contains("春季") || semester.contains("前期")) return true;
      return false;
    }

    // ====================================================
    // ① 未提出課題（タスク）データのパッキング
    // ====================================================
    final List<Map<String, String>> tasksWidgetData = [];
    for (var t in finalTasks) {
      String rawDue = t['due_at'] ?? ''; if (rawDue.isEmpty) continue;
      DateTime? dueTime = DateTime.tryParse(rawDue)?.toLocal(); if (dueTime == null || dueTime.isBefore(now)) continue;
      bool isCompleted = false;
      if (t['course_id'] == 'custom_t' || t['is_app_custom_task'] == true) { isCompleted = t['is_completed'] == true; } else {
        final sub = t['submission']; isCompleted = sub != null && (sub['workflow_state'] == 'submitted' || sub['workflow_state'] == 'graded' || sub['workflow_state'] == 'graded_excused');
      }
      if (isCompleted) continue;
      tasksWidgetData.add({
        'title': t['name'] ?? '無題の課題', 'subject': currentLMS.cleanTitle(t['context_name'] ?? ''),
        'sub': "${dueTime.month}/${dueTime.day}", 'due_time': "${dueTime.hour.toString().padLeft(2, '0')}:${dueTime.minute.toString().padLeft(2, '0')}", 'id': (t['id'] ?? '').toString(),
      });
    }

    // ====================================================
    // ② 予定ウィジェット（Today）データのパッキング
    // ====================================================
    final List<Map<String, String>> todayWidgetData = [];
    final Map<int, List<String>> timeMap = {
      1: ["09:00", "10:30"], 2: ["10:45", "12:15"], 3: ["13:00", "14:30"],
      4: ["14:45", "16:15"], 5: ["16:30", "18:00"], 6: ["18:15", "19:45"],
    };

    for (int i = 0; i < 7; i++) {
      final targetDate = now.add(Duration(days: i));
      final int targetDayIdx = ['月', '火', '水', '木', '金', '土'].indexOf({1: '月', 2: '火', 3: '水', 4: '木', 5: '金', 6: '土', 7: '日'}[targetDate.weekday] ?? '');
      final List<Map<String, dynamic>> dayEvents = [];

      for (int index = 0; index < finalCourses.length; index++) {
        final c = finalCourses[index];
        if (c['is_custom'] != true && !currentLMS.isTargetCourse(c, selectedYear, selectedTerm)) continue;
        if (!isTargetQuarter(c)) continue;

        String rawName = c['raw_name'] ?? c['name'] ?? '';
        bool isTargetDayCourse = false; int periodStr = -1;
        if (c['is_custom'] == true) {
          if (c['day'] == targetDayIdx) { isTargetDayCourse = true; periodStr = (c['period'] ?? 0) + 1; }
        } else {
          List<Map<String, int>> schedules = currentLMS.parseWeeklySchedule(rawName);
          for (var s in schedules) { if (s['day'] == targetDayIdx) { isTargetDayCourse = true; periodStr = s['period']! + 1; break; } }
        }
        if (isTargetDayCourse && targetDayIdx != -1) {
          String startTimeStr = "00:00"; String endTimeStr = "00:00";
          if (timeMap.containsKey(periodStr)) { startTimeStr = timeMap[periodStr]![0]; endTimeStr = timeMap[periodStr]![1]; }
          final parts = startTimeStr.split(':');
          final eventTime = DateTime(targetDate.year, targetDate.month, targetDate.day, int.parse(parts[0]), int.parse(parts[1]));
          dayEvents.add({
            'time': eventTime, 'title': currentLMS.cleanTitle(rawName), 'sub': startTimeStr, 'end_time': endTimeStr, 'room': (c['is_custom'] == true ? (c['room'] ?? '') : currentLMS.extractRoom(rawName)).trim(), 'id': (c['id'] ?? '').toString(), 'page_route': 'course_detail', 'is_task': 'false',
          });
        }
      }

      for (var t in finalTasks) {
        String rawDue = t['due_at'] ?? ''; if (rawDue.isEmpty) continue;
        DateTime? dueTime = DateTime.tryParse(rawDue)?.toLocal(); if (dueTime == null) continue;
        if (dueTime.year == targetDate.year && dueTime.month == targetDate.month && dueTime.day == targetDate.day) {
          bool isCompleted = false;
          if (t['course_id'] == 'custom_t' || t['is_app_custom_task'] == true) { isCompleted = t['is_completed'] == true; } else {
            final sub = t['submission']; isCompleted = sub != null && (sub['workflow_state'] == 'submitted' || sub['workflow_state'] == 'graded' || sub['workflow_state'] == 'graded_excused');
          }
          if (isCompleted) continue;
          dayEvents.add({
            'time': dueTime, 'title': t['name'] ?? '無題の課題', 'sub': "${dueTime.hour.toString().padLeft(2, '0')}:${dueTime.minute.toString().padLeft(2, '0')}", 'end_time': '', 'room': currentLMS.cleanTitle(t['context_name'] ?? ''), 'id': (t['id'] ?? '').toString(), 'page_route': 'task_detail', 'is_task': 'true',
          });
        }
      }

      try {
        final extEvents = await CalendarSyncService.getDeviceEventsForDate(targetDate);
        for (var e in extEvents) {
          DateTime st = (e['time'] as DateTime).toLocal(); DateTime et = e['endTime'] != null ? (e['endTime'] as DateTime).toLocal() : st.add(const Duration(hours: 1));
          dayEvents.add({
            'time': st, 'title': "${e['title'] ?? '外部予定'}", 'sub': e['isAllDay'] == true ? "ALL" : "${st.hour.toString().padLeft(2, '0')}:${st.minute.toString().padLeft(2, '0')}", 'end_time': e['isAllDay'] == true ? "DAY" : "${et.hour.toString().padLeft(2, '0')}:${et.minute.toString().padLeft(2, '0')}", 'room': e['isAllDay'] == true ? "終日予定" : (e['subtitle'] ?? ''), 'id': '', 'page_route': 'main', 'is_task': 'false',
          });
        }
      } catch (_) {}

      dayEvents.sort((a, b) => (a['time'] as DateTime).compareTo(b['time'] as DateTime));
      final daysEn = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
      String dateLabel = "${targetDate.month}/${targetDate.day} ${daysEn[targetDate.weekday - 1]}";

      bool isFirstOfDays = true;
      for (var ev in dayEvents) {
        todayWidgetData.add({
          'title': ev['title'] as String, 'sub': ev['sub'] as String, 'end_time': ev['end_time'] as String, 'room': ev['room'] as String, 'id': ev['id'] as String, 'date_label': dateLabel, 'is_first_of_day': isFirstOfDays ? "true" : "false", 'page_route': ev['page_route'] as String, 'is_task': ev['is_task'] as String,
        });
        isFirstOfDays = false;
      }
    }

    if (todayWidgetData.isEmpty) {
      final daysEn = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
      todayWidgetData.add({ 'title': "向こう7日間の予定はありません(Q2)", 'sub': "--:--", 'end_time': "--:--", 'room': "All cleared", 'date_label': "${now.month}/${now.day} ${daysEn[now.weekday - 1]}", 'is_first_of_day': "true", 'page_route': 'main', 'is_task': 'false' });
    }
    if (tasksWidgetData.isEmpty) { tasksWidgetData.add({'title': "未提出課題はありません", 'sub': "All cleared"}); }

    String colorToHex(Color c) => '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final String taskBgHex = (gradientMode == 'white') ? '#EEEEEE' : '#222222';

    final List<Map<String, dynamic>> timetableMatrixData = [];

    for (int index = 0; index < finalCourses.length; index++) {
      final c = finalCourses[index];
      if (c['is_custom'] != true && !currentLMS.isTargetCourse(c, selectedYear, selectedTerm)) continue;
      if (!isTargetQuarter(c)) continue;

      String rawName = c['raw_name'] ?? c['name'] ?? '';
      String titleStr = currentLMS.cleanTitle(rawName);
      String roomStr = (c['is_custom'] == true ? (c['room'] ?? '') : currentLMS.extractRoom(rawName)).trim();

      // 🎯 授業名の自動2行分割パース
      if (titleStr.length > 4) titleStr = "${titleStr.substring(0, 4)}\n${titleStr.substring(4)}";

      final String courseColorHex = getCourseColorHex(index, c);

      if (c['is_custom'] == true) {
        int d = int.tryParse(c['day']?.toString() ?? '') ?? -1;
        int p = (int.tryParse(c['period']?.toString() ?? '') ?? 0) + 1;
        if (d >= 0 && d <= 5 && p >= 1 && p <= 6) {
          // 🟢 変更：@マークを排除し、title と room を個別のキーとして独立射出
          timetableMatrixData.add({'day': d, 'period': p, 'title': titleStr, 'room': roomStr, 'id': c['id'].toString(), 'color': courseColorHex});
        }
      } else {
        List<Map<String, int>> schedules = currentLMS.parseWeeklySchedule(rawName);
        for (var s in schedules) {
          int d = int.tryParse(s['day']?.toString() ?? '') ?? -1;
          int p = (int.tryParse(s['period']?.toString() ?? '') ?? 0) + 1;
          if (d >= 0 && d <= 5 && p >= 1 && p <= 6) {
            timetableMatrixData.add({'day': d, 'period': p, 'title': titleStr, 'room': roomStr, 'id': c['id'].toString(), 'color': courseColorHex});
          }
        }
      }
    }

    try {
      await HomeWidget.saveWidgetData('widget_task_bg', taskBgHex);
      await HomeWidget.saveWidgetData('widget_c1', colorToHex(currentPalette[0]));
      await HomeWidget.saveWidgetData('widget_c2', colorToHex(currentPalette[1]));
      await HomeWidget.saveWidgetData('widget_c3', colorToHex(currentPalette[2]));
      await HomeWidget.saveWidgetData('tasks_json', jsonEncode(tasksWidgetData));
      await HomeWidget.saveWidgetData('today_json', jsonEncode(todayWidgetData));
      await HomeWidget.saveWidgetData('timetable_matrix_json', jsonEncode(timetableMatrixData));

      await HomeWidget.updateWidget(androidName: 'TimetableWidgetProvider');
      await HomeWidget.updateWidget(androidName: 'TasksWidgetProvider');
      await HomeWidget.updateWidget(androidName: 'TodayWidgetProvider');
    } catch (e) {
      print("ウィジェット連動同期エラー: $e");
    }
  }
}