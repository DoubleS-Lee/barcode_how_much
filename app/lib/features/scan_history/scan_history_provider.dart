import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/api/favorites_api.dart';
import '../../shared/api/scan_api.dart';
import '../../shared/providers/device_provider.dart';

/// 스캔 이력 조회 — GET /api/v1/scans/history
final scanHistoryProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final deviceUuid = await ref.watch(deviceUuidProvider.future);
  final result = await ScanApi.getHistory(deviceUuid);
  return (result['items'] as List).cast<Map<String, dynamic>>();
});

/// 특정 바코드의 가격 이력 — GET /api/v1/scans/products/:barcode/price-history
final priceHistoryProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, barcode) async {
  final deviceUuid = await ref.watch(deviceUuidProvider.future);
  final result = await ScanApi.getPriceHistory(
    barcode: barcode,
    deviceUuid: deviceUuid,
  );
  return (result['price_history'] as List).cast<Map<String, dynamic>>();
});

/// 오프라인 가격 즉각 반영용 로컬 상태 (바코드별) — 절약 배너에서 사용
final liveOfflinePriceProvider =
    StateProvider.family<int?, String>((ref, barcode) => null);

/// 오프라인 가격 즉각 반영용 로컬 상태 (scanId별) — 개별 스캔 row에서 사용
/// 프로모션(1+1, 2+1, 3+1) 포함 단가를 해당 scanId row에만 즉시 반영
final liveScanOfflinePriceProvider =
    StateProvider.family<int?, String>((ref, scanId) => null);

// ── 찜 기능 ────────────────────────────────────────────────

const _kFavKey = 'favorites_barcodes';

/// 찜한 바코드 목록 — 서버 DB 저장 + SharedPreferences 로컬 캐시
class FavoritesNotifier extends StateNotifier<Set<String>> {
  final String? _deviceUuid;

  FavoritesNotifier(this._deviceUuid) : super({}) {
    _load();
  }

  /// 앱 시작 시: 서버에서 먼저 로드, 실패하면 로컬 캐시 사용
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    // 로컬 캐시를 먼저 즉시 반영 (빠른 표시)
    final cached = (prefs.getStringList(_kFavKey) ?? []).toSet();
    if (cached.isNotEmpty) state = cached;

    // 서버에서 최신 목록 동기화
    if (_deviceUuid != null) {
      try {
        final barcodes = await FavoritesApi.fetchBarcodes(_deviceUuid);
        final serverSet = barcodes.toSet();
        state = serverSet;
        await prefs.setStringList(_kFavKey, serverSet.toList());
      } catch (_) {
        // 오프라인이면 로컬 캐시 유지
      }
    }
  }

  Future<void> toggle(String barcode) async {
    final isFav = state.contains(barcode);
    // 낙관적 업데이트
    final next = Set<String>.from(state);
    if (isFav) {
      next.remove(barcode);
    } else {
      next.add(barcode);
    }
    state = next;

    // 로컬 캐시 즉시 저장
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kFavKey, next.toList());

    // 서버 동기화
    if (_deviceUuid != null) {
      try {
        if (isFav) {
          await FavoritesApi.remove(_deviceUuid, barcode);
        } else {
          await FavoritesApi.add(_deviceUuid, barcode);
        }
      } catch (_) {
        // 서버 실패 시 롤백
        state = Set<String>.from(state)..toggle(barcode);
        await prefs.setStringList(_kFavKey, state.toList());
      }
    }
  }

  bool isFavorite(String barcode) => state.contains(barcode);
}

extension on Set<String> {
  void toggle(String value) =>
      contains(value) ? remove(value) : add(value);
}

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, Set<String>>((ref) {
  final deviceUuid = ref.watch(deviceUuidProvider).valueOrNull;
  return FavoritesNotifier(deviceUuid);
});
