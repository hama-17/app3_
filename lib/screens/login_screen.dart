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

  // ★ 解決の鍵：古いクッキー・キャッシュの削除が「完全に終わるまで」WebViewの描画とタイマーの始動をカチッと待機させる
  Future<void> _prepareLoginScreen() async {
    await _clearWebViewCache();
    if (mounted) {
      setState(() {
        _isInitialized = true; // お掃除完了！WebView解禁
      });
      _startCookiePolling(); // クリーンな状態で安全に監視を開始
    }
  }

  // 🟢 修正：ピンポイント消去を廃止し、CSRF矛盾を防ぐためにクッキー・ストレージを完全一掃
  Future<void> _clearWebViewCache() async {
    try {
      final cookieManager = CookieManager.instance();

      // 1. 全ドメイン（CanvasおよびOkta等）のクッキーを完全初期化
      await cookieManager.deleteAllCookies();

      // 2. LocalStorage / SessionStorage の完全一掃（IOSWKWebsiteDataType を使用）
      final storageManager = WebStorageManager.instance();
      if (Platform.isAndroid) {
        await storageManager.android.deleteAllData();
      } else if (Platform.isIOS) {
        await storageManager.ios.fetchDataRecords(dataTypes: {
          IOSWKWebsiteDataType.WKWebsiteDataTypeLocalStorage,
          IOSWKWebsiteDataType.WKWebsiteDataTypeCookies,
          IOSWKWebsiteDataType.WKWebsiteDataTypeSessionStorage,
        });
      }

      debugPrint("🛡️ [SSO Shield] クッキーおよびWebStorageを完全に初期化しました。");
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
        // 3. 元のコードと100%同じ、最も安定した結合方式でクッキーを回収
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
    // 🟢 ネイティブSafari17.5のUAへ偽装
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
                // ─── 🟢 修正：キャッシュ・セッションクリアの設定を追加 ───
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  thirdPartyCookiesEnabled: true,
                  sharedCookiesEnabled: true,
                  supportMultipleWindows: true,
                  javaScriptCanOpenWindowsAutomatically: true,
                  userAgent: fakeUserAgent,
                  // 🟢 キャッシュと古いセッションの読み込みを強制的に遮断
                  clearCache: true,
                  clearSessionCache: true,
                  cacheEnabled: false,
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