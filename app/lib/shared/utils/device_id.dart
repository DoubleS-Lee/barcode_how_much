import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceId {
  static const _key = 'device_uuid';

  /// 저장된 UUID 반환, 없으면 새로 생성하여 저장
  static Future<String> get() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null) return existing;
    final newId = const Uuid().v4();
    await prefs.setString(_key, newId);
    return newId;
  }
}
