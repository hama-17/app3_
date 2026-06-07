import 'lms_adapter.dart'; // ★ currentLMS を読み込む
//course_parser.dart

class CourseTitleParser {
  static String getCleanTitle(String rawName) => currentLMS.cleanTitle(rawName);
}
class CourseScheduleParser {
  static String getRoomNumber(String rawName) => currentLMS.extractRoom(rawName);
  static String getDayPeriod(String rawName) => currentLMS.extractDayPeriod(rawName);
}

class CourseInstructorParser {
  static String getInstructorName(dynamic course) {
    try {
      if (course['teachers'] != null && (course['teachers'] as List).isNotEmpty) return course['teachers'][0]['display_name'] ?? '';
      return '';
    } catch (_) { return ''; }
  }
}

