import 'api_client.dart';

class RecommendApi {
  /// GET /api/v1/recommend?barcode=...&product_name=...&category=...
  static Future<Map<String, dynamic>> getRecommendations({
    required String barcode,
    required String productName,
    String category = '',
  }) async {
    final response = await dio.get('/api/v1/recommend', queryParameters: {
      'barcode': barcode,
      'product_name': productName,
      if (category.isNotEmpty) 'category': category,
    });
    return Map<String, dynamic>.from(response.data as Map);
  }
}
