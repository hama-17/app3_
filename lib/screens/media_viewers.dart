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
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';

class InAppBrowserScreen extends StatefulWidget {
  final String url;
  final String cookie;
  final Function(List<String>)? onImagesSaved; // 🟢 追記：ブラウザ経由時もイベントを逆流させるための中継皿を新設

  const InAppBrowserScreen({super.key, required this.url, required this.cookie, this.onImagesSaved}); // 🟢 修正
  @override
  State<InAppBrowserScreen> createState() => _InAppBrowserScreenState();
}

class _InAppBrowserScreenState extends State<InAppBrowserScreen> {
  bool _isTop = true;
  InAppWebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    _injectGlobalCookies();
  }

  Future<void> _injectGlobalCookies() async {
    if (widget.cookie.isEmpty) return;
    try {
      final cookieManager = CookieManager.instance();
      final uri = Uri.parse(widget.url);

      final hostParts = uri.host.split('.');
      String domain = uri.host;
      if (hostParts.length >= 3) {
        domain = ".${hostParts.sublist(hostParts.length - 3).join('.')}";
      }

      for (var cookiePart in widget.cookie.split(';')) {
        final kv = cookiePart.split('=');
        if (kv.length >= 2) {
          final name = kv[0].trim();
          final value = kv.sublist(1).join('=').trim();

          await cookieManager.setCookie(
            url: WebUri("${uri.scheme}://${uri.host}"),
            name: name,
            value: value,
            domain: domain,
            path: '/',
            isSecure: true,
          );
        }
      }
    } catch (e) {
      debugPrint("❌ クッキーのストア注入に失敗: $e");
    }
  }

  bool _checkIsPdf(String urlStr) {
    final urlLower = urlStr.toLowerCase();
    bool isNotPdf = urlLower.contains('.doc') || urlLower.contains('.docx') ||
        urlLower.contains('.xls') || urlLower.contains('.xlsx') ||
        urlLower.contains('.ppt') || urlLower.contains('.pptx') ||
        urlLower.contains('.zip') || urlLower.contains('.rar') ||
        urlLower.contains('.png') || urlLower.contains('.jpg') || urlLower.contains('.jpeg') || urlLower.contains('.gif') ||
        urlLower.contains('.mp4') || urlLower.contains('.mov') || urlLower.contains('.webm') ||
        urlLower.contains('.mp3') || urlLower.contains('.wav') || urlLower.contains('.m4a') ||
        urlLower.contains('isvideo=1');

    if (isNotPdf) return false;

    if (urlLower.contains('.pdf') || urlLower.contains('response-content-type=application/pdf')) {
      return true;
    }
    if (urlStr.contains('/files/')) {
      return true;
    }
    return false;
  }

  void _replaceWithPdfViewer(String urlStr) {
    String downloadUrl = urlStr;
    final match = RegExp(r'/files/(\d+)').firstMatch(urlStr);
    if (match != null) {
      final fileId = match.group(1);
      try {
        final uri = Uri.parse(urlStr);
        downloadUrl = "${uri.origin}/files/$fileId/download?download_frd=1";
      } catch (_) {
        if (!urlStr.contains('download')) {
          downloadUrl = "${urlStr.split('?').first}/download?download_frd=1";
        }
      }
    }
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => PdfViewerScreen(
              url: downloadUrl,
              cookie: widget.cookie,
              onImagesSaved: widget.onImagesSaved, // 🎯 徹底修復：千切れていたコールバックをここでPDFビューアへパススルー
            )
        ),
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
                          left: 0, right: 0,
                          child: InAppWebView(
                              onWebViewCreated: (controller) {
                                _webViewController = controller;
                                controller.addJavaScriptHandler(
                                  handlerName: 'onCanvasFileTapped',
                                  callback: (args) {
                                    final String urlStr = args[0];
                                    if (_checkIsPdf(urlStr)) {
                                      _replaceWithPdfViewer(urlStr);
                                    } else {
                                      controller.loadUrl(urlRequest: URLRequest(url: WebUri(urlStr)));
                                    }
                                  },
                                );
                              },
                              initialUrlRequest: URLRequest(
                                url: WebUri(widget.url),
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
                                supportMultipleWindows: false,
                              ),
                              onLoadStop: (controller, url) async {
                                await controller.evaluateJavascript(source: """
                          window.addEventListener('click', function(e) {
                            const a = e.target.closest('a');
                            if (a && a.href) {
                              const href = a.href;
                              if (href.includes('/files/') || href.toLowerCase().includes('.pdf') || href.includes('download_frd=1')) {
                                e.preventDefault();
                                e.stopPropagation();
                                window.flutter_inappwebview.callHandler('onCanvasFileTapped', href);
                              }
                            }
                          }, true);
                        """);
                              },
                              onScrollChanged: (c, x, y) {
                                if (y <= 0 && !_isTop) setState(() => _isTop = true);
                                else if (y > 5 && _isTop) setState(() => _isTop = false);
                              },
                              onLoadStart: (controller, url) async {
                                if (url != null) {
                                  final urlStr = url.toString();
                                  if (_checkIsPdf(urlStr)) {
                                    await controller.stopLoading();
                                    _replaceWithPdfViewer(urlStr);
                                  }
                                }
                              },
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

class StrokePoint {
  final double rx;
  final double ry;
  StrokePoint(this.rx, this.ry);
}

class DrawingStroke {
  final List<StrokePoint> points;
  final Color color;
  final double width;
  final bool isMarker;
  DrawingStroke({required this.points, required this.color, required this.width, this.isMarker = false});
}

class PdfViewerScreen extends StatefulWidget {
  final String url;
  final String cookie;
  final Function(List<String>)? onImagesSaved;

  const PdfViewerScreen({super.key, required this.url, required this.cookie, this.onImagesSaved});
  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> with SingleTickerProviderStateMixin {
  bool _isTop = true;
  bool _isSharing = false;

  String? _resolvedUrl;
  Map<String, String>? _resolvedHeaders;
  bool _isResolving = true;
  String? _localPdfPath;

  final GlobalKey _pdfCaptureKey = GlobalKey();
  ui.Image? _capturedImage;
  bool _isCropMode = false;
  bool _isSavingCrop = false;
  bool _isSharingCrop = false;

  double _cropTopY = 0.15;
  double _cropBottomY = 0.85;

  double _cropZoom = 1.0;
  Offset _cropOffset = Offset.zero;
  double _baseCropZoom = 1.0;
  Offset _baseCropOffset = Offset.zero;
  bool _isPinching = false;
  Offset _baseFocalPoint = Offset.zero;

  final List<DrawingStroke> _strokes = [];
  final List<DrawingStroke> _redoStrokes = [];
  Color _selectedColor = Colors.red;
  bool _isPenMode = false;
  bool _isMarkerMode = false;
  String? _activeBar;
  bool _blockDrawing = false;

  // ─── 📝 新設：テキストメモ専用のオーバーレイ管理ステート ───
  bool _isTextMemoMode = false;
  final TextEditingController _textMemoController = TextEditingController();
  final FocusNode _textMemoFocusNode = FocusNode();
  String _tempTextMemo = ""; // 🟢 新設：テキストを一時的に仮ホールドしておくためのスタック変数

  AnimationController? _saveAnimController;
  Animation<double>? _saveScaleAnim;
  Animation<double>? _saveSlideAnim;

  @override
  void initState() {
    super.initState();
    _resolvePdfUrl();
    pruneExpiredPdfCache();

    _saveAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _saveScaleAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _saveAnimController!, curve: Curves.easeInBack),
    );
    _saveSlideAnim = Tween<double>(begin: 0.0, end: 350.0).animate(
      CurvedAnimation(parent: _saveAnimController!, curve: Curves.easeInBack),
    );
  }

  @override
  void dispose() {
    _saveAnimController?.dispose();
    if (_localPdfPath != null) {
      try {
        final file = File(_localPdfPath!);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

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

  Future<void> _triggerPdfCapture() async {
    if (_isResolving) return;
    try {
      final RenderRepaintBoundary? boundary = _pdfCaptureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);

      setState(() {
        _capturedImage = image;
        _isCropMode = true;
        _cropTopY = 0.25;
        _cropBottomY = 0.75;
        _cropZoom = 1.0;
        _cropOffset = Offset.zero;
        _isPenMode = false;
        _strokes.clear();
        _redoStrokes.clear();
      });
    } catch (e) {
      debugPrint("PDF 画面キャプチャエラー: $e");
    }
  }

  void _drawStrokesOnCanvas(Canvas canvas, double srcW, double srcH, double drawW) {
    for (var stroke in _strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.width * (srcW / drawW);

      final path = Path();
      path.moveTo(stroke.points[0].rx * srcW, stroke.points[0].ry * srcH);
      for (int i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].rx * srcW, stroke.points[i].ry * srcH);
      }
      canvas.drawPath(path, paint);
    }
  }

  Future<void> _executeCroppedShare() async {
    if (_capturedImage == null || _isSharingCrop) return;
    setState(() => _isSharingCrop = true);

    try {
      final double srcW = _capturedImage!.width.toDouble();
      final double srcH = _capturedImage!.height.toDouble();

      // ─── 🟢 追記：プレビュー時と解像度の比率を完全に一致させるため、実際の描画論理幅(drawW)を正確に再現 ───
      final double boxW = MediaQuery.of(context).size.width;
      final double statusBarHeight = MediaQuery.of(context).padding.top;
      final double boxH = MediaQuery.of(context).size.height - statusBarHeight - MediaQuery.of(context).padding.bottom - 185.0;

      double drawW, drawH;
      if ((srcW / srcH) > (boxW / boxH)) {
        drawW = boxW;
        drawH = boxW / (srcW / srcH);
      } else {
        drawH = boxH;
        drawW = boxH * (srcW / srcH);
      }

      final double topPixel = srcH * _cropTopY;
      final double bottomPixel = srcH * _cropBottomY;
      final double targetHeight = bottomPixel - topPixel;

      if (targetHeight <= 10) return;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(_capturedImage!, Offset.zero, Paint());

      // 🎯 修正：第4引数を srcW から、今計算した画面上の論理幅である drawW へ変更！
      _drawStrokesOnCanvas(canvas, srcW, srcH, drawW);

      final picture = recorder.endRecording();
      final compositedImage = await picture.toImage(srcW.toInt(), srcH.toInt());

      final cropRecorder = ui.PictureRecorder();
      final cropCanvas = Canvas(cropRecorder);
      cropCanvas.drawImageRect(
        compositedImage,
        Rect.fromLTRB(0, topPixel, srcW, bottomPixel),
        Rect.fromLTWH(0, 0, srcW, targetHeight),
        Paint(),
      );

      final cropPicture = cropRecorder.endRecording();
      final croppedUiImage = await cropPicture.toImage(srcW.toInt(), targetHeight.toInt());
      final byteData = await croppedUiImage.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final Uint8List pngBytes = byteData.buffer.asUint8List();
        final tempDir = await getTemporaryDirectory();
        final String filePath = '${tempDir.path}/SHARE_CROP_${DateTime.now().millisecondsSinceEpoch}.png';
        final file = File(filePath);
        await file.writeAsBytes(pngBytes);

        final box = context.findRenderObject() as RenderBox?;
        final rect = box != null ? box.localToGlobal(Offset.zero) & box.size : null;

        await Share.shareXFiles([XFile(filePath)], sharePositionOrigin: rect);

        try {
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint("トリミング共有エラー: $e");
    } finally {
      if (mounted) {
        setState(() => _isSharingCrop = false);
      }
    }
  }

  Future<void> _executeCroppedSave() async {
    if (_capturedImage == null || _isSavingCrop) return;
    setState(() => _isSavingCrop = true);

    try {
      final double srcW = _capturedImage!.width.toDouble();
      final double srcH = _capturedImage!.height.toDouble();

      // ─── 🟢 追記：プレビュー時と解像度の比率を完全に一致させるため、実際の描画論理幅(drawW)を正確に再現 ───
      final double boxW = MediaQuery.of(context).size.width;
      final double statusBarHeight = MediaQuery.of(context).padding.top;
      final double boxH = MediaQuery.of(context).size.height - statusBarHeight - MediaQuery.of(context).padding.bottom - 185.0;

      double drawW, drawH;
      if ((srcW / srcH) > (boxW / boxH)) {
        drawW = boxW;
        drawH = boxW / (srcW / srcH);
      } else {
        drawH = boxH;
        drawW = boxH * (srcW / srcH);
      }

      final double topPixel = srcH * _cropTopY;
      final double bottomPixel = srcH * _cropBottomY;
      final double targetHeight = bottomPixel - topPixel;

      if (targetHeight <= 10) return;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(_capturedImage!, Offset.zero, Paint());

      // 🎯 修正：第4引数を srcW から、今計算した画面上の論理幅である drawW へ変更！
      _drawStrokesOnCanvas(canvas, srcW, srcH, drawW);

      final picture = recorder.endRecording();
      final compositedImage = await picture.toImage(srcW.toInt(), srcH.toInt());

      final cropRecorder = ui.PictureRecorder();
      final cropCanvas = Canvas(cropRecorder);
      cropCanvas.drawImageRect(
        compositedImage,
        Rect.fromLTRB(0, topPixel, srcW, bottomPixel),
        Rect.fromLTWH(0, 0, srcW, targetHeight),
        Paint(),
      );

      final cropPicture = cropRecorder.endRecording();
      final croppedUiImage = await cropPicture.toImage(srcW.toInt(), targetHeight.toInt());
      final byteData = await croppedUiImage.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final Uint8List pngBytes = byteData.buffer.asUint8List();

        final docDir = await getApplicationDocumentsDirectory();
        final String memoDirPath = '${docDir.path}/memo_images';
        final memoDir = Directory(memoDirPath);
        if (!await memoDir.exists()) {
          await memoDir.create(recursive: true);
        }

        final String timeStamp = DateTime.now().millisecondsSinceEpoch.toString();
        final String filePath = '$memoDirPath/IMG_$timeStamp.jpg';

        final file = File(filePath);
        await file.writeAsBytes(pngBytes);

        // 1. アルバム『AXYZ』への保存処理
        try {
          await Gal.requestAccess(toAlbum: true);
          await Gal.putImage(filePath, album: 'dot archive');
          debugPrint("AXYZ アルバムへのPDFスクショ保存に成功しました");
        } catch (albumError) {
          debugPrint("アルバム保存でエラーが発生: $albumError");
          await Gal.putImage(filePath); // フォールバック
        }

        // ─── 🎯 【重要】ここが2回記述されていないか確認してください ───
        // 画像パスと、もしあれば仮保存テキストをパッキングして「1回だけ」親に射撃します
        final List<String> payload = [filePath];
        if (_tempTextMemo.isNotEmpty) {
          payload.add("TEXT_MEMO:$_tempTextMemo");
        }
        widget.onImagesSaved?.call(payload);
        // ───────────────────────────────────────────────────────────

        await _saveAnimController!.forward();
      }
    } catch (e) {
      debugPrint("トリミング保存エラー: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isSavingCrop = false;
          _isCropMode = false;
          _capturedImage = null;
          // ─── 🟢 保存処理通過時も、すべてのキャッシュ・テキストコンソールを完全に初期化 ───
          _strokes.clear();
          _redoStrokes.clear();
          _tempTextMemo = "";
        });
        _textMemoController.clear();
        _saveAnimController!.reset();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    SystemUiOverlayStyle overlayStyle = isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;
    final double statusBarHeight = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: Scaffold(
            backgroundColor: AppTheme.bg(context),
            body: Stack(
                children: [
                  AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      top: _isTop ? statusBarHeight : 0,
                      bottom: _isTop ? -statusBarHeight : 0,
                      left: 0, right: 0,
                      child: Listener(
                          onPointerMove: (e) {
                            if (e.delta.dy < -5 && _isTop) setState(() => _isTop = false);
                            else if (e.delta.dy > 5 && !_isTop) setState(() => _isTop = true);
                          },
                          child: _isResolving
                              ? Center(child: CircularProgressIndicator(color: AppTheme.textMain(context)))
                              : RepaintBoundary(
                            key: _pdfCaptureKey,
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
                                _resolvedUrl!,
                                headers: _resolvedHeaders,
                                placeholder: (p) => Center(child: CircularProgressIndicator(color: AppTheme.textMain(context))),
                                errorWidget: (e) => Center(child: Icon(Icons.error_outline, color: AppTheme.textMain(context)))
                            ),
                          )
                      )
                  ),

                  AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      top: _isTop ? statusBarHeight + 8 : -100,
                      left: 16,
                      child: Container(
                          decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                          child: IconButton(
                            icon: const Icon(Icons.crop, color: Colors.white),
                            onPressed: _triggerPdfCapture,
                          )
                      )
                  ),

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

                                  await Share.shareXFiles([XFile(filePath)], sharePositionOrigin: rect);
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
                  ),

                  if (_isCropMode && _capturedImage != null)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black,
                        child: SafeArea(
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.close, color: Colors.white, size: 26),
                                      onPressed: () => setState(() {
                                        // ─── 🟢 徹底排除：スクショ画面を閉じた瞬間に、すべての書きかけデータをメモリから完全抹殺 ───
                                        _isCropMode = false;
                                        _strokes.clear();
                                        _redoStrokes.clear();
                                        _tempTextMemo = "";
                                        _textMemoController.clear();
                                      }),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.undo_rounded, size: 24),
                                          color: _strokes.isNotEmpty ? Colors.white : Colors.white24,
                                          onPressed: _strokes.isNotEmpty ? () {
                                            setState(() {
                                              _redoStrokes.add(_strokes.removeLast());
                                            });
                                          } : null,
                                        ),
                                        const SizedBox(width: 12),
                                        IconButton(
                                          icon: const Icon(Icons.redo_rounded, size: 24),
                                          color: _redoStrokes.isNotEmpty ? Colors.white : Colors.white24,
                                          onPressed: _redoStrokes.isNotEmpty ? () {
                                            setState(() {
                                              _strokes.add(_redoStrokes.removeLast());
                                            });
                                          } : null,
                                        ),
                                      ],
                                    ),
                                    _isSharingCrop
                                        ? const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 12.0),
                                      child: SizedBox(
                                        width: 20, height: 20,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                      ),
                                    )
                                        : IconButton(
                                      icon: const Icon(Icons.share_outlined, color: Colors.white, size: 24),
                                      onPressed: _executeCroppedShare,
                                    ),
                                  ],
                                ),
                              ),

                              Expanded(
                                child: AnimatedBuilder(
                                  animation: _saveAnimController!,
                                  builder: (context, child) {
                                    return Transform(
                                      transform: Matrix4.identity()
                                        ..translate(_saveSlideAnim!.value, 0.0)
                                        ..scale(_saveScaleAnim!.value),
                                      alignment: Alignment.bottomRight,
                                      child: child,
                                    );
                                  },
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final double boxW = constraints.maxWidth;
                                      final double boxH = constraints.maxHeight;

                                      final double imgW = _capturedImage!.width.toDouble();
                                      final double imgH = _capturedImage!.height.toDouble();
                                      final double imgAspect = imgW / imgH;
                                      final double boxAspect = boxW / boxH;

                                      double drawW, drawH;
                                      if (imgAspect > boxAspect) {
                                        drawW = boxW;
                                        drawH = boxW / imgAspect;
                                      } else {
                                        drawH = boxH;
                                        drawW = boxH * imgAspect;
                                      }

                                      final double left = (boxW - drawW) / 2;
                                      final double top = (boxH - drawH) / 2;
                                      final double centerX = boxW / 2;
                                      final double centerY = boxH / 2;

                                      if (_isPenMode) {
                                        final double cropH = drawH * (_cropBottomY - _cropTopY);
                                        final double cropW = drawW;
                                        final double fitScale = math.min(boxW / cropW, boxH / cropH);

                                        final double activeW = cropW * fitScale;
                                        final double activeH = cropH * fitScale;
                                        final double activeLeft = (boxW - activeW) / 2;
                                        final double activeTop = (boxH - activeH) / 2;

                                        return GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onScaleStart: (details) {
                                            if (details.pointerCount >= 2) {
                                              _isPinching = true;
                                              _baseCropZoom = _cropZoom;
                                              _baseCropOffset = _cropOffset;
                                              _baseFocalPoint = details.localFocalPoint;
                                            } else {
                                              if (_blockDrawing) return;
                                              _isPinching = false;

                                              final double px = details.localFocalPoint.dx;
                                              final double py = details.localFocalPoint.dy;
                                              final double x1 = px - _cropOffset.dx;
                                              final double y1 = py - _cropOffset.dy;
                                              final double x2 = centerX + (x1 - centerX) / _cropZoom;
                                              final double y2 = centerY + (y1 - centerY) / _cropZoom;
                                              final double localX = x2 - activeLeft;
                                              final double localY = y2 - activeTop;
                                              final double originalLocalX = localX / fitScale;
                                              final double originalLocalY = (localY / fitScale) + (_cropTopY * drawH);
                                              final double rx = (originalLocalX / drawW).clamp(0.0, 1.0);
                                              final double ry = (originalLocalY / drawH).clamp(0.0, 1.0);

                                              _redoStrokes.clear();
                                              _strokes.add(DrawingStroke(
                                                points: [StrokePoint(rx, ry)],
                                                color: _isMarkerMode ? _selectedColor.withOpacity(0.4) : _selectedColor,
                                                width: _isMarkerMode ? 14.0 : 2.0,
                                                isMarker: _isMarkerMode,
                                              ));
                                            }
                                          },
                                          onScaleUpdate: (details) {
                                            if (_isPinching) {
                                              setState(() {
                                                _cropZoom = (_baseCropZoom * details.scale).clamp(1.0, 4.0);
                                                if (_cropZoom <= 1.01) {
                                                  _cropOffset = Offset.zero;
                                                } else {
                                                  final Offset totalDelta = details.localFocalPoint - _baseFocalPoint;
                                                  _cropOffset = _baseCropOffset + totalDelta;

                                                  double maxOffsetX = (activeW * _cropZoom - boxW).clamp(0.0, double.infinity) / 2;
                                                  double maxOffsetY = (activeH * _cropZoom - boxH).clamp(0.0, double.infinity) / 2;

                                                  if (activeW * _cropZoom <= boxW) maxOffsetX = 0.0;
                                                  if (activeH * _cropZoom <= boxH) maxOffsetY = 0.0;

                                                  _cropOffset = Offset(
                                                    _cropOffset.dx.clamp(-maxOffsetX, maxOffsetX),
                                                    _cropOffset.dy.clamp(-maxOffsetY, maxOffsetY),
                                                  );
                                                }
                                              });
                                            } else {
                                              if (_blockDrawing) return;

                                              final double px = details.localFocalPoint.dx;
                                              final double py = details.localFocalPoint.dy;
                                              final double x1 = px - _cropOffset.dx;
                                              final double y1 = py - _cropOffset.dy;
                                              final double x2 = centerX + (x1 - centerX) / _cropZoom;
                                              final double y2 = centerY + (y1 - centerY) / _cropZoom;
                                              final double localX = x2 - activeLeft;
                                              final double localY = y2 - activeTop;
                                              final double originalLocalX = localX / fitScale;
                                              final double originalLocalY = (localY / fitScale) + (_cropTopY * drawH);
                                              final double rx = (originalLocalX / drawW).clamp(0.0, 1.0);
                                              final double ry = (originalLocalY / drawH).clamp(0.0, 1.0);

                                              setState(() {
                                                if (_strokes.isNotEmpty) {
                                                  final stroke = _strokes.last;
                                                  if (stroke.isMarker) {
                                                    final startPoint = stroke.points.first;
                                                    stroke.points.clear();
                                                    stroke.points.add(startPoint);
                                                    stroke.points.add(StrokePoint(rx, startPoint.ry));
                                                  } else {
                                                    stroke.points.add(StrokePoint(rx, ry));
                                                  }
                                                }
                                              });
                                            }
                                          },
                                          onScaleEnd: (details) {
                                            if (_isPinching) {
                                              _isPinching = false;
                                              _blockDrawing = true;
                                              Future.delayed(const Duration(milliseconds: 200), () {
                                                _blockDrawing = false;
                                              });
                                            }
                                          },
                                          onDoubleTap: () {
                                            setState(() {
                                              _cropZoom = 1.0;
                                              _cropOffset = Offset.zero;
                                            });
                                          },
                                          child: ClipRect(
                                            child: Transform(
                                              transform: Matrix4.identity()
                                                ..translate(_cropOffset.dx, _cropOffset.dy)
                                                ..scale(_cropZoom),
                                              alignment: Alignment.center,
                                              child: Center(
                                                child: SizedBox(
                                                  width: activeW,
                                                  height: activeH,
                                                  child: ClipRect(
                                                    child: Stack(
                                                      children: [
                                                        Positioned(
                                                          left: 0,
                                                          top: -_cropTopY * drawH * fitScale,
                                                          width: drawW * fitScale,
                                                          height: drawH * fitScale,
                                                          child: Stack(
                                                            children: [
                                                              Positioned.fill(
                                                                child: RawImage(image: _capturedImage, fit: BoxFit.fill),
                                                              ),
                                                              Positioned.fill(
                                                                child: CustomPaint(
                                                                  painter: _PreviewStrokePainter(strokes: _strokes),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      } else {
                                        return GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onScaleStart: (details) {
                                            _activeBar = null;
                                            final double py = details.localFocalPoint.dy;
                                            final double absTopY = top + drawH * _cropTopY;
                                            final double absBottomY = top + drawH * _cropBottomY;

                                            if ((py - absTopY).abs() < (py - absBottomY).abs()) {
                                              _activeBar = 'top';
                                            } else {
                                              _activeBar = 'bottom';
                                            }
                                          },
                                          onScaleUpdate: (details) {
                                            if (_activeBar != null) {
                                              final double localYOnImage = details.localFocalPoint.dy - top;
                                              final double rawY = localYOnImage / drawH;
                                              final double currentY = rawY.clamp(0.0, 1.0);

                                              setState(() {
                                                if (_activeBar == 'top') {
                                                  _cropTopY = math.min(currentY, _cropBottomY - 0.04);
                                                } else {
                                                  _cropBottomY = math.max(currentY, _cropTopY + 0.04);
                                                }
                                              });
                                            }
                                          },
                                          child: Stack(
                                            children: [
                                              Center(
                                                child: SizedBox(
                                                  width: drawW, height: drawH,
                                                  child: RawImage(image: _capturedImage, fit: BoxFit.contain),
                                                ),
                                              ),
                                              Center(
                                                child: SizedBox(
                                                  width: drawW, height: drawH,
                                                  child: CustomPaint(
                                                    painter: _PreviewStrokePainter(strokes: _strokes),
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                left: left, top: top, width: drawW, height: drawH * _cropTopY,
                                                child: Container(color: Colors.black.withOpacity(0.75)),
                                              ),
                                              Positioned(
                                                left: left, top: top + (drawH * _cropBottomY), width: drawW,
                                                height: drawH * (1.0 - _cropBottomY),
                                                child: Container(color: Colors.black.withOpacity(0.75)),
                                              ),
                                              Positioned(
                                                left: left - 10, top: top + (drawH * _cropTopY) - 1.0, width: drawW + 20,
                                                child: Container(height: 2.0, color: Colors.white.withOpacity(0.9)),
                                              ),
                                              Positioned(
                                                left: left - 10, top: top + (drawH * _cropBottomY) - 1.0, width: drawW + 20,
                                                child: Container(height: 2.0, color: Colors.white.withOpacity(0.9)),
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ),

                              Container(
                                height: 90,
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // ─── ◀️ 左翼：手書きえんぴつボタン（消失ガード版） ───
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 240),
                                      curve: Curves.easeOutCubic,
                                      height: 48,
                                      width: _isPenMode ? 200 : 48,
                                      decoration: BoxDecoration(
                                        color: _isPenMode ? Colors.white : Colors.transparent,
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(color: Colors.white, width: _isPenMode ? 0.0 : 1.5),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(24),
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          physics: const NeverScrollableScrollPhysics(),
                                          child: SizedBox(
                                            width: 200, height: 48,
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.start,
                                              children: [
                                                GestureDetector(
                                                  onTap: () {
                                                    setState(() {
                                                      _isPenMode = !_isPenMode;
                                                      if (!_isPenMode) {
                                                        _cropZoom = 1.0;
                                                        _cropOffset = Offset.zero;
                                                      }
                                                    });
                                                  },
                                                  child: Container(
                                                    width: 44, height: 48,
                                                    color: Colors.transparent,
                                                    child: Icon(
                                                      _isPenMode ? Icons.close_rounded : Icons.edit_outlined,
                                                      color: _isPenMode ? Colors.black : Colors.white,
                                                      size: 21,
                                                    ),
                                                  ),
                                                ),
                                                if (_isPenMode)
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      _buildColorElement(Colors.black, false),
                                                      _buildColorElement(Colors.red, false),
                                                      _buildColorElement(Colors.blue, false),
                                                      _buildColorElement(Colors.green, false),
                                                      _buildColorElement(Colors.yellow[700]!, true),
                                                      _buildColorElement(Colors.blueAccent, true),
                                                    ],
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // ─── 🟢 中央翼：干渉しない最大幅を自動確保する、テキスト仮保存連動カプセル ───
                                    // ─── 🟢 中央翼：最大幅自動確保 ＆ 背景色固定・入力時白枠スイッチ型カプセル ───
                                    if (!_isPenMode) ...[
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _textMemoController.text = _tempTextMemo;
                                              _isTextMemoMode = true;
                                            });
                                            _textMemoFocusNode.requestFocus();
                                          },
                                          child: Container(
                                            height: 48,
                                            padding: const EdgeInsets.symmetric(horizontal: 16),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.12), // 🎯 要望：背景色は一切変えずにプレーンな灰色で固定
                                              borderRadius: BorderRadius.circular(24),
                                              // 🎯 要望：文字が仮保存されている時だけ、枠線を「白」にして入力済みであることを明示
                                              border: Border.all(
                                                color: _tempTextMemo.isNotEmpty ? Colors.white : Colors.transparent,
                                                width: _tempTextMemo.isNotEmpty ? 1.5 : 0.0,
                                              ),
                                            ),
                                            alignment: Alignment.centerLeft,
                                            child: _tempTextMemo.isNotEmpty
                                                ? Text(
                                              _tempTextMemo, // 🎯 テキストは引き続きそのまま表示
                                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w400),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            )
                                                : Text(
                                              "メモを追加",
                                              style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13, fontWeight: FontWeight.w400, letterSpacing: 0.5),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                    ] else
                                      const Spacer(),

                                    // ─── ▶️ 右翼：白のSAVEボタン（一括保存コア） ───
                                    _isSavingCrop
                                        ? const SizedBox(width: 105, height: 48, child: Center(child: CircularProgressIndicator(color: Colors.white)))
                                        : GestureDetector(
                                      onTap: _executeCroppedSave,
                                      child: Container(
                                        height: 48,
                                        width: 105,
                                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                                        alignment: Alignment.center,
                                        child: const Text(
                                          "SAVE",
                                          style: TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // ─── 📝 最前面オーバーレイ：それ以外を完全非表示にしてキーボード直上で文字を編むコンソールユニット ───
                  // ─── 📝 最前面オーバーレイ：キーボード直上にジャストフィットする特化型コンソール ───
                  // ─── 📝 最前面オーバーレイ：トリミング後プレビュー ＆ テキスト破棄リセット機能搭載型 ───
                  // ─── 📝 最前面オーバーレイ：トリミング追従最大化表示 ＆ 右下固定チェックボタン仕様 ───
                  // ─── 📝 最前面オーバーレイ：手書き完全追従プレビュー ＆ 入力欄沈み込みバグ完全修正コンソール ───
                  if (_isTextMemoMode && _capturedImage != null)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.95),
                        child: SafeArea(
                          child: Column(
                            children: [
                              // ① 上部：限界最大サイズプレビューの中に、画像と完全に同期した手書き線をオーバーレイ表示
                              Expanded(
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(32.0),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: FittedBox(
                                        fit: BoxFit.contain,
                                        child: Align(
                                          alignment: Alignment(0, -1.0 + (_cropTopY + _cropBottomY)),
                                          heightFactor: _cropBottomY - _cropTopY,
                                          child: Stack( // 🎯 要望：手書きを画像の上に重ねてテキスト入力時も常時見えるように連動
                                            children: [
                                              RawImage(image: _capturedImage),
                                              Positioned.fill(
                                                child: CustomPaint(
                                                  painter: _PreviewStrokePainter(strokes: _strokes),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // ② 下部：1行目の沈み込みを完全修正し、チェック円を右下に完全ホールドする入力セクター
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16.0, left: 16, right: 16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 破棄用のプレーンな×ボタン（テキストリセット機能付き）
                                    GestureDetector(
                                      onTap: () {
                                        _textMemoController.clear();
                                        setState(() {
                                          _tempTextMemo = "";
                                          _isTextMemoMode = false;
                                        });
                                        _textMemoFocusNode.unfocus();
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.only(left: 6, bottom: 10),
                                        child: Icon(Icons.close_rounded, color: Colors.white, size: 24),
                                      ),
                                    ),

                                    // 入力コンソールシェル（バグを根治するため内部を強固なStack構造に換装）
                                    Container(
                                      decoration: BoxDecoration(
                                        color: AppTheme.panel(context),
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                      child: Stack(
                                        alignment: Alignment.bottomRight, // 🎯 要望：チェックマークを常に右下に配置するアンカー
                                        children: [
                                          // テキスト入力フィールド本体
                                          Padding(
                                            // 右側にチェック円ボタン（38px）＋余白分の座席シート（計62px）をあらかじめ確保
                                            padding: const EdgeInsets.fromLTRB(20, 12, 62, 12),
                                            child: TextField(
                                              controller: _textMemoController,
                                              focusNode: _textMemoFocusNode,
                                              maxLines: null,
                                              cursorColor: Colors.white,
                                              style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
                                              decoration: InputDecoration(
                                                hintText: "メモを追加",
                                                hintStyle: TextStyle(color: Colors.white.withOpacity(0.25), fontWeight: FontWeight.w400 , fontSize: 15),
                                                border: InputBorder.none,
                                                isDense: true,
                                                // 🎯 決定打：垂直方向のパディングを均等に与えることで、1行目の沈み込み・下にずれるバグを完全パージ！
                                                contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
                                              ),
                                            ),
                                          ),

                                          // 右下固定式の白い円のチェックマークボタン
                                          Positioned(
                                            right: 12,
                                            bottom: 12, // 入力欄が縦にどれだけ伸びても、常に右下12pxの位置に完全へばりつきます
                                            child: GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  _tempTextMemo = _textMemoController.text.trim();
                                                  _isTextMemoMode = false;
                                                });
                                                _textMemoFocusNode.unfocus();
                                              },
                                              child: Container(
                                                width: 38, height: 38,
                                                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                                child: const Icon(Icons.check_rounded, color: Colors.black, size: 22),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ]
            )
        )
    );
  }

  Widget _buildColorElement(Color color, bool isSquare) {
    final bool isSelected = (_selectedColor.value == color.value) && (_isMarkerMode == isSquare);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _selectedColor = color;
          _isMarkerMode = isSquare;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 12.0),
        color: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          width: isSelected ? 20.0 : 13.0,
          height: isSelected ? 20.0 : 13.0,
          decoration: BoxDecoration(
            color: color,
            shape: isSquare ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: isSquare ? BorderRadius.zero : null,
          ),
        ),
      ),
    );
  }
}

class _PreviewStrokePainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  _PreviewStrokePainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    for (var stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.width;

      final path = Path();
      path.moveTo(stroke.points[0].rx * size.width, stroke.points[0].ry * size.height);

      for (int i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].rx * size.width, stroke.points[i].ry * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewStrokePainter old) => true;
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

Future<void> openSmartUrl(BuildContext context, String url, String cookie, {String? title, Function(List<String>)? onImagesSaved}) async {
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
      Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(url: fullUrl, cookie: cookie, onImagesSaved: onImagesSaved)));
    }
    else {
      // 🎯 徹底修復：ここ！！ブラウザ経由で資料を開く際にもコールバックを渡さないと電気信号が完全に途切れます
      Navigator.push(context, MaterialPageRoute(builder: (_) => InAppBrowserScreen(url: fullUrl, cookie: cookie, onImagesSaved: onImagesSaved)));
    }
  } catch (e) {
    debugPrint("openSmartUrl Routing Error: $e");
  }
}

Future<void> pruneExpiredPdfCache() async {
  try {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory(tempDir.path);

    if (await dir.exists()) {
      final List<FileSystemEntity> files = dir.listSync();
      final now = DateTime.now();

      for (var file in files) {
        if (file is File && file.path.toLowerCase().endsWith('.pdf')) {
          final lastModified = await file.lastModified();

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


