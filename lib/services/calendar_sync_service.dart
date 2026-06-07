import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_calendar/device_calendar.dart' as dc;
import '../utils/lms_adapter.dart'; // currentLMS を使うために必要
//calendar_sync_service.dart

// ----------------------------------------------------
// ★ カレンダー同期サービス v7 (絶対確実・クリーンアップ完備版)
// ----------------------------------------------------
class CalendarSyncService {
  static final dc.DeviceCalendarPlugin _deviceCalendarPlugin = dc.DeviceCalendarPlugin();

  static Future<bool> requestPermissions() async {
    var permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
    if (permissionsGranted.isSuccess && !permissionsGranted.data!) {
      permissionsGranted = await _deviceCalendarPlugin.requestPermissions();
      if (!permissionsGranted.isSuccess || !permissionsGranted.data!) return false;
    }
    return true;
  }

  static Future<List<dc.Calendar>> getWritableCalendars() async {
    if (!await requestPermissions()) return <dc.Calendar>[];
    final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
    return (calendarsResult.data ?? []).cast<dc.Calendar>().where((c) => c.isReadOnly == false).toList();
  }

  // ★ 単一タスクの即時削除（完了ダイアログ等から呼ばれる）
  static Future<void> deleteTaskFromCalendar(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? targetCalendarId = prefs.getString('calendar_sync_target_id');
    if (targetCalendarId == null || targetCalendarId.isEmpty) return;

    Map<String, String> eventMapping = Map<String, String>.from(jsonDecode(prefs.getString('cal_map_tasks') ?? '{}'));

    if (eventMapping.containsKey(taskId)) {
      await _deviceCalendarPlugin.deleteEvent(targetCalendarId, eventMapping[taskId]);
      eventMapping.remove(taskId);
      await prefs.setString('cal_map_tasks', jsonEncode(eventMapping));
    }
  }

  // ==========================================
  // 1. TASKS -> カレンダー 同期
  // ==========================================
  static Future<void> syncTasks(List<dynamic> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('sync_tasks_enabled') ?? false)) return;
    final targetCalId = prefs.getString('calendar_sync_target_id');
    if (targetCalId == null || targetCalId.isEmpty || !await requestPermissions()) return;

    Map<String, String> eventMapping = Map<String, String>.from(jsonDecode(prefs.getString('cal_map_tasks') ?? '{}'));
    List<String> dismissedIds = prefs.getStringList('dismissed_tasks_v10') ?? [];
    List<String> activeTaskIds = [];

    for (var task in tasks) {
      String taskId = task['id'].toString();
      String rawDue = task['due_at'] ?? '';
      if (rawDue.isEmpty) continue;

      DateTime? dueAt = DateTime.tryParse(rawDue)?.toLocal();
      if (dueAt == null) continue;

      bool isCompleted = false;
      if (task['course_id'] == 'custom_t' || task['is_app_custom_task'] == true) {
        isCompleted = task['is_completed'] == true;
      } else {
        final sub = task['submission'];
        isCompleted = sub != null && (sub['workflow_state'] == 'submitted' || sub['workflow_state'] == 'graded' || sub['workflow_state'] == 'graded_excused');
      }

      // ★ 要件クリア：完了したタスク・非表示タスク・過去のタスクはOSカレンダーから削除
      if (isCompleted || dismissedIds.contains(taskId) || dueAt.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
        if (eventMapping.containsKey(taskId)) {
          await _deviceCalendarPlugin.deleteEvent(targetCalId, eventMapping[taskId]);
          eventMapping.remove(taskId);
        }
        continue; // 登録処理はスキップ
      }

      activeTaskIds.add(taskId);
      dc.Event event = dc.Event(targetCalId);

      // 既存IDがあれば上書き（Upsert）
      if (eventMapping.containsKey(taskId)) {
        event.eventId = eventMapping[taskId];
      }

      event.title = "[課題] ${task['name'] ?? 'Untitled'}";
      event.description = "${currentLMS.cleanTitle(task['context_name'] ?? '')}\n${task['html_url'] ?? task['url'] ?? ''}";

      event.start = dc.TZDateTime.from(dueAt.subtract(const Duration(hours: 1)), dc.local);
      event.end = dc.TZDateTime.from(dueAt, dc.local);

      final result = await _deviceCalendarPlugin.createOrUpdateEvent(event);
      if (result?.isSuccess == true && result?.data != null) {
        eventMapping[taskId] = result!.data!;
      }
    }

    // カレンダーに残っているが、アプリ側から消えたタスクを掃除
    List<String> toRemove = [];
    for (var key in eventMapping.keys) {
      if (!activeTaskIds.contains(key)) {
        await _deviceCalendarPlugin.deleteEvent(targetCalId, eventMapping[key]);
        toRemove.add(key);
      }
    }
    toRemove.forEach((k) => eventMapping.remove(k));
    await prefs.setString('cal_map_tasks', jsonEncode(eventMapping));
  }

  // ★ 要件クリア：タスク同期オフ時に完全一掃する
  static Future<void> disableTaskSync() async {
    final prefs = await SharedPreferences.getInstance();
    final targetCalId = prefs.getString('calendar_sync_target_id');
    if (targetCalId == null || targetCalId.isEmpty) return;

    // 1. マップに記録されたIDベースで削除
    Map<String, String> eventMapping = Map<String, String>.from(jsonDecode(prefs.getString('cal_map_tasks') ?? '{}'));
    for (var eventId in eventMapping.values) {
      await _deviceCalendarPlugin.deleteEvent(targetCalId, eventId);
    }
    await prefs.remove('cal_map_tasks');
    await prefs.setBool('sync_tasks_enabled', false);

    // 2. フェイルセーフ（記録漏れの [課題] を検索して強制一掃）
    final startDate = dc.TZDateTime.local(DateTime.now().year - 1, 1, 1);
    final endDate = dc.TZDateTime.local(DateTime.now().year + 2, 1, 1);
    final eventsResult = await _deviceCalendarPlugin.retrieveEvents(targetCalId, dc.RetrieveEventsParams(startDate: startDate, endDate: endDate));
    if (eventsResult.isSuccess && eventsResult.data != null) {
      for (var e in eventsResult.data!) {
        if (e.title != null && e.title!.startsWith('[課題]')) {
          await _deviceCalendarPlugin.deleteEvent(targetCalId, e.eventId);
        }
      }
    }
  }

  // ==========================================
  // 2. SCHEDULES -> カレンダー 同期
  // ==========================================
  static Future<void> syncSchedules(List<dynamic> courses, int year, String term) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('sync_schedules_enabled') ?? false)) return;
    final targetCalId = prefs.getString('calendar_sync_target_id');
    if (targetCalId == null || targetCalId.isEmpty || !await requestPermissions()) return;

    Map<String, String> eventMapping = Map<String, String>.from(jsonDecode(prefs.getString('cal_map_schedules') ?? '{}'));
    List<String> activeScheduleIds = [];

    DateTime now = DateTime.now();
    bool isSpring = term.contains('春') || term.contains('Q1') || term.contains('Q2') || term.contains('前期') || term.contains('SPRING');
    DateTime semStart = currentLMS.getSemesterStartDate(now, isSpring);
    DateTime semEnd = currentLMS.getSemesterEndDate(now, isSpring);

    if (term.contains('Q1') || term.contains('Q3')) {
      semEnd = semStart.add(Duration(days: (semEnd.difference(semStart).inDays / 2).floor()));
    } else if (term.contains('Q2') || term.contains('Q4')) {
      semStart = semStart.add(Duration(days: (semEnd.difference(semStart).inDays / 2).floor()));
    }

    final Map<int, Map<String, int>> periods = {
      0: {'start': 900, 'end': 1030}, 1: {'start': 1045, 'end': 1215}, 2: {'start': 1300, 'end': 1430},
      3: {'start': 1445, 'end': 1615}, 4: {'start': 1630, 'end': 1800}, 5: {'start': 1815, 'end': 1945}
    };

    for (var c in courses) {
      String courseId = c['is_custom'] == true ? (c['raw_name'] ?? c['name'] ?? '') : c['id'].toString();
      String rawName = c['raw_name'] ?? c['name'] ?? '';

      if (c['is_custom'] == true && c['is_weekly'] == false) continue;

      List<Map<String, int>> schedules = c['is_custom'] == true ? [{'day': c['day'], 'period': c['period']}] : currentLMS.parseWeeklySchedule(rawName);

      for (var s in schedules) {
        int dayIdx = s['day']!;
        int periodIdx = s['period']!;
        if (!periods.containsKey(periodIdx)) continue;

        String uniqueSchId = "${courseId}_${dayIdx}_$periodIdx";
        activeScheduleIds.add(uniqueSchId);

        DateTime firstClassDate = semStart;
        while (firstClassDate.weekday - 1 != dayIdx) {
          firstClassDate = firstClassDate.add(const Duration(days: 1));
        }
        if (firstClassDate.isAfter(semEnd)) continue;

        int startHour = periods[periodIdx]!['start']! ~/ 100;
        int startMin = periods[periodIdx]!['start']! % 100;
        int endHour = periods[periodIdx]!['end']! ~/ 100;
        int endMin = periods[periodIdx]!['end']! % 100;

        dc.Event event = dc.Event(targetCalId);

        if (eventMapping.containsKey(uniqueSchId)) {
          event.eventId = eventMapping[uniqueSchId];
        }

        String titleStr = currentLMS.cleanTitle(rawName);
        String roomStr = currentLMS.extractRoom(rawName);
        if (c['is_custom'] == true) { titleStr = rawName; roomStr = c['room'] ?? ''; }

        event.title = "[授業] $titleStr";
        event.description = "教室: $roomStr\nアプリから同期されたスケジュール";
        event.location = roomStr;

        DateTime startDt = DateTime(firstClassDate.year, firstClassDate.month, firstClassDate.day, startHour, startMin);
        DateTime endDt = DateTime(firstClassDate.year, firstClassDate.month, firstClassDate.day, endHour, endMin);

        event.start = dc.TZDateTime.from(startDt, dc.local);
        event.end = dc.TZDateTime.from(endDt, dc.local);

        dc.RecurrenceRule rrule = dc.RecurrenceRule(dc.RecurrenceFrequency.Weekly);
        rrule.endDate = dc.TZDateTime.from(DateTime(semEnd.year, semEnd.month, semEnd.day, 23, 59), dc.local);
        event.recurrenceRule = rrule;

        final result = await _deviceCalendarPlugin.createOrUpdateEvent(event);
        if (result?.isSuccess == true && result?.data != null) {
          eventMapping[uniqueSchId] = result!.data!;
        }
      }
    }

    List<String> toRemove = [];
    for (var key in eventMapping.keys) {
      if (!activeScheduleIds.contains(key)) {
        await _deviceCalendarPlugin.deleteEvent(targetCalId, eventMapping[key]);
        toRemove.add(key);
      }
    }
    toRemove.forEach((k) => eventMapping.remove(k));
    await prefs.setString('cal_map_schedules', jsonEncode(eventMapping));
  }

  // ★ 要件クリア：スケジュール同期オフ時に完全一掃する
  static Future<void> disableScheduleSync() async {
    final prefs = await SharedPreferences.getInstance();
    final targetCalId = prefs.getString('calendar_sync_target_id');
    if (targetCalId == null || targetCalId.isEmpty) return;

    // 1. マップに記録されたIDベースで削除
    Map<String, String> eventMapping = Map<String, String>.from(jsonDecode(prefs.getString('cal_map_schedules') ?? '{}'));
    for (var eventId in eventMapping.values) {
      await _deviceCalendarPlugin.deleteEvent(targetCalId, eventId);
    }
    await prefs.remove('cal_map_schedules');
    await prefs.setBool('sync_schedules_enabled', false);

    // 2. フェイルセーフ（記録漏れの [授業] を検索して強制一掃）
    final startDate = dc.TZDateTime.local(DateTime.now().year - 1, 1, 1);
    final endDate = dc.TZDateTime.local(DateTime.now().year + 2, 1, 1);
    final eventsResult = await _deviceCalendarPlugin.retrieveEvents(targetCalId, dc.RetrieveEventsParams(startDate: startDate, endDate: endDate));
    if (eventsResult.isSuccess && eventsResult.data != null) {
      for (var e in eventsResult.data!) {
        if (e.title != null && e.title!.startsWith('[授業]')) {
          await _deviceCalendarPlugin.deleteEvent(targetCalId, e.eventId);
        }
      }
    }
  }

  // ==========================================
  // 3. カレンダー -> アプリ (Dynamic Read)
  // ==========================================
  static Future<List<Map<String, dynamic>>> getDeviceEventsForDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('sync_import_enabled') ?? false)) return [];
    if (!await requestPermissions()) return [];

    Map<String, String> appTaskMap = Map<String, String>.from(jsonDecode(prefs.getString('cal_map_tasks') ?? '{}'));
    Map<String, String> appScheduleMap = Map<String, String>.from(jsonDecode(prefs.getString('cal_map_schedules') ?? '{}'));
    List<String> masterIds = [...appTaskMap.values, ...appScheduleMap.values];

    List<Map<String, dynamic>> externalEvents = [];
    final calendars = await getWritableCalendars();

    final startDate = dc.TZDateTime(dc.local, date.year, date.month, date.day);
    final endDate = startDate.add(const Duration(days: 1));

    // ★ 追加：複数のカレンダー間で同じ予定がダブるのを防ぐセット
    Set<String> uniqueSignatures = {};

    for (var cal in calendars) {
      final eventsResult = await _deviceCalendarPlugin.retrieveEvents(cal.id, dc.RetrieveEventsParams(startDate: startDate, endDate: endDate));
      if (eventsResult.isSuccess && eventsResult.data != null) {
        for (var e in eventsResult.data!) {
          String currentEventId = e.eventId ?? '';

          if (masterIds.contains(currentEventId)) continue;
          bool isInstance = masterIds.any((id) => currentEventId.startsWith(id));
          if (isInstance) continue;
          if (e.title != null && (e.title!.startsWith('[課題]') || e.title!.startsWith('[授業]'))) continue;

          bool isAllDay = e.allDay ?? false;
          DateTime eventStart;
          DateTime eventEnd; // ★ 追加
          if (e.start != null && e.end != null) {
            eventStart = DateTime(e.start!.year, e.start!.month, e.start!.day, e.start!.hour, e.start!.minute);
            eventEnd = DateTime(e.end!.year, e.end!.month, e.end!.day, e.end!.hour, e.end!.minute);
          } else {
            continue;
          }

          if (isAllDay) {
            eventStart = DateTime(date.year, date.month, date.day, 0, 0);
            eventEnd = DateTime(date.year, date.month, date.day, 23, 59);
          }

          // ★ 同一タイトル・同一開始時間の予定は1つにまとめる（ダブり防止）
          String signature = "${e.title}_${eventStart.millisecondsSinceEpoch}";
          if (uniqueSignatures.contains(signature)) continue;
          uniqueSignatures.add(signature);

          externalEvents.add({
            'type': 'external_event',
            'time': eventStart,
            'endTime': eventEnd, // ★ 追加
            'title': e.title ?? '予定',
            'subtitle': e.location ?? 'OSカレンダーより',
            'status': 0,
            'isAllDay': isAllDay,
          });
        }
      }
    }
    return externalEvents;
  }
}


