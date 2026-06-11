import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import '../utils/lms_adapter.dart';

class LiveNotificationService {
  static const MethodChannel _platform = MethodChannel('app3.kportal/live_notification');

  // 🟢 15分前・1時間前になった瞬間に、OSから裏側（バックグラウンド）で呼び出される関数
  @pragma('vm:entry-point')
  static void alarmTriggerCallback(int id, Map<String, dynamic> params) async {
    final String title = params['title'] ?? '予定';
    final String subtitle = params['subtitle'] ?? '';
    final int endTimeMillis = params['endTimeMillis'] ?? 0;
    final String type = params['type'] ?? 'class';
    final String targetId = params['targetId'] ?? '';

    // ネイティブ（Swift/Kotlin）を叩いて、最前面のライブ通知を強制起動！
    await _platform.invokeMethod('startLiveNotification', {
      'title': title,
      'subtitle': subtitle,
      'endTimeMillis': endTimeMillis,
      'type': type,
      'targetId': targetId,
    });
  }

  // 🟢 既存のCalendarSyncServiceの各syncメソッドの最後尾からこれを呼び出す
  static Future<void> scheduleNextWeekAlerts(List<dynamic> courses, List<dynamic> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    await _clearAllScheduledAlarms(prefs);

    final now = DateTime.now();
    final oneWeekLater = now.add(const Duration(days: 7));
    int alarmIdCounter = 0;
    List<int> registeredIds = [];

    // ====================================================
    // ① タスク（課題）の1時間前アラームを計算・予約
    // ====================================================
    for (var t in tasks) {
      String rawDue = t['due_at'] ?? '';
      if (rawDue.isEmpty) continue;
      DateTime? dueTime = DateTime.tryParse(rawDue)?.toLocal();
      if (dueTime == null || dueTime.isBefore(now) || dueTime.isAfter(oneWeekLater)) continue;

      // 🔥 提出済みの課題かどうかを厳密にチェック
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

      // ➔ 提出済みの課題は完全に無視（通知の対象外にする）
      if (isCompleted) continue;

      // 🔥 締め切りの「1時間前」にトリガー時間を計算
      DateTime triggerTime = dueTime.subtract(const Duration(hours: 1));

      // 【救済措置】すでに締切1時間前を切っているが、まだ締切が過ぎていない場合
      if (triggerTime.isBefore(now)) {
        triggerTime = now.add(const Duration(seconds: 1));
      }

      alarmIdCounter++;
      registeredIds.add(alarmIdCounter);

      final params = {
        'title': "[締切まで1時間] ${t['name']}",
        'subtitle': currentLMS.cleanTitle(t['context_name'] ?? ''),
        'endTimeMillis': dueTime.millisecondsSinceEpoch,
        'type': 'task',
        'targetId': t['id'].toString(),
      };

      await _registerOSAlarm(alarmIdCounter, triggerTime, params);
    }

    // ====================================================
    // ② 授業スケジュールのアラーム予約（15分前）
    // ====================================================
    // ※ ここに今後、今週の授業スケジュール（15分前着火）のループ処理を
    // タスクと同様に構築して _registerOSAlarm を叩くロジックが入ります。

    // 最後に予約した全アラームIDのリストを保存
    await prefs.setStringList('scheduled_alarm_ids', registeredIds.map((e) => e.toString()).toList());
  }

  // 🟢 OSのアラーム機構へチケットを登録する共通処理
  static Future<void> _registerOSAlarm(int id, DateTime triggerTime, Map<String, dynamic> params) async {
    // Android用の精密バックグラウンドアラーム予約
    await AndroidAlarmManager.oneShotAt(
      triggerTime,
      id,
      alarmTriggerCallback,
      exact: true,
      wakeup: true,
      alarmClock: true,
      params: params,
    );

    // iOS用のネイティブ通知予約（15分前・1時間前着火のタイムスタンプを仕込む）
    await _platform.invokeMethod('scheduleIOSLocalNotification', {
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
    }
    await _platform.invokeMethod('cancelAllIOSLocalNotifications');
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