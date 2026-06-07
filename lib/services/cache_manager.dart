import 'dart:convert';
import 'package:flutter/foundation.dart'; // ← debugPrint用に追加
import 'package:shared_preferences/shared_preferences.dart';
//cache_manager.dart

class CacheManager {
  static Future<void> save(String key, dynamic data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode({'timestamp': DateTime.now().millisecondsSinceEpoch, 'data': data}));
    } catch (e) {
      debugPrint("CacheManager.save Error [$key]: $e");
    }
  }

  static Future<dynamic> load(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(key);
      if (str == null) return null;
      final decoded = jsonDecode(str);
      if (decoded is Map && decoded.containsKey('data')) return decoded['data'];
    } catch (e) {
      debugPrint("CacheManager.load Error [$key]: $e");
    }
    return null;
  }
}

