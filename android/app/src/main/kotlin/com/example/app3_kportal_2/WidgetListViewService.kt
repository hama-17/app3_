package com.example.app3_kportal_2

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray
import org.json.JSONException

class WidgetListViewService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        val dataKey = intent.getStringExtra("data_key") ?: ""
        return WidgetListViewFactory(applicationContext, dataKey)
    }
}

class WidgetListViewFactory(private val context: Context, private val dataKey: String) : RemoteViewsService.RemoteViewsFactory {
    private var itemList = mutableListOf<Pair<String, String>>()
    private val res = context.resources
    private val pkg = context.packageName

    // 💡 リストの行パーツも名前から動的にID解決
    private val rowLayoutId = res.getIdentifier("widget_item_row", "layout", pkg)
    private val titleId = res.getIdentifier("item_title", "id", pkg)
    private val subId = res.getIdentifier("item_sub", "id", pkg)

    private fun loadDataFromFlutter() {
        itemList.clear()
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val jsonStr = prefs.getString(dataKey, "[]") ?: "[]"

        try {
            val jsonArray = JSONArray(jsonStr)
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                val title = obj.optString("title", "")
                val sub = obj.optString("sub", "")
                itemList.add(Pair(title, sub))
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
            views.setTextViewText(titleId, item.first)
            views.setTextViewText(subId, item.second)
        }
        return views
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = true
}