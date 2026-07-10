import 'dart:io';
import 'dart:async'; // タイマーを使用
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/app_theme.dart';
import '../services/auth_service.dart';
import '../utils/lms_adapter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

//login_screen.dartの本文です。


class OktaLoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const OktaLoginScreen({super.key, required this.onLoginSuccess});
  @override State<OktaLoginScreen> createState() => _OktaLoginScreenState();
}



class _OktaLoginScreenState extends State<OktaLoginScreen> {
  bool _isSuccessTriggered = false;
  Timer? _pollingTimer;
  InAppWebViewController? _webViewController;
  bool _isInitialized = false;

  // 🟢 追記：タイマーの多重衝突を物理的に防ぐためのロックフラグ
  bool _isValidating = false; // ★ フライング防止用の初期化フラグ

  @override
  void initState() {
    super.initState();
    _prepareLoginScreen(); // 古いキャッシュやクッキーを完全に消し去ってから起動
  }

  @override
  void dispose() {
    _pollingTimer?.cancel(); // 閉じたらタイマーを確実に止める
    super.dispose();
  }

  // ★ 解決の鍵：古いクッキーの削除が「完全に終わるまで」WebViewの描画とタイマーの始動をカチッと待機させる
  Future<void> _prepareLoginScreen() async {
    await _clearWebViewCache();
    if (mounted) {
      setState(() {
        _isInitialized = true; // お掃除完了！WebView解禁
      });
      _startCookiePolling(); // クリーンな状態で安全に監視を開始
    }
  }

  // 差し替え対象の関数
  Future<void> _clearWebViewCache() async {
    try {
      final cookieManager = CookieManager.instance();
      final url = WebUri(canvasBaseUrl);

      // 🎯 Okta(auth.keio.jp)のSSOクッキーは絶対に消さず、
      // 命の切れたLMSのセッション残骸だけをピンポイントで爆破します。
      final cookies = await cookieManager.getCookies(url: url);
      for (var cookie in cookies) {
        if (cookie.name == 'canvas_session' || cookie.name == '_csrf_token') {
          await cookieManager.deleteCookie(url: url, name: cookie.name);
        }
      }
      debugPrint("🛡️ [SSO Shield] Oktaのセッションを保護しつつ、LMSのクッキーのみをお掃除しました。");
    } catch (e) {
      debugPrint("Targeted cookie clear error: $e");
    }
  }

  // 裏で常にCookieを監視し続けるメソッド
  void _startCookiePolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_isSuccessTriggered || !mounted) {
        timer.cancel();
        return;
      }
      await _checkAndValidateCookies();
    });
  }

  // Cookieを引っこ抜いて検証・即時クリーニングする処理
  // 差し替え対象の関数
  // 差し替え対象の関数
  // login_screen.dart 内の同名関数をこの内容に丸ごと差し替えてください
  Future<void> _checkAndValidateCookies() async {
    if (_webViewController == null || _isSuccessTriggered) return;

    try {
      // 1. 現在のURLを取得
      final currentUrl = await _webViewController!.getUrl();
      if (currentUrl == null) return;
      final urlString = currentUrl.toString();

      // 2. 🎯 URLガード：Oktaの認証ドメインやLMSのログイン画面の中にいる間は、タイマーを完全に無視（スルー）する
      // これにより、ログイン前の _csrf_token によるフライング暴発を100%封殺します。
      bool isInsideCanvasDashboard = urlString.startsWith(canvasBaseUrl) &&
          !urlString.contains('/login') &&
          !urlString.contains('/saml');

      if (isInsideCanvasDashboard) {
        // 3. あなたの元のコードと100%同じ、最も安定した結合方式でクッキーを回収
        final String? jsCookie = await _webViewController!.evaluateJavascript(source: "document.cookie");
        final cookies = await CookieManager.instance().getCookies(url: WebUri(canvasBaseUrl));
        final String managerCookie = cookies.map((c) => "${c.name}=${c.value}").join("; ");

        String? cookieString = "${jsCookie ?? ''}; $managerCookie";

        // 4. セッション検証
        final isValid = await AuthService.validateSession(cookieString);

        if (isValid && !_isSuccessTriggered && mounted) {
          _isSuccessTriggered = true;

          _pollingTimer?.cancel();
          _pollingTimer = null;

          try {
            await _webViewController!.stopLoading();
            await _webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri("about:blank")));
          } catch (_) {}

          await AuthService.saveSession(cookieString);
          cookieString = null;

          if (mounted) {
            Navigator.pop(context);
            widget.onLoginSuccess();
          }
        }
      }
    } catch (e) {
      debugPrint("Cookie check error: $e");
    }
  }

  @override Widget build(BuildContext context) {
    // 🟢 修正：余計なインプットブラウザ臭を完全に消し去った、純度100%のネイティブSafari17.5のUAへ偽装
    final String fakeUserAgent = Platform.isIOS
        ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1'
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
        // クッキーの完全お掃除が終わるまでは、インジケータを回してフライング誤検知を100%ブロックします
        body: SafeArea(
            child: !_isInitialized
                ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
                : InAppWebView(
                onWebViewCreated: (controller) => _webViewController = controller,
                initialUrlRequest: URLRequest(url: WebUri(canvasBaseUrl)),
                // ─── 🟢 修正：InAppWebViewSettings の内部 ───
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  thirdPartyCookiesEnabled: true,
                  sharedCookiesEnabled: true, // 🟢 追記：アプリ全体（ネイティブとブラウザ間）でのクッキーの即時共有・同期を許可
                  supportMultipleWindows: true,
                  javaScriptCanOpenWindowsAutomatically: true,
                  userAgent: fakeUserAgent,
                ),
                onLoadStop: (controller, url) {
                  _checkAndValidateCookies();
                },
                onUpdateVisitedHistory: (controller, url, isReload) {
                  _checkAndValidateCookies();
                }
            )
        )
    );
  }
}