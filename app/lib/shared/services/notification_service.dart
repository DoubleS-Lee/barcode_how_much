import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isLinux);

  static Future<void> init() async {
    if (!_supported || _initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios, macOS: ios),
    );
    _initialized = true;
  }

  /// 가격 하락 알림
  static Future<void> showPriceDrop({
    required String productName,
    required int onlinePrice,
    required int offlinePrice,
  }) async {
    if (!_supported) return;
    await init();

    final saved = offlinePrice - onlinePrice;
    await _plugin.show(
      1,
      '💰 $productName',
      '온라인이 마트보다 ${_fmt(saved)}원 저렴해요! 온라인 최저가: ${_fmt(onlinePrice)}원',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'price_drop',
          '가격 하락 알림',
          channelDescription: '마트보다 온라인이 저렴할 때 알려드립니다',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  /// 권한 요청 (Android 13+, iOS)
  static Future<bool> requestPermission() async {
    if (!_supported) return false;
    await init();

    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }
    return true;
  }

  static String _fmt(int n) {
    final s = n.toString();
    final result = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) result.write(',');
      result.write(s[i]);
    }
    return result.toString();
  }
}
