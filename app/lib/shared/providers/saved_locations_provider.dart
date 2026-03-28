import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';
import 'device_provider.dart';
import '../api/saved_locations_api.dart';

class SavedLocationsNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final auth = ref.watch(authProvider).valueOrNull;
    if (auth == null || !auth.isLoggedIn) return [];
    final uuid = await ref.watch(deviceUuidProvider.future);
    return SavedLocationsApi.fetch(uuid);
  }

  Future<void> add(String location) async {
    final auth = ref.read(authProvider).valueOrNull;
    if (auth == null || !auth.isLoggedIn) return;
    final loc = location.trim();
    if (loc.isEmpty) return;
    final uuid = await ref.read(deviceUuidProvider.future);
    final updated = await SavedLocationsApi.add(uuid, loc);
    state = AsyncValue.data(updated);
  }

  Future<void> remove(String location) async {
    final uuid = await ref.read(deviceUuidProvider.future);
    final updated = await SavedLocationsApi.remove(uuid, location);
    state = AsyncValue.data(updated);
  }
}

final savedLocationsProvider =
    AsyncNotifierProvider<SavedLocationsNotifier, List<String>>(
        SavedLocationsNotifier.new);
