import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../api/device_api.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message: ${message.messageId}');
}

class FcmService {
  static bool _initialized = false;

  static Future<void> init(String deviceUuid) async {
    try {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        final token = await messaging.getToken();
        if (token != null) {
          await DeviceApi.registerFcmToken(deviceUuid: deviceUuid, fcmToken: token);
          debugPrint('[FCM] Token registered');
        }

        messaging.onTokenRefresh.listen((newToken) {
          DeviceApi.registerFcmToken(deviceUuid: deviceUuid, fcmToken: newToken);
        });
      }

      _initialized = true;
    } catch (e) {
      debugPrint('[FCM] Init failed: $e');
    }
  }

  static bool get isInitialized => _initialized;
}
