import 'package:dio/dio.dart';
import 'api_client.dart';

class PriceApi {
  /// GET /api/v1/price?barcode=...
  static Future<Map<String, dynamic>> getPrice(String barcode) async {
    final response = await dio.get(
      '/api/v1/price',
      queryParameters: {'barcode': barcode},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }
}

class PriceApiException implements Exception {
  final int? statusCode;
  final String message;
  PriceApiException({this.statusCode, required this.message});

  @override
  String toString() => 'PriceApiException($statusCode): $message';
}

/// dio DioException → 사용자 친화 메시지
String friendlyError(Object e) {
  if (e is DioException) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return '마트 안이라 인터넷이 느려요!\n조금 이동해서 다시 찍어볼까요?';
    }
    if (e.type == DioExceptionType.connectionError) {
      return '서버에 연결할 수 없어요.\n잠시 후 다시 시도해주세요.';
    }
    final code = e.response?.statusCode;
    if (code == 404) return '등록되지 않은 상품입니다.';
    if (code != null && code >= 500) return '서버 오류가 발생했습니다.';
  }
  return '알 수 없는 오류가 발생했습니다.';
}
