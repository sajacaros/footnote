import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../theme/app_theme.dart';
import 'walk_reminder_service.dart';

/// 산책 중 오래 멈춰 있을 때 띄우는 알림.
class IdleNotifier {
  IdleNotifier({
    required void Function() onContinue,
    required void Function() onFinish,
  }) {
    WalkReminderService.instance.registerResponseHandler(_payload, (response) {
      switch (response.actionId) {
        case _continueActionId:
          onContinue();
        case _finishActionId:
          onFinish();
      }
    });
  }

  static const _payload = 'walk_idle';
  static const _continueActionId = 'walk_idle_continue';
  static const _finishActionId = 'walk_idle_finish';
  static const _channelId = 'walk_idle';
  static const _promptId = 9001;
  static const _endedId = 9002;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> showPrompt() async {
    await _plugin.show(
      id: _promptId,
      title: '아직 산책 중인가요?',
      body: '한자리에 오래 머물러 있어요. 응답이 없으면 10분 뒤 기록을 끝내고 저장합니다.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          '산책 멈춤 알림',
          channelDescription: '산책 중 오래 멈춰 있으면 기록을 끝낼지 묻습니다.',
          importance: Importance.high,
          priority: Priority.high,
          color: AppColors.brand,
          actions: [
            // 앱의 기록 상태를 바꿔야 하므로 앱을 앞으로 가져와 메인 isolate에서 처리한다.
            AndroidNotificationAction(
              _continueActionId,
              '계속 기록',
              showsUserInterface: true,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              _finishActionId,
              '종료하고 저장',
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
        ),
      ),
      payload: _payload,
    );
  }

  Future<void> cancelPrompt() => _plugin.cancel(id: _promptId);

  Future<void> showEnded() async {
    await cancelPrompt();
    await _plugin.show(
      id: _endedId,
      title: '산책 기록을 저장했어요',
      body: '오래 멈춰 있어서 기록을 끝냈습니다. 멈추기 전까지의 경로만 저장했어요.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          '산책 멈춤 알림',
          channelDescription: '산책 중 오래 멈춰 있으면 기록을 끝낼지 묻습니다.',
          color: AppColors.brand,
        ),
      ),
    );
  }
}
