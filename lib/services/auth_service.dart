import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as fss;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import '../utils/lms_adapter.dart';
import 'dart:io';

class AuthService {
  static const _storage = fss.FlutterSecureStorage(
    aOptions: fss.AndroidOptions(encryptedSharedPreferences: true),
  );
  static const String _cookieKey = 'canvas_cookie';

  /// 🟢 セッション（クッキーまたはAPIトークン）の保存
  static Future<void> saveSession(String credential) async {
    try {
      await _storage.write(key: _cookieKey, value: credential);
    } catch (e) {
      debugPrint("AuthService.saveSession Error: $e");
    }
  }

  /// 🟢 保存されているセッション（クッキーまたはAPIトークン）の取得
  static Future<String?> getSession() async {
    try {
      return await _storage.read(key: _cookieKey);
    } catch (e) {
      debugPrint("AuthService.getSession Error: $e");
      return null;
    }
  }

  /// 🟢 セッションおよびキャッシュの一括初期化（ログアウト用）
  static Future<void> clearSession() async {
    try {
      // 1. SecureStorage から暗号化データを削除
      await _storage.delete(key: _cookieKey);

      // 2. 全クッキーを一括完全初期化
      await CookieManager.instance().deleteAllCookies();

      // 3. WebStorage (LocalStorage / SessionStorage) の削除
      final storageManager = WebStorageManager.instance();
      if (Platform.isAndroid) {
        await storageManager.android.deleteAllData();
      } else if (Platform.isIOS) {
        await storageManager.ios.fetchDataRecords(dataTypes: {
          IOSWKWebsiteDataType.WKWebsiteDataTypeLocalStorage,
          IOSWKWebsiteDataType.WKWebsiteDataTypeCookies,
        });
      }
    } catch (e) {
      debugPrint("AuthService.clearSession Error: $e");
    }
  }

  /// 🟢 クレデンシャル形式（Cookie / Bearer Token）を自動判定してヘッダーを構築
  static Map<String, String> buildHeaders(String credential) {
    // クッキー形式（'=' や ';' を含む）か API トークン形式（純粋な文字列）かを自動判別
    if (credential.contains('=') || credential.contains(';')) {
      return {
        'Cookie': credential,
        'Accept': 'application/json',
      };
    } else {
      return {
        'Authorization': 'Bearer $credential',
        'Accept': 'application/json',
      };
    }
  }

  /// 🟢 保存中のクレデンシャルから最適な HTTP リクエストヘッダーを取得
  static Future<Map<String, String>> getHeaders() async {
    final credential = await getSession();
    if (credential == null || credential.isEmpty) {
      return {'Accept': 'application/json'};
    }
    return buildHeaders(credential);
  }

  /// 🟢 クッキー／APIトークンの両方に対応したセッション検証
  static Future<bool> validateSession(String credential) async {
    try {
      final uri = Uri.tryParse('$canvasBaseUrl/api/v1/users/self');
      if (uri == null) return false;

      // 自動判別された適切なヘッダーで API をテスト
      final headers = buildHeaders(credential);
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("AuthService.validateSession Error: $e");
      return false;
    }
  }
}