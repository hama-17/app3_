import 'dart:convert';
import 'dart:ui'; // 🟢 追記：DartPluginRegistrant を使うために必要
import 'package:flutter/material.dart'; // 🟢 追記：WidgetsFlutterBinding のために必要
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import '../utils/lms_adapter.dart';

class LiveNotificationService {
  static const MethodChannel _platform = MethodChannel('app3.kportal/live_notification');

  @pragma('vm:entry-point')
  static void alarmTriggerCallback(int id) async {
    // 🟢 修正：隔離された裏の空間（Isolate）で Flutter ＆ プラグインの通信バインディングを強制初期化！
    // これがないと、バックグラウンドからの MethodChannel 呼び出しがシステムに無視されて沈黙します。
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

    await _platform.invokeMethod('startLiveNotification', {
      'title': title,
      'subtitle': subtitle,
      'endTimeMillis': endTimeMillis,
      'type': type,
      'targetId': targetId,
    });

    await prefs.remove('live_alarm_data_$id');
  }

  // -------------------------------------------------------------------
  // 🟢 新設（エンジン関数）：最新の授業・課題データから15分前・1時間前を自動計算して全予約
  // -------------------------------------------------------------------
  static Future<void> reScheduleLiveNotifications({
    required List<dynamic> currentCourses,
    required List<dynamic> currentAssignments,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // まずは古い予約を一度すべて綺麗にお掃除（多重登録の防止）
    await _clearAllScheduledAlarms(prefs);

    List<String> newScheduledIds = [];
    final now = DateTime.now();
    int uniqueIdCounter = 1000; // アラームの重複を防ぐ一意のIDカウンタ

    // ① 【授業の予約】
    for (var course in currentCourses) {
      // ※ 内部データから直近の「次回の授業日時（DateTime）」を算出するロジック（以下は構造例）
      if (course['next_session_time'] == null) continue;
      DateTime classStartTime = DateTime.parse(course['next_session_time']);

      // ➔ 授業開始の「15分前」を算出
      DateTime triggerTime = classStartTime.subtract(const Duration(minutes: 15));

      // すでに過ぎ去った過去の時刻ならスキップ
      if (triggerTime.isBefore(now)) continue;

      int alarmId = uniqueIdCounter++;
      Map<String, dynamic> params = {
        'title': course['name'] ?? '授業',
        'subtitle': 'まもなく 15 分前に始まります（${course['location'] ?? "教室未定"}）',
        'endTimeMillis': classStartTime.add(const Duration(minutes: 90)).millisecondsSinceEpoch, // 授業終了予定時刻
        'type': 'class',
        'targetId': course['id'].toString(),
      };

      await _registerOSAlarm(alarmId, triggerTime, params);
      newScheduledIds.add(alarmId.toString());
    }

    // ② 【課題の予約】
    for (var task in currentAssignments) {
      if (task['due_at'] == null) continue;
      DateTime dueTime = DateTime.parse(task['due_at']);

      // ➔ 締め切りの「1時間前」を算出
      DateTime triggerTime = dueTime.subtract(const Duration(hours: 1));

      if (triggerTime.isBefore(now)) continue;

      int alarmId = uniqueIdCounter++;
      Map<String, dynamic> params = {
        'title': task['name'] ?? '課題締切',
        'subtitle': '提出締め切りまであと 1 時間です',
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

  // （...以下、既存の _registerOSAlarm, _clearAllScheduledAlarms, setupMethodCallHandler は1文字も変えずそのまま残します）

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