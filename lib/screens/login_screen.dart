import 'dart:io'; // ★ 追加：OSを判定するために必要
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/app_theme.dart';
import '../services/auth_service.dart';
import '../utils/lms_adapter.dart';
//login_screen.dart

class OktaLoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const OktaLoginScreen({super.key, required this.onLoginSuccess});
  @override State<OktaLoginScreen> createState() => _OktaLoginScreenState();
}


class _OktaLoginScreenState extends State<OktaLoginScreen> {
  bool _isSuccessTriggered = false;

  @override
  void initState() {
    super.initState();
    _clearWebViewCache(); // ★ 追加：画面を開くたびにキャッシュとCookieを大掃除する
  }

  // ★ 追加：古いエラー状態を引き継がないための大掃除処理
  Future<void> _clearWebViewCache() async {
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (e) {
      debugPrint("Cookie clear error: $e");
    }
  }

  Future<void> _checkLoginStatus(Uri? url) async {
    if (url == null || _isSuccessTriggered) return;

    // 完全に一致しなくても、lms.keio.jpドメインに到達していればチェックを開始
    if (url.host.contains('lms.keio.jp')) {
      try {
        // ★ 解決の鍵：iOSのCookie同期遅延対策として、0.5秒おきに最大5回（2.5秒間）確認を繰り返す
        for (int i = 0; i < 5; i++) {
          if (_isSuccessTriggered || !mounted) return;

          final cookies = await CookieManager.instance().getCookies(url: WebUri(canvasBaseUrl));

          if (cookies.any((c) => c.name.contains('canvas_session') || c.name == '_csrf_token')) {
            final cookieString = cookies.map((c) => "${c.name}=${c.value}").join("; ");
            final isValid = await AuthService.validateSession(cookieString);

            if (isValid && !_isSuccessTriggered) {
              _isSuccessTriggered = true;
              await AuthService.saveSession(cookieString);
              if (mounted) {
                Navigator.pop(context);
                widget.onLoginSuccess();
              }
              return; // 成功したらループを抜けて完了
            }
          }

          // Cookieがまだ同期されていない、またはセッションが無効な場合は少し待って再トライ
          await Future.delayed(const Duration(milliseconds: 500));
        }
      } catch (e) {
        debugPrint("Check Login Status Error: $e");
      }
    }
  }

  @override Widget build(BuildContext context) {
    // ★ 追加：Oktaの「WebView弾き」を完全に回避するための偽装User-Agent
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
                    userAgent: fakeUserAgent, // ★ ここで偽装！
                    cacheEnabled: false,      // ★ キャッシュを使わない
                    clearCache: true          // ★ 開くときにキャッシュをクリア
                ),
                onLoadStop: (c, url) => _checkLoginStatus(url),
                onUpdateVisitedHistory: (c, url, isR) => _checkLoginStatus(url)
            )
        )
    );
  }
}

