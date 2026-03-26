import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// 이미지를 압축해서 반환합니다. 실패 시 원본 파일을 반환합니다.
/// quality: 82 — 육안으로 차이 없는 수준에서 용량 최소화
Future<File> compressImage(File file) async {
  final outPath =
      '${Directory.systemTemp.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
  final result = await FlutterImageCompress.compressAndGetFile(
    file.absolute.path,
    outPath,
    quality: 82,
    minWidth: 1280,
    minHeight: 720,
    format: CompressFormat.jpeg,
  );
  return result != null ? File(result.path) : file;
}
