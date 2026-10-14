import 'package:flutter/services.dart';

class CookieService {
  static const _platform = MethodChannel('com.h.k.portal/cookies');

  /// App Group から保存された Cookie を読み出す
  static Future<String?> getSavedCookie() async {
    try {
      final String? cookie = await _platform.invokeMethod('getAppGroupCookie');
      return cookie;
    } on PlatformException catch (e) {
      print("Failed to read App Group Cookie: '${e.message}'.");
      return null;
    }
  }
}