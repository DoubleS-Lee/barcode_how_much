import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../utils/device_id.dart';
import 'auth_provider.dart';

/// 로그인 상태면 계정 기반 UUID(v5), 비로그인이면 기기 UUID 반환.
/// 같은 계정 → 기기가 달라도 동일 UUID → 스캔 이력 공유.
final deviceUuidProvider = FutureProvider<String>((ref) async {
  final auth = ref.watch(authProvider).valueOrNull;
  if (auth != null && auth.isLoggedIn && auth.socialId != null) {
    return const Uuid().v5(Namespace.url.value, '${auth.loginType}:${auth.socialId}');
  }
  return DeviceId.get();
});
