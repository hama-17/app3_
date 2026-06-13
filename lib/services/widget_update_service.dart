import 'dart:convert';
import 'dart:io';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/lms_adapter.dart';
import 'cache_manager.dart';

class WidgetUpdateService {
  static Future<void> updateHomeWidgets({
    List<dynamic>? tasks,
    List<dynamic>? courses,
  }) async {
    if (!Platform.isAndroid) return;

    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    // 慶應アダプター基準の曜日インデックス (月=0, 火=1, 水=2, 木=3, 金=4, 土=5, 日=-1)
    final int todayIdx = ['月', '火', '水', '木', '金', '土'].indexOf(
        {1: '月', 2: '火', 3: '水', 4: '木', 5: '金', 6: '土', 7: '日'}[now.weekday] ?? ''
    );

    // 🟢 アプリ側でユーザーが手動選択している現在の「年度」と「学期」を完全にサルベージ
    int? savedYear = prefs.getInt('manual_year_v10');
    String? savedTerm = prefs.getString('manual_term_v10');

    // 万が一のフォールバック用計算
    int defaultYear = now.year;
    if (now.month < 4) defaultYear -= 1;

    int selectedYear = savedYear ?? defaultYear;
    String selectedTerm = savedTerm ?? (now.month >= 4 && now.month <= 8 ? "春学期" : "秋学期");

    final List<dynamic> finalTasks = tasks ?? await CacheManager.load('cached_assignments_v14_all_year') ?? [];
    final List<dynamic> finalCourses = courses ?? await CacheManager.load('my_course_cache_v10') ?? [];

    // ====================================================
    // ① 未提出課題（タスク）データのパッキング
    // ====================================================
    final List<Map<String, String>> tasksWidgetData = [];

    for (var t in finalTasks) {
      String rawDue = t['due_at'] ?? '';
      if (rawDue.isEmpty) continue;
      DateTime? dueTime = DateTime.tryParse(rawDue)?.toLocal();
      if (dueTime == null || dueTime.isBefore(now)) continue;

      bool isCompleted = false;
      if (t['course_id'] == 'custom_t' || t['is_app_custom_task'] == true) {
        isCompleted = t['is_completed'] == true;
      } else {
        final sub = t['submission'];
        isCompleted = sub != null && (
            sub['workflow_state'] == 'submitted' ||
                sub['workflow_state'] == 'graded' ||
                sub['workflow_state'] == 'graded_excused'
        );
      }
      if (isCompleted) continue;

      final String title = t['name'] ?? '無題の課題';
      final String dueStr = "${dueTime.month}/${dueTime.day} ${dueTime.hour}:${dueTime.minute.toString().padLeft(2, '0')}";
      final String contextName = currentLMS.cleanTitle(t['context_name'] ?? '');

      tasksWidgetData.add({
        'title': "[$contextName] $title",
        'sub': " $dueStr",
      });
    }

    // ====================================================
    // ② 今日の授業スケジュールデータのパッキング（該当学期厳密フィルタ版）
    // ====================================================
    final List<Map<String, String>> todayWidgetData = [];

    for (var c in finalCourses) {
      // 🟢 慶應アダプターの判定器をそのまま流用し、現在アプリで指定されている年度・学期（Q1/Q2/春など）以外を鉄壁ガードで弾く
      if (c['is_custom'] != true && !currentLMS.isTargetCourse(c, selectedYear, selectedTerm)) {
        continue;
      }

      String rawName = c['raw_name'] ?? c['name'] ?? '';
      bool isTodayCourse = false;
      int periodStr = -1;

      if (c['is_custom'] == true) {
        if (c['day'] == todayIdx) {
          isTodayCourse = true;
          periodStr = (c['period'] ?? 0) + 1;
        }
      } else {
        List<Map<String, int>> schedules = currentLMS.parseWeeklySchedule(rawName);
        for (var s in schedules) {
          if (s['day'] == todayIdx) {
            isTodayCourse = true;
            periodStr = s['period']! + 1;
            break;
          }
        }
      }

      if (isTodayCourse && todayIdx != -1) {
        String titleStr = currentLMS.cleanTitle(rawName);
        String roomStr = c['is_custom'] == true
            ? (c['room'] ?? '指定なし')
            : currentLMS.extractRoom(rawName);

        if (roomStr.isEmpty) roomStr = "オンデマンド/指定なし";

        todayWidgetData.add({
          'title': "$periodStr限: $titleStr",
          'sub': " $roomStr",
        });
      }
    }

    // フェイルセーフ
    if (tasksWidgetData.isEmpty) {
      tasksWidgetData.add({'title': "未提出課題はありません", 'sub': "All cleared"});
    }
    if (todayWidgetData.isEmpty) {
      todayWidgetData.add({'title': "本日の授業予定はありません", 'sub': "No classes today"});
    }

    // ネイティブへ射出
    try {
      await HomeWidget.saveWidgetData('tasks_json', jsonEncode(tasksWidgetData));
      await HomeWidget.saveWidgetData('today_json', jsonEncode(todayWidgetData));

      await HomeWidget.updateWidget(androidName: 'TasksWidgetProvider');
      await HomeWidget.updateWidget(androidName: 'TodayWidgetProvider');
    } catch (e) {
      print("ウィジェット連動同期エラー: $e");
    }
  }
}