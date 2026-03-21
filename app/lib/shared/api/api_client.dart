import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 서버 Base URL — Windows 개발 환경
const kBaseUrl = 'http://localhost:3000';

/// Dio 싱글톤 클라이언트
final dio = Dio(
  BaseOptions(
    baseUrl: kBaseUrl,
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 6),
    headers: {'Content-Type': 'application/json'},
  ),
)..interceptors.add(
    LogInterceptor(
      requestBody: false,
      responseBody: false,
      logPrint: (o) => debugPrint('[API] $o'),
    ),
  );
