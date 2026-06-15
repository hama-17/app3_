// lib/utils/dummy_data_helper.dart

class DummyDataHelper {
  // 1. 曜日・時限・教室を完璧に定義した全8科目のリアルな授業リスト
  // lib/utils/dummy_data_helper.dart 内の getCourses を以下に差し替え
  // lib/utils/dummy_data_helper.dart 内の getCourses を本番生データ形式に修正
  static List<dynamic> getCourses(int currentYear) {
    return [
      {
        'id': 991,
        'name': '[月1] 材料力学第1[14棟201]',
        'created_at': '${currentYear}-04-01T00:00:00Z',
        'term': {'name': '$currentYear年度 春学期'},
        'teachers': [{'id': 1, 'name': '佐藤 教授'}]
      },
      {
        'id': 992,
        'name': '[月3月4] 制御工学概論[11棟312]',
        'created_at': '${currentYear}-04-01T00:00:00Z',
        'term': {'name': '$currentYear年度 春学期'},
        'teachers': [{'id': 2, 'name': '田中 准教授'}]
      },
      {
        'id': 993,
        'name': '[火4木4] 熱力学基礎[12棟102]',
        'created_at': '${currentYear}-04-01T00:00:00Z',
        'term': {'name': '$currentYear年度 春学期'},
        'teachers': [{'id': 3, 'name': '鈴木 教授'}]
      },
      {
        'id': 994,
        'name': '[水2金2] 電磁気学[14棟101]',
        'created_at': '${currentYear}-04-01T00:00:00Z',
        'term': {'name': '$currentYear年度 春学期'},
        'teachers': [{'id': 4, 'name': '高橋 教授'}]
      },
      {
        'id': 995,
        'name': '[水5] 流体力学[14棟203]',
        'created_at': '${currentYear}-04-01T00:00:00Z',
        'term': {'name': '$currentYear年度 春学期'},
        'teachers': [{'id': 5, 'name': '渡辺 准教授'}]
      },
      {
        'id': 996,
        'name': '[木1木2] 解析力学[14棟202]',
        'created_at': '${currentYear}-04-01T00:00:00Z',
        'term': {'name': '$currentYear年度 春学期'},
        'teachers': [{'id': 6, 'name': '伊藤 教授'}]
      },
      {
        'id': 997,
        'name': '[水4金4] 数理統計学[10棟201]',
        'created_at': '${currentYear}-04-01T00:00:00Z',
        'term': {'name': '$currentYear年度 春学期'},
        'teachers': [{'id': 7, 'name': '山本 教授'}]
      },
      {
        'id': 998,
        'name': '[金5] システムデザイン論[11棟205]',
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
  // lib/utils/dummy_data_helper.dart 内の getDetails メソッドを完全に置き換え
  static List<dynamic> getDetails(String type, int courseId) {
    // ----------------------------------------------------
    // ① MODULES タブ（PDF / Fileビューアが開くものを完全に排除）
    // ----------------------------------------------------
    if (type == 'MODULES') {
      String courseName = "講義";
      if (courseId == 991) courseName = "材料力学";
      if (courseId == 992) courseName = "制御工学";
      if (courseId == 993) courseName = "熱力学";
      if (courseId == 994) courseName = "電磁気学";
      if (courseId == 995) courseName = "流体力学";
      if (courseId == 996) courseName = "解析力学";
      if (courseId == 997) courseName = "数理統計学";
      if (courseId == 998) courseName = "システムデザイン論";

      return [
        {
          'id': 'dm_${courseId}_1',
          'name': '第1回：ガイダンスと$courseNameの概要',
          'items': [
            // ★ 修正：File型や.pdfを排除し、すべてWebViewで安全に開くPage型やExternalUrl型へ変更
            {'title': '講義概要・進め方の確認ページ', 'type': 'Page', 'url': 'https://example.com/intro_$courseId'},
            {'title': '公式ポータル参考オンラインリンク', 'type': 'ExternalUrl', 'url': 'https://keio.jp'}
          ]
        },
        {
          'id': 'dm_${courseId}_2',
          'name': '第2回：基礎方程式と数式モデルの構築',
          'items': [
            {'title': 'オンライン学習項目セルフチェック', 'type': 'Page', 'url': 'https://example.com/check_$courseId'},
            {'title': '第2回 復習用確認オンラインクイズ', 'type': 'Quiz', 'url': 'https://example.com/quiz_$courseId'}
          ]
        }
      ];
    }

    // ----------------------------------------------------
    // ② ASSIGNMENTS / GRADES タブ（ホームのTASKSデータとIDを完全一致化）
    // ----------------------------------------------------
    if (type == 'ASSIGNMENTS' || type == 'GRADES') {
      // 各授業IDに紐づく、ホームの getDummyAssignments と完全に一致する課題データを返却
      if (courseId == 991) {
        return [
          {
            'id': '881', // ホームのタスクID「881」と連携
            'name': '第3章：不静定応力に関する演習問題レポート',
            'due_at': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
            'points_possible': 10,
            'submission_types': ['online_upload'],
            'allowed_extensions': ['pdf'],
            'submission': {'score': 9.0, 'workflow_state': 'graded'}
          }
        ];
      } else if (courseId == 994) {
        return [
          {
            'id': '882', // ホームのタスクID「882」と連携
            'name': 'マクスウェル方程式の導出と境界条件の考察',
            'due_at': DateTime.now().add(const Duration(days: 3)).toIso8601String(),
            'points_possible': 20,
            'submission_types': ['online_upload'],
            'allowed_extensions': ['pdf'],
            'submission': {'score': null, 'workflow_state': 'submitted'}
          }
        ];
      } else if (courseId == 996) {
        return [
          {
            'id': '883', // ホームのタスクID「883」と連携
            'name': '前半部分の中間振り返りレポート（全2枚）',
            'due_at': DateTime.now().add(const Duration(days: 6)).toIso8601String(),
            'points_possible': 100,
            'submission_types': ['online_upload'],
            'allowed_extensions': ['pdf', 'docx'],
            'submission': {'score': null, 'workflow_state': 'unsubmitted'}
          }
        ];
      }
      return []; // 課題が元々定義されていない授業は、リアルに空のリストを返す
    }

    // ----------------------------------------------------
    // ③ ANNOUNCE タブ（ホームのMESSAGESデータとIDを完全一致化）
    // ----------------------------------------------------
    if (type == 'ANNOUNCE') {
      // 各授業IDに紐づく、ホームの getDummyMessages と完全に一致するお知らせデータを返却
      if (courseId == 991) {
        return [
          {
            'id': '771', // ホームのメッセージID「771」と連携
            'title': '【重要】来週の講義について（対面からオンデマンドへの一時変更）',
            'posted_at': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
            'message': '出張に伴い、来週月曜日の講義はオンデマンド形式（動画視聴と確認クイズ）に変更します。資料はモジュールを確認してください。'
          }
        ];
      } else if (courseId == 994) {
        return [
          {
            'id': '772', // ホームのメッセージID「772」と連携
            'title': 'レポート課題の評価基準（ルーブリック）の公開について',
            'posted_at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
            'message': '現在公開中の課題について、評価基準をPDFで添付しました。採点時の参考にしてください。'
          }
        ];
      } else if (courseId == 998) {
        return [
          {
            'id': '773', // ホームのメッセージID「773」と連携
            'title': '【お知らせ】参考図書の紹介と図書室での貸出について',
            'posted_at': DateTime.now().subtract(const Duration(days: 3)).toIso8601String(),
            'message': '講義内で触れた「近代システム工学」の解説書が、理工学図書室の指定図書コーナーに配架されました。自由に活用してください。'
          }
        ];
      }
      return []; // お知らせが元々定義されていない授業は空リストを返す
    }
    return [];
  }
}