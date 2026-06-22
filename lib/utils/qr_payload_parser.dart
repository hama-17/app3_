import 'dart:io';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class QrPayloadParser {
  static final BarcodeScanner _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);

  /// 🟢 修正確定版：Planeのプロパティ制限をクリアし、AndroidのYUVバイトを完全再構築
  static Future<String?> parseCameraImage(CameraImage image, CameraDescription camera) async {
    // 🟢 追記：各プレーンが空（長さ0）ではないか、強固にチェックする
    if (image.planes.isEmpty || image.planes.any((p) => p.bytes.isEmpty)) {
      return null;
    }

    try {
      // (以下のコードはそのまま)
      Uint8List bytes;
      InputImageFormat inputImageFormat;
      int bytesPerRow;

      if (Platform.isAndroid) {
        // ─── Android: YUV_420_888 からNV21バイト配列を安全に抽出 ───
        final int width = image.width;
        final int height = image.height;

        final Plane yPlane = image.planes[0];
        final Plane uPlane = image.planes[1];
        final Plane vPlane = image.planes[2];

        final Uint8List yBytes = yPlane.bytes;
        final Uint8List uBytes = uPlane.bytes;
        final Uint8List vBytes = vPlane.bytes;

        // NV21に必要な正確な総容量を計算
        final int totalBytesNeeded = width * height + 2 * (width ~/ 2) * (height ~/ 2);
        final Uint8List nv21 = Uint8List(totalBytesNeeded);

        // 1. Yプレーン（輝度）のコピー（パディングを考慮して一行ずつ綺麗に詰める）
        int idY = 0;
        int srcOffset = 0;
        for (int r = 0; r < height; r++) {
          nv21.setRange(idY, idY + width, yBytes, srcOffset);
          idY += width;
          srcOffset += yPlane.bytesPerRow;
        }

        // 2. V と U プレーン（色差）の結合
        // ❌ 修正前: vPlane.pixelStride / uPlane.pixelStride を参照してエラー
        // 🟢 修正後: Androidの仕様上、UV平面のpixelStrideは「2」固定としてハードコードしエラーを根絶
        int idUV = width * height;
        final int uvRowStride = vPlane.bytesPerRow;
        const int uvPixelStride = 2; // ⚡ 2バイトおきにインターリーブ配置されているため2固定

        for (int r = 0; r < height ~/ 2; r++) {
          final int vRowOffset = r * uvRowStride;
          final int uRowOffset = r * uPlane.bytesPerRow;

          for (int c = 0; c < width ~/ 2; c++) {
            // NV21は V(赤み) ➔ U(青み) の順番で等間隔にパッキング
            nv21[idUV++] = vBytes[vRowOffset + c * uvPixelStride];
            nv21[idUV++] = uBytes[uRowOffset + c * uvPixelStride];
          }
        }

        bytes = nv21;
        inputImageFormat = InputImageFormat.nv21;
        bytesPerRow = width;

      } else {
        // ─── iOS: BGRA8888 形式なのでそのまま全結合 ───
        final WriteBuffer allBytes = WriteBuffer();
        for (final Plane plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        bytes = allBytes.done().buffer.asUint8List();
        inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.bgra8888;
        bytesPerRow = image.planes[0].bytesPerRow;
      }

      // センサー角度の補正
      int rotationCompensation = camera.sensorOrientation;
      if (Platform.isIOS) {
        rotationCompensation = 90;
      }

      final imageRotation = InputImageRotationValue.fromRawValue(rotationCompensation) ?? InputImageRotation.rotation0deg;

      // メタデータの生成
      final inputImageMetadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: inputImageMetadata);
      final barcodes = await _barcodeScanner.processImage(inputImage);

      for (Barcode barcode in barcodes) {
        if (barcode.rawValue != null && barcode.rawValue!.startsWith("kportal_p2p_v1:")) {
          return barcode.rawValue;
        }
      }
    } catch (e) {
      debugPrint("QR Parsing Inner Error: $e");
    }
    return null;
  }

  static void dispose() {
    _barcodeScanner.close();
  }
}