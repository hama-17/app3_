import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class P2pSyncService {
  static HttpServer? _httpServer;
  static const int _port = 8888; // 固定ポート

  /// 🟢 ① iPad（受信側）：超軽量なHTTPサーバーを起動し、自分のIPを仕込んだQR文字列を返す
  static Future<String> startReceiverServer({required VoidCallback onSyncSuccess}) async {
    await stopServer(); // 念のため二重起動防止

    try {
      // 端末のローカルネットワーク上のIPアドレス（192.168.xx.xxなど）を自動抽出
      String localIp = "";
      final interfaces = await NetworkInterface.list(includeLoopback: false, type: InternetAddressType.IPv4);
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.address.startsWith("169.254")) { // リンクローカルアドレスを除外
            localIp = addr.address;
            break;
          }
        }
        if (localIp.isNotEmpty) break;
      }

      if (localIp.isEmpty) {
        return "kportal_p2p_v1:error_no_wifi";
      }

      // 指定ポートでローカルHTTPサーバーをバインド（全インターフェースで受付）
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      debugPrint("🚀 P2P Server Started on http://$localIp:$_port");

      // 内部リスナーの開通（iPhoneからのPOST突入をここで待ち受ける）
      _httpServer!.listen((HttpRequest request) async {
        debugPrint("📥 [P2P] リクエスト到達: ${request.method} ${request.uri.path}"); // 👈 これがログに出るか確認

        if (request.method == 'POST' && request.uri.path == '/sync_cookie') {
          try {
            // 送られてきた暗号化パケットの解析
            final content = await utf8.decoder.bind(request).join();
            final Map<String, dynamic> data = jsonDecode(content);

            String encryptedCookie = data['cookie'] ?? '';

            if (encryptedCookie.isNotEmpty) {
              // 🔒 ここでクッキーの復号・ローカル保存処理を执行
              // (例: await AuthService.saveCookie(decrypt(encryptedCookie)); )
              debugPrint("⚡ クッキーの密輸を検知・復元に成功しました。");

              // iPhone側に200 OKをレスポンス
              request.response
                ..statusCode = HttpStatus.ok
                ..write(jsonEncode({'status': 'success'}))
                ..close();

              onSyncSuccess(); // 画面側の時間割復元トリガーを発火
              return;
            }
          } catch (e) {
            debugPrint("Server Parsing Error: $e");
          }
        }

        // 不正アクセス、または処理失敗時は400を返す
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write(jsonEncode({'status': 'fail'}))
          ..close();
      });

      // 🎯 カメラ側に渡すQRコードのペイロード文字列
      // Quick Shareのメタデータではなく、ただの「独自の接続先プレーンテキスト」にする
      return "kportal_p2p_v1:$localIp";

    } catch (e) {
      debugPrint("P2P Server Start Failed: $e");
      return "kportal_p2p_v1:error_server_failed";
    }
  }

  /// 🟢 ② iPhone（送信側）：QRからIPを読み取り、HTTP POSTでクッキーを相手に直接射出する
  static Future<bool> scanAndSendCookie(String qrText) async {
    debugPrint("📸 [P2P] QR検出成功: $qrText"); // 👈 これが出ていなければQR読み取り自体がNG

    final String ipAddress = qrText.replaceAll("kportal_p2p_v1:", "");
    if (ipAddress.contains("error") || ipAddress.isEmpty) return false;

    try {
      final targetUrl = Uri.parse("http://$ipAddress:$_port/sync_cookie");
      debugPrint("✈️ [P2P] 射出先アドレス: $targetUrl"); // 👈 IPが正しいか確認

      final response = await http.post(
        targetUrl,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'cookie': "test_data"}), // 一旦ダミー
      ).timeout(const Duration(seconds: 5));

      debugPrint("📡 [P2P] 受信側の反応コード: ${response.statusCode}"); // 👈 これが 200 なら成功、それ以外ならエラー
      return response.statusCode == HttpStatus.ok;
    } catch (e) {
      debugPrint("❌ [P2P] 通信エラー詳細: $e"); // 👈 接続拒否ならここに出る
      return false;
    }
  }

  /// 🟢 ③ サーバーの完全シャットダウン
  static Future<void> stopServer() async {
    if (_httpServer != null) {
      await _httpServer!.close(force: true);
      _httpServer = null;
      debugPrint("🛑 P2P Server Safely Closed.");
    }
  }
}