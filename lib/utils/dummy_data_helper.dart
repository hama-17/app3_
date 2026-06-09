// lib/utils/dummy_data_helper.dart

class DummyDataHelper {
  // 1. 曜日・時限・教室を完璧に定義した全8科目のリアルな授業リスト
  // lib/utils/dummy_data_helper.dart 内の getCourses を以下に差し替え
  // lib/utils/dummy_data_helper.dart 内の getCourses を本番生データ形式に修正
  static List<dynamic> getCourses(int currentYear) {
    return [
      {
        'id': 991,
        'name': '[月1月2]佐藤 教授 材料力学第1[14棟201]',
        'created_at': '${currentYear}-04-01T00:00:00Z',
        'term': {'name': '$currentYear年度 春学期'},
        'teachers': [{'id': 1, 'name': '佐藤 教授'}]
      },
      {
        'id': 992,
        'name': '[月3月4]田中 准教授 制御工学概論[11棟312]',
        'created_at': '${currentYear}-04-01T00:00:00Z',
        'term': {'name': '$currentYear年度 春学期'},
        'teachers': [{'id': 2, 'name': '田中 准教授'}]
      },
      {
        'id': 993,
        'name': '[火3火4]鈴木 教授 熱力学基礎[12棟102]',
        'created_at': '${currentYear}-04-01T00:00:00Z',
        'term': {'name': '$currentYear年度 春学期'},
        'teachers': [{'id': 3, 'name': '鈴木 教授'}]
      },
      {
        'id': 994,
        'name': '[水1水2]高橋 教授 電磁気学[14棟101]',
        'created_at': '${currentYear}-04-01T00:00:00Z',
        'term': {'name': '$currentYear年度 春学期'},
        'teachers': [{'id': 4, 'name': '高橋 教授'}]
      },
      {
        'id': 995,
        'name': '[水5水6]渡辺 准教授 流体力学[14棟203]',
        'created_at': '${currentYear}-04-01T00:00:00Z',
        'term': {'name': '$currentYear年度 春学期'},
        'teachers': [{'id': 5, 'name': '渡辺 准教授'}]
      },
      {
        'id': 996,
        'name': '[木1木2]伊藤 教授 解析力学[14棟202]',
        'created_at': '${currentYear}-04-01T00:00:00Z',
        'term': {'name': '$currentYear年度 春学期'},
        'teachers': [{'id': 6, 'name': '伊藤 教授'}]
      },
      {
        'id': 997,
        'name': '[金3金4]山本 教授 数理統計学[10棟201]',
        'created_at': '${currentYear}-04-01T00:00:00Z',
        'term': {'name': '$currentYear年度 春学期'},
        'teachers': [{'id': 7, 'name': '山本 教授'}]
      },
      {
        'id': 998,
        'name': '[金5]中村 准教授 システムデザイン論[11棟205]',
        'created_at': '${currentYear}-04-01T00:00:00Z',
        'term': {'name': '$currentYear年度 春学期'},
        'teachers': [{'id': 8, 'name': '中村 准教授'}]
      }
    ];
  }

  // 2. 本番さながらの課題リスト（TASKSセクション連動）
  static List<dynamic> getDummyAssignments(int currentYear) {
    final now = DateTime.now();
    return [
      {
        'id': 881,
        'name': '第3章：不静定応力に関する演習問題レポート',
        'due_at': DateTime(now.year, now.month, now.day + 1, 23, 59).toIso8601String(),
        'context_name': '材料力学第1 [MON 1.2] [14棟201]',
        'course_id': 991,
        'points_possible': 10,
        'submission_types': ['online_upload'],
        'allowed_extensions': ['pdf']
      },
      {
        'id': 882,
        'name': 'マクスウェル方程式の導出と境界条件の考察',
        'due_at': DateTime(now.year, now.month, now.day + 3, 18, 0).toIso8601String(),
        'context_name': '電磁気学 [WED 1.2] [14棟101]',
        'course_id': 994,
        'points_possible': 20,
        'submission_types': ['online_upload'],
        'allowed_extensions': ['pdf']
      },
      {
        'id': 883,
        'name': '前半部分の中間振り返りレポート（全2枚）',
        'due_at': DateTime(now.year, now.month, now.day + 6, 23, 59).toIso8601String(),
        'context_name': '解析力学 [THU 1.2] [14棟202]',
        'course_id': 996,
        'points_possible': 100,
        'submission_types': ['online_upload'],
        'allowed_extensions': ['pdf', 'docx']
      }
    ];
  }

  // 3. リアルな掲示板連絡（MESSAGESセクション連動）
  static List<dynamic> getDummyMessages() {
    return [
      {
        'id': 771,
        'title': '【重要】来週の講義について（対面からオンデマンドへの一時変更）',
        'posted_at': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
        'context_name': '材料力学第1',
        'course_id': 991,
        'message': '出張に伴い、来週月曜日の講義はオンデマンド形式（動画視聴と確認クイズ）に変更します。資料はモジュールを確認してください。'
      },
      {
        'id': 772,
        'title': 'レポート課題の評価基準（ルーブリック）の公開について',
        'posted_at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        'context_name': '電磁気学',
        'course_id': 994,
        'message': '現在公開中の課題について、評価基準をPDFで添付しました。採点時の参考にしてください。'
      },
      {
        'id': 773,
        'title': '【お知らせ】参考図書の紹介と図書室での貸出について',
        'posted_at': DateTime.now().subtract(const Duration(days: 3)).toIso8601String(),
        'context_name': 'システムデザイン論',
        'course_id': 998,
        'message': '講義内で触れた「近代システム工学」の解説書が、理工学図書室の指定図書コーナーに配架されました。自由に活用してください。'
      }
    ];
  }

  // 4. 各授業をタップした時の詳細画面用データ（MODULES / ASSIGNMENTS / GRADES / ANNOUNCE）
  static List<dynamic> getDetails(String type) {
    if (type == 'MODULES') {
      return [
        {
          'id': 'dm1',
          'name': '第1回：イントロダクションとシラバス解説',
          'items': [
            {'title': '講義ガイドライン配布資料', 'type': 'File', 'url': 'https://example.com/guide.pdf'},
            {'title': '教科書の紹介と講義スケジュールについて', 'type': 'Page', 'url': 'https://example.com/page1'}
          ]
        },
        {
          'id': 'dm2',
          'name': '第2回：基礎方程式とマトリクス表現',
          'items': [
            {'title': '第2回 講義レジュメノート（PDF）', 'type': 'File', 'url': 'https://example.com/resume2.pdf'},
            {'title': '演習問題：基本プログラミングと数式検証', 'type': 'Assignment', 'url': 'https://example.com/assign2'}
          ]
        }
      ];
    } else if (type == 'ASSIGNMENTS' || type == 'GRADES') {
      return [
        {
          'id': 'da1',
          'name': '第1回演習課題の提出（講義内容のまとめ）',
          'due_at': DateTime.now().add(const Duration(days: 3)).toIso8601String(),
          'points_possible': 10,
          'submission_types': ['file_upload'],
          'allowed_extensions': ['pdf'],
          'submission': {'score': 8.5, 'workflow_state': 'graded'}
        },
        {
          'id': 'da2',
          'name': '中間課題：テーマに基づく考察論文',
          'due_at': DateTime.now().add(const Duration(days: 10)).toIso8601String(),
          'points_possible': 50,
          'submission_types': ['file_upload'],
          'allowed_extensions': ['pdf', 'docx'],
          'submission': {'score': null, 'workflow_state': 'submitted'}
        }
      ];
    } else {
      return [
        {
          'id': 'dn1',
          'title': '講義に関する補足説明と質問への回答',
          'posted_at': DateTime.now().toIso8601String(),
          'message': '前回の講義後のアンケートで要望の多かった、数式展開の補足ドキュメントを作成しました。詳細なステップを記載していますので各自復習に用いてください。'
        }
      ];
    }
  }
}