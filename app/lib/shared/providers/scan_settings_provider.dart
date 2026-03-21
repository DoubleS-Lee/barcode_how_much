import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScanSettingNotifier extends StateNotifier<bool> {
  final String key;

  ScanSettingNotifier(this.key) : super(true) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) state = prefs.getBool(key) ?? true;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool(key, state);
  }
}

final scanSoundProvider = StateNotifierProvider<ScanSettingNotifier, bool>(
  (ref) => ScanSettingNotifier('scan_sound'),
);

final scanVibrationProvider = StateNotifierProvider<ScanSettingNotifier, bool>(
  (ref) => ScanSettingNotifier('scan_vibration'),
);
