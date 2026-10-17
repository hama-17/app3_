import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

class CookieService {
  static const MethodChannel _appGroupChannel = MethodChannel('com.h.k.portal/app_group');

  /// 🟢 bool から String に変更し、最終的なヘッダーを返す
  static Future<String> syncSessionFromExtension() async {
    try {
      String? sessionToken = await _appGroupChannel.invokeMethod('getAppGroupCookie');
      if (sessionToken != null && sessionToken.isNotEmpty) {



        await AuthService.saveSession(sessionToken);

        // 🚨 最終的にAPIに送られるヘッダーを取得
        final headers = await AuthService.getHeaders();

        // ヘッダーの中身を画面に表示するために返す
        return "SUCCESS: $headers";
      }
      return "EMPTY: トークンが空でした";
    } on PlatformException catch (e) {
      return "ERROR: '${e.message}'";
    } catch (e) {
      return "ERROR: $e";
    }
  }

  static Future<Map<String, String>> getHeaders() async {
    return await AuthService.getHeaders();
  }

  static Future<String?> getSavedCookie() async {
    return await AuthService.getSession();
  }
}