import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

class CookieService {
  // iOSのApp Groupと通信するための専用チャンネル
  static const MethodChannel _appGroupChannel = MethodChannel('com.h.k.portal/app_group');

  /// 🟢 Safari拡張機能からトークンを回収し、アプリ内に同期する
  static Future<void> syncSessionFromExtension() async {
    try {
      final String? sessionToken = await _appGroupChannel.invokeMethod('getAppGroupCookie');
      if (sessionToken != null && sessionToken.isNotEmpty) {
        // App Groupから回収したトークンをSecureStorageに保存し、アプリ全体で使えるようにする
        await AuthService.saveSession(sessionToken);
        debugPrint("Safari拡張機能からのセッション同期に成功しました");
      }
    } on PlatformException catch (e) {
      debugPrint("拡張機能からのセッション取得エラー: '${e.message}'.");
    }
  }

  /// 🟢 App Group ではなく AuthService (SecureStorage) から最新ヘッダーを取得
  static Future<Map<String, String>> getHeaders() async {
    return await AuthService.getHeaders();
  }

  /// 🟢 既存コードとの互換性のためのセッション文字列取得
  static Future<String?> getSavedCookie() async {
    return await AuthService.getSession();
  }
}