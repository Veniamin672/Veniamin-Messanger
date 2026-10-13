import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Локальные уведомления (пока процесс жив и сокет подключён).
class VeniaminNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static int _nid = 1000;

  /// Текущее состояние приложения (обновляет RootScreen).
  static AppLifecycleState lifecycle = AppLifecycleState.resumed;

  /// id группы, которую сейчас смотрит пользователь (чтобы не спамить в открытом чате).
  static String? activeGroupId;

  static Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const init = InitializationSettings(
      android: android,
      iOS: ios,
    );
    await _plugin.initialize(init);

    if (!kIsWeb && Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'veniamin_messages',
          'Сообщения Veniamin',
          description: 'Новые сообщения в чатах',
          importance: Importance.high,
        ),
      );
    }
    _ready = true;
  }

  /// Приложение на переднем плане (экране).
  static bool get isForeground {
    switch (lifecycle) {
      case AppLifecycleState.resumed:
        return true;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        return false;
    }
  }

  /// Показывать ли уведомление о сообщении.
  /// - свёрнуто / не на экране → да
  /// - открыт другой чат → да
  /// - смотрим именно эту группу → нет (уже видно в UI)
  static bool shouldNotifyMessage({String? groupId}) {
    if (!isForeground) return true;
    if (groupId == null || groupId.isEmpty) return true;
    if (activeGroupId == null) return true;
    return groupId != activeGroupId;
  }

  static Future<void> showMessage({
    required String title,
    required String body,
    String? payload,
    String? groupId,
  }) async {
    if (!_ready) {
      try {
        await init();
      } catch (e) {
        debugPrint('[notify] init failed: $e');
        return;
      }
    }
    if (!shouldNotifyMessage(groupId: groupId ?? payload)) {
      debugPrint(
          '[notify] skip message (foreground group=${activeGroupId}, msg=$groupId, life=$lifecycle)');
      return;
    }

    const android = AndroidNotificationDetails(
      'veniamin_messages',
      'Сообщения Veniamin',
      channelDescription: 'Новые сообщения в чатах',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: android,
      iOS: ios,
    );

    try {
      await _plugin.show(
        _nid++,
        title,
        body,
        details,
        payload: payload,
      );
      if (_nid > 100000) _nid = 1000;
      debugPrint('[notify] shown: $title / $body');
    } catch (e) {
      debugPrint('[notify] show failed: $e');
    }
  }

  static Future<void> showIncomingCall({
    required String fromName,
  }) async {
    if (!_ready) {
      try {
        await init();
      } catch (_) {
        return;
      }
    }
    const android = AndroidNotificationDetails(
      'veniamin_calls',
      'Звонки Veniamin',
      channelDescription: 'Входящие звонки',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      category: AndroidNotificationCategory.call,
    );
    const details = NotificationDetails(
      android: android,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    );
    try {
      await _plugin.show(
        1,
        'Входящий звонок',
        fromName,
        details,
      );
    } catch (e) {
      debugPrint('[notify] call failed: $e');
    }
  }
}
