package com.hk_app3_k.portal

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import android.os.Build

class LiveNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", 0)
        val title = intent.getStringExtra("title") ?: "予定"
        val subtitle = intent.getStringExtra("subtitle") ?: ""
        val endTimeMillis = intent.getLongExtra("endTimeMillis", 0L)
        val type = intent.getStringExtra("type") ?: "class"
        val targetId = intent.getStringExtra("targetId") ?: ""

        val SYSTEM_CHANNEL_ID = "live_countdown_channel"

        // タップ時にアプリを引き起こすためのインテント
        val tapIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("type", type)
            putExtra("targetId", targetId)
        }
        val pendingIntent = PendingIntent.getActivity(
            context, id, tapIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // クロノメーター搭載のOngoing通知ビルド
        val notification = NotificationCompat.Builder(context, SYSTEM_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setOngoing(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setWhen(endTimeMillis)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()

        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(9999, notification) // 9999に上書き常駐
    }
}