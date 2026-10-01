import 'dart:convert';
import 'dart:io'; // 🟢 追記：Platform.isAndroid を識別するために必須
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import '../utils/lms_adapter.dart';
//live_notification_service.dart
class LiveNotificationService {
  static const MethodChannel _platform = MethodChannel('app3.kportal/live_notification');

  static bool _isAlarmManagerInitialized = false;

  // iOSネイティブ層の準備不足による Dart側の即死フリーズを100%物理封殺する安全装置
  static Future<T?> _invokeSafe<T>(String method, [dynamic arguments]) async {
    try {
      return await _platform.invokeMethod<T>(method, arguments);
    } catch (e) {
      debugPrint("⚠️ LiveNotificationService._invokeSafe [$method] スキップ: $e");
      return null;
    }
  }

  @pragma('vm:entry-point')
  static void alarmTriggerCallback(int id) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString('live_alarm_data_$id');
    if (jsonStr == null) return;

    final Map<String, dynamic> params = jsonDecode(jsonStr);
    final String title = params['title'] ?? '予定';
    final String subtitle = params['subtitle'] ?? '';
    final int endTimeMillis = params['endTimeMillis'] ?? 0;
    final String type = params['type'] ?? 'class';
    final String targetId = params['targetId'] ?? '';

    await _invokeSafe('startLiveNotification', {
      'title': title,
      'subtitle': subtitle,
      'endTimeMillis': endTimeMillis,
      'type': type,
      'targetId': targetId,
    });

    await prefs.remove('live_alarm_data_$id');
  }

  // 最新の授業・課題データから15分前・1時間前を自動計算して全予約
  static Future<void> reScheduleLiveNotifications({
    required List<dynamic> currentCourses,
    required List<dynamic> currentAssignments,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // ─── 🟢 修正：LMSデータが更新された最初のタイミングで、Androidアラームエンジンを強制起爆 ───
    if (Platform.isAndroid && !_isAlarmManagerInitialized) {
      _isAlarmManagerInitialized = await AndroidAlarmManager.initialize();
      debugPrint("🤖 AndroidAlarmManager の初期化に成功しました: $_isAlarmManagerInitialized");
    }

    // 古い予約を一度すべてクリーンアップ
    await _clearAllScheduledAlarms(prefs);

    List<String> newScheduledIds = [];
    final now = DateTime.now();
    int uniqueIdCounter = 1000;

    // ① 【授業の予約】
    int todayWeekdayIdx = now.weekday - 1;

    for (var course in currentCourses) {
      if (course == null) continue;

      final String rawName = course['name'] ?? '';
      final schedules = currentLMS.parseWeeklySchedule(rawName);

      for (var s in schedules) {
        if (s['day'] == todayWeekdayIdx) {
          int period = s['period'] ?? 0;

          final periodsMap = {
            0: {'start': 900}, 1: {'start': 1045}, 2: {'start': 1300},
            3: {'start': 1445}, 4: {'start': 1630}, 5: {'start': 1815}
          };

          final p = periodsMap[period];
          if (p == null) continue;

          int startHour = p['start']! ~/ 100;
          int startMin = p['start']! % 100;

          DateTime classStartTime = DateTime(now.year, now.month, now.day, startHour, startMin);
          DateTime triggerTime = classStartTime.subtract(const Duration(minutes: 15));

          if (triggerTime.isBefore(now)) continue;

          int alarmId = uniqueIdCounter++;
          Map<String, dynamic> params = {
            'title': currentLMS.cleanTitle(rawName),
            'subtitle': 'まもなく第 ${period + 1} 時限の授業が始まります（${currentLMS.extractRoom(rawName)}）',
            'endTimeMillis': classStartTime.add(const Duration(minutes: 90)).millisecondsSinceEpoch,
            'type': 'class',
            'targetId': course['id'].toString(),
          };

          await _registerOSAlarm(alarmId, triggerTime, params);
          newScheduledIds.add(alarmId.toString());
        }
      }
    }

    // ② 【課題の予約】
    for (var task in currentAssignments) {
      if (task['due_at'] == null || task['due_at'].toString().isEmpty) continue;

      DateTime dueTime = DateTime.tryParse(task['due_at'] ?? '')?.toLocal() ?? now;
      DateTime triggerTime = dueTime.subtract(const Duration(hours: 1));

      if (triggerTime.isBefore(now)) continue;

      int alarmId = uniqueIdCounter++;
      Map<String, dynamic> params = {
        'title': task['name'] ?? '課題締切',
        'subtitle': '提出締め切りまであと 1 時間です（${currentLMS.cleanTitle(task['context_name'] ?? '')}）',
        'endTimeMillis': dueTime.millisecondsSinceEpoch,
        'type': 'task',
        'targetId': task['id'].toString(),
      };

      await _registerOSAlarm(alarmId, triggerTime, params);
      newScheduledIds.add(alarmId.toString());
    }

    await prefs.setStringList('scheduled_alarm_ids', newScheduledIds);
  }

  // OSのアラーム機構へチケットを登録する共通処理
  // OSのアラーム機構へチケットを登録する共通処理
  static Future<void> _registerOSAlarm(int id, DateTime triggerTime, Map<String, dynamic> params) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('live_alarm_data_$id', jsonEncode(params));

    // 🟢 修正：AndroidAlarmManager を廃止し、直接Kotlinの物理予約システムをキック
    if (Platform.isAndroid) {
      await _platform.invokeMethod('scheduleAndroidLiveNotification', {
        'id': id,
        'triggerTimeMillis': triggerTime.millisecondsSinceEpoch,
        'title': params['title'],
        'subtitle': params['subtitle'],
        'endTimeMillis': params['endTimeMillis'],
        'type': params['type'],
        'targetId': params['targetId'],
      });
    }

    // iOS用のネイティブ通知予約
    await _invokeSafe('scheduleIOSLocalNotification', {
      'id': id,
      'triggerTimeMillis': triggerTime.millisecondsSinceEpoch,
      'params': params,
    });
  }

  // 過去の予約を一度すべてクリアして二重登録を防ぐクリーンアップ
  static Future<void> _clearAllScheduledAlarms(SharedPreferences prefs) async {
    List<String> oldIds = prefs.getStringList('scheduled_alarm_ids') ?? [];
    for (var idStr in oldIds) {
      int id = int.parse(idStr);

      // 🟢 修正：こちらもKotlin側へキャンセル命令を1発飛ばすだけ
      if (Platform.isAndroid) {
        await _platform.invokeMethod('cancelAndroidLiveNotification', {'id': id});
      }
      await prefs.remove('live_alarm_data_$id');
    }
    await _invokeSafe('cancelAllIOSLocalNotifications');
  }


  // アプリ起動時に通知がタップされた際、ここから該当画面へディープリンクでジャンプ
  static void setupMethodCallHandler(Function(String type, String targetId) onDeepLinkReceived) {
    _platform.setMethodCallHandler((call) async {
      if (call.method == "onNotificationTap") {
        final String type = call.arguments['type'] ?? '';
        final String targetId = call.arguments['targetId'] ?? '';
        onDeepLinkReceived(type, targetId);
      }
      return null;
    });
  }
}