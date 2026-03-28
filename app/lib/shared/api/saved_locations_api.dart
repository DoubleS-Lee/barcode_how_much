import 'api_client.dart';

class SavedLocationsApi {
  /// GET /api/v1/saved-locations?device_uuid=
  static Future<List<String>> fetch(String deviceUuid) async {
    final res = await dio.get('/api/v1/saved-locations', queryParameters: {'device_uuid': deviceUuid});
    return List<String>.from(res.data['locations'] as List);
  }

  /// POST /api/v1/saved-locations  { device_uuid, name }
  static Future<List<String>> add(String deviceUuid, String name) async {
    final res = await dio.post('/api/v1/saved-locations', data: {'device_uuid': deviceUuid, 'name': name});
    return List<String>.from(res.data['locations'] as List);
  }

  /// DELETE /api/v1/saved-locations/:name?device_uuid=
  static Future<List<String>> remove(String deviceUuid, String name) async {
    final res = await dio.delete(
      '/api/v1/saved-locations/${Uri.encodeComponent(name)}',
      queryParameters: {'device_uuid': deviceUuid},
    );
    return List<String>.from(res.data['locations'] as List);
  }
}
