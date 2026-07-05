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
import android.graphics.Rect
import android.graphics.Shader
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

class TimetableWidgetProvider : HomeWidgetProvider() {

    // 🟢 精密制御：授業名と教室名を別々にセキュアバインドする専用データ構造体
    private class CourseCellData(val title: String, val room: String, val id: String, val color: String)

    private fun parseColorSafe(colorStr: String?, fallbackColor: Int): Int {
        if (colorStr.isNullOrEmpty()) return fallbackColor
        return try { Color.parseColor(colorStr) } catch (e: Exception) { fallbackColor }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        try {
            val res = context.resources
            val pkg = context.packageName

            val layoutId = res.getIdentifier("widget_timetable_layout", "layout", pkg)
            val bgImageId = res.getIdentifier("widget_background_image", "id", pkg)
            val headerSatId = res.getIdentifier("header_sat", "id", pkg)
            val rowPeriod6Id = res.getIdentifier("row_period_6", "id", pkg)
            val cellRoundBgResId = res.getIdentifier("widget_cell_round_bg", "drawable", pkg)

            val prefs = HomeWidgetPlugin.getData(context)
            val c1Str = prefs.getString("widget_c1", "#1C1C1E") ?: "#1C1C1E"
            val c2Str = prefs.getString("widget_c2", "#111112") ?: "#111112"
            val c3Str = prefs.getString("widget_c3", "#000000") ?: "#000000"
            val timetableJsonStr = prefs.getString("timetable_matrix_json", "[]") ?: "[]"

            val c1 = parseColorSafe(c1Str, Color.parseColor("#1C1C1E"))
            val c2 = parseColorSafe(c2Str, Color.parseColor("#111112"))
            val c3 = parseColorSafe(c3Str, Color.parseColor("#000000"))

            val matrixA = Array(6) { Array(7) { CourseCellData("", "", "", "") } }
            val matrixB = Array(6) { Array(7) { CourseCellData("", "", "", "") } }

            var maxDayDetected = 4
            var maxPeriodDetected = 5

            try {
                val jsonArray = JSONArray(timetableJsonStr)
                for (i in 0 until jsonArray.length()) {
                    val obj = jsonArray.getJSONObject(i)
                    val day = obj.optInt("day", -1)
                    val period = obj.optInt("period", -1)
                    val titleStr = obj.optString("title", "")
                    val roomStr = obj.optString("room", "")
                    val courseId = obj.optString("id", "")
                    val cellColor = obj.optString("color", "")

                    if (day in 0..5 && period in 1..6) {
                        if (matrixA[day][period].title.isEmpty()) {
                            matrixA[day][period] = CourseCellData(titleStr, roomStr, courseId, cellColor)
                        } else {
                            matrixB[day][period] = CourseCellData(titleStr, roomStr, courseId, cellColor)
                        }
                        if (day > maxDayDetected) maxDayDetected = day
                        if (period > maxPeriodDetected) maxPeriodDetected = period
                    }
                }
            } catch (e: Exception) {}

            val widthPx = 128
            val heightPx = 128
            val bitmap = try {
                val b = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(b)
                val shader = LinearGradient(0f, 0f, widthPx.toFloat(), heightPx.toFloat(), intArrayOf(c1, c2, c3), floatArrayOf(0.0f, 0.5f, 1.0f), Shader.TileMode.CLAMP)
                val paint = Paint().apply { this.shader = shader; isAntiAlias = true }
                canvas.drawRect(Rect(0, 0, widthPx, heightPx), paint)
                b
            } catch (e: Exception) { null }

            for (appWidgetId in appWidgetIds) {
                val views = RemoteViews(pkg, layoutId)

                if (bgImageId != 0 && bitmap != null) { views.setImageViewBitmap(bgImageId, bitmap) }

                if (maxDayDetected < 5 && headerSatId != 0) { views.setViewVisibility(headerSatId, View.GONE) }
                else if (headerSatId != 0) { views.setViewVisibility(headerSatId, View.VISIBLE) }

                if (maxPeriodDetected < 6 && rowPeriod6Id != 0) { views.setViewVisibility(rowPeriod6Id, View.GONE) }
                else if (rowPeriod6Id != 0) { views.setViewVisibility(rowPeriod6Id, View.VISIBLE) }

                for (day in 0..5) {
                    for (period in 1..6) {
                        val containerStr = "container_${day}_${period}"
                        val containerResId = res.getIdentifier(containerStr, "id", pkg)

                        val cellIdStrA = "cell_${day}_${period}_a"
                        val cellIdStrB = "cell_${day}_${period}_b"
                        val cellResIdA = res.getIdentifier(cellIdStrA, "id", pkg)
                        val cellResIdB = res.getIdentifier(cellIdStrB, "id", pkg)

                        if (containerResId != 0) {
                            if (day == 5 && maxDayDetected < 5) {
                                views.setViewVisibility(containerResId, View.GONE)
                                continue
                            } else {
                                views.setViewVisibility(containerResId, View.VISIBLE)
                            }

                            val dataA = matrixA[day][period]
                            val dataB = matrixB[day][period]

                            if (dataA.title.isNotEmpty()) {
                                // ─── 🟢 スロットAの処理 ───
                                views.setViewVisibility(cellResIdA, View.VISIBLE)

                                val titleResIdA = res.getIdentifier("cell_${day}_${period}_a_title", "id", pkg)
                                val roomResIdA = res.getIdentifier("cell_${day}_${period}_a_room", "id", pkg)

                                views.setTextViewText(titleResIdA, dataA.title)
                                views.setTextViewText(roomResIdA, dataA.room)

                                if (cellRoundBgResId != 0) {
                                    views.setInt(cellResIdA, "setBackgroundResource", cellRoundBgResId)
                                    if (dataA.color.isNotEmpty()) {
                                        val cellColor = Color.parseColor(dataA.color)
                                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                                            views.setColorStateList(cellResIdA, "setBackgroundTintList", android.content.res.ColorStateList.valueOf(cellColor))
                                        } else { views.setInt(cellResIdA, "setBackgroundColor", cellColor) }

                                        // 自動文字反転処理をタイトル・教室の双方に完全同期適用
                                        val luminance = (Color.red(cellColor) * 0.299 + Color.green(cellColor) * 0.587 + Color.blue(cellColor) * 0.114)
                                        val targetTextCol = if (luminance > 180) Color.BLACK else Color.WHITE
                                        views.setTextColor(titleResIdA, targetTextCol)
                                        views.setTextColor(roomResIdA, targetTextCol.apply { Color.alpha(178) }) // 教室は若干柔らかい透過に
                                    }
                                }
                                if (dataA.id.isNotEmpty()) {
                                    val cellIntent = Intent().apply { setClassName(pkg, "$pkg.MainActivity"); action = "es.antonborri.home_widget.action.LAUNCH"; data = Uri.parse("app3k://widget/course_detail?id=${dataA.id}") }
                                    val requestCode = appWidgetId * 2000 + day * 20 + period * 2
                                    val pendingIntent = PendingIntent.getActivity(context, requestCode, cellIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
                                    views.setOnClickPendingIntent(cellResIdA, pendingIntent)
                                }

                                // ─── 🟢 スロットBの処理 ───
                                if (dataB.title.isNotEmpty()) {
                                    views.setViewVisibility(cellResIdB, View.VISIBLE)

                                    val titleResIdB = res.getIdentifier("cell_${day}_${period}_b_title", "id", pkg)
                                    val roomResIdB = res.getIdentifier("cell_${day}_${period}_b_room", "id", pkg)

                                    views.setTextViewText(titleResIdB, dataB.title)
                                    views.setTextViewText(roomResIdB, dataB.room)

                                    if (cellRoundBgResId != 0) {
                                        views.setInt(cellResIdB, "setBackgroundResource", cellRoundBgResId)
                                        if (dataB.color.isNotEmpty()) {
                                            val cellColor = Color.parseColor(dataB.color)
                                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                                                views.setColorStateList(cellResIdB, "setBackgroundTintList", android.content.res.ColorStateList.valueOf(cellColor))
                                            } else { views.setInt(cellResIdB, "setBackgroundColor", cellColor) }

                                            val luminance = (Color.red(cellColor) * 0.299 + Color.green(cellColor) * 0.587 + Color.blue(cellColor) * 0.114)
                                            val targetTextCol = if (luminance > 180) Color.BLACK else Color.WHITE
                                            views.setTextColor(titleResIdB, targetTextCol)
                                            views.setTextColor(roomResIdB, targetTextCol.apply { Color.alpha(178) })
                                        }
                                    }
                                    if (dataB.id.isNotEmpty()) {
                                        val cellIntent = Intent().apply { setClassName(pkg, "$pkg.MainActivity"); action = "es.antonborri.home_widget.action.LAUNCH"; data = Uri.parse("app3k://widget/course_detail?id=${dataB.id}") }
                                        val requestCode = appWidgetId * 2000 + day * 20 + period * 2 + 1
                                        val pendingIntent = PendingIntent.getActivity(context, requestCode, cellIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
                                        views.setOnClickPendingIntent(cellResIdB, pendingIntent)
                                    }
                                } else {
                                    views.setViewVisibility(cellResIdB, View.GONE)
                                }
                            } else {
                                views.setViewVisibility(cellResIdA, View.GONE)
                                views.setViewVisibility(cellResIdB, View.GONE)
                            }
                        }
                    }
                }

                val mainIntent = Intent().apply { setClassName(pkg, "$pkg.MainActivity"); action = "es.antonborri.home_widget.action.LAUNCH"; data = Uri.parse("app3k://widget/main") }
                val mainPendingIntent = PendingIntent.getActivity(context, appWidgetId, mainIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
                if (bgImageId != 0) { views.setOnClickPendingIntent(bgImageId, mainPendingIntent) }

                appWidgetManager.updateAppWidget(appWidgetId, views)
            }
        } catch (e: Exception) {}
    }
}