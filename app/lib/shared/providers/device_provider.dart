import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/device_id.dart';

/// 앱 전체에서 사용하는 디바이스 UUID
final deviceUuidProvider = FutureProvider<String>((ref) => DeviceId.get());
