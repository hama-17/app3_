package com.hk_app3_k.portal

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class HomeWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_layout).apply {
                // Flutterの「widget_class_name」キーからデータを取得して反映
                setTextViewText(R.id.widget_class_name, widgetData.getString("widget_class_name", "予定なし"))
                // Flutterの「widget_room」キーからデータを取得して反映
                setTextViewText(R.id.widget_room, widgetData.getString("widget_room", "教室情報なし"))
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}