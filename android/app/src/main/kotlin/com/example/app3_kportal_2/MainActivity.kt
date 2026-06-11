// 👇 元々書いてあった package の行はそのまま残してください！
package com.hk_app3_k.portal

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.webkit.CookieManager

// 🟢 ライブ通知の実装に必要なネイティブライブラリをインポート
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

class MainActivity: FlutterActivity() {
    // 既存のCookie用チャンネル名
    private val COOKIE_CHANNEL = "com.example.app/cookie"
    // 🟢 Dart側のLiveNotificationServiceと足並みを揃えた通知用チャンネル名
    private val NOTIFICATION_CHANNEL = "app3.kportal/live_notification"
    // Androidシステム内部で識別するための通知チャンネルID
    private val SYSTEM_CHANNEL_ID = "live_countdown_channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. 既存のCookie取得処理（そのまま維持）
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, COOKIE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getCookies") {
                val url = call.argument<String>("url")
                val cookies = CookieManager.getInstance().getCookie(url)
                result.success(cookies ?: "")
            } else {
                result.notImplemented()
            }
        }

        // 2. 🟢 新設：15分前アラームから叩かれるライブ通知起動処理
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "startLiveNotification") {
                val title = call.argument<String>("title") ?: "予定"
                val subtitle = call.argument<String>("subtitle") ?: ""
                val endTimeMillis = call.argument<Long>("endTimeMillis") ?: 0L
                val type = call.argument<String>("type") ?: "class"
                val targetId = call.argument<String>("targetId") ?: ""

                // 進行中（Ongoing）通知を画面にぶち込む
                showOngoingNotification(title, subtitle, endTimeMillis, type, targetId)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        // 3. 🟢 Android 8.0以上向けに通知枠をあらかじめシステムに登録
        createNotificationChannel()
    }

    // 🟢 カウントダウンタイマー付きの常駐通知を表示するコアロジック
    private fun showOngoingNotification(title: String, subtitle: String, endTimeMillis: Long, type: String, targetId: String) {
        val context = applicationContext

        // 通知をタップしたときにアプリを安全に起動し、ディープリンク情報をFlutterへ引き渡すインテント
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("type", type)
            putExtra("targetId", targetId)
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 通知のビルド（OS標準のChronometerをフル駆動させる設定）
        val notification = NotificationCompat.Builder(context, SYSTEM_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm) // システム標準のアラームアイコン（後でIcon_o.png等に変更可能）
            .setContentTitle(title)
            .setContentText(subtitle)
            .setOngoing(true)                      // 👈 絶対条件：ユーザーがスワイプしても消えない常駐属性
            .setUsesChronometer(true)              // 👈 絶対条件：タイマーモードを有効化
            .setChronometerCountDown(true)         // 👈 絶対条件：カウントダウン（引き算）モードに設定
            .setWhen(endTimeMillis)                // 👈 絶対条件：目標時刻（授業開始や締切）のミリ秒をセット
            .setContentIntent(pendingIntent)       // タップ時の挙動
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC) // ロック画面でも表示を許可
            .build()

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(9999, notification) // 固定のIDで通知を1つだけスマートに常駐させる
    }

    // 🟢 通知チャンネルの作成（これがないとAndroid 8.0以降で通知が完全にサイレント化します）
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "ライブカウントダウン通知"
            val descriptionText = "授業の開始時間や課題の締め切りまでの残り時間を秒単位でリアルタイム表示します"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(SYSTEM_CHANNEL_ID, name, importance).apply {
                description = descriptionText
                setShowBadge(false) // アプリのアイコンバッジは汚さないようにOFF
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
}