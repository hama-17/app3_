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

class _OktaLoginScreenState extends State<OktaLoginScreen> with WidgetsBindingObserver {
  bool _isSuccessTriggered = false;
  Timer? _pollingTimer;
  InAppWebViewController? _webViewController;
  bool _isInitialized = false;
  String _statusText = "初期化中...";

  static const _appGroupChannel = MethodChannel('com.h.k.portal/app_group');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (Platform.isAndroid) {
      _prepareLoginScreenAndroid();
    } else if (Platform.isIOS) {
      _prepareLoginScreenIos();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Platform.isIOS) {
      _checkAndValidateIosAppGroupCookies();
    }
  }

  // 🍎 iOS：画面起動時に App Group の古いクッキーを消去してから監視開始
  Future<void> _prepareLoginScreenIos() async {
    await _clearAppGroupCookie();
    if (mounted) {
      setState(() {
        _isInitialized = true;
        _statusText = "🟡 [${_getTimeStr()}] App Group監視中\n(Cookie未検出 / Safariでログイン完了待ち)";
      });
      _startCookiePolling();
    }
  }

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
    } catch (e) {
      debugPrint("Cookie clear error: $e");
    }
  }

  /// App Group のクッキーを削除するヘルパー
  Future<void> _clearAppGroupCookie() async {
    try {
      await _appGroupChannel.invokeMethod('clearAppGroupCookie');
      debugPrint("App Group cookie cleared.");
    } catch (e) {
      debugPrint("Clear App Group cookie error: $e");
    }
  }

  String _getTimeStr() {
    final now = DateTime.now();
    return "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
  }

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

  // 🍎 iOS：毎秒App Groupを読み出し、リアルタイム時刻と状態を画面に描画
  Future<void> _checkAndValidateIosAppGroupCookies() async {
    if (_isSuccessTriggered) return;

    try {
      final String? appGroupCookie = await _appGroupChannel.invokeMethod<String>('getAppGroupCookie');

      if (appGroupCookie != null && appGroupCookie.isNotEmpty) {
        if (mounted) {
          setState(() {
            _statusText = "🟢 [${_getTimeStr()}] Cookie取得成功 (${appGroupCookie.length}文字)\n検証処理を実行中...";
          });
        }
        await _validateAndSave(appGroupCookie);
      } else {
        if (mounted) {
          setState(() {
            _statusText = "🟡 [${_getTimeStr()}] App Group監視中\n(Cookie未検出 / Safariでログイン完了待ち)";
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = "🔴 App Group 呼び出しエラー:\n$e";
        });
      }
    }
  }

  Future<void> _validateAndSave(String cookieString) async {
    final isValid = await AuthService.validateSession(cookieString);

    if (isValid && !_isSuccessTriggered && mounted) {
      _isSuccessTriggered = true;
      _pollingTimer?.cancel();
      _pollingTimer = null;

      if (Platform.isIOS) {
        await _clearAppGroupCookie();
      }

      await AuthService.saveSession(cookieString);

      if (mounted) {
        Navigator.pop(context);
        widget.onLoginSuccess();
      }
    } else if (!isValid && mounted) {
      // 🟢 セッションが無効（106文字などの仮クッキー）だった場合、App Groupから即座に削除して無限ループを防ぐ
      if (Platform.isIOS) {
        await _clearAppGroupCookie();
      }
      if (mounted) {
        setState(() {
          _statusText = "🟡 [${_getTimeStr()}] 仮Cookie検知 (${cookieString.length}文字 - 無効)\nApp Groupをクリアしました。Safariでログインを完了させてください。";
        });
      }
    }
  }

  Future<void> _launchSafariLogin() async {
    final Uri safariUri = Uri.parse('x-safari-https://lms.keio.jp');
    final Uri fallbackUri = Uri.parse('https://lms.keio.jp');

    try {
      // 🟢 Safari起動直前に古データをApp Groupから完全消去し、画面状態をリセット
      if (Platform.isIOS) {
        await _clearAppGroupCookie();
        if (mounted) {
          setState(() {
            _statusText = "🟡 [${_getTimeStr()}] App Group監視中\n(Cookie未検出 / Safariでログイン完了待ち)";
          });
        }
      }

      if (await canLaunchUrl(safariUri)) {
        await launchUrl(safariUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint("Safari launch error: $e");
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
            "Safariでパスキー（Face ID / Touch ID）を使ってログインしてください。認証完了後、アプリに復帰すると同期されます。",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppTheme.textSub(context)),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.accent.withAlpha(120), width: 1.5),
            ),
            child: Text(
              _statusText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.accent, height: 1.4),
            ),
          ),
          const SizedBox(height: 24),
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