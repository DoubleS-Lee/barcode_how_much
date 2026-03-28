import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 닉네임 전역 상태 — invalidate하면 SharedPreferences에서 재조회
final nicknameProvider = FutureProvider<String?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('device_nickname');
});
