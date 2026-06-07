import 'package:flutter/foundation.dart'; // ← debugPrint用に追加
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as fss;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import '../utils/lms_adapter.dart';
//auth_service.dart

class AuthService {
  static const _storage = fss.FlutterSecureStorage(
    aOptions: fss.AndroidOptions(encryptedSharedPreferences: true),
  );
  static const String _cookieKey = 'canvas_cookie';

  static Future<void> saveSession(String cookie) async {
    try {
      await _storage.write(key: _cookieKey, value: cookie);
    } catch (e) {
      debugPrint("AuthService.saveSession Error: $e");
    }
  }

  static Future<String?> getSession() async {
    try {
      return await _storage.read(key: _cookieKey);
    } catch (e) {
      debugPrint("AuthService.getSession Error: $e");
      return null;
    }
  }

  static Future<void> clearSession() async {
    try {
      await _storage.delete(key: _cookieKey);
      await CookieManager.instance().deleteCookies(url: WebUri(canvasBaseUrl));
    } catch (e) {
      debugPrint("AuthService.clearSession Error: $e");
    }
  }

  static Future<bool> validateSession(String cookie) async {
    try {
      final uri = Uri.tryParse('$canvasBaseUrl/api/v1/users/self');
      if (uri == null) return false;
      final response = await http.get(uri, headers: {'Cookie': cookie}).timeout(const Duration(seconds: 10)); // ← タイムアウト追加
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("AuthService.validateSession Error: $e");
      return false;
    }
  }
}


