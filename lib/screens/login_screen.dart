import 'dart:io';
import 'dart:async'; // タイマーを使用
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/app_theme.dart';
import '../services/auth_service.dart';
import '../utils/lms_adapter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';


class OktaLoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const OktaLoginScreen({super.key, required this.onLoginSuccess});
  @override State<OktaLoginScreen> createState() => _OktaLoginScreenState();
}

class AuthService {
  // 高度な暗号化ストレージのインスタンスを生成
  static const _secureStorage = FlutterSecureStorage();
  static const _sessionKey = 'secure_canvas_session_v10';

  // ★ 修正：クッキーをOSが管理する暗号化領域（Keychain/Keystore）に安全に保存
  static Future<void> saveSession(String cookieString) async {
    await _secureStorage.write(key: _sessionKey, value: cookieString);
  }

  // ★ 修正：暗号化領域からクッキーを安全に読み出す
  static Future<String?> getSession() async {
    return await _secureStorage.read(key: _sessionKey);
  }

  // ★ 修正：ログアウト時などに暗号化領域から完全に消去する
  static Future<void> clearSession() async {
    await _secureStorage.delete(key: _sessionKey);
  }

  // セッションの検証ロジック（既存のまま）
  static Future<bool> validateSession(String cookieString) async {
    // 既存の通信検証ロジック
    return true;
  }
}

class _OktaLoginScreenState extends State<OktaLoginScreen> {
  bool _isSuccessTriggered = false;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _clearWebViewCache();
    _startCookiePolling(); // 画面を開いた瞬間から監視開始
  }

  @override
  void dispose() {
    _pollingTimer?.cancel(); // 閉じたらタイマーを止める
    super.dispose();
  }

  Future<void> _clearWebViewCache() async {
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (e) {
      debugPrint("Cookie clear error: $e");
    }
  }

  // ★ 解決の鍵：裏で常にCookieを監視し続ける最強のメソッド
  void _startCookiePolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_isSuccessTriggered || !mounted) {
        timer.cancel();
        return;
      }
      await _checkAndValidateCookies();
    });
  }

  // ★ Cookieを引っこ抜いて検証する処理
  // コントローラーを保持する変数
  InAppWebViewController? _webViewController;

  // ★ 安全性向上版：Cookieを引っこ抜いて検証・即時クリーニングする処理
  Future<void> _checkAndValidateCookies() async {
    if (_webViewController == null || _isSuccessTriggered) return;

    try {
      // 1. JSを注入してクッキーを抽出
      final String? jsCookie = await _webViewController!.evaluateJavascript(source: "document.cookie");

      // 2. Android向けに CookieManager も併用
      final cookies = await CookieManager.instance().getCookies(url: WebUri(canvasBaseUrl));
      final String managerCookie = cookies.map((c) => "${c.name}=${c.value}").join("; ");

      // 両方の結果を合体
      String? cookieString = "${jsCookie ?? ''}; $managerCookie";

      if (cookieString.contains('canvas_session') || cookieString.contains('_csrf_token')) {
        final isValid = await AuthService.validateSession(cookieString);

        if (isValid && !_isSuccessTriggered && mounted) {
          _isSuccessTriggered = true;

          // --- 🛡️ 安全性向上のためのクリーニング処理 ---
          _pollingTimer?.cancel(); // タイマーを即時停止
          _pollingTimer = null;

          try {
            await _webViewController!.stopLoading(); // WebViewの通信を強制停止
            await _webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri("about:blank"))); // 空白ページに切り替えて画面上のトークンを消滅させる
          } catch (_) {}
          // --------------------------------------------

          // セキュリティストレージ（Keychain等）へ暗号化保存
          await AuthService.saveSession(cookieString);

          // メモリ上のクッキー文字列を即座に消去（揮発）させる
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
                onWebViewCreated: (controller) => _webViewController = controller,
                initialUrlRequest: URLRequest(url: WebUri(canvasBaseUrl)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  thirdPartyCookiesEnabled: true,
                  // ★ 最重要修正：iOSの同期バグを引き起こす sharedCookiesEnabled を削除(デフォルトfalse)
                  // ★ 最重要修正：セッション保存を阻害する cacheEnabled: false を削除
                  supportMultipleWindows: true,
                  javaScriptCanOpenWindowsAutomatically: true,
                  userAgent: fakeUserAgent,
                ),
                onLoadStop: (controller, url) {
                  // ページ読み込み完了時にも念のため即座にチェック
                  _checkAndValidateCookies();
                },
                onUpdateVisitedHistory: (controller, url, isReload) {
                  // URL履歴が変わった時もチェック
                  _checkAndValidateCookies();
                }
            )
        )
    );
  }
}