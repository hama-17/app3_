import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'auth_service.dart'; // パスは適宜合わせてください
import '../utils/lms_adapter.dart';
//silent_refresh_service.dart
class LmsSilentRefreshService {
  static HeadlessInAppWebView? _headlessWebView;

  /// 裏方隠しWebViewを起動し、Oktaのブラウザセッションを利用して新しいCookieを全自動で奪還する
  static Future<bool> trySilentRefresh() async {
    final completer = Completer<bool>();
    bool isSettled = false;

    debugPrint("🔄 [SSO Engine] 24時間制限の壁を突破するため、サイレントリフレッシュ回路を起動します...");

    _headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(canvasBaseUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        thirdPartyCookiesEnabled: true,
      ),
      onLoadStop: (controller, url) async {
        // 隠しブラウザのロードが進むたびに、Canvasの最新クッキーが降臨したかスキャン
        final cookies = await CookieManager.instance().getCookies(url: WebUri(canvasBaseUrl));
        final String cookieString = cookies.map((c) => "${c.name}=${c.value}").join("; ");

        if (cookieString.contains('canvas_session')) {
          final isValid = await AuthService.validateSession(cookieString);
          if (isValid && !isSettled) {
            isSettled = true;

            // 新しい24時間寿命の命をSecureStorageへ上書き保存
            await AuthService.saveSession(cookieString);
            debugPrint("🟢 [SSO Engine] 自動SSO延長に大成功しました。新しいセッションCookieをSecureStorageへコミットしました。");

            if (!completer.isCompleted) completer.complete(true);
          }
        }
      },
    );

    // 裏方ブラウザを物理着火
    await _headlessWebView?.run();

    // ⏳ タイムアウトスタビライザー（5秒待っても通らない場合はOkta自体の命も切れているので手動へ）
    final bool result = await completer.future.timeout(const Duration(seconds: 5), onTimeout: () {
      if (!isSettled) {
        isSettled = true;
        debugPrint("❌ [SSO Engine] Oktaのセッションも完全に切れているため、自動延長を断念し手動ログインを要求します。");
        return false;
      }
      return false;
    });

    // メモリ解放（お掃除）
    await _headlessWebView?.dispose();
    _headlessWebView = null;

    return result;
  }
}