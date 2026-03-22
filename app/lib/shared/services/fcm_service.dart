import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../api/device_api.dart';

/// FCM 초기화 및 토큰 관리
/// Firebase 설정이 완료된 후에만 동작함
class FcmService {
  static bool _initialized = false;

  static Future<void> init(String deviceUuid) async {
    // Windows/Web에서는 FCM 미지원
    if (kIsWeb) return;
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;

    try {
      final messaging = FirebaseMessaging.instance;

      // 알림 권한 요청
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[FCM] Permission denied');
        return;
      }

      // iOS: APNs 토큰 설정
      if (Platform.isIOS) {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      // FCM 토큰 가져오기 → 서버 등록
      final token = await messaging.getToken();
      if (token != null) {
        await DeviceApi.registerFcmToken(deviceUuid: deviceUuid, fcmToken: token);
        debugPrint('[FCM] Token registered: ${token.substring(0, 20)}...');
      }

      // 토큰 갱신 시 자동 재등록
      messaging.onTokenRefresh.listen((newToken) async {
        await DeviceApi.registerFcmToken(deviceUuid: deviceUuid, fcmToken: newToken);
        debugPrint('[FCM] Token refreshed');
      });

      // 포그라운드 메시지 (앱 켜져있을 때)
      FirebaseMessaging.onMessage.listen((message) {
        debugPrint('[FCM] Foreground: ${message.notification?.title}');
      });

      _initialized = true;
      debugPrint('[FCM] Initialized successfully');
    } catch (e) {
      debugPrint('[FCM] Init error: $e');
    }
  }

  static bool get isInitialized => _initialized;
}
