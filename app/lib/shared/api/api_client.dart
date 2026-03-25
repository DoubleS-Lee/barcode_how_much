import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 서버 Base URL — 실기기 테스트용 (PC와 같은 와이파이 필요)
const kBaseUrl = 'http://192.168.219.110:3000';

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
      requestBody: true,
      responseBody: true,
      logPrint: (o) => debugPrint('[API] $o'),
    ),
  );
