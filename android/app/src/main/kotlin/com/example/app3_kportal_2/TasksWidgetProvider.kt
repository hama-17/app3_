package com.example.app3_kportal_2

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class TasksWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        val res = context.resources
        val pkg = context.packageName

        // 💡 魔法のコード：Rクラスを使わず、文字列からネイティブIDを安全に一瞬で引っ張る
        val layoutId = res.getIdentifier("widget_tasks_layout", "layout", pkg)
        val listId = res.getIdentifier("widget_tasks_list", "id", pkg)

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(pkg, layoutId)

            val intent = Intent(context, WidgetListViewService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                putExtra("data_key", "tasks_json")
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }

            views.setRemoteAdapter(listId, intent)
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, listId)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}