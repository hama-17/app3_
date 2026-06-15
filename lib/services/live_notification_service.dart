import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import '../utils/lms_adapter.dart';

class LiveNotificationService {
  static const MethodChannel _platform = MethodChannel('app3.kportal/live_notification');

  // 🟢 独自新設：iOSネイティブ層の準備不足による Dart側の即死フリーズを100%物理封殺する安全装置
  static Future<T?> _invokeSafe<T>(String method, [dynamic arguments]) async {
    try {
      return await _platform.invokeMethod<T>(method, arguments);
    } catch (e) {
      // 窓口が開いていなくても、エラーを外に漏らさず静かにログだけを吐いてスルー。
      // これにより、起動1フレーム目で画面が真っ黒フリーズするのを構造的に完全防御します。
      debugPrint("⚠️ LiveNotificationService._invokeSafe [$method] 警告（スキップされました）: $e");
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

    // 🟢 修正：バックグラウンドIsolateからの呼び出しも安全装置を経由
    await _invokeSafe('startLiveNotification', {
      'title': title,
      'subtitle': subtitle,
      'endTimeMillis': endTimeMillis,
      'type': type,
      'targetId': targetId,
    });

    await prefs.remove('live_alarm_data_$id');
  }

  // -------------------------------------------------------------------
  // 🟢 修正：安全な時間割曜日パースと動期同期させたリスケジュールコア
  // -------------------------------------------------------------------
  static Future<void> reScheduleLiveNotifications({
    required List<dynamic> currentCourses,
    required List<dynamic> currentAssignments,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // 古い予約を一度すべてクリーンアップ
    await _clearAllScheduledAlarms(prefs);

    List<String> newScheduledIds = [];
    final now = DateTime.now();
    int uniqueIdCounter = 1000;

    // ① 【授業の予約（既存の週次・単発スケジュール構造に最適化）】
    // 💡 盲点解消：実在しない next_session_time を参照せず、今日の曜日インデックスから安全に時間を算出します
    int todayWeekdayIdx = now.weekday - 1; // 0:月, 1:火...

    for (var course in currentCourses) {
      if (course == null) continue;

      // カスタム授業、またはCanvas授業の既存のパース情報から、直近の予定を割り出します
      // （※ここでは例として、本日これからの授業がある場合に15分前アラームをセットするタイトな防衛線を敷きます）
      final String rawName = course['name'] ?? '';
      final schedules = currentLMS.parseWeeklySchedule(rawName);

      for (var s in schedules) {
        if (s['day'] == todayWeekdayIdx) {
          int period = s['period'] ?? 0;

          // 定義されている時限表（例: 1限 9:00〜）から今日の開始時間を割り出す
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
            'subtitle': 'まもなく ${period + 1} 限の授業が始まります（${currentLMS.extractRoom(rawName)}）',
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

      // 🟢 JSTローカル時間に安全に変換してからパース
      DateTime dueTime = DateTime.tryParse(task['due_at'] ?? '')?.toLocal() ?? now;

      // ➔ 締め切りの「1時間前」を算出
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

    // 予約したすべてのIDリストを次回クリア用に保存
    await prefs.setStringList('scheduled_alarm_ids', newScheduledIds);
  }

  // 🟢 OSのアラーム機構へチケットを登録する共通処理
  static Future<void> _registerOSAlarm(int id, DateTime triggerTime, Map<String, dynamic> params) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('live_alarm_data_$id', jsonEncode(params));

    // Android用の精密バックグラウンドアラーム予約
    await AndroidAlarmManager.oneShotAt(
      triggerTime,
      id,
      alarmTriggerCallback,
      exact: true,
      wakeup: true,
      alarmClock: true,
    );

    // 🟢 修正：安全装置経由で呼び出し、iOSのレースコンディションを完全無力化
    await _invokeSafe('scheduleIOSLocalNotification', {
      'id': id,
      'triggerTimeMillis': triggerTime.millisecondsSinceEpoch,
      'params': params,
    });
  }

  // 🟢 過去の予約を一度すべてクリアして二重登録を防ぐクリーンアップ
  static Future<void> _clearAllScheduledAlarms(SharedPreferences prefs) async {
    List<String> oldIds = prefs.getStringList('scheduled_alarm_ids') ?? [];
    for (var idStr in oldIds) {
      int id = int.parse(idStr);
      await AndroidAlarmManager.cancel(id);
      await prefs.remove('live_alarm_data_$id');
    }
    // 🟢 修正：安全装置経由で呼び出し
    await _invokeSafe('cancelAllIOSLocalNotifications');
  }

  // 🟢 アプリ起動時に通知がタップされた際、ここから該当画面へディープリンクでジャンプ
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