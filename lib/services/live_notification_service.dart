import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import '../utils/lms_adapter.dart';

class LiveNotificationService {
  static const MethodChannel _platform = MethodChannel('app3.kportal/live_notification');

  // 🟢 15分前・1時間前になった瞬間に、OSから裏側（バックグラウンド）で呼び出される関数
  // ============================================================================
  // 🟢 修正：引数は「int id」のみに固定（これ以外の形はOSが呼び出せず沈黙します）
  // ============================================================================
  @pragma('vm:entry-point')
  static void alarmTriggerCallback(int id) async {
    // 💡 隔離されたバックグラウンドIsolate用に、ストレージのインスタンスを新しく開く
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString('live_alarm_data_$id');
    if (jsonStr == null) return;

    final Map<String, dynamic> params = jsonDecode(jsonStr);
    final String title = params['title'] ?? '予定';
    final String subtitle = params['subtitle'] ?? '';
    final int endTimeMillis = params['endTimeMillis'] ?? 0;
    final String type = params['type'] ?? 'class';
    final String targetId = params['targetId'] ?? '';

    // ネイティブを叩いて、最前面のライブ通知を強制起動！
    await _platform.invokeMethod('startLiveNotification', {
      'title': title,
      'subtitle': subtitle,
      'endTimeMillis': endTimeMillis,
      'type': type,
      'targetId': targetId,
    });

    // 使い終わったテンポラリキャッシュは綺麗にお掃除
    await prefs.remove('live_alarm_data_$id');
  }

  // 🟢 OSのアラーム機構へチケットを登録する共通処理
  static Future<void> _registerOSAlarm(int id, DateTime triggerTime, Map<String, dynamic> params) async {
    final prefs = await SharedPreferences.getInstance();

    // 💡 発火した瞬間に id からデータを引っ張れるようにストレージへパッキングして退避
    await prefs.setString('live_alarm_data_$id', jsonEncode(params));

    // Android用の精密バックグラウンドアラーム予約（引数から params を撤去）
    await AndroidAlarmManager.oneShotAt(
      triggerTime,
      id,
      alarmTriggerCallback,
      exact: true,
      wakeup: true,
      alarmClock: true,
    );

    // iOS用のネイティブ通知予約
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
      await prefs.remove('live_alarm_data_$id'); // 🟢 キャッシュデータもクリーンアップ
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