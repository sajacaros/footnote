/// 정해진 요일·시각에 "산책 기록 시작" 알림을 띄우는 설정.
class WalkReminder {
  const WalkReminder({
    this.id,
    required this.label,
    required this.hour,
    required this.minute,
    required this.weekdays,
    this.enabled = true,
  });

  /// DB에 저장되기 전에는 null.
  final int? id;
  final String label;
  final int hour;
  final int minute;

  /// [DateTime.weekday] 값(월=1 … 일=7).
  final Set<int> weekdays;
  final bool enabled;

  static const weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

  String get timeText =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String get weekdaysText {
    if (weekdays.length == 7) {
      return '매일';
    }
    if (weekdays.length == 5 && weekdays.every((day) => day <= 5)) {
      return '평일';
    }
    if (weekdays.length == 2 && weekdays.containsAll({6, 7})) {
      return '주말';
    }
    final sorted = weekdays.toList()..sort();
    return sorted.map((day) => weekdayLabels[day - 1]).join(' ');
  }

  WalkReminder copyWith({
    int? id,
    String? label,
    int? hour,
    int? minute,
    Set<int>? weekdays,
    bool? enabled,
  }) {
    return WalkReminder(
      id: id ?? this.id,
      label: label ?? this.label,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      weekdays: weekdays ?? this.weekdays,
      enabled: enabled ?? this.enabled,
    );
  }
}
