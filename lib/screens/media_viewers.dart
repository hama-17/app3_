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
  // 🟢 Web内で遭遇するあらゆる形式のPDFURL（拡張子、Canvas、リダイレクト等）を判定するロジック
  bool _checkIsPdf(String urlStr) {
    final urlLower = urlStr.toLowerCase();
    if (urlLower.contains('.pdf') || urlStr.contains('download_frd=1') || urlLower.contains('response-content-type=application/pdf')) {
      return true;
    }
    // ⚠️ 修正：Canvasのファイルタイトルタップ時（/files/）のインラインプレビューページを確実に捕捉
    if (urlStr.contains('/files/')) {
      bool isVideo = urlLower.contains('isvideo=1') || urlLower.contains('.mp4') || urlLower.contains('.mov') || urlLower.contains('.webm');
      bool isAudio = urlLower.contains('.mp3') || urlLower.contains('.wav') || urlLower.contains('.m4a'); // 👈 音声ファイルも弾いて安全化
      if (!isVideo && !isAudio) return true;
    }
    return false;
  }

  // 🟢 Web内からPDFビューアへ完全に画面をすり替える処理（戻り先をアプリに固定する要）
  void _replaceWithPdfViewer(String urlStr) {
    String downloadUrl = urlStr;

    // ⚠️ 修正：RegExpを使ってCanvasのファイルID（/files/の直後の数字）を1ミリの狂いもなく抽出
    final match = RegExp(r'/files/(\d+)').firstMatch(urlStr);
    if (match != null) {
      final fileId = match.group(1);
      try {
        final uri = Uri.parse(urlStr);
        // どんな複雑なコース階層に埋まっていても、Canvas公式の「クリーンな直ダウンロードURL」に強制組み換え
        downloadUrl = "${uri.origin}/files/$fileId/download?download_frd=1";
      } catch (_) {
        // 万が一のUriパース失敗時は、安全のため元の分割ロジックをフォールバック
        if (!urlStr.contains('download')) {
          downloadUrl = "${urlStr.split('?').first}/download?download_frd=1";
        }
      }
    }

    if (context.mounted) {
      // pushReplacement によりWebView画面を履歴スタックから消滅させ、PDF側で戻った時は直接アプリへ直帰させます
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
    // 🟢 追記：現在のテーマがダークモードかどうかの判定シールドを展開
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    // 🟢 追記：ライトモードなら「黒文字（dark）」、ダークモードなら「白文字（light）」を動的に指定
    SystemUiOverlayStyle overlayStyle = isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;

    final double statusBarHeight = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: PopScope(
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
                          onWebViewCreated: (controller) {
                            _webViewController = controller;

                            // 🟢 追記：JavaScriptからのダイレクト着信を受けるレーダーを登録
                            controller.addJavaScriptHandler(
                              handlerName: 'onCanvasFileTapped',
                              callback: (args) {
                                final String urlStr = args[0];
                                // Flutter側でPDF判定を行い、合致すれば爆速ネイティブビューアへ強制連行
                                if (_checkIsPdf(urlStr)) {
                                  _replaceWithPdfViewer(urlStr);
                                } else {
                                  // PDF以外（動画やOffice系等）だった場合は、ブラウザ内で通常ロードさせる
                                  controller.loadUrl(urlRequest: URLRequest(url: WebUri(urlStr)));
                                }
                              },
                            );
                          },
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
                            useOnDownloadStart: true,
                            javaScriptCanOpenWindowsAutomatically: true,
                            supportMultipleWindows: true,
                          ),

                          // 🟢 修正：ページ読み込み完了時に、最優先クリック泥棒JSをインジェクト
                          onLoadStop: (controller, url) async {
                            await controller.evaluateJavascript(source: """
                          window.addEventListener('click', function(e) {
                            // クリックされた要素の最寄りのAタグ（リンク）を探索
                            const a = e.target.closest('a');
                            if (a && a.href) {
                              const href = a.href;
                              
                              // Canvasのファイルエンドポイント、またはPDFの拡張子を検知
                              if (href.includes('/files/') || href.toLowerCase().includes('.pdf') || href.includes('download_frd=1')) {
                                
                                // 🛑 超重要: PreventDefault & StopPropagation
                                // 第3引数を「true(キャプチャフェーズ)」にすることで、
                                // Canvas(React)の内部JSがクリックを検知するより前に、イベントの息の根を止めて横取りします。
                                e.preventDefault();
                                e.stopPropagation();
                                
                                // FlutterのハンドラーへURLを直接投げつける
                                window.flutter_inappwebview.callHandler('onCanvasFileTapped', href);
                              }
                            }
                          }, true); // 👈 この『true』がキャプチャフェーズ（最優先割り込み）の魔法です
                        """);
                          },

                          onScrollChanged: (c, x, y) {
                            if (y <= 0 && !_isTop) setState(() => _isTop = true);
                            else if (y > 5 && _isTop) setState(() => _isTop = false);
                          },

                          // ⚠️ 保険：通常のロード開始（ダウンロードボタン用など）
                          onLoadStart: (controller, url) async {
                            if (url != null) {
                              final urlStr = url.toString();
                              if (_checkIsPdf(urlStr)) {
                                await controller.stopLoading();
                                _replaceWithPdfViewer(urlStr);
                              }
                            }
                          },

                          // ⚠️ 保険：通常のリンク型遷移の横取り
                          shouldOverrideUrlLoading: (c, nav) async {
                            final uri = nav.request.url;
                            if (uri != null) {
                              final urlStr = uri.toString();
                              if (_checkIsPdf(urlStr)) {
                                await c.stopLoading();
                                Future.microtask(() => _replaceWithPdfViewer(urlStr));
                                return NavigationActionPolicy.CANCEL;
                              }
                            }
                            return NavigationActionPolicy.ALLOW;
                          },

                          // ⚠️ 保険：iOSのバックグラウンドストリーム処理用の包囲網
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
    ));
  }
}

// 🟢 修正版 PdfViewerScreen クラス（media_viewers.dart の中身と差し替えてください）

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

  // 🟢 追加：リダイレクト解析用の状態変数
  String? _resolvedUrl;
  Map<String, String>? _resolvedHeaders;
  bool _isResolving = true;

  @override
  void initState() {
    super.initState();
    _resolvePdfUrl(); // 👈 起動時にURLの転送先を安全に解析する
    pruneExpiredPdfCache();
  }

  // 🟢 追加：AWS S3へのCookie流出を徹底的にブロックするプリフライト処理
  Future<void> _resolvePdfUrl() async {
    String currentUrl = widget.url;
    Map<String, String>? currentHeaders = {'Cookie': widget.cookie};

    final lowerUrl = currentUrl.toLowerCase();
    if (lowerUrl.contains('amazonaws.com') || lowerUrl.contains('sign=')) {
      currentHeaders = null;
    } else {
      try {
        final client = http.Client();
        final request = http.Request('GET', Uri.parse(currentUrl))
          ..headers['Cookie'] = widget.cookie
          ..followRedirects = false;

        // 🟢 修正：send() の引数にリクエストオブジェクト（request）を渡します
        final response = await client.send(request).timeout(const Duration(seconds: 5));

        if ((response.statusCode == 301 || response.statusCode == 302) && response.headers['location'] != null) {
          currentUrl = response.headers['location']!;
          currentHeaders = null;
        }
        client.close();
      } catch (e) {
        debugPrint("PDF Pre-flight Redirect Resolve Error: $e");
      }
    }

    if (mounted) {
      setState(() {
        _resolvedUrl = currentUrl;
        _resolvedHeaders = currentHeaders;
        _isResolving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🟢 追記：テーマ判定とオーバースタイルの動的生成
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    SystemUiOverlayStyle overlayStyle = isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;

    final double statusBarHeight = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: Scaffold(
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
                      // 🟢 修正：URLの解析が終わるまではインジケータを回す
                      child: _isResolving
                          ? Center(child: CircularProgressIndicator(color: AppTheme.textMain(context)))
                          : PDF(
                          swipeHorizontal: false,
                          autoSpacing: false,
                          pageFling: false,
                          pageSnap: false,
                          fitEachPage: true,
                          onPageChanged: (p, t) {
                            if (p == 0 && !_isTop) setState(() => _isTop = true);
                          }
                      ).cachedFromUrl(
                          _resolvedUrl!, // 👈 解析済みの安全なURL
                          headers: _resolvedHeaders, // 👈 S3の時はキレイにNullになったヘッダー
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
                            // 🟢 修正：共有のダウンロードロジックも解析済みURLとヘッダーに同期させる
                            final response = await http.get(
                              Uri.parse(_resolvedUrl ?? widget.url),
                              headers: _resolvedHeaders ?? {},
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
    ));
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
    // 🟢 追記：テーマ判定とオーバースタイルの動的生成
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    SystemUiOverlayStyle overlayStyle = isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;

    final double statusBarHeight = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: PopScope(
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
    ));
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

// 🟢 24時間以上経過した古いPDFファイルだけをバックグラウンドで自動抹殺するヘルパー
Future<void> pruneExpiredPdfCache() async {
  try {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory(tempDir.path);

    if (await dir.exists()) {
      // 一時フォルダ内のファイルを全スキャン
      final List<FileSystemEntity> files = dir.listSync();
      final now = DateTime.now();

      for (var file in files) {
        // PDFファイル（キャッシュや前回生成した共有用PDF）を対象にする
        if (file is File && file.path.toLowerCase().endsWith('.pdf')) {
          final lastModified = await file.lastModified();

          // 🟢 最終更新から24時間（1日）以上が経過しているか判定
          if (now.difference(lastModified).inHours >= 24) {
            await file.delete();
            debugPrint("🗑️ 24時間が経過した古いキャッシュをパージしました: ${file.path}");
          }
        }
      }
    }
  } catch (e) {
    debugPrint("PDFパージエラー: $e");
  }
}




