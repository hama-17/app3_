// 👇 元々書いてあった package の行はそのまま残してください！
package com.hk_app3_k.portal

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.webkit.CookieManager

class MainActivity: FlutterActivity() {
    // Flutterと通信するためのチャンネル名
    private val CHANNEL = "com.example.app/cookie"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Flutterから「getCookies」と呼ばれたら動く処理
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getCookies") {
                // 引数からURLを受け取る
                val url = call.argument<String>("url")
                // Android標準機能を使って、そのURLのクッキー（HttpOnly含む）を全部取得
                val cookies = CookieManager.getInstance().getCookie(url)

                // Flutterに返す（nullなら空文字を返す）
                result.success(cookies ?: "")
            } else {
                result.notImplemented()
            }
        }
    }
}