import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

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
  Timer? _pollingTimer;
  InAppWebViewController? _webViewController;
  bool _isInitialized = false;

  // 🟢 iOS App Group 読み取り用 MethodChannel
  static const _appGroupChannel = MethodChannel('com.h.k.portal/app_group');

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _prepareLoginScreenAndroid();
    } else if (Platform.isIOS) {
      setState(() {
        _isInitialized = true;
      });
      _startCookiePolling(); // iOS: App Group 監視スタート
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  // 🤖 Android用：既存のキャッシュ・クッキー一掃処理
  Future<void> _prepareLoginScreenAndroid() async {
    await _clearWebViewCache();
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
      _startCookiePolling();
    }
  }

  Future<void> _clearWebViewCache() async {
    try {
      final cookieManager = CookieManager.instance();
      await cookieManager.deleteAllCookies();

      final storageManager = WebStorageManager.instance();
      if (Platform.isAndroid) {
        await storageManager.android.deleteAllData();
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

      if (Platform.isAndroid) {
        await _checkAndValidateAndroidCookies();
      } else if (Platform.isIOS) {
        await _checkAndValidateIosAppGroupCookies();
      }
    });
  }

  // 🤖 Android：従来の WebView からクッキーを回収
  Future<void> _checkAndValidateAndroidCookies() async {
    if (_webViewController == null || _isSuccessTriggered) return;

    try {
      final currentUrl = await _webViewController!.getUrl();
      if (currentUrl == null) return;
      final urlString = currentUrl.toString();

      bool isInsideCanvasDashboard = urlString.startsWith(canvasBaseUrl) &&
          !urlString.contains('/login') &&
          !urlString.contains('/saml');

      if (isInsideCanvasDashboard) {
        final String? jsCookie = await _webViewController!.evaluateJavascript(source: "document.cookie");
        final cookies = await CookieManager.instance().getCookies(url: WebUri(canvasBaseUrl));
        final String managerCookie = cookies.map((c) => "${c.name}=${c.value}").join("; ");

        String? cookieString = "${jsCookie ?? ''}; $managerCookie";
        await _validateAndSave(cookieString);
      }
    } catch (e) {
      debugPrint("Android Cookie check error: $e");
    }
  }

  // 🍎 iOS：Safari Web Extension が書き込んだ App Group (UserDefaults) から回収
  Future<void> _checkAndValidateIosAppGroupCookies() async {
    if (_isSuccessTriggered) return;

    try {
      final String? appGroupCookie = await _appGroupChannel.invokeMethod<String>('getAppGroupCookie');
      if (appGroupCookie != null && appGroupCookie.isNotEmpty) {
        await _validateAndSave(appGroupCookie);
      }
    } catch (e) {
      debugPrint("iOS AppGroup Cookie check error: $e");
    }
  }

  // 🟢 共通：クッキーの有効性を確認してログイン完了へ導く
  Future<void> _validateAndSave(String cookieString) async {
    final isValid = await AuthService.validateSession(cookieString);

    if (isValid && !_isSuccessTriggered && mounted) {
      _isSuccessTriggered = true;

      _pollingTimer?.cancel();
      _pollingTimer = null;

      if (Platform.isAndroid && _webViewController != null) {
        try {
          await _webViewController!.stopLoading();
          await _webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri("about:blank")));
        } catch (_) {}
      }

      if (Platform.isIOS) {
        // 使用済み App Group クッキーの消去
        await _appGroupChannel.invokeMethod('clearAppGroupCookie');
      }

      await AuthService.saveSession(cookieString);

      if (mounted) {
        Navigator.pop(context);
        widget.onLoginSuccess();
      }
    }
  }

  Future<void> _launchSafariLogin() async {
    final Uri url = Uri.parse(canvasBaseUrl);

    // externalApplication で起動（デフォルトブラウザがSafariでない場合はChromeが開くため、案内に「Safariで開いてください」と明記するのが最も確実です）
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: AppTheme.bg(context),
        appBar: AppBar(
          backgroundColor: AppTheme.panel(context),
          elevation: 0,
          leading: IconButton(
              icon: Icon(Icons.close, color: AppTheme.textMain(context)),
              onPressed: () => Navigator.pop(context)
          ),
          title: Text("lms.keio.jp login", style: TextStyle(color: AppTheme.textMain(context), fontSize: 14)),
          centerTitle: true,
        ),
        body: SafeArea(
            child: Platform.isIOS
                ? _buildIosPasskeyGuidance()
                : !_isInitialized
                ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
                : _buildAndroidWebView()
        )
    );
  }

  // 🤖 Android用 WebView
  Widget _buildAndroidWebView() {
    const fakeUserAgent = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

    return InAppWebView(
        onWebViewCreated: (controller) => _webViewController = controller,
        initialUrlRequest: URLRequest(url: WebUri(canvasBaseUrl)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          thirdPartyCookiesEnabled: true,
          sharedCookiesEnabled: true,
          supportMultipleWindows: true,
          javaScriptCanOpenWindowsAutomatically: true,
          userAgent: fakeUserAgent,
          clearCache: true,
          clearSessionCache: true,
          cacheEnabled: false,
        ),
        onLoadStop: (controller, url) => _checkAndValidateAndroidCookies(),
        onUpdateVisitedHistory: (controller, url, isReload) => _checkAndValidateAndroidCookies()
    );
  }

  // 🍎 iOS用 パキーログインガイド UI
  Widget _buildIosPasskeyGuidance() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.fingerprint, size: 72, color: AppTheme.accent),
          const SizedBox(height: 20),
          Text(
            "Safariでパスキーログイン",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textMain(context)),
          ),
          const SizedBox(height: 12),
          Text(
            "Safariでパスキー（Face ID / Touch ID）を使ってログインしてください。認証が完了すると、自動的にアプリへ同期されます。",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppTheme.textSub(context)),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _launchSafariLogin,
            icon: const Icon(Icons.open_in_browser),
            label: const Text("Safariを開いてパスキーログイン"),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}