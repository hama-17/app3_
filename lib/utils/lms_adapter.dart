import 'dart:core';
//lms_adapter.dart

// ============================================================================
// ★ 新規追加: LMS Adapter Pattern (大学依存ロジックの隔離レイヤー)
// ============================================================================
abstract class LMSAdapter {
  String get baseUrl;

  // 文字列パース系
  String cleanTitle(String rawName);
  String extractRoom(String rawName);
  String extractDayPeriod(String rawName);
  List<Map<String, int>> parseWeeklySchedule(String rawName);

  // 学期・年度判定系
  bool isSpringSemester(DateTime now);
  int getDefaultYear(DateTime now);
  String getDefaultTerm(DateTime now);
  bool isTargetCourse(dynamic course, int selectedYear, String selectedTerm);

  // 月・スケジュールの期間判定系
  bool isSpringMonth(int month);

  bool isFallMonth(int month);
  bool isSpringCourse(String combinedName);
  bool isFallCourse(String combinedName);
  bool isFullYearCourse(String combinedName);

  DateTime getSemesterStartDate(DateTime now, bool isSpring);
  DateTime getSemesterEndDate(DateTime now, bool isSpring);
}

class KeioAdapter implements LMSAdapter {
  @override
  String get baseUrl => 'https://lms.keio.jp';

  @override
  String cleanTitle(String rawName) {
    try {
      String name = rawName.replaceAll(RegExp(r'\[.*?\]'), '').trim();
      if (name.contains('　')) {
        final parts = name.split('　');
        if (parts.isNotEmpty) return parts.last.trim();
      }
      return name;
    } catch (_) { return rawName; }
  }

  @override
  String extractRoom(String rawName) {
    try {
      final match = RegExp(r'[\[［]([^\[\]［］]+)[\]］]$').firstMatch(rawName.trim());
      return match != null ? (match.group(1) ?? "").trim() : "";
    } catch (_) { return ""; }
  }

  @override
  String extractDayPeriod(String rawName) {
    try {
      final match = RegExp(r'[\[［]([月火水木金土\s1-7１-７,，]+)[\]］]').firstMatch(rawName);
      if (match != null) {
        String content = match.group(1)!;
        final pairs = RegExp(r'(月|火|水|木|金|土)\s*([1-7１-７])').allMatches(content);
        if (pairs.isNotEmpty) {
          const dayMap = {'月':'MON','火':'TUE','水':'WED','木':'THU','金':'FRI','土':'SAT'};
          const pMap = {'１':'1','２':'2','３':'3','４':'4','５':'5','６':'6','７':'7'};
          return pairs.map((p) => "${dayMap[p.group(1)!] ?? p.group(1)!} ${pMap[p.group(2)!] ?? p.group(2)!}").join(' / ');
        }
      }
      return "";
    } catch (_) { return ""; }
  }

  @override
  List<Map<String, int>> parseWeeklySchedule(String rawName) {
    List<Map<String, int>> schedule = [];
    final match = RegExp(r'\[([月火水木金土\s1-7１-７,，]+)\]').firstMatch(rawName);
    if (match != null) {
      final pairs = RegExp(r'(月|火|水|木|金|土)\s*([1-7１-７])').allMatches(match.group(1)!);
      for (var p in pairs) {
        int day = ['月', '火', '水', '木', '金', '土'].indexOf(p.group(1)!);
        int period = (int.tryParse(p.group(2)!) ?? 1) - 1;
        if (day >= 0 && period >= 0 && period < 6) schedule.add({'day': day, 'period': period});
      }
    }
    return schedule;
  }

  @override
  bool isSpringSemester(DateTime now) {
    return (now.month >= 4 && now.month <= 8) || (now.month == 9 && now.day <= 1);
  }

  @override
  int getDefaultYear(DateTime now) {
    bool isSpring = isSpringSemester(now);
    return (!isSpring && now.month < 4) ? now.year - 1 : now.year;
  }

  @override
  String getDefaultTerm(DateTime now) {
    return isSpringSemester(now) ? "春学期" : "秋学期";
  }

  @override
  bool isTargetCourse(dynamic course, int selectedYear, String selectedTerm) {
    String courseName = course['name'] ?? '';
    String courseCode = course['course_code'] ?? '';
    String termName = course['term']?['name'] ?? '';
    String combined = "$courseName $courseCode $termName".toUpperCase();

    // 1. 年度のチェック
    String fullYear = selectedYear.toString();
    String shortYear = (selectedYear % 100).toString();
    if (!combined.contains(fullYear) && !combined.contains(shortYear)) return false;

    // 2. 「通年」のチェック（常に表示）
    if (combined.contains("通年") || combined.contains("FULL YEAR")) return true;

    // 3. 基本となる学期の判定
    bool isSpringCourse = combined.contains("春") || combined.contains("前期") || combined.contains("SPRING");
    bool isFallCourse = combined.contains("秋") || combined.contains("後期") || combined.contains("FALL");

    // 4. クォーター（前半/後半）の強力な判定
    // ※「微積分第1」などの科目名に誤爆しないよう「第1」単体ではなく「1Q」「第1クォーター」等で厳密に拾います
    bool isQ1 = combined.contains("Q1") || combined.contains("1Q") || combined.contains("第1クォーター") || combined.contains("春学期前半");
    bool isQ2 = combined.contains("Q2") || combined.contains("2Q") || combined.contains("第2クォーター") || combined.contains("春学期後半");
    bool isQ3 = combined.contains("Q3") || combined.contains("3Q") || combined.contains("第3クォーター") || combined.contains("秋学期前半");
    bool isQ4 = combined.contains("Q4") || combined.contains("4Q") || combined.contains("第4クォーター") || combined.contains("秋学期後半");

    // （救済措置）もし「前半」「後半」という文字が含まれていて、春か秋かが判明している場合
    if (combined.contains("前半")) {
      if (isSpringCourse) isQ1 = true;
      if (isFallCourse) isQ3 = true;
    }
    if (combined.contains("後半")) {
      if (isSpringCourse) isQ2 = true;
      if (isFallCourse) isQ4 = true;
    }

    // 5. フルセメスター（学期全体）かどうかの判定
    // 春学期だけど、Q1でもQ2でもない ＝ 「春学期の半年間ずっとある授業（フルセメスター）」
    bool isFullSpring = isSpringCourse && !isQ1 && !isQ2;
    // 秋学期だけど、Q3でもQ4でもない ＝ 「秋学期の半年間ずっとある授業（フルセメスター）」
    bool isFullFall = isFallCourse && !isQ3 && !isQ4;

    // 6. ユーザーの選択（selectedTerm）に基づいたフィルタリング

    // --- 春学期系 ---
    if (selectedTerm == "春学期") {
      // 春学期全体を選ぶと、「Q1」「Q2」「春学期全体」の全てを表示
      return isFullSpring || isQ1 || isQ2;
    }
    if (selectedTerm.contains("Q1") && !selectedTerm.contains("Q2")) {
      // Q1のみ選択時：「Q1」と「春学期全体」を表示（Q2専用は非表示）
      return isQ1 || isFullSpring;
    }
    if (selectedTerm.contains("Q2") && !selectedTerm.contains("Q1")) {
      // Q2のみ選択時：「Q2」と「春学期全体」を表示（Q1専用は非表示）
      return isQ2 || isFullSpring;
    }
    if (selectedTerm.contains("Q1") && selectedTerm.contains("Q2")) {
      return isFullSpring || isQ1 || isQ2;
    }

    // --- 秋学期系 ---
    if (selectedTerm == "秋学期") {
      return isFullFall || isQ3 || isQ4;
    }
    if (selectedTerm.contains("Q3") && !selectedTerm.contains("Q4")) {
      // Q3のみ選択時：「Q3」と「秋学期全体」を表示（Q4専用は非表示）
      return isQ3 || isFullFall;
    }
    if (selectedTerm.contains("Q4") && !selectedTerm.contains("Q3")) {
      // Q4のみ選択時：「Q4」と「秋学期全体」を表示（Q3専用は非表示）
      return isQ4 || isFullFall;
    }
    if (selectedTerm.contains("Q3") && selectedTerm.contains("Q4")) {
      return isFullFall || isQ3 || isQ4;
    }

    // どれにも当てはまらない場合（カスタムで変な文字が指定された時の保険）
    return combined.contains(selectedTerm);
  }

  @override
  bool isSpringMonth(int month) => (month >= 4 && month <= 7);

  @override
  bool isFallMonth(int month) => (month >= 10 || month == 1);

  @override
  bool isSpringCourse(String combinedName) => combinedName.contains('春') || combinedName.contains('前期') || combinedName.contains('Q1') || combinedName.contains('Q2');

  @override
  bool isFallCourse(String combinedName) => combinedName.contains('秋') || combinedName.contains('後期') || combinedName.contains('Q3') || combinedName.contains('Q4');

  @override
  bool isFullYearCourse(String combinedName) => combinedName.contains('通年');

  @override
  DateTime getSemesterStartDate(DateTime now, bool isSpring) {
    return isSpring ? DateTime(now.year, 4, 1) : DateTime(now.month < 4 ? now.year - 1 : now.year, 9, 20);
  }

  @override
  DateTime getSemesterEndDate(DateTime now, bool isSpring) {
    return isSpring ? DateTime(now.year, 7, 31) : DateTime(now.month < 4 ? now.year : now.year + 1, 1, 31);
  }
}

// ★ グローバルで現在のアダプターを定義（これを切り替えるだけで他大学に対応可能になります）
final LMSAdapter currentLMS = KeioAdapter();
String get canvasBaseUrl => currentLMS.baseUrl;
// ============================================================================
