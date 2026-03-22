import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/api/scan_api.dart';
import '../../shared/services/share_service.dart';
import '../../shared/widgets/admob_banner.dart';
import '../scan_history/price_graph_widget.dart';
import '../scan_history/scan_history_provider.dart';
import 'price_result_provider.dart';
import 'recommend_provider.dart';

class PriceResultScreen extends ConsumerWidget {
  final String barcode;
  const PriceResultScreen({super.key, required this.barcode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final priceAsync = ref.watch(priceResultProvider(barcode));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(
          color: kOnSurface,
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            const Icon(Icons.barcode_reader, color: kPrimary, size: 20),
            const SizedBox(width: 6),
            Text(
              '얼마였지?',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: kPrimaryDark,
              ),
            ),
          ],
        ),
        actions: [
          // 카카오톡 공유 버튼 — 데이터 로드 완료 시 활성화
          if (priceAsync.hasValue)
            IconButton(
              icon: const Icon(Icons.share_outlined, color: kPrimary),
              tooltip: '카카오톡 공유',
              onPressed: () => _onShare(context, priceAsync.value!),
            ),
          IconButton(
            icon: const Icon(Icons.history_outlined, color: kPrimary),
            onPressed: () => context.push('/history'),
          ),
        ],
      ),
      body: priceAsync.when(
        loading: () => const _PriceLoadingSkeleton(),
        error: (e, _) {
          if (_is404(e)) {
            return _ProductNotFoundView(
              barcode: barcode,
              onNameSubmitted: (name) async {
                await ScanApi.patchProductName(barcode: barcode, name: name);
                ref.invalidate(priceResultProvider(barcode));
              },
            );
          }
          return _PriceErrorView(
            message: _friendlyError(e),
            onRetry: () => ref.invalidate(priceResultProvider(barcode)),
          );
        },
        data: (data) => _PriceResultBody(barcode: barcode, data: data),
      ),
    );
  }

  Future<void> _onShare(BuildContext context, Map<String, dynamic> data) async {
    final prices = (data['prices'] as List).cast<Map>();
    final lowestPlatform = data['lowest_platform'] as String;
    final productName = (data['product_name'] as String?) ?? '상품';
    final lowestPrice = data['lowest_price'] as int;

    try {
      await ShareService.sharePriceResult(
        productName: productName,
        lowestPlatform: lowestPlatform,
        lowestPrice: lowestPrice,
        allPrices: prices,
      );
    } catch (_) {
      // 공유 실패 시 클립보드 복사로 폴백
      await ShareService.copyToClipboard(
        productName: productName,
        lowestPlatform: lowestPlatform,
        lowestPrice: lowestPrice,
        allPrices: prices,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📋 가격 정보가 클립보드에 복사되었습니다')),
        );
      }
    }
  }

  bool _is404(Object e) {
    if (e is DioException) return e.response?.statusCode == 404;
    return e.toString().contains('404');
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('timeout') || msg.contains('Timeout')) {
      return '마트 안이라 인터넷이 느려요!\n조금 이동해서 다시 찍어볼까요?';
    }
    if (msg.contains('connection') || msg.contains('Connection')) {
      return '서버에 연결할 수 없어요.\n잠시 후 다시 시도해주세요.';
    }
    return '가격 정보를 불러오지 못했어요.';
  }
}

class _PriceResultBody extends ConsumerWidget {
  final String barcode;
  final Map<String, dynamic> data;
  const _PriceResultBody({required this.barcode, required this.data});

  String _platformLabel(String platform) =>
      platform == 'coupang' ? '쿠팡' : '네이버 쇼핑';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nf = NumberFormat('#,###');
    final prices = (data['prices'] as List).cast<Map>();
    final lowestPlatform = data['lowest_platform'] as String;
    final productName = (data['product_name'] as String?) ?? '바코드: $barcode';
    final lowestPrice = (data['lowest_price'] as num?)?.toInt() ?? 0;
    final cacheAge = (data['cache_age_minutes'] as num?)?.toInt() ?? 0;

    final offlinePrice = ref.watch(offlinePriceProvider(barcode));
    final priceHistoryAsync = ref.watch(priceHistoryProvider(barcode));
    final recommendAsync = ref.watch(recommendProvider(
      RecommendArgs(barcode: barcode, productName: productName),
    ));

    final lowest = prices.firstWhere((p) => p['platform'] == lowestPlatform,
        orElse: () => prices.first);
    final others =
        prices.where((p) => p['platform'] != lowestPlatform).toList();

    // ── 동적 헤드라인 ──────────────────────────────────────
    String badgeText;
    String headlineText;
    Color headlineColor = kPrimaryDark;

    if (offlinePrice != null) {
      badgeText = 'Price Compared';
      if (offlinePrice > lowestPrice) {
        final pct = ((offlinePrice - lowestPrice) / offlinePrice * 100).round();
        headlineText = '온라인이 마트보다\n$pct% 더 저렴해요!';
        headlineColor = const Color(0xFF16A34A);
      } else if (offlinePrice < lowestPrice) {
        final pct =
            ((lowestPrice - offlinePrice) / lowestPrice * 100).round();
        headlineText = '마트가 온라인보다\n$pct% 더 저렴해요';
        headlineColor = kAmber;
      } else {
        headlineText = '마트와 온라인\n가격이 같아요';
      }
    } else {
      badgeText = 'Price Found';
      headlineText = '이 상품,\n온라인 최저가는?';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 배지 + 헤드라인
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badgeText,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: kPrimary,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            headlineText,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: headlineColor,
              height: 1.25,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 20),

          // 상품 카드
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '스캔한 상품',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade400,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        productName,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: kPrimaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  cacheAge == 0 ? '방금 조회' : '$cacheAge분 전',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── 비교 결과 카드 (마트 가격 입력 시) ────────────
          if (offlinePrice != null) ...[
            _ComparisonCard(
              offlinePrice: offlinePrice,
              onlinePrice: lowestPrice,
              lowestPlatform: lowestPlatform,
              nf: nf,
            ),
            const SizedBox(height: 8),
            // 가격 수정 버튼 (작게)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 14),
                label: Text('마트 가격 수정',
                    style: GoogleFonts.inter(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: kOnSurfaceVariant,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => context.push('/manual-price/$barcode'),
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            // 마트 가격 미입력 시 입력 버튼
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.storefront_outlined, size: 18),
                label: Text(
                  '마트 현재 가격 직접 입력',
                  style:
                      GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                ),
                onPressed: () => context.push('/manual-price/$barcode'),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── 온라인 최저가 카드 (hero) ──────────────────────
          Container(
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: kPrimary, width: 2),
              boxShadow: [
                BoxShadow(
                  color: kPrimary.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: kPrimary.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.shopping_cart_outlined,
                                color: kPrimary, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _platformLabel(lowestPlatform),
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            nf.format(lowest['price'] as int),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 52,
                              fontWeight: FontWeight.w900,
                              color: kPrimaryDark,
                              height: 1,
                              letterSpacing: -2,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '원',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: kPrimaryDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () async {
                            final url = lowest['url'] as String?;
                            if (url != null && url.isNotEmpty) {
                              final uri = Uri.tryParse(url);
                              if (uri != null && await canLaunchUrl(uri)) {
                                await launchUrl(
                                    uri,
                                    mode:
                                        LaunchMode.externalApplication);
                              }
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        '${_platformLabel(lowestPlatform)} 앱으로 이동합니다')),
                              );
                            }
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '최저가로 구매하기',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.arrow_forward, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: const BoxDecoration(
                      color: kPrimary,
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(22),
                        bottomLeft: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.stars, color: Colors.white, size: 13),
                        const SizedBox(width: 4),
                        Text(
                          '온라인 최저가',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 다른 쇼핑몰
          ...others.map((p) {
            final diff = (p['price'] as int) - (lowest['price'] as int);
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey.shade100),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.local_mall_outlined,
                                  color: Colors.grey.shade400, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _platformLabel(p['platform'] as String),
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              nf.format(p['price'] as int),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                color: kOnSurface.withValues(alpha: 0.75),
                                letterSpacing: -1,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '원',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: kOnSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: kError.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '+${nf.format(diff)}원',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: kError,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          // ── 내 가격 이력 그래프 ────────────────────────────
          const SizedBox(height: 8),
          priceHistoryAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (_, __) => const SizedBox.shrink(),
            data: (history) {
              if (history.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '내 가격 이력',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kPrimaryDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade100),
                    ),
                    child: PriceGraphWidget(priceHistory: history),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),

          // AdMob 배너
          const AdmobBanner(),
          const SizedBox(height: 24),

          // 인기 유사상품 추천 섹션
          _RecommendSection(recommendAsync: recommendAsync, nf: nf),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _RecommendSection extends StatelessWidget {
  final AsyncValue<Map<String, dynamic>> recommendAsync;
  final NumberFormat nf;
  const _RecommendSection({required this.recommendAsync, required this.nf});

  @override
  Widget build(BuildContext context) {
    return recommendAsync.when(
      loading: () => const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) {
        final items =
            (data['recommendations'] as List).cast<Map<String, dynamic>>();
        final keywords =
            (data['trending_keywords'] as List).cast<String>();
        final isDatalab = data['source'] == 'datalab';
        if (items.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '이런 상품도 인기 있어요',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: kPrimaryDark,
                  ),
                ),
                if (isDatalab) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '데이터랩 트렌드',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: kPrimary,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            // 인기 키워드 칩
            if (keywords.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                children: keywords
                    .take(4)
                    .map((k) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '# $k',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 14),

            // 상품 카드 가로 스크롤
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final item = items[i];
                  final price = (item['price'] as num).toInt();
                  final trendScore = item['trend_score'] as num?;
                  return _RecommendCard(
                    productName: item['product_name'] as String,
                    price: price,
                    imageUrl: item['image_url'] as String?,
                    shoppingUrl: item['shopping_url'] as String,
                    trendScore: trendScore?.toDouble(),
                    nf: nf,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RecommendCard extends StatelessWidget {
  final String productName;
  final int price;
  final String? imageUrl;
  final String shoppingUrl;
  final double? trendScore;
  final NumberFormat nf;

  const _RecommendCard({
    required this.productName,
    required this.price,
    required this.imageUrl,
    required this.shoppingUrl,
    required this.trendScore,
    required this.nf,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 이미지 or 플레이스홀더
          Container(
            height: 72,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: imageUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.inventory_2_outlined,
                        color: Colors.grey.shade300,
                        size: 28,
                      ),
                    ),
                  )
                : Icon(
                    Icons.inventory_2_outlined,
                    color: Colors.grey.shade300,
                    size: 28,
                  ),
          ),
          const SizedBox(height: 10),

          // 상품명
          Text(
            productName,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: kOnSurface,
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),

          // 가격 + 트렌드 점수
          Row(
            children: [
              Text(
                '${nf.format(price)}원',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: kPrimaryDark,
                ),
              ),
              if (trendScore != null) ...[
                const Spacer(),
                Icon(Icons.trending_up, size: 13, color: Colors.green.shade500),
                const SizedBox(width: 2),
                Text(
                  trendScore!.toStringAsFixed(0),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade600,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // 보러가기 버튼
          SizedBox(
            width: double.infinity,
            height: 30,
            child: OutlinedButton(
              onPressed: () async {
                final uri = Uri.tryParse(shoppingUrl);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                side: BorderSide(color: kPrimary.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                '보러가기',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: kPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 마트 vs 온라인 비교 카드 ─────────────────────────────────────────────

class _ComparisonCard extends StatelessWidget {
  final int offlinePrice;
  final int onlinePrice;
  final String lowestPlatform;
  final NumberFormat nf;

  const _ComparisonCard({
    required this.offlinePrice,
    required this.onlinePrice,
    required this.lowestPlatform,
    required this.nf,
  });

  @override
  Widget build(BuildContext context) {
    final diff = offlinePrice - onlinePrice;
    final onlineCheaper = diff > 0;
    final equal = diff == 0;

    final accentColor = equal
        ? kOnSurfaceVariant
        : onlineCheaper
            ? const Color(0xFF16A34A)
            : kAmber;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 절약/추가 뱃지
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  equal
                      ? Icons.compare_arrows
                      : onlineCheaper
                          ? Icons.savings_outlined
                          : Icons.storefront_outlined,
                  size: 14,
                  color: accentColor,
                ),
                const SizedBox(width: 6),
                Text(
                  equal
                      ? '마트 = 온라인'
                      : onlineCheaper
                          ? '온라인이 ${nf.format(diff)}원 더 저렴'
                          : '마트가 ${nf.format(-diff)}원 더 저렴',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 가격 비교 행
          Row(
            children: [
              // 마트 가격
              Expanded(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.storefront_outlined,
                            size: 14, color: kAmber),
                        const SizedBox(width: 4),
                        Text('마트',
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: kAmber)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${nf.format(offlinePrice)}원',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: onlineCheaper
                            ? kOnSurface.withValues(alpha: 0.5)
                            : kAmber,
                      ),
                    ),
                  ],
                ),
              ),
              // 화살표
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  equal
                      ? Icons.compare_arrows
                      : onlineCheaper
                          ? Icons.arrow_forward
                          : Icons.arrow_back,
                  size: 16,
                  color: kOnSurfaceVariant,
                ),
              ),
              // 온라인 가격
              Expanded(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_cart_outlined,
                            size: 14, color: kPrimary),
                        const SizedBox(width: 4),
                        Text(
                          lowestPlatform == 'coupang' ? '쿠팡' : '네이버',
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: kPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${nf.format(onlinePrice)}원',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: onlineCheaper
                            ? const Color(0xFF16A34A)
                            : kOnSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Scenario 2: 바코드로 상품을 못 찾았을 때 ─────────────────────────────

class _ProductNotFoundView extends StatefulWidget {
  final String barcode;
  final Future<void> Function(String name) onNameSubmitted;
  const _ProductNotFoundView({required this.barcode, required this.onNameSubmitted});

  @override
  State<_ProductNotFoundView> createState() => _ProductNotFoundViewState();
}

class _ProductNotFoundViewState extends State<_ProductNotFoundView> {
  final _controller = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty || _isLoading) return;
    setState(() => _isLoading = true);
    try {
      await widget.onNameSubmitted(name);
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('검색 중 오류가 발생했어요. 다시 시도해주세요.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.search_off_rounded,
                  size: 36, color: Colors.orange.shade400),
            ),
            const SizedBox(height: 20),
            Text(
              '바코드로 상품을 찾지 못했어요',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: kPrimaryDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '상품명을 직접 입력하면\n온라인 최저가를 조회해드려요',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: kOnSurfaceVariant,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: '예) 농심 신라면 120g',
                hintStyle: GoogleFonts.inter(color: Colors.grey.shade400),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: kPrimary, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        '온라인 가격 검색',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _PriceLoadingSkeleton extends StatelessWidget {
  const _PriceLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Shimmer(width: 80, height: 24, radius: 6),
          const SizedBox(height: 12),
          _Shimmer(width: 240, height: 36, radius: 8),
          const SizedBox(height: 8),
          _Shimmer(width: 160, height: 36, radius: 8),
          const SizedBox(height: 20),
          _Shimmer(width: double.infinity, height: 80, radius: 16),
          const SizedBox(height: 16),
          _Shimmer(width: double.infinity, height: 200, radius: 20),
          const SizedBox(height: 12),
          _Shimmer(width: double.infinity, height: 120, radius: 20),
        ],
      ),
    );
  }
}

class _Shimmer extends StatefulWidget {
  final double width, height, radius;
  const _Shimmer(
      {required this.width, required this.height, required this.radius});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _anim = Tween<double>(begin: -1, end: 2).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: [
              (_anim.value - 0.5).clamp(0.0, 1.0),
              _anim.value.clamp(0.0, 1.0),
              (_anim.value + 0.5).clamp(0.0, 1.0),
            ],
            colors: const [
              Color(0xFFEEEEEE),
              Color(0xFFF8F8F8),
              Color(0xFFEEEEEE),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _PriceErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 20),
            Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 16,
                color: kOnSurfaceVariant,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
