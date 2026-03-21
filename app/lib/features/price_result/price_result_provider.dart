import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../shared/api/price_api.dart';
import '../../shared/api/scan_api.dart';
import '../../shared/providers/device_provider.dart';

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

    // 첫 로드 시 스캔 이벤트를 서버에 저장 (fire-and-forget)
    if (!_scanSaved) {
      _scanSaved = true;
      _saveScan(barcode, data);
    }

    return data;
  }

  Future<void> _saveScan(
      String barcode, Map<String, dynamic> priceData) async {
    try {
      final deviceUuid = await ref.read(deviceUuidProvider.future);
      final prices = (priceData['prices'] as List).cast<Map>();
      await ScanApi.postScan(
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
    } catch (e) {
      // 저장 실패 시 사용자에게 영향 없음 — 로그만 출력
      debugPrint('[ScanSave] Failed: $e');
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => PriceApi.getPrice(arg));
  }
}

final priceResultProvider = AsyncNotifierProvider.family<PriceResultNotifier,
    Map<String, dynamic>, String>(PriceResultNotifier.new);
