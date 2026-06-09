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

  // 🟢 Web内で遭遇するあらゆる形式のPDFURL（拡張子、Canvas、リダイレクト等）を判定するロジック
  bool _checkIsPdf(String urlStr) {
    final urlLower = urlStr.toLowerCase();
    if (urlLower.contains('.pdf') || urlStr.contains('download_frd=1') || urlLower.contains('response-content-type=application/pdf')) {
      return true;
    }
    if (urlStr.contains('/files/') && !urlStr.contains('download')) {
      bool isVideo = urlLower.contains('isvideo=1') || urlLower.contains('.mp4') || urlLower.contains('.mov') || urlLower.contains('.webm');
      if (!isVideo) return true;
    }
    return false;
  }

  // 🟢 Web内からPDFビューアへ完全に画面をすり替える処理（戻り先をアプリに固定する要）
  void _replaceWithPdfViewer(String urlStr) {
    String downloadUrl = urlStr;
    if (urlStr.contains('/files/') && !urlStr.contains('download')) {
      downloadUrl = "${urlStr.split('?').first}/download?download_frd=1";
    }
    if (context.mounted) {
      // ⚠️ pushReplacement にすることで、現在のWebView画面（ブラウザ）を履歴ごとスタックから完全に消滅させます。
      // これにより、PDFViewer側で戻るボタンを押した時、Webを挟まずに直接「アプリの元の画面」へ一発で戻れます。
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => PdfViewerScreen(url: downloadUrl, cookie: widget.cookie)),
      );
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
                            useOnDownloadStart: true, // 👈 iOS用のPDFストリームを確実に横取りするためのトリガー
                          ),
                          onScrollChanged: (c, x, y) {
                            if (y <= 0 && !_isTop) setState(() => _isTop = true);
                            else if (y > 5 && _isTop) setState(() => _isTop = false);
                          },

                          // 🔥 iOS対策：WebViewがロード処理を開始した瞬間を監視。画面に白・黒のノイズが出る前に即座にフリーズさせて引き剥がす
                          onLoadStart: (controller, url) async {
                            if (url != null) {
                              final urlStr = url.toString();
                              if (_checkIsPdf(urlStr)) {
                                await controller.stopLoading(); // 👈 即座にWebViewの読み込み・描画を停止させてゾンビ画面の発生を防ぐ
                                _replaceWithPdfViewer(urlStr);
                              }
                            }
                          },

                          // 🔥 Android / 通常リンクタップ時の横取り
                          shouldOverrideUrlLoading: (c, nav) async {
                            final uri = nav.request.url;
                            if (uri != null) {
                              final urlStr = uri.toString();
                              if (_checkIsPdf(urlStr)) {
                                // 描画処理が走る前に裏側でストップ
                                await c.stopLoading();
                                Future.microtask(() => _replaceWithPdfViewer(urlStr));
                                return NavigationActionPolicy.CANCEL; // WebView内でのリダイレクト遷移を完全に遮断
                              }
                            }
                            return NavigationActionPolicy.ALLOW;
                          },

                          // 🔥 iOSのバックグラウンドストリーム処理用の包囲網
                          onDownloadStartRequest: (c, req) async {
                            final urlStr = req.url.toString();
                            if (_checkIsPdf(urlStr)) {
                              await c.stopLoading();
                              _replaceWithPdfViewer(urlStr);
                              return;
                            }
                            try {
                              if (await canLaunchUrl(req.url)) await launchUrl(req.url, mode: LaunchMode.externalApplication);
                            } catch (e) {}
                          }
                      )
                  ),

                  // 右上の黒い円形閉じる（×）ボタン
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
                                Navigator.pop(context);
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
  bool _isSharing = false;

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

              // 右上の黒い円形ボタン（高セキュリティ共有型）
              AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  top: _isTop ? statusBarHeight + 8 : -100,
                  right: 16,
                  child: Container(
                      decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                      child: _isSharing
                          ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        ),
                      )
                          : IconButton(
                        icon: const Icon(Icons.share, color: Colors.white),
                        onPressed: () async {
                          if (_isSharing) return;
                          setState(() => _isSharing = true);

                          try {
                            final response = await http.get(
                              Uri.parse(widget.url),
                              headers: {'Cookie': widget.cookie},
                            ).timeout(const Duration(seconds: 15));

                            if (response.statusCode == 200) {
                              final tempDir = await getTemporaryDirectory();
                              final filePath = '${tempDir.path}/shared_doc_${DateTime.now().millisecondsSinceEpoch}.pdf';
                              final file = File(filePath);
                              await file.writeAsBytes(response.bodyBytes);

                              final box = context.findRenderObject() as RenderBox?;
                              final rect = box != null ? box.localToGlobal(Offset.zero) & box.size : null;

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
            _webViewController!.goBack();
          } else {
            if (context.mounted) Navigator.pop(context);
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

    bool isMediaOrDoc = checkStr.contains('.mp4') || checkStr.contains('.mov') || checkStr.contains('.webm') ||
        checkStr.contains('.pptx') || checkStr.contains('.ppt') ||
        checkStr.contains('.docx') || checkStr.contains('.doc') ||
        checkStr.contains('.xlsx') || checkStr.contains('.xls');

    if (isMediaOrDoc) {
      String safeUrl = fullUrl.replaceAll(RegExp(r'[?&]download_frd=1'), '');
      if (safeUrl.endsWith('/download')) {
        safeUrl = safeUrl.substring(0, safeUrl.length - 9);
      }
      Navigator.push(context, MaterialPageRoute(builder: (_) => VideoViewerScreen(url: safeUrl, cookie: cookie)));
    }
    else if (fullUrl.toLowerCase().contains('.pdf') || fullUrl.contains('download_frd=1')) {
      if (fullUrl.contains('/files/') && !fullUrl.contains('download')) {
        fullUrl = "${fullUrl.split('?').first}/download?download_frd=1";
      }
      Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(url: fullUrl, cookie: cookie)));
    }
    else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => InAppBrowserScreen(url: fullUrl, cookie: cookie)));
    }
  } catch (e) {}
}