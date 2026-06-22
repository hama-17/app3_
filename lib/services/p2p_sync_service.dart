import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import './auth_service.dart';
import '../utils/lms_adapter.dart';

class P2pSyncService {
  static HttpServer? _server;
  static String? _currentOtpKey; // 使い捨て暗号鍵

  /// 🟢 【iPad側（レシーバー）】ソケットサーバーを起動し、QRコード用のペイロードを生成する
  static Future<String> startReceiverServer({required VoidCallback onSyncSuccess}) async {
    await stopServer(); // 念のため古いサーバーを完全パージ

    // 1. 自身のローカルIPアドレス（Wi-FiのIP）を自動抽出
    String localIp = "127.0.0.1";
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (var interface in interfaces) {
      for (var addr in interface.addresses) {
        if (!addr.isLoopback && addr.address.startsWith("10.") || addr.address.startsWith("192.168.") || addr.address.startsWith("172.")) {
          localIp = addr.address;
          break;
        }
      }
    }

    // 2. この通信のためだけの「使い捨ての16文字暗号鍵(AES)」をランダム生成
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random.secure();
    _currentOtpKey = List.generate(16, (index) => chars[rnd.nextInt(chars.length)]).join();

    // 3. ステルスHTTPサーバーをポート「8989」でバインド起動
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 8989);
    debugPrint("P2P Receiver Server Started on $localIp:8989");

    // 4. データ受信時の迎撃インターセプター
    _server!.listen((HttpRequest request) async {
      if (request.method == 'POST') {
        try {
          final body = await utf8.decoder.bind(request).join();
          final Map<String, dynamic> json = jsonDecode(body);
          final String encryptedCookie = json['data'];
          final String ivStr = json['iv'];

          // 5. 保持している使い捨て鍵でAES-256復号を執行
          final key = encrypt.Key.fromUtf8(_currentOtpKey!);
          final iv = encrypt.IV.fromBase64(ivStr);
          final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

          final decryptedCookie = encrypter.decrypt64(encryptedCookie, iv: iv);

          // 6. 復号されたクッキーを自前のAuthServiceへインプラント（保存）
          if (decryptedCookie.contains('canvas_session') || decryptedCookie.contains('_csrf_token')) {
            await AuthService.saveSession(decryptedCookie);

            // WebView側のシステムクッキーマネージャーにもスタンプを強制同期
            final cookieManager = CookieManager.instance();
            await cookieManager.setCookie(
              url: WebUri(canvasBaseUrl),
              name: "canvas_session",
              value: RegExp(r'canvas_session=([^;]+)').firstMatch(decryptedCookie)?.group(1) ?? '',
              isSecure: true,
            );

            // 成功レスポンスを返して回線を閉じる
            request.response
              ..statusCode = HttpStatus.ok
              ..write(jsonEncode({'status': 'success'}))
              ..close();

            await stopServer();
            onSyncSuccess(); // UI側に成功を通知
            return;
          }
        } catch (e) {
          debugPrint("P2P Data Parse Error: $e");
        }
      }
      request.response
        ..statusCode = HttpStatus.badRequest
        ..close();
    });

    // 💡 QRコードに埋め込むデータ（バージョン名:自分のIP:暗号鍵）
    return "kportal_p2p_v1:$localIp:$_currentOtpKey";
  }

  /// 🟢 【iPhone側（センダー）】QRコードからパースした情報を元に、暗号化クッキーをソケット射出する
  static Future<bool> scanAndSendCookie(String qrPayload) async {
    try {
      if (!qrPayload.startsWith("kportal_p2p_v1:")) return false;

      // 1. QRコードのペイロードを分解 (IPと暗号鍵を抽出)
      final parts = qrPayload.split(":");
      if (parts.length < 3) return false;
      final String targetIp = parts[1];
      final String targetKeyStr = parts[2];

      // 2. 自前のストレージから現役のクッキー（通行証）をサルベージ
      final String? currentCookie = await AuthService.getSession();
      if (currentCookie == null || currentCookie.isEmpty) return false;

      // 3. 抽出した使い捨て鍵を使ってクッキーを最高強度AESで暗号化
      final key = encrypt.Key.fromUtf8(targetKeyStr);
      final iv = encrypt.IV.fromLength(16); // 16バイトのランダムIV
      final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

      final encrypted = encrypter.encrypt(currentCookie, iv: iv);

      // 4. 相手のiPadのポート「8989」めがけてソケット（HTTP POST）で超高速射出
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final request = await client.post(targetIp, 8989, '/');
      request.headers.contentType = ContentType.json;

      request.write(jsonEncode({
        'data': encrypted.base64,
        'iv': iv.base64,
      }));

      final response = await request.close();
      return response.statusCode == HttpStatus.ok;
    } catch (e) {
      debugPrint("P2P Send Error: $e");
      return false;
    }
  }

  /// サーバーの安全停止
  static Future<void> stopServer() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      _currentOtpKey = null;
      debugPrint("P2P Receiver Server Stopped.");
    }
  }
}
