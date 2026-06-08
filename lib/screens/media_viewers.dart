import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_cached_pdfview/flutter_cached_pdfview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_theme.dart';
import '../utils/lms_adapter.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
//media_viewers.dart

class InAppBrowserScreen extends StatefulWidget {
  final String url;
  final String cookie;
  const InAppBrowserScreen({super.key, required this.url, required this.cookie});
  @override
  State<InAppBrowserScreen> createState() => _InAppBrowserScreenState();
}


class _InAppBrowserScreenState extends State<InAppBrowserScreen> {
  bool _isTop = true;
  InAppWebViewController? _webViewController;

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // ★ 追加：ブラウザを閉じたら、そのブラウザが溜めた一時的なキャッシュを削除する
    _webViewController?.clearCache();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double statusBarHeight = MediaQuery.of(context).padding.top;

    return PopScope(
        canPop: false,
        onPopInvoked: (didPop) async {
          if (didPop) return;
          if (_webViewController != null && await _webViewController!.canGoBack()) {
            _webViewController!.goBack();
          } else {
            if (context.mounted) Navigator.pop(context);
          }
        },
        child: Scaffold(
            backgroundColor: AppTheme.bg(context),
            body: Stack(
                children: [
                  // --- 1. WebView 本体 ---
                  AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      top: _isTop ? statusBarHeight : 0,
                      bottom: _isTop ? -statusBarHeight : 0,
                      left: 0,
                      right: 0,
                      child: InAppWebView(
                          onWebViewCreated: (controller) => _webViewController = controller,
                          initialUrlRequest: URLRequest(
                            url: WebUri(widget.url),
                            headers: {'Cookie': widget.cookie},
                          ),
                          initialSettings: InAppWebViewSettings(
                            javaScriptEnabled: true,
                            domStorageEnabled: true,
                            sharedCookiesEnabled: true,
                            thirdPartyCookiesEnabled: true,
                            useShouldOverrideUrlLoading: true,
                            mediaPlaybackRequiresUserGesture: true,
                            allowsInlineMediaPlayback: true,
                          ),
                          onScrollChanged: (c, x, y) {
                            if (y <= 0 && !_isTop) setState(() => _isTop = true);
                            else if (y > 5 && _isTop) setState(() => _isTop = false);
                          },
                          shouldOverrideUrlLoading: (c, nav) async {
                            final uri = nav.request.url;
                            if (uri != null) {
                              final urlStr = uri.toString();
                              final urlLower = urlStr.toLowerCase();
                              bool isVideo = urlLower.contains('isvideo=1') || urlLower.contains('.mp4') || urlLower.contains('.mov') || urlLower.contains('.webm');

                              if (urlStr.contains('/files/') && !urlStr.contains('download') && !isVideo) {
                                final downloadUrl = "${urlStr.split('?').first}/download?download_frd=1";
                                Future.microtask(() => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(url: downloadUrl, cookie: widget.cookie))));
                                return NavigationActionPolicy.CANCEL;
                              }
                            }
                            return NavigationActionPolicy.ALLOW;
                          },
                          onDownloadStartRequest: (c, req) async {
                            try {
                              if (await canLaunchUrl(req.url)) await launchUrl(req.url, mode: LaunchMode.externalApplication);
                            } catch (e) {}
                          }
                      )
                  ),

                  // ★ 追加 2. 右上の黒い円形閉じる（×）ボタン ---
                  // 画面を下にスクロールすると自動的に画面外へ隠れ、最上部に戻るとスッと現れます
                  AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      top: _isTop ? statusBarHeight + 8 : -100,
                      right: 16,
                      child: Container(
                          decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                          child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: () {
                                Navigator.pop(context); // 一発でアプリの元の画面に戻る
                              }
                          )
                      )
                  )
                ]
            )
        )
    );
  }
}


class PdfViewerScreen extends StatefulWidget {
  final String url;
  final String cookie;
  const PdfViewerScreen({super.key, required this.url, required this.cookie});
  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}


class _PdfViewerScreenState extends State<PdfViewerScreen> {
  bool _isTop = true;
  bool _isSharing = false; // ★ 追加：ダウンロード＆共有処理中の連打ガード

  @override
  Widget build(BuildContext context) {
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    return Scaffold(
        backgroundColor: AppTheme.bg(context),
        body: Stack(
            children: [
              // --- PDF ビューア本体 ---
              AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  top: _isTop ? statusBarHeight : 0,
                  bottom: _isTop ? -statusBarHeight : 0,
                  left: 0,
                  right: 0,
                  child: Listener(
                      onPointerMove: (e) {
                        if (e.delta.dy < -5 && _isTop) setState(() => _isTop = false);
                        else if (e.delta.dy > 5 && !_isTop) setState(() => _isTop = true);
                      },
                      child: PDF(
                          swipeHorizontal: false,
                          autoSpacing: false,
                          pageFling: false,
                          pageSnap: false,
                          fitEachPage: true,
                          onPageChanged: (p, t) {
                            if (p == 0 && !_isTop) setState(() => _isTop = true);
                          }
                      ).cachedFromUrl(
                          widget.url,
                          headers: {'Cookie': widget.cookie},
                          placeholder: (p) => Center(child: CircularProgressIndicator(color: AppTheme.textMain(context))),
                          errorWidget: (e) => Center(child: Icon(Icons.error_outline, color: AppTheme.textMain(context)))
                      )
                  )
              ),

              // ★ 修正：右上の黒い円形ボタン（高セキュリティ共有型） ---
              AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  top: _isTop ? statusBarHeight + 8 : -100,
                  right: 16,
                  child: Container(
                      decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                      // 通信・書き出し処理中はインジケータを回して連打を完全に防ぐ
                      child: _isSharing
                          ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        ),
                      )
                          : IconButton(
                        icon: const Icon(Icons.share, color: Colors.white), // ★三角の共有マーク
                        onPressed: () async {
                          if (_isSharing) return;
                          setState(() => _isSharing = true);

                          try {
                            // 1. クッキーを乗せて認証を突破し、PDFのバイナリを直接叩く
                            final response = await http.get(
                              Uri.parse(widget.url),
                              headers: {'Cookie': widget.cookie},
                            ).timeout(const Duration(seconds: 15));

                            if (response.statusCode == 200) {
                              // 2. アプリ専用の一時領域に安全に書き出し
                              final tempDir = await getTemporaryDirectory();
                              final filePath = '${tempDir.path}/shared_doc_${DateTime.now().millisecondsSinceEpoch}.pdf';
                              final file = File(filePath);
                              await file.writeAsBytes(response.bodyBytes);

                              // 3. 【最重要】iPadOSでポップオーバーがどこから生えるかを計算（これをしないとiPadで100%クラッシュします）
                              final box = context.findRenderObject() as RenderBox?;
                              final rect = box != null ? box.localToGlobal(Offset.zero) & box.size : null;

                              // 4. ネイティブの共有シートを起動
                              await Share.shareXFiles(
                                [XFile(filePath)],
                                sharePositionOrigin: rect,
                              );
                            } else {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("ファイルの取得に失敗しました。")),
                                );
                              }
                            }
                          } catch (e) {
                            debugPrint("PDF Share Error: $e");
                          } finally {
                            if (mounted) setState(() => _isSharing = false);
                          }
                        },
                      )
                  )
              )
            ]
        )
    );
  }
}


class VideoViewerScreen extends StatefulWidget {
  final String url;
  final String cookie;
  const VideoViewerScreen({super.key, required this.url, required this.cookie});
  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}


class _VideoViewerScreenState extends State<VideoViewerScreen> {
  bool _isTop = true;
  InAppWebViewController? _webViewController;

  @override
  void dispose() {
    _webViewController?.clearCache();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double statusBarHeight = MediaQuery.of(context).padding.top;



    return PopScope(
        canPop: false,
        onPopInvoked: (didPop) async {
          if (didPop) return;
          if (_webViewController != null && await _webViewController!.canGoBack()) {
            _webViewController!.goBack(); // Webの履歴があれば戻る
          } else {
            if (context.mounted) Navigator.pop(context); // なければ画面を閉じる
          }
        },
        child: Scaffold(
          backgroundColor: AppTheme.bg(context),
          body: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                top: _isTop ? statusBarHeight : 0,
                bottom: _isTop ? -statusBarHeight : 0,
                left: 0,
                right: 0,
                child: Listener(
                  onPointerMove: (e) {
                    if (e.delta.dy < -5 && _isTop) setState(() => _isTop = false);
                    else if (e.delta.dy > 5 && !_isTop) setState(() => _isTop = true);
                  },
                  // 1. InAppBrowserScreen の InAppWebView を以下のように修正します
                  child: InAppWebView(
                    onWebViewCreated: (controller) => _webViewController = controller,
                    // ★ 修正：クッキーをヘッダーに注入
                    initialUrlRequest: URLRequest(
                      url: WebUri(widget.url),
                      headers: {'Cookie': widget.cookie},
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      // ★ 追加：クッキーの共有設定
                      sharedCookiesEnabled: true,
                      thirdPartyCookiesEnabled: true,
                      mediaPlaybackRequiresUserGesture: true,
                      allowsInlineMediaPlayback: true,
                    ),
                    onScrollChanged: (c, x, y) {
                      if (y <= 0 && !_isTop) setState(() => _isTop = true);
                      else if (y > 5 && _isTop) setState(() => _isTop = false);
                    },
                  ),
                ),
              ),
            ],
          ),
        )
    );
  }
}


Future<void> openSmartUrl(BuildContext context, String url, String cookie, {String? title}) async {
  try {
    String fullUrl = url.startsWith('/') ? '$canvasBaseUrl$url' : url;
    if (Uri.tryParse(fullUrl) == null) return;


    String checkStr = (fullUrl + (title ?? '')).toLowerCase();


    // ★ 動画だけでなく、Office系ドキュメント（PPTX, DOCX, XLSX）もWebViewへ逃がす
    bool isMediaOrDoc = checkStr.contains('.mp4') || checkStr.contains('.mov') || checkStr.contains('.webm') ||
        checkStr.contains('.pptx') || checkStr.contains('.ppt') ||
        checkStr.contains('.docx') || checkStr.contains('.doc') ||
        checkStr.contains('.xlsx') || checkStr.contains('.xls');


    if (isMediaOrDoc) {
      // WebViewがフリーズ（強制保存）しないよう、純粋なCanvasプレビューURLに変換する
      String safeUrl = fullUrl.replaceAll(RegExp(r'[?&]download_frd=1'), '');
      if (safeUrl.endsWith('/download')) {
        safeUrl = safeUrl.substring(0, safeUrl.length - 9);
      }
      // 前回シンプルにしたVideoViewerScreen（安全なWebView）へ送る
      Navigator.push(context, MaterialPageRoute(builder: (_) => VideoViewerScreen(url: safeUrl, cookie: cookie)));
    }
    // ★ PDFの場合（今まで通り専用の高速ビューアへ）
    else if (fullUrl.toLowerCase().contains('.pdf') || fullUrl.contains('download_frd=1')) {
      if (fullUrl.contains('/files/') && !fullUrl.contains('download')) {
        fullUrl = "${fullUrl.split('?').first}/download?download_frd=1";
      }
      Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(url: fullUrl, cookie: cookie)));
    }
    // ★ その他の場合
    else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => InAppBrowserScreen(url: fullUrl, cookie: cookie)));
    }
  } catch (e) {}
}

