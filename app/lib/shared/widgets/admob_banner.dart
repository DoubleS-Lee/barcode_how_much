import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../core/theme.dart';

/// ✅ 테스트 광고 단위 ID (출시 전 실제 ID로 교체)
/// Android: admob.google.com → 앱 등록 → 광고 단위 생성
/// iOS:     admob.google.com → 앱 등록 → 광고 단위 생성
const _kAndroidBannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';
const _kIosBannerAdUnitId = 'ca-app-pub-3940256099942544/2934735716';

String get _bannerAdUnitId {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return _kAndroidBannerAdUnitId;
  }
  return _kIosBannerAdUnitId;
}

/// AdMob 배너 위젯
/// - Android/iOS: 실제 AdMob BannerAd (320×50 표준)
/// - Windows/기타: 프리미엄 업셀 플레이스홀더
class AdmobBanner extends StatefulWidget {
  const AdmobBanner({super.key});

  @override
  State<AdmobBanner> createState() => _AdmobBannerState();
}

class _AdmobBannerState extends State<AdmobBanner> {
  BannerAd? _bannerAd;
  bool _adLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    // Windows/웹에서는 광고 SDK 미지원
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }

    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: AdSize.banner, // 320×50
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _adLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[AdMob] 배너 로드 실패: ${error.message}');
          ad.dispose();
          _bannerAd = null;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Android/iOS + 광고 로드 완료
    if (_adLoaded && _bannerAd != null) {
      return SizedBox(
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      );
    }

    // 광고 로드 중 또는 Windows/기타 → 프리미엄 업셀 표시
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: kSurfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kOutlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(Icons.verified_user_outlined,
              color: kPrimary.withValues(alpha: 0.4), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '프리미엄 멤버십으로 광고 제거',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kOnSurface,
                  ),
                ),
                Text(
                  '더 빠르고 쾌적한 가격 비교를 경험하세요',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: kOnSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'Ad',
              style: GoogleFonts.inter(
                  fontSize: 9, color: Colors.grey.shade400),
            ),
          ),
        ],
      ),
    );
  }
}
