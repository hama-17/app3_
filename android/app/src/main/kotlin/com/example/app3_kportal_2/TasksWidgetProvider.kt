package com.example.app3_kportal_2

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetPlugin

class TasksWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        val res = context.resources
        val pkg = context.packageName

        val layoutId = res.getIdentifier("widget_tasks_layout", "layout", pkg)
        val listId = res.getIdentifier("widget_tasks_list", "id", pkg)
        val bgImageId = res.getIdentifier("widget_background_image", "id", pkg)

        val currentNightMode = res.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        val isSystemDarkMode = currentNightMode == Configuration.UI_MODE_NIGHT_YES
        val bgHex = if (isSystemDarkMode) "#222222" else "#EEEEEE"

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(pkg, layoutId)

            try {
                val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
                var minWidthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
                var minHeightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)

                if (minWidthDp <= 0) minWidthDp = 300
                if (minHeightDp <= 0) minHeightDp = 200

                val density = res.displayMetrics.density
                val widthPx = (minWidthDp * density).toInt().coerceAtLeast(200)
                val heightPx = (minHeightDp * density).toInt().coerceAtLeast(100)

                val bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)
                val paint = Paint().apply {
                    color = Color.parseColor(bgHex)
                    isAntiAlias = true
                }
                val cornerRadius = 26f * density
                canvas.drawRoundRect(RectF(0f, 0f, widthPx.toFloat(), heightPx.toFloat()), cornerRadius, cornerRadius, paint)

                if (bgImageId != 0) { views.setImageViewBitmap(bgImageId, bitmap) }
            } catch (e: Exception) {
                Log.e("TasksWidgetProvider", "⚠️ 背景生成スキップ", e)
                if (bgImageId != 0) { views.setInt(bgImageId, "setBackgroundColor", Color.parseColor(bgHex)) }
            }

            try {
                // ─── 🟢 修正：ListViewがキャッシュをサボらないよう、IntentにユニークなDataを付与 ───
                val intent = Intent(context, WidgetListViewService::class.java).apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                    putExtra("data_key", "tasks_json")
                    // ★ 修正：現在の時刻をURIに含めて毎回Intentを別物として認識させる
                    data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME) + "/" + System.currentTimeMillis().toString())
                }
                views.setRemoteAdapter(listId, intent)

                val launchIntent = Intent().apply {
                    setClassName(pkg, "$pkg.MainActivity")
                    action = "es.antonborri.home_widget.action.LAUNCH"
                }
                val pendingIntent = PendingIntent.getActivity(
                    context, 101, launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                )
                views.setPendingIntentTemplate(listId, pendingIntent)

                val mainIntent = Intent().apply {
                    setClassName(pkg, "$pkg.MainActivity")
                    action = "es.antonborri.home_widget.action.LAUNCH"
                    data = Uri.parse("app3k://widget/main")
                }
                val mainPendingIntent = PendingIntent.getActivity(
                    context, appWidgetId, mainIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                )
                if (bgImageId != 0) { views.setOnClickPendingIntent(bgImageId, mainPendingIntent) }
            } catch (e: Exception) {
                Log.e("TasksWidgetProvider", "リストシステム結線エラー", e)
            }

            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, listId)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        val prefs = HomeWidgetPlugin.getData(context)
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId), prefs)
    }
}