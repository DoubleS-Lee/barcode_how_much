import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kKey = 'saved_locations';
const _kMax = 8;

class SavedLocationsNotifier extends StateNotifier<List<String>> {
  SavedLocationsNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw != null) {
      state = List<String>.from(jsonDecode(raw) as List);
    }
  }

  Future<void> add(String location) async {
    final loc = location.trim();
    if (loc.isEmpty || state.contains(loc)) return;
    final updated = [loc, ...state.where((e) => e != loc)].take(_kMax).toList();
    state = updated;
    await _save();
  }

  Future<void> remove(String location) async {
    state = state.where((e) => e != location).toList();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(state));
  }
}

final savedLocationsProvider =
    StateNotifierProvider<SavedLocationsNotifier, List<String>>(
        (_) => SavedLocationsNotifier());
