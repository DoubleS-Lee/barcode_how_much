import 'api_client.dart';

class ScanApi {
  /// POST /api/v1/scans — 스캔 이벤트 저장
  static Future<Map<String, dynamic>> postScan({
    required String deviceUuid,
    required String scanType,
    String? barcode,
    List<Map<String, dynamic>>? onlinePrices,
    Map<String, dynamic>? barcodeContent,
  }) async {
    final body = <String, dynamic>{
      'device_uuid': deviceUuid,
      'os': 'android', // Windows 데스크톱 테스트용 기본값
      'app_version': '1.0.0',
      'scan_type': scanType,
      if (barcode != null) 'barcode': barcode,
      if (onlinePrices != null) 'online_prices': onlinePrices,
      if (barcodeContent != null) 'barcode_content': barcodeContent,
    };
    final response = await dio.post('/api/v1/scans', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// GET /api/v1/scans/history?device_uuid=...
  static Future<Map<String, dynamic>> getHistory(String deviceUuid) async {
    final response = await dio.get(
      '/api/v1/scans/history',
      queryParameters: {'device_uuid': deviceUuid},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// POST /api/v1/scans/:scanId/offline-price
  static Future<void> postOfflinePrice({
    required String scanId,
    required int price,
    double? latitude,
    double? longitude,
    String? storeHint,
  }) async {
    await dio.post('/api/v1/scans/$scanId/offline-price', data: {
      'price': price,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (storeHint != null) 'store_hint': storeHint,
    });
  }

  /// PATCH /api/v1/scans/:scanId/offline-price — 오프라인 가격/장소/메모 수정 (없으면 생성)
  static Future<void> patchOfflinePrice({
    required String scanId,
    int? price,
    String? storeHint,
    String? memo,
  }) async {
    await dio.patch('/api/v1/scans/$scanId/offline-price', data: {
      if (price != null) 'price': price,
      'store_hint': storeHint,
      'memo': memo,
    });
  }

  /// PATCH /api/v1/price/products/:barcode — 상품명 직접 수정
  static Future<void> patchProductName({
    required String barcode,
    required String name,
  }) async {
    await dio.patch('/api/v1/price/products/$barcode', data: {'name': name});
  }

  /// DELETE /api/v1/scans/history?device_uuid=...
  static Future<int> deleteHistory(String deviceUuid) async {
    final response = await dio.delete(
      '/api/v1/scans/history',
      queryParameters: {'device_uuid': deviceUuid},
    );
    return (response.data as Map)['deleted'] as int? ?? 0;
  }

  /// GET /api/v1/scans/products/:barcode/price-history
  static Future<Map<String, dynamic>> getPriceHistory({
    required String barcode,
    required String deviceUuid,
  }) async {
    final response = await dio.get(
      '/api/v1/scans/products/$barcode/price-history',
      queryParameters: {'device_uuid': deviceUuid},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }
}
