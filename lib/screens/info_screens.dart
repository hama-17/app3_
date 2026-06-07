import 'package:flutter/material.dart';
import '../core/app_theme.dart';
//info_screens.dart

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
                padding: const EdgeInsets.all(24.0),
                child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.arrow_back_ios, color: AppTheme.textMain(context), size: 20),
                      const SizedBox(width: 8),
                      Text("GUIDE", style: TextStyle(color: AppTheme.textMain(context), fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                    ]))),
            const SizedBox(height: 32),
            Center(
              child: Text(
                  "UNDER DEVELOPMENT",
                  style: TextStyle(
                      color: AppTheme.textMain(context).withOpacity(0.4),
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 2.0
                  )
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
                padding: const EdgeInsets.all(24.0),
                child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.arrow_back_ios, color: AppTheme.textMain(context), size: 20),
                      const SizedBox(width: 8),
                      Text("PRIVACY POLICY", style: TextStyle(color: AppTheme.textMain(context), fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                    ]))),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                children: [
                  Text("データのローカル保存について", style: TextStyle(color: AppTheme.textMain(context), fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                      "本アプリ内で作成されたパーソナライズデータ（講義メモ、カスタムタスク、設定等）は、すべてご利用の端末内にのみローカル保存されます。開発者や第三者のサーバーへデータが送信・収集されることは一切ありません。",
                      style: TextStyle(color: AppTheme.textSub(context), fontSize: 14, height: 1.6)
                  ),
                  const SizedBox(height: 32),
                  Text("認証情報と通信の安全性", style: TextStyle(color: AppTheme.textMain(context), fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                      "大学システム（Canvas LMS）へのログイン情報は、OS標準のセキュア領域（暗号化領域）に厳重に保管され、公式サーバーとの直接通信にのみ使用されます。\n\n"
                          "開発者が利用者のログイン情報を取得、閲覧、または外部へ保存することは技術的・システム的に不可能ですので、安心してお使いください。",
                      style: TextStyle(color: AppTheme.textSub(context), fontSize: 14, height: 1.6)
                  ),
                  const SizedBox(height: 64),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class TermsOfUseScreen extends StatelessWidget {
  const TermsOfUseScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
                padding: const EdgeInsets.all(24.0),
                child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.arrow_back_ios, color: AppTheme.textMain(context), size: 20),
                      const SizedBox(width: 8),
                      Text("TERMS OF USE", style: TextStyle(color: AppTheme.textMain(context), fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                    ]))),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                children: [
                  Text("システムと安全性について", style: TextStyle(color: AppTheme.textMain(context), fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                      "本アプリ内における「課題の提出」などの重要操作は、大学公式のCanvas LMSをアプリ内ブラウザ（WebView）で直接呼び出して行われます。そのため、実際のデータ送信や処理は公式システムにて安全に完結いたします。",
                      style: TextStyle(color: AppTheme.textSub(context), fontSize: 14, height: 1.6)
                  ),
                  const SizedBox(height: 32),
                  Text("ご利用にあたっての免責事項", style: TextStyle(color: AppTheme.textMain(context), fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                      "本アプリは利便性向上を目指して提供されるベータ版であり、通信状況や予期せぬシステムの不具合により、アプリ上の表示（期限、成績、スケジュール等）が公式の最新情報と異なる場合がございます。\n\n"
                          "成績に関わる重要な提出物やテストの日程につきましては、念のため公式のCanvas LMS（ブラウザ版または公式アプリ）でもご確認をお願いいたします。\n\n"
                          "なお、本アプリのご利用に起因して生じたトラブルや不利益につきましては、開発者は責任を負いかねますので、あらかじめご了承の上ご活用ください。",
                      style: TextStyle(color: AppTheme.textSub(context), fontSize: 14, height: 1.6)
                  ),
                  const SizedBox(height: 64),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

