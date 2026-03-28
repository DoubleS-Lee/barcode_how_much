import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../shared/api/price_api.dart';
import '../../shared/api/scan_api.dart';
import '../../shared/providers/device_provider.dart';
import '../scan_history/scan_history_provider.dart';

/// 마트 직접 입력 가격 — ManualPrice → PriceResult 간 공유
final offlinePriceProvider =
    StateProvider.autoDispose.family<int?, String>((ref, barcode) => null);

/// 바코드별 가격 조회 — GET /api/v1/price?barcode=
final priceProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, barcode) async {
  return PriceApi.getPrice(barcode);
});

/// 스캔 가격 조회 Notifier — 저장은 사용자가 명시적으로 '저장' 버튼을 누를 때
class PriceResultNotifier
    extends AutoDisposeFamilyAsyncNotifier<Map<String, dynamic>, String> {

  @override
  Future<Map<String, dynamic>> build(String barcode) async {
    // 가격 조회만 — 자동 저장 없음
    return PriceApi.getPrice(barcode);
  }

  /// 저장 버튼 또는 마트 가격 입력 전 호출 — scan 이벤트 DB 저장
  Future<String?> saveScan(
      String barcode, List<Map<String, dynamic>> prices) async {
    try {
      final deviceUuid = await ref.read(deviceUuidProvider.future);
      final result = await ScanApi.postScan(
        deviceUuid: deviceUuid,
        scanType: 'product',
        barcode: barcode,
        onlinePrices: prices
            .map((p) => {
                  'platform': p['platform'] as String,
                  'price': p['price'] as int,
                  'is_lowest': p['is_lowest'] as bool,
                  if (p['url'] != null) 'url': p['url'] as String,
                })
            .toList(),
      );
      // scan_id를 현재 state에 주입해 ManualPriceScreen이 참조 가능하도록
      final current = state.valueOrNull;
      if (current != null) {
        state = AsyncValue.data({...current, 'scan_id': result['scan_id']});
      }
      ref.invalidate(scanHistoryProvider);
      ref.invalidate(priceHistoryProvider(barcode));
      return result['scan_id'] as String?;
    } catch (e) {
      debugPrint('[ScanSave] Failed: $e');
      return null;
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => PriceApi.getPrice(arg));
  }
}

final priceResultProvider = AsyncNotifierProvider.autoDispose.family<PriceResultNotifier,
    Map<String, dynamic>, String>(PriceResultNotifier.new);
