package com.example.app3_kportal_2

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONException

class WidgetListViewService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        val dataKey = intent.getStringExtra("data_key") ?: ""
        return WidgetListViewFactory(applicationContext, dataKey)
    }
}

class WidgetListViewFactory(private val context: Context, private val dataKey: String) : RemoteViewsService.RemoteViewsFactory {
    private var itemList = mutableListOf<Map<String, String>>()
    private val res = context.resources
    private val pkg = context.packageName

    private val rowLayoutId = if (dataKey == "today_json") {
        res.getIdentifier("widget_item_row_today", "layout", pkg)
    } else {
        res.getIdentifier("widget_item_row_tasks", "layout", pkg)
    }

    private val titleId = res.getIdentifier("item_title", "id", pkg)
    private val subId = res.getIdentifier("item_sub", "id", pkg)
    private val subjectId = res.getIdentifier("item_subject", "id", pkg)
    private val dueTimeId = res.getIdentifier("item_due_time", "id", pkg)

    private val endTimeId = res.getIdentifier("item_end_time", "id", pkg)
    private val roomId = res.getIdentifier("item_room", "id", pkg)
    private val dateLabelId = res.getIdentifier("item_date_label", "id", pkg)

    private fun loadDataFromFlutter() {
        itemList.clear()
        // ─── 🟢 修正：プラグイン公式のデータストアに完全統一 ───
        val prefs = HomeWidgetPlugin.getData(context)
        val jsonStr = prefs.getString(dataKey, "[]") ?: "[]"

        try {
            val jsonArray = JSONArray(jsonStr)
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                itemList.add(mapOf(
                    "title" to obj.optString("title", ""),
                    "sub" to obj.optString("sub", ""),
                    "due_time" to obj.optString("due_time", ""),
                    "subject" to obj.optString("subject", ""),
                    "end_time" to obj.optString("end_time", ""),
                    "room" to obj.optString("room", ""),
                    "date_label" to obj.optString("date_label", ""),
                    "is_first_of_day" to obj.optString("is_first_of_day", "false"),
                    "page_route" to obj.optString("page_route", ""),
                    "is_task" to obj.optString("is_task", "false"),
                    "id" to obj.optString("id", "")
                ))
            }
        } catch (e: JSONException) {
            e.printStackTrace()
        }
    }

    override fun onCreate() { loadDataFromFlutter() }
    override fun onDataSetChanged() { loadDataFromFlutter() }
    override fun onDestroy() { itemList.clear() }
    override fun getCount(): Int = itemList.size

    override fun getViewAt(position: Int): RemoteViews {
        val views = RemoteViews(pkg, rowLayoutId)
        if (position < itemList.size) {
            val item = itemList[position]
            views.setTextViewText(titleId, item["title"])
            views.setTextViewText(subId, item["sub"])

            val currentNightMode = context.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK
            val isDark = currentNightMode == android.content.res.Configuration.UI_MODE_NIGHT_YES

            if (dataKey == "tasks_json") {
                val primaryColor = android.graphics.Color.parseColor(if (isDark) "#FFFFFF" else "#1C1C1E")
                val secondaryColor = android.graphics.Color.parseColor(if (isDark) "#8CFFFFFF" else "#8C1C1C1E")

                views.setTextColor(subId, primaryColor)
                if (dueTimeId != 0) { views.setTextViewText(dueTimeId, item["due_time"]); views.setTextColor(dueTimeId, secondaryColor) }
                views.setTextColor(titleId, primaryColor)
                if (subjectId != 0) { views.setTextViewText(subjectId, item["subject"]); views.setTextColor(subjectId, secondaryColor) }
            }
            else {
                if (endTimeId != 0) { views.setTextViewText(endTimeId, item["end_time"]) }
                if (roomId != 0) { views.setTextViewText(roomId, item["room"]) }

                if (dateLabelId != 0) {
                    if (item["is_first_of_day"] == "true") {
                        views.setViewVisibility(dateLabelId, android.view.View.VISIBLE)
                        views.setTextViewText(dateLabelId, item["date_label"])
                        views.setTextColor(dateLabelId, android.graphics.Color.WHITE)
                    } else {
                        views.setViewVisibility(dateLabelId, android.view.View.GONE)
                    }
                }

                if (item["is_task"] == "true") {
                    views.setTextViewTextSize(subId, android.util.TypedValue.COMPLEX_UNIT_SP, 14f)
                    if (endTimeId != 0) { views.setTextViewText(endTimeId, "") }

                    val rawTitle = item["title"] ?: ""
                    val spannable = android.text.SpannableString("●  $rawTitle")
                    spannable.setSpan(
                        android.text.style.ForegroundColorSpan(android.graphics.Color.parseColor("#FF3B30")),
                        0, 1, android.text.Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                    spannable.setSpan(
                        android.text.style.ForegroundColorSpan(android.graphics.Color.WHITE),
                        3, spannable.length, android.text.Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                    views.setTextViewText(titleId, spannable)
                } else {
                    views.setTextViewTextSize(subId, android.util.TypedValue.COMPLEX_UNIT_SP, 11f)
                    views.setTextViewText(titleId, item["title"])
                    views.setTextColor(titleId, android.graphics.Color.WHITE)
                }

                views.setTextColor(subId, android.graphics.Color.WHITE)
                if (endTimeId != 0) { views.setTextColor(endTimeId, android.graphics.Color.parseColor("#B3FFFFFF")) }
                if (roomId != 0) { views.setTextColor(roomId, android.graphics.Color.parseColor("#99FFFFFF")) }
            }

            val rowRootId = res.getIdentifier("widget_item_root", "id", pkg)
            if (rowRootId != 0) {
                val pageRoute = item["page_route"]?.takeIf { it.isNotEmpty() }
                    ?: (if (dataKey == "today_json") "course_detail" else "task_detail")

                val fillInIntent = Intent().apply {
                    data = Uri.parse("app3k://widget/$pageRoute?id=${item["id"]}")
                }
                views.setOnClickFillInIntent(rowRootId, fillInIntent)
            }
        }
        return views
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = true
}