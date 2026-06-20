import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' show join;
import 'package:gal/gal.dart'; // 🟢 スマホ本体への保存パッケージ
import '../core/app_theme.dart';
import 'dart:ui' as ui;           // 🟢 追記
import 'package:flutter/rendering.dart'; // 🟢 追記
import 'package:shared_preferences/shared_preferences.dart'; // 🟢 追記（これで1つ目のエラー消滅）

class CustomCameraScreen extends StatefulWidget {
  const CustomCameraScreen({super.key});

  @override
  State<CustomCameraScreen> createState() => _CustomCameraScreenState();
}

class _CustomCameraScreenState extends State<CustomCameraScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;

  final GlobalKey _previewContainerKey = GlobalKey();

  bool _isInitialized = false;
  bool _isTakingPicture = false;

  // ズーム制御用
  double _currentZoomLevel = 1.0;
  double _minZoomLevel = 1.0;
  double _maxZoomLevel = 1.0;
  double _baseZoomLevel = 1.0;

  // 🟢 ズームテキスト表示フラグ
  bool _showZoomText = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      _controller = CameraController(
        _cameras[_selectedCameraIndex],
        ResolutionPreset.max, // センサーの最高物理画質
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      // ズーム限界の取得と最高20倍のロック
      _minZoomLevel = await _controller!.getMinZoomLevel();
      double deviceMaxZoom = await _controller!.getMaxZoomLevel();
      _maxZoomLevel = math.min(20.0, deviceMaxZoom);
      _currentZoomLevel = _minZoomLevel;

      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      debugPrint("Camera Init Error: $e");
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _switchCamera() {
    if (_cameras.length < 2 || _isTakingPicture) return;
    setState(() {
      _isInitialized = false;
      _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    });
    _initializeCamera();
  }

  // 🟢 修正：撮影レイテンシを0にし、画質を4.0へ極限ブーストした決定版シャッター
  // 🟢 修正：20msのテクスチャ固定ディレイ ＆ .png拡張子への完全バインド決定版
  // 🟢 修正：中身のデータ形式と拡張子を100%完全一致させ、ブラックアウトを根絶する動的ルート分岐
  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized || _isTakingPicture) return;

    setState(() => _isTakingPicture = true);

    try {
      // ─── 🟢 20msのテクスチャ確定ホールド ───
      await Future.delayed(const Duration(milliseconds: 20));

      final docDir = await getApplicationDocumentsDirectory();
      final memoImgDir = Directory('${docDir.path}/memo_images');
      if (!await memoImgDir.exists()) {
        await memoImgDir.create(recursive: true);
      }

      final String timeStamp = DateTime.now().millisecondsSinceEpoch.toString();

      if (Platform.isIOS) {
        final prefs = await SharedPreferences.getInstance();
        final bool isSilentMode = prefs.getBool('ios_silent_camera_v10') ?? true;

        if (isSilentMode) {
          // 🔇 【ルートA】完全無音モード（描画キャプチャ ➔ 中身はPNGバイト）
          final String permanentPath = join(memoImgDir.path, 'IMG_$timeStamp.png'); // 🟢 PNGでバインド

          final RenderRepaintBoundary boundary = _previewContainerKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final ui.Image image = await boundary.toImage(pixelRatio: 4.0);

          _customBackgroundWriteTask(image, permanentPath);

          if (mounted) {
            Navigator.pop(context, permanentPath);
          }
          return;
        }
      }

      // 📸 【ルートB】音あり最高物理画質モード / Androidルート（カメラ本来のJPEG出力）
      final String permanentPath = join(memoImgDir.path, 'IMG_$timeStamp.jpg'); // 🟢 中身に合わせてJPGでバインド

      final XFile rawImage = await _controller!.takePicture();
      await File(rawImage.path).copy(permanentPath);

      try {
        await Gal.putImage(permanentPath);
      } catch (galleryError) {
        debugPrint("スマホ本体への保存に失敗しました: $galleryError");
      }

      if (mounted) {
        Navigator.pop(context, permanentPath);
      }
    } catch (e) {
      debugPrint("Take Picture Error: $e");
      if (mounted) {
        setState(() => _isTakingPicture = false);
      }
    }
  }

  // 🟢 追記：重いエンコードとカメラロール保存をUIスレッドの裏で完全非同期処理するエンジン
  void _customBackgroundWriteTask(ui.Image image, String permanentPath) {
    Future(() async {
      try {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) return;

        await File(permanentPath).writeAsBytes(byteData.buffer.asUint8List());
        await Gal.putImage(permanentPath);
        debugPrint("iOS 無音バックグラウンド保存完了: $permanentPath");
      } catch (e) {
        debugPrint("Background write error: $e");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
      );
    }

    double screenWidth = MediaQuery.of(context).size.width;

    // 🟢 修正①：デバイスの回転状態を検知
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    double camAspect = _controller!.value.aspectRatio;

    // 🟢 修正②：縦画面なら「縦長（1 / Aspect）」、横画面なら「横長（Aspect）」に比率を動的スイッチ
    double finalAspect = isLandscape ? camAspect : (1 / camAspect);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        left: false,
        right: false,
        top: true,
        bottom: true,
        child: Column(
          children: [
        // -------------------------------------------------------------------
        // 1. 左右余白なし・画像が歪まない「完全縦長/横長」の角丸プレビュー窓
        // -------------------------------------------------------------------
        Expanded(
        child: Center(
        // 🟢 修正：Center の直下に AspectRatio をインジェクション
        child: AspectRatio(
          aspectRatio: finalAspect, // センサーの縦横比（isLandscape に応じて自動反転）を強制ホールド
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28.0),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    // ピンチズーム開始
                    onScaleStart: (details) {
                            setState(() {
                              _baseZoomLevel = _currentZoomLevel;
                              _showZoomText = true; // 🟢 テキスト表示
                            });
                          },
                          // ピンチズーム中
                          onScaleUpdate: (details) async {
                            double newZoom = (_baseZoomLevel * details.scale).clamp(_minZoomLevel, _maxZoomLevel);
                            setState(() => _currentZoomLevel = newZoom);
                            _controller!.setZoomLevel(newZoom);
                          },
                          // ピンチズーム終了
                          onScaleEnd: (details) {
                            setState(() => _showZoomText = false);
                          },
                          // ❌ 修正前: child: CameraPreview(_controller!),
                          // 🟢 修正後：グラフィックをそのままコピーできるように防衛線を張る
                          child: RepaintBoundary(
                            key: _previewContainerKey,
                            child: CameraPreview(_controller!),
                          ),
                        ),
                      ),

                      // プレビュー下端のフェードグラデーション
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        height: 160,
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.black.withOpacity(0.5),
                                  Colors.black.withOpacity(0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // プレビュー内にオーバーレイされたズームUI
                      Positioned(
                        bottom: 24,
                        left: 0,
                        right: 0,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 🟢 修正：操作している時だけフワッと浮かび上がるアニメーションに変更
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: _showZoomText ? 1.0 : 0.0,
                              child: Text(
                                "${_currentZoomLevel.toStringAsFixed(1)}x",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 36,
                                  fontWeight: FontWeight.w200,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // ダイヤル目盛りバー
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onHorizontalDragStart: (_) {
                                setState(() => _showZoomText = true); // 🟢 スライド開始でテキスト表示
                              },
                              onHorizontalDragUpdate: (details) async {
                                if (_maxZoomLevel <= _minZoomLevel) return;
                                double sensitivity = 0.04;
                                double deltaZoom = -details.delta.dx * sensitivity;
                                double targetZoom = _currentZoomLevel + deltaZoom;

                                setState(() {
                                  _currentZoomLevel = targetZoom.clamp(_minZoomLevel, _maxZoomLevel);
                                });
                                await _controller!.setZoomLevel(_currentZoomLevel);
                              },
                              onHorizontalDragEnd: (_) {
                                setState(() => _showZoomText = false); // 🟢 スライド終了でテキスト非表示
                              },
                              child: SizedBox(
                                width: screenWidth,
                                height: 32,
                                child: CustomPaint(
                                  painter: _SlidingDialTicksPainter(
                                    progress: (_currentZoomLevel - _minZoomLevel) / (_maxZoomLevel - _minZoomLevel),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                     ],
                   ),
                  ),
               ), // 🟢 追記：この位置に AspectRatio を閉じるカッコを追加
              ),
            ),

            // -------------------------------------------------------------------
            // 2. 下部操作バー（戻る - シンプル白正円シャッター - カメラ反転）
            // -------------------------------------------------------------------
            // -------------------------------------------------------------------
            // 2. 下部操作バー（カメラ反転[左] - シャッター[中央] - 戻る×[右]）
            // -------------------------------------------------------------------
            Container(
              height: 100,
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 40.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 🔄 左側：カメラ反転（矢印2つが滑らかに循環するソリッドな意匠へ変更）
                  _cameras.length > 1
                      ? IconButton(
                    icon: const Icon(Icons.sync_rounded, color: Colors.white, size: 28),
                    onPressed: _switchCamera,
                  )
                      : const SizedBox(width: 48), // カメラが1つの場合のスペーサー

                  // ⚪ 中央：シンプル白正円シャッター
                  GestureDetector(
                    onTap: _takePicture,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isTakingPicture ? Colors.white.withOpacity(0.5) : Colors.white,
                      ),
                    ),
                  ),

                  // ✖ 右側：閉じるボタン（他のパーツと親和性を高めるため、端の丸い close_rounded へ微調整）
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── ファイル下部にある _SlidingDialTicksPainter を丸ごと上書き ───
class _SlidingDialTicksPainter extends CustomPainter {
  final double progress;
  _SlidingDialTicksPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final double centerX = size.width / 2;

    // 🟢 密度の調教：トータルの目盛り数を160本に倍増させ、隙間を 14.0 ➔ 7.0px へハーフ化して高密度に並べます
    const int totalTicks = 160;
    const double tickSpacing = 7.0;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    double activeOffset = progress * totalTicks * tickSpacing;

    for (int i = 0; i <= totalTicks; i++) {
      double x = centerX + (i * tickSpacing) - activeOffset;

      // 画面外の見えない目盛りは計算をスキップ
      if (x < 0 || x > size.width) continue;

      // 画面中央（現在のズーム位置）からの物理的な距離を測定
      double dist = (x - centerX).abs();

      // 左右にフェードアウトしていくお馴染みの超極細透過エフェクト
      double opacity = (1.0 - (dist / centerX)).clamp(0.0, 1.0);
      opacity = math.pow(opacity, 2.5).toDouble();
      if (opacity <= 0.02) continue;

      paint.color = Colors.white.withOpacity(opacity);

      // 🟢 形状の調教：基本の長さはすべて均一（高さの30%）に整列
      double th = size.height * 0.3;

      // 🎯 選択中央イージング：中央から「前後3.5本分」の狭いエリアだけ、中央に近づくほど段階的に膨らませます
      double maxInfluenceDist = tickSpacing * 3.5;
      if (dist < maxInfluenceDist) {
        // 中央ジャストで1.0、離れると0.0になる減衰係数
        double factor = (1.0 - (dist / maxInfluenceDist)).clamp(0.0, 1.0);

        // 中央に向かって最大で高さの50%分、段階的に「じんわり」と縦線を引き伸ばします
        th += size.height * 0.5 * factor;
      }

      // 縦線が常にコンテナの上下中央（センターライン）を基準に上下に等しく伸びるように描画
      double topY = (size.height - th) / 2;
      canvas.drawLine(Offset(x, topY), Offset(x, topY + th), paint);
    }

    // 🟢 物理パージ：不要になった「三角の指示器」の描画ロジック（Path）は跡形もなく完全抹消しました
  }

  @override
  bool shouldRepaint(covariant _SlidingDialTicksPainter old) => old.progress != progress;
}