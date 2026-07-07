package com.example.app3_kportal_2

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetPlugin

class TodayWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        val res = context.resources
        val pkg = context.packageName

        val layoutId = res.getIdentifier("widget_today_layout", "layout", pkg)
        val listId = res.getIdentifier("widget_today_list", "id", pkg)
        val bgImageId = res.getIdentifier("widget_background_image", "id", pkg)

        val c1Str = widgetData.getString("widget_c1", "#222222") ?: "#222222"
        val c2Str = widgetData.getString("widget_c2", "#222222") ?: "#222222"
        val c3Str = widgetData.getString("widget_c3", "#222222") ?: "#222222"

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

                val shader = LinearGradient(
                    0f, 0f, widthPx.toFloat(), heightPx.toFloat(),
                    intArrayOf(Color.parseColor(c1Str), Color.parseColor(c2Str), Color.parseColor(c3Str)),
                    floatArrayOf(0.0f, 0.5f, 1.0f),
                    Shader.TileMode.CLAMP
                )
                val paint = Paint().apply {
                    this.shader = shader
                    isAntiAlias = true
                }
                val rectF = RectF(0f, 0f, widthPx.toFloat(), heightPx.toFloat())
                val cornerRadius = 26f * density
                canvas.drawRoundRect(rectF, cornerRadius, cornerRadius, paint)

                if (bgImageId != 0) { views.setImageViewBitmap(bgImageId, bitmap) }
            } catch (e: Exception) {
                Log.e("TodayWidgetProvider", "⚠️ 背景生成スキップ", e)
                if (bgImageId != 0) { views.setInt(bgImageId, "setBackgroundColor", Color.parseColor(c1Str)) }
            }

            try {
                // ─── 🟢 修正：ListViewがキャッシュをサボらないよう、IntentにユニークなDataを付与 ───
                val intent = Intent(context, WidgetListViewService::class.java).apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                    putExtra("data_key", "today_json")
                    // ★ ここにポイント：現在の時刻をURIに含めて毎回Intentを別物にする
                    data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME) + "/" + System.currentTimeMillis().toString())
                }
                views.setRemoteAdapter(listId, intent)

                val launchIntent = Intent().apply {
                    setClassName(pkg, "$pkg.MainActivity")
                    action = "es.antonborri.home_widget.action.LAUNCH"
                }
                val pendingIntent = PendingIntent.getActivity(
                    context, 102, launchIntent,
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
                appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, listId)
            } catch (e: Exception) {
                Log.e("TodayWidgetProvider", "リストシステム結線エラー", e)
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