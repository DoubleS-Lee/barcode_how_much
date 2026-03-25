import 'api_client.dart';

class FavoritesApi {
  /// GET /api/v1/favorites?device_uuid=xxx
  static Future<List<String>> fetchBarcodes(String deviceUuid) async {
    final res = await dio.get('/api/v1/favorites', queryParameters: {'device_uuid': deviceUuid});
    return List<String>.from(res.data['barcodes'] as List);
  }

  /// POST /api/v1/favorites  { device_uuid, barcode }
  static Future<void> add(String deviceUuid, String barcode) async {
    await dio.post('/api/v1/favorites', data: {'device_uuid': deviceUuid, 'barcode': barcode});
  }

  /// DELETE /api/v1/favorites/:barcode  body: { device_uuid }
  static Future<void> remove(String deviceUuid, String barcode) async {
    await dio.delete('/api/v1/favorites/$barcode', data: {'device_uuid': deviceUuid});
  }
}
