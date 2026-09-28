import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/walk_reminder.dart';
import '../theme/app_theme.dart';
import 'walk_repository.dart';

/// 설정된 요일·시각마다 "산책 기록 시작" 알림을 예약하고,
/// 사용자가 알림을 누르면 [startRequested]를 켜서 홈 화면이 기록 화면을 열게 한다.
class WalkReminderService extends ChangeNotifier {
  WalkReminderService._();

  static final WalkReminderService instance = WalkReminderService._();

  static const _payload = 'start_walk';
  static const _startActionId = 'start_walk';
  static const _channelId = 'walk_reminders';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final WalkRepository _repository = WalkRepository.instance;

  bool _startRequested = false;

  /// 알림을 눌러 앱이 열렸고 아직 기록 화면을 띄우지 않은 상태.
  bool get startRequested => _startRequested;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> initialize() async {
    tz_data.initializeTimeZones();
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: _handleResponse,
    );

    // 앱이 꺼져 있을 때 알림으로 실행된 경우.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if (launch?.didNotificationLaunchApp == true && response != null) {
      _handleResponse(response);
    }

    // 재설치·시간대 변경 등으로 예약이 어긋났을 수 있으니 시작할 때마다 다시 맞춘다.
    await reschedule();
  }

  /// 홈 화면이 기록 화면을 연 뒤 호출한다.
  void consumeStartRequest() {
    _startRequested = false;
  }

  Future<bool> notificationsEnabled() async {
    return await _android?.areNotificationsEnabled() ?? true;
  }

  Future<bool> exactAlarmsAllowed() async {
    return await _android?.canScheduleExactNotifications() ?? true;
  }

  Future<void> requestNotificationPermission() async {
    await _android?.requestNotificationsPermission();
  }

  /// 시스템 설정의 "알람 및 리마인더" 화면을 연다.
  Future<void> requestExactAlarmPermission() async {
    await _android?.requestExactAlarmsPermission();
  }

  /// 저장된 알림 설정 전체를 기준으로 예약을 다시 만든다.
  Future<void> reschedule() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      if (request.payload == _payload) {
        await _plugin.cancel(id: request.id);
      }
    }

    final reminders = await _repository.loadReminders();
    final scheduleMode = await exactAlarmsAllowed()
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    for (final reminder in reminders) {
      if (!reminder.enabled || reminder.id == null) {
        continue;
      }
      for (final weekday in reminder.weekdays) {
        await _plugin.zonedSchedule(
          id: reminder.id! * 10 + weekday,
          title: reminder.label.isEmpty ? '산책 기록' : reminder.label,
          body: '지금 산책 경로 기록을 시작할까요?',
          scheduledDate: _nextInstance(reminder, weekday),
          notificationDetails: _details,
          androidScheduleMode: scheduleMode,
          payload: _payload,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
    }
  }

  void _handleResponse(NotificationResponse response) {
    if (response.payload != _payload && response.actionId != _startActionId) {
      return;
    }
    _startRequested = true;
    notifyListeners();
  }

  static tz.TZDateTime _nextInstance(WalkReminder reminder, int weekday) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      reminder.hour,
      reminder.minute,
    );
    while (scheduled.weekday != weekday || !scheduled.isAfter(now)) {
      scheduled = tz.TZDateTime(
        tz.local,
        scheduled.year,
        scheduled.month,
        scheduled.day + 1,
        reminder.hour,
        reminder.minute,
      );
    }
    return scheduled;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      '산책 기록 알림',
      channelDescription: '정해 둔 시간에 산책 기록 시작을 알려 줍니다.',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      color: AppColors.brand,
      actions: [
        AndroidNotificationAction(
          _startActionId,
          '기록 시작',
          showsUserInterface: true,
        ),
      ],
    ),
  );
}
