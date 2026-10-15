import '../services/auth_service.dart';

class CookieService {
  /// 🟢 App Group ではなく AuthService (SecureStorage) から最新ヘッダーを取得
  static Future<Map<String, String>> getHeaders() async {
    return await AuthService.getHeaders();
  }

  /// 🟢 既存コードとの互換性のためのセッション文字列取得
  static Future<String?> getSavedCookie() async {
    return await AuthService.getSession();
  }

}