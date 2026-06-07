// lib/utils/term_helper.dart

class TermHelper {
  /// 1. 日付から「現在のQ（クォーター）」を自動判定する
  static String getTermForDate(DateTime date) {
    int m = date.month;
    if (m >= 4 && m <= 5) return 'Q1'; // 4〜5月はQ1
    if (m >= 6 && m <= 8) return 'Q2'; // 6〜8月はQ2
    if (m >= 9 && m <= 10) return 'Q3'; // 9〜10月はQ3
    return 'Q4'; // 11〜3月はQ4
  }

  /// 2. 授業データから「年度（Year）」を抽出する（日本の4月始まり対応）
  static int getCourseYear(dynamic course, int fallbackYear) {
    if (course['is_custom'] == true) return fallbackYear; // カスタム授業は年度スルー

    String termName = course['term']?['name'] ?? '';
    RegExp yearExp = RegExp(r'(20[0-9]{2})'); // 例: "2026年度" から 2026 を抽出
    var match = yearExp.firstMatch(termName);
    if (match != null) {
      return int.parse(match.group(1)!);
    }

    String createdAt = course['created_at'] ?? '';
    if (createdAt.isNotEmpty) {
      DateTime? dt = DateTime.tryParse(createdAt)?.toLocal();
      if (dt != null) {
        int year = dt.year;
        if (dt.month < 4) year -= 1; // 1〜3月は前年度扱い
        return year;
      }
    }
    return fallbackYear;
  }

  /// 3. 授業データ＋ユーザーの手動上書きから、その授業の「真の学期属性」を抽出する
  static List<String> getCourseTerms(dynamic course, Map<String, String> overrides) {
    String cId = course['is_custom'] == true ? (course['raw_name'] ?? course['name'] ?? '') : course['id'].toString();

    if (overrides.containsKey(cId)) {
      String overrideStr = overrides[cId]!;
      if (overrideStr == "未選択") return [];
      return overrideStr.split('.');
    }

    String rawName = course['name'] ?? '';
    String termName = course['term']?['name'] ?? '';
    String combined = "$rawName $termName".toUpperCase();

    List<String> terms = [];
    bool isSpring = combined.contains('春') || combined.contains('前学期') || combined.contains('前期');
    bool isFall = combined.contains('秋') || combined.contains('後学期') || combined.contains('後期');
    bool isFullYear = combined.contains('通年');

    if (combined.contains('Q1')) terms.add('Q1');
    if (combined.contains('Q2')) terms.add('Q2');
    if (combined.contains('Q3')) terms.add('Q3');
    if (combined.contains('Q4')) terms.add('Q4');

    if (terms.isEmpty) {
      if (isFullYear) {
        terms.addAll(['Q1', 'Q2', 'Q3', 'Q4']);
      } else if (isSpring) {
        if (combined.contains('前半')) terms.add('Q1');
        else if (combined.contains('後半')) terms.add('Q2');
        else terms.addAll(['Q1', 'Q2']);
      } else if (isFall) {
        if (combined.contains('前半')) terms.add('Q3');
        else if (combined.contains('後半')) terms.add('Q4');
        else terms.addAll(['Q3', 'Q4']);
      } else {
        terms.addAll(['Q1', 'Q2', 'Q3', 'Q4']);
      }
    }
    return terms;
  }

  /// 4. ダッシュボードやカレンダーで「この授業は今表示すべきか？」を年度と学期で最終判定する
  static bool shouldDisplayCourse(dynamic course, Map<String, String> overrides, int targetYear, String targetTerm) {
    // 💡 まずは年度（Year）が一致しているかを厳密にチェック！
    int courseYear = getCourseYear(course, targetYear);
    if (courseYear != targetYear) return false;

    // 年度チェックを通過したら、学期（Term）のチェック
    List<String> courseTerms = getCourseTerms(course, overrides);

    if (targetTerm.contains('春')) return courseTerms.contains('Q1') || courseTerms.contains('Q2');
    if (targetTerm.contains('秋')) return courseTerms.contains('Q3') || courseTerms.contains('Q4');
    if (targetTerm.contains('通年')) return courseTerms.isNotEmpty;

    if (targetTerm.contains('Q1') && courseTerms.contains('Q1')) return true;
    if (targetTerm.contains('Q2') && courseTerms.contains('Q2')) return true;
    if (targetTerm.contains('Q3') && courseTerms.contains('Q3')) return true;
    if (targetTerm.contains('Q4') && courseTerms.contains('Q4')) return true;

    return false;
  }
}