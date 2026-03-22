import 'api_client.dart';

class DeviceApi {
  /// POST /api/v1/devices/token — FCM 토큰 서버 등록
  static Future<void> registerFcmToken({
    required String deviceUuid,
    required String fcmToken,
  }) async {
    await dio.post('/api/v1/devices/token', data: {
      'device_uuid': deviceUuid,
      'fcm_token': fcmToken,
    });
  }
}
