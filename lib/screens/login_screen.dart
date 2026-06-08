import 'dart:io';
import 'dart:async'; // ★ 追加：タイマーを使うために必要
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/app_theme.dart';
import '../services/auth_service.dart';
import '../utils/lms_adapter.dart';

class OktaLoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const OktaLoginScreen({super.key, required this.onLoginSuccess});
  @override State<OktaLoginScreen> createState() => _OktaLoginScreenState();
}

class _OktaLoginScreenState extends State<OktaLoginScreen> {
  bool _isSuccessTriggered = false;
  Timer? _pollingTimer; // ★ 追加：裏で監視し続けるタイマー

  @override
  void initState() {
    super.initState();
    _clearWebViewCache();
    _startCookiePolling(); // ★ 追加：画面を開いた瞬間からCookieの監視をスタート！
  }

  @override
  void dispose() {
    _pollingTimer?.cancel(); // ★ 追加：画面が閉じたらタイマーを安全に停止
    super.dispose();
  }

  Future<void> _clearWebViewCache() async {
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (e) {
      debugPrint("Cookie clear error: $e");
    }
  }

  // ★ 追加：WebViewの動きに関係なく、1秒に1回強制的にCookieをチェックする最強のメソッド
  void _startCookiePolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      // すでに成功したか、画面が閉じられていればタイマー終了
      if (_isSuccessTriggered || !mounted) {
        timer.cancel();
        return;
      }

      try {
        // lms.keio.jp に紐づくCookieを取得（iOSの遅延に関係なく、存在するタイミングで取れる）
        final cookies = await CookieManager.instance().getCookies(url: WebUri(canvasBaseUrl));

        // ログインの証である canvas_session か _csrf_token が発行されているかチェック
        if (cookies.any((c) => c.name.contains('canvas_session') || c.name == '_csrf_token')) {
          final cookieString = cookies.map((c) => "${c.name}=${c.value}").join("; ");

          // 本当に有効なセッションかAPIを叩いて確認する
          final isValid = await AuthService.validateSession(cookieString);

          if (isValid && !_isSuccessTriggered && mounted) {
            _isSuccessTriggered = true;
            timer.cancel(); // 成功したらタイマーを止める

            await AuthService.saveSession(cookieString); // 保存
            Navigator.pop(context); // WebViewを閉じる
            widget.onLoginSuccess(); // ホーム画面を更新
          }
        }
      } catch (e) {
        debugPrint("Cookie polling error: $e");
      }
    });
  }

  @override Widget build(BuildContext context) {
    final String fakeUserAgent = Platform.isIOS
        ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1'
        : 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

    return Scaffold(
        backgroundColor: AppTheme.bg(context),
        appBar: AppBar(
          backgroundColor: AppTheme.panel(context),
          elevation: 0,
          leading: IconButton(
              icon: Icon(Icons.close, color: AppTheme.textMain(context)),
              onPressed: () => Navigator.pop(context)
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 6),
              Text("lms.keio.jp login", style: TextStyle(color: AppTheme.textMain(context), fontSize: 14)),
            ],
          ),
          centerTitle: true,
        ),
        body: SafeArea(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(canvasBaseUrl)),
              initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  thirdPartyCookiesEnabled: true,
                  sharedCookiesEnabled: true,
                  supportMultipleWindows: true,
                  javaScriptCanOpenWindowsAutomatically: true,
                  userAgent: fakeUserAgent,
                  cacheEnabled: false,
                  clearCache: true
              ),
              // ★ 修正：onLoadStopなどのイベントに依存してチェックするのをやめる。
              // タイマーが裏で常に監視しているので、WebView側からは何も報告させなくてOK。
            )
        )
    );
  }
}