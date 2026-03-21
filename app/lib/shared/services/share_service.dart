import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kakao_flutter_sdk_share/kakao_flutter_sdk_share.dart';
import 'package:share_plus/share_plus.dart' show Share, ShareResult, ShareResultStatus;

/// 카카오톡 공유 서비스
///
/// - Android/iOS + Kakao 앱 설치: KakaoTalk 커스텀 템플릿 공유
/// - Android/iOS + Kakao 미설치: share_plus → OS 공유시트
/// - Windows/기타: share_plus → OS 공유 / 클립보드 복사
class ShareService {
  static final _nf = NumberFormat('#,###');

  /// 가격 결과 공유
  static Future<ShareResult> sharePriceResult({
    required String productName,
    required String lowestPlatform,
    required int lowestPrice,
    required List<Map> allPrices,
  }) async {
    final text = _buildShareText(
      productName: productName,
      lowestPlatform: lowestPlatform,
      lowestPrice: lowestPrice,
      allPrices: allPrices,
    );

    // Android/iOS에서만 Kakao SDK 시도
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      return await _tryKakaoShare(
        productName: productName,
        lowestPlatform: lowestPlatform,
        lowestPrice: lowestPrice,
        allPrices: allPrices,
        fallbackText: text,
      );
    }

    // Windows/기타: share_plus 직접 사용
    return await Share.share(text);
  }

  /// Kakao 공유 시도 → 실패 시 share_plus로 폴백
  static Future<ShareResult> _tryKakaoShare({
    required String productName,
    required String lowestPlatform,
    required int lowestPrice,
    required List<Map> allPrices,
    required String fallbackText,
  }) async {
    try {
      final isKakaoAvailable = await ShareClient.instance.isKakaoTalkSharingAvailable();

      if (isKakaoAvailable) {
        // 카카오 피드 템플릿 생성
        final otherPlatform = allPrices
            .where((p) => p['platform'] != lowestPlatform)
            .firstOrNull;

        final descLines = <String>[
          '✅ ${_platformName(lowestPlatform)} 최저가: ${_nf.format(lowestPrice)}원',
          if (otherPlatform != null)
            '🔸 ${_platformName(otherPlatform['platform'] as String)}: ${_nf.format(otherPlatform['price'] as int)}원',
          '',
          '가짜 세일에 속지 마세요!',
        ];

        final template = FeedTemplate(
          content: Content(
            title: '📦 $productName',
            description: descLines.join('\n'),
            imageUrl: Uri.parse(
                'https://via.placeholder.com/400x200/0747AD/FFFFFF?text=얼마였지%3F'),
            link: Link(
              webUrl: Uri.parse(
                  'https://play.google.com/store/apps/details?id=com.eolmaeossjeo.eolmaeossjeo'),
              mobileWebUrl: Uri.parse(
                  'https://play.google.com/store/apps/details?id=com.eolmaeossjeo.eolmaeossjeo'),
            ),
          ),
          buttons: [
            Button(
              title: '앱에서 확인하기',
              link: Link(
                androidExecutionParams: {'barcode': ''},
                iosExecutionParams: {'barcode': ''},
              ),
            ),
          ],
        );

        final uri = await ShareClient.instance.shareDefault(template: template);
        await ShareClient.instance.launchKakaoTalk(uri);
        return const ShareResult('kakao_success', ShareResultStatus.success);
      }
    } catch (e) {
      debugPrint('[KakaoShare] Failed, falling back to share_plus: $e');
    }

    // 폴백: OS 공유시트
    return await Share.share(fallbackText);
  }

  /// 클립보드 복사 (Windows/대안)
  static Future<void> copyToClipboard({
    required String productName,
    required String lowestPlatform,
    required int lowestPrice,
    required List<Map> allPrices,
  }) async {
    final text = _buildShareText(
      productName: productName,
      lowestPlatform: lowestPlatform,
      lowestPrice: lowestPrice,
      allPrices: allPrices,
    );
    await Clipboard.setData(ClipboardData(text: text));
  }

  static String _buildShareText({
    required String productName,
    required String lowestPlatform,
    required int lowestPrice,
    required List<Map> allPrices,
  }) {
    final sb = StringBuffer();
    sb.writeln('[얼마였지? 앱 - 가격 비교]');
    sb.writeln();
    sb.writeln('📦 $productName');
    sb.writeln();
    sb.writeln('✅ ${_platformName(lowestPlatform)} 최저가: ${_nf.format(lowestPrice)}원');
    for (final p in allPrices) {
      if (p['platform'] != lowestPlatform) {
        sb.writeln(
            '🔸 ${_platformName(p['platform'] as String)}: ${_nf.format(p['price'] as int)}원');
      }
    }
    sb.writeln();
    sb.writeln('가짜 세일에 속지 마세요!');
    sb.writeln('\'얼마였지?\' 앱으로 직접 확인해보세요 👇');
    sb.write(
        'https://play.google.com/store/apps/details?id=com.eolmaeossjeo.eolmaeossjeo');
    return sb.toString();
  }

  static String _platformName(String platform) => switch (platform) {
        'coupang' => '쿠팡',
        'naver' => '네이버 쇼핑',
        'gmarket' => 'G마켓',
        'elevenst' => '11번가',
        _ => platform,
      };
}
