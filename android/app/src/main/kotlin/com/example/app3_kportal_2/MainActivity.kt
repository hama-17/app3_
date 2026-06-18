// ─── 🟢 修正版: android/app/src/main/kotlin/com/hk_app3_k/portal/MainActivity.kt ───
package com.hk_app3_k.portal

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.webkit.CookieManager

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

class MainActivity: FlutterActivity() {
    private val COOKIE_CHANNEL = "com.example.app/cookie"
    private val NOTIFICATION_CHANNEL = "app3.kportal/live_notification"
    private val SYSTEM_CHANNEL_ID = "live_countdown_channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ① 既存のCookie取得処理
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, COOKIE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getCookies") {
                val url = call.argument<String>("url")
                val cookies = CookieManager.getInstance().getCookie(url)
                result.success(cookies ?: "")
            } else {
                result.notImplemented()
            }
        }

        // ② Dartから「1週間分の予約スタンプ」をまとめて引き受ける高剛性ハブ
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleAndroidLiveNotification" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val triggerTimeMillis = call.argument<Long>("triggerTimeMillis") ?: 0L
                    val title = call.argument<String>("title") ?: "予定"
                    val subtitle = call.argument<String>("subtitle") ?: ""
                    val endTimeMillis = call.argument<Long>("endTimeMillis") ?: 0L
                    val type = call.argument<String>("type") ?: "class"
                    val targetId = call.argument<String>("targetId") ?: ""

                    scheduleNativeAlarm(id, triggerTimeMillis, title, subtitle, endTimeMillis, type, targetId)
                    result.success(null)
                }
                "cancelAndroidLiveNotification" -> {
                    val id = call.argument<Int>("id") ?: 0
                    cancelNativeAlarm(id)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // ③ 通知枠のシステム事前登録
        createNotificationChannel()
    }

    private fun scheduleNativeAlarm(id: Int, triggerTimeMillis: Long, title: String, subtitle: String, endTimeMillis: Long, type: String, targetId: String) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, LiveNotificationReceiver::class.java).apply {
            putExtra("id", id)
            putExtra("title", title)
            putExtra("subtitle", subtitle)
            putExtra("endTimeMillis", endTimeMillis)
            putExtra("type", type)
            putExtra("targetId", targetId)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            this, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerTimeMillis, pendingIntent)
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerTimeMillis, pendingIntent)
        }
    }

    private fun cancelNativeAlarm(id: Int) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, LiveNotificationReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            this, id, intent, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        if (pendingIntent != null) {
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "ライブカウントダウン通知"
            val descriptionText = "授業の開始時間や課題の締め切りまでの残り時間を秒単位でリアルタイム表示します"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(SYSTEM_CHANNEL_ID, name, importance).apply {
                description = descriptionText
                setShowBadge(false)
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
}