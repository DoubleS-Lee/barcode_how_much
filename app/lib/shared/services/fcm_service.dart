import 'package:flutter/foundation.dart';

/// FCM 서비스 스텁
/// 실제 FCM은 Firebase 설정 후 모바일 빌드에서 활성화됩니다.
/// pubspec.yaml의 firebase_core / firebase_messaging 주석 해제 후
/// flutterfire configure를 실행하면 이 파일을 실제 구현으로 교체할 수 있습니다.
class FcmService {
  static bool _initialized = false;

  static Future<void> init(String deviceUuid) async {
    // Firebase 패키지 미포함 상태 — 모바일 빌드 시 활성화 예정
    debugPrint('[FCM] Skipped: Firebase not configured (Windows dev build)');
  }

  static bool get isInitialized => _initialized;
}
