import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/material.dart';

//app_snackbar.dart

// ★ 修正： OSのアクセシビリティ設定を無視して、強制的に1.5秒で消すタイマーを追加
class AppSnackBar {
  // ★ 追加：現在稼働中のタイマーを保持し、重複実行を防ぐための変数
  static Timer? _hideTimer;

  static void showUndo(BuildContext context, String message, VoidCallback onUndo) {
    final messenger = ScaffoldMessenger.of(context);

    // 既存のスナックバーを確実に消してから新しいものを表示
    messenger.clearSnackBars();

    // ★ 追加：以前のタイマーが動いていたらキャンセル（リセット）する
    _hideTimer?.cancel();

    const Color barBgColor = Colors.black;
    const Color vibrantRed = Color(0xFFFF1744);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
            message,
            style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.w300,
                fontSize: 13
            )
        ),
        backgroundColor: barBgColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 2000),
        elevation: 0,
        margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 2.0,
            left: 8.0,
            right: 8.0
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        action: SnackBarAction(
          label: "元に戻す",
          textColor: vibrantRed,
          onPressed: onUndo,
        ),
      ),
    );

    // ★ 修正：タイマーを変数に格納し、2秒後に実行。連続呼び出し時は上でキャンセルされる
    _hideTimer = Timer(const Duration(milliseconds: 2000), () {
      try {
        messenger.hideCurrentSnackBar();
      } catch (_) {}
    });
  }

  static void showError(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    _hideTimer?.cancel(); // エラー表示時も念のためタイマーをリセット

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFD0312D), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                    color: Color(0xFFD0312D),
                    fontWeight: FontWeight.w300,
                    fontSize: 13
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.black,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        elevation: 0,
        margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 80.0,
            left: 8.0,
            right: 8.0
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
    );
  }
}