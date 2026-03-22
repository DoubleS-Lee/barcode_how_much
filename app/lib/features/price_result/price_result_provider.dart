import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../shared/api/price_api.dart';
import '../../shared/api/scan_api.dart';
import '../../shared/providers/device_provider.dart';
import '../scan_history/scan_history_provider.dart';

/// 마트 직접 입력 가격 — ManualPrice → PriceResult 간 공유
final offlinePriceProvider =
    StateProvider.family<int?, String>((ref, barcode) => null);

/// 바코드별 가격 조회 — GET /api/v1/price?barcode=
final priceProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, barcode) async {
  return PriceApi.getPrice(barcode);
});

/// 스캔 저장 + 가격 조회를 한 번에 처리하는 Notifier
class PriceResultNotifier
    extends FamilyAsyncNotifier<Map<String, dynamic>, String> {
  bool _scanSaved = false;

  @override
  Future<Map<String, dynamic>> build(String barcode) async {
    final data = await PriceApi.getPrice(barcode);

    // 첫 로드 시 스캔 이벤트 저장 후 scan_id를 data에 주입
    if (!_scanSaved) {
      _scanSaved = true;
      final scanId = await _saveScan(barcode, data);
      if (scanId != null) {
        return {...data, 'scan_id': scanId};
      }
    }

    return data;
  }

  Future<String?> _saveScan(
      String barcode, Map<String, dynamic> priceData) async {
    try {
      final deviceUuid = await ref.read(deviceUuidProvider.future);
      final prices = (priceData['prices'] as List).cast<Map>();
      final result = await ScanApi.postScan(
        deviceUuid: deviceUuid,
        scanType: 'product',
        barcode: barcode,
        onlinePrices: prices
            .map((p) => {
                  'platform': p['platform'] as String,
                  'price': p['price'] as int,
                  'is_lowest': p['is_lowest'] as bool,
                })
            .toList(),
      );
      ref.invalidate(scanHistoryProvider);
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

final priceResultProvider = AsyncNotifierProvider.family<PriceResultNotifier,
    Map<String, dynamic>, String>(PriceResultNotifier.new);
