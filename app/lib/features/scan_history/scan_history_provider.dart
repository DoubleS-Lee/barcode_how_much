import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, barcode) async {
  final deviceUuid = await ref.watch(deviceUuidProvider.future);
  final result = await ScanApi.getPriceHistory(
    barcode: barcode,
    deviceUuid: deviceUuid,
  );
  return (result['price_history'] as List).cast<Map<String, dynamic>>();
});
