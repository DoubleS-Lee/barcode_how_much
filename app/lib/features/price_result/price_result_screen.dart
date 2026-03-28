import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/api/scan_api.dart';
import '../../shared/providers/device_provider.dart';
import '../../shared/services/share_service.dart';
import '../../shared/widgets/admob_banner.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../scan_history/price_graph_widget.dart';
import '../scan_history/scan_history_provider.dart';
import 'price_result_provider.dart';
import 'recommend_provider.dart';
import '../../shared/providers/saved_locations_provider.dart';

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
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
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
        data: (data) {
          final prices = (data['prices'] as List?)?.cast<Map>() ?? [];
          if (prices.isEmpty) {
            return _NoPriceView(
              barcode: barcode,
              productName: (data['product_name'] as String?) ?? barcode,
            );
          }
          return _PriceResultBody(barcode: barcode, data: data);
        },
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

class _PriceResultBody extends ConsumerStatefulWidget {
  final String barcode;
  final Map<String, dynamic> data;
  const _PriceResultBody({required this.barcode, required this.data});

  @override
  ConsumerState<_PriceResultBody> createState() => _PriceResultBodyState();
}

class _PriceResultBodyState extends ConsumerState<_PriceResultBody> {
  String? _overrideName;
  List<Map<String, dynamic>>? _overridePrices;
  String? _storeHint;
  String? _memo;
  int? _pendingOfflinePrice;   // 입력됐지만 아직 저장 안 된 오프라인 가격
  bool _isSaving = false;
  bool _saved = false;

  String _platformLabel(String platform) =>
      platform == 'coupang' ? '쿠팡' : '네이버 쇼핑';

  @override
  Widget build(BuildContext context) {
    final barcode = widget.barcode;
    final data = widget.data;
    final nf = NumberFormat('#,###');
    final prices = (data['prices'] as List).cast<Map>();
    final lowestPlatform = data['lowest_platform'] as String;
    final productName = _overrideName ?? (data['product_name'] as String?) ?? '바코드: $barcode';
    final lowestPrice = (data['lowest_price'] as num?)?.toInt() ?? 0;
    final cacheAge = (data['cache_age_minutes'] as num?)?.toInt() ?? 0;

    // 오버라이드된 가격 적용
    final effectivePrices = (_overridePrices ?? prices).cast<Map<String, dynamic>>();
    final effectiveLowest = effectivePrices.isNotEmpty
        ? effectivePrices.reduce((a, b) => (a['price'] as int) <= (b['price'] as int) ? a : b)
        : (prices.isNotEmpty ? Map<String, dynamic>.from(prices.first) : <String, dynamic>{});
    final effectiveLowestPrice = effectiveLowest.isNotEmpty ? effectiveLowest['price'] as int : lowestPrice;
    final effectiveLowestPlatform = effectiveLowest.isNotEmpty ? effectiveLowest['platform'] as String : lowestPlatform;

    final savedOfflinePrice = ref.watch(offlinePriceProvider(barcode));
    // 입력됐지만 아직 저장 전인 가격 우선 표시
    final offlinePrice = _pendingOfflinePrice ?? savedOfflinePrice;
    final priceHistoryAsync = ref.watch(priceHistoryProvider(barcode));
    final recommendAsync = ref.watch(recommendProvider(
      RecommendArgs(barcode: barcode, productName: productName),
    ));

    final lowest = effectiveLowest;
    final others =
        effectivePrices.where((p) => p['platform'] != effectiveLowestPlatform).toList();

    // ── 동적 헤드라인 ──────────────────────────────────────
    String badgeText;
    String headlineText;
    Color headlineColor = kPrimaryDark;

    if (offlinePrice != null) {
      badgeText = 'Price Compared';
      if (offlinePrice > effectiveLowestPrice) {
        final pct = ((offlinePrice - effectiveLowestPrice) / offlinePrice * 100).round();
        headlineText = '온라인이 마트보다\n$pct% 더 저렴해요!';
        headlineColor = const Color(0xFF16A34A);
      } else if (offlinePrice < effectiveLowestPrice) {
        final pct =
            ((effectiveLowestPrice - offlinePrice) / effectiveLowestPrice * 100).round();
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
                      const SizedBox(height: 8),
                      // 상품명 수정 / 네이버 재검색 / 장소 / 메모 버튼
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        GestureDetector(
                          onTap: _showNameEditDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.edit_outlined, size: 11, color: kOnSurfaceVariant),
                              const SizedBox(width: 3),
                              Text('상품명 수정', style: GoogleFonts.inter(fontSize: 11, color: kOnSurfaceVariant)),
                            ]),
                          ),
                        ),
                        GestureDetector(
                          onTap: _showNaverSheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: kPrimary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.search, size: 11, color: kPrimary),
                              const SizedBox(width: 3),
                              Text('네이버 재검색', style: GoogleFonts.inter(fontSize: 11, color: kPrimary)),
                            ]),
                          ),
                        ),
                        GestureDetector(
                          onTap: _showStoreDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _storeHint != null
                                  ? kPrimary.withValues(alpha: 0.08)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.place_outlined, size: 11,
                                  color: _storeHint != null ? kPrimary : kOnSurfaceVariant),
                              const SizedBox(width: 3),
                              Text(
                                _storeHint ?? '장소',
                                style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: _storeHint != null ? kPrimary : kOnSurfaceVariant),
                              ),
                            ]),
                          ),
                        ),
                        GestureDetector(
                          onTap: _showMemoDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _memo != null
                                  ? kPrimary.withValues(alpha: 0.08)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.notes, size: 11,
                                  color: _memo != null ? kPrimary : kOnSurfaceVariant),
                              const SizedBox(width: 3),
                              Text(
                                _memo != null
                                    ? (_memo!.length > 10 ? '${_memo!.substring(0, 10)}…' : _memo!)
                                    : '메모',
                                style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: _memo != null ? kPrimary : kOnSurfaceVariant),
                              ),
                            ]),
                          ),
                        ),
                      ]),
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
              onlinePrice: effectiveLowestPrice,
              lowestPlatform: effectiveLowestPlatform,
              nf: nf,
            ),
            const SizedBox(height: 8),
            // 가격 수정 버튼 (작게)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 14),
                label: Text('오프라인 가격 수정',
                    style: GoogleFonts.inter(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: kOnSurfaceVariant,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _showOfflinePriceSheet(context),
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            // 오프라인 가격 입력 버튼
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.storefront_outlined, size: 18),
                label: Text(
                  '오프라인 가격 직접 입력',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                ),
                onPressed: () => _showOfflinePriceSheet(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          // 저장 버튼 — 미저장이거나 pending 가격이 있으면 항상 표시
          if (!_saved || _pendingOfflinePrice != null) ...[
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle_outline, size: 18),
                label: Text('저장', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                onPressed: _isSaving ? null : () => _doSave(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 16),
              const SizedBox(width: 6),
              Text('저장됐어요', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF16A34A), fontWeight: FontWeight.w600)),
            ]),
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
                            _platformLabel(effectiveLowestPlatform),
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
                        child: OutlinedButton(
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
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kOnSurface,
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '최저가로 구매하기',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 16, fontWeight: FontWeight.w600),
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

          const SizedBox(height: 24),

          // 인기 유사상품 추천 섹션
          _RecommendSection(recommendAsync: recommendAsync, nf: nf),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _showNameEditDialog() async {
    final controller = TextEditingController(
        text: _overrideName ?? widget.data['product_name'] as String? ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('상품명 수정',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          decoration: InputDecoration(
            hintText: '올바른 상품명 입력',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소', style: GoogleFonts.inter(color: kOnSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('확인', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final newName = controller.text.trim();
    if (newName.isNotEmpty) {
      setState(() => _overrideName = newName);
      // 즉시 DB 반영 + 스캔 기록 갱신
      try {
        await ScanApi.patchProductName(barcode: widget.barcode, name: newName);
        if (mounted) {
          ref.invalidate(scanHistoryProvider);
          ref.invalidate(priceHistoryProvider(widget.barcode));
        }
      } catch (_) {}
    }
  }

  Future<void> _showStoreDialog() async {
    final controller = TextEditingController(text: _storeHint ?? '');
    final savedLocations = ref.read(savedLocationsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('장소', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (savedLocations.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: savedLocations.map((loc) => GestureDetector(
                  onTap: () => controller.text = loc,
                  child: Chip(
                    label: Text(loc, style: GoogleFonts.inter(fontSize: 11)),
                    backgroundColor: kPrimary.withValues(alpha: 0.06),
                    side: BorderSide(color: kPrimary.withValues(alpha: 0.2)),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )).toList(),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: controller,
              autofocus: savedLocations.isEmpty,
              maxLength: 100,
              decoration: InputDecoration(
                hintText: '이마트 왕십리점',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              style: GoogleFonts.inter(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소', style: GoogleFonts.inter(color: kOnSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('확인', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final text = controller.text.trim();
    setState(() => _storeHint = text.isEmpty ? null : text);
  }

  Future<void> _showMemoDialog() async {
    final controller = TextEditingController(text: _memo ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('메모', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(
            hintText: '1+1 행사 중',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소', style: GoogleFonts.inter(color: kOnSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('확인', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final text = controller.text.trim();
    setState(() => _memo = text.isEmpty ? null : text);
  }

  void _showNaverSheet() {
    final searchName = _overrideName ?? widget.data['product_name'] as String? ?? '';
    if (searchName.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _NaverPickerSheet(
        productName: searchName,
        onSelected: (candidate) {
          final originalPrices = (widget.data['prices'] as List).cast<Map<String, dynamic>>();
          final nonNaver = originalPrices.where((p) => p['platform'] != 'naver').toList();
          final newNaver = <String, dynamic>{
            'platform': 'naver',
            'price': candidate['price'] as int,
            'is_lowest': false,
            'url': candidate['shopping_url'] as String? ?? '',
            'image_url': candidate['image_url'] as String?,
          };
          final merged = [...nonNaver, newNaver];
          final minP = merged.map((p) => p['price'] as int).reduce((a, b) => a < b ? a : b);
          for (final p in merged) { p['is_lowest'] = p['price'] == minP; }
          // 상품명은 사용자가 설정한 그대로 유지 (_overrideName 변경하지 않음)
          setState(() {
            _overridePrices = merged;
          });
        },
      ),
    );
  }

  Future<void> _doSave(BuildContext context) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      String? scanId = ref.read(priceResultProvider(widget.barcode)).valueOrNull?['scan_id'] as String?;

      // 스캔이 아직 저장 안 됐으면 저장
      if (!_saved) {
        final currentName = _overrideName;
        if (currentName != null) {
          await ScanApi.patchProductName(barcode: widget.barcode, name: currentName);
        }
        final currentPrices = _overridePrices
            ?? (widget.data['prices'] as List).cast<Map<String, dynamic>>();
        scanId = await ref.read(priceResultProvider(widget.barcode).notifier)
            .saveScan(widget.barcode, currentPrices);

        // 네이버 재검색으로 상품을 선택한 경우 → DB에 선택한 상품 가격 반영
        if (_overridePrices != null) {
          final naverEntry = _overridePrices!.where((p) => p['platform'] == 'naver').toList();
          if (naverEntry.isNotEmpty) {
            try {
              final deviceUuid = await ref.read(deviceUuidProvider.future);
              final productName = currentName ?? (widget.data['product_name'] as String? ?? '');
              await ScanApi.relinkNaver(
                deviceUuid: deviceUuid,
                barcode: widget.barcode,
                productName: productName,
                price: naverEntry.first['price'] as int,
                shoppingUrl: naverEntry.first['url'] as String? ?? '',
                imageUrl: naverEntry.first['image_url'] as String?
                    ?? widget.data['image_url'] as String?,
              );
            } catch (_) {}
          }
        }
      }

      // 오프라인 가격이 입력돼 있으면 저장
      if (_pendingOfflinePrice != null && scanId != null) {
        await ScanApi.postOfflinePrice(
          scanId: scanId,
          price: _pendingOfflinePrice!,
          storeHint: _storeHint,
          memo: _memo,
        );
        ref.read(offlinePriceProvider(widget.barcode).notifier).state = _pendingOfflinePrice;
        ref.read(liveOfflinePriceProvider(widget.barcode).notifier).state = _pendingOfflinePrice!;
        ref.read(liveScanOfflinePriceProvider(scanId).notifier).state = _pendingOfflinePrice!;
        ref.invalidate(priceHistoryProvider(widget.barcode));
        ref.invalidate(scanHistoryProvider);
      }

      if (mounted) setState(() { _saved = true; _isSaving = false; _pendingOfflinePrice = null; });
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  void _showOfflinePriceSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OfflinePriceSheet(
        initialStore: _storeHint,
        initialMemo: _memo,
        initialPrice: _pendingOfflinePrice,
        savedLocations: ref.read(savedLocationsProvider),
        onConfirmed: (price, store, memo) {
          setState(() {
            _pendingOfflinePrice = price;
            _storeHint = store;
            _memo = memo;
          });
        },
      ),
    );
  }
}

// ── 스캔 결과 화면 — 네이버 상품 선택 시트 ───────────────

class _NaverPickerSheet extends StatefulWidget {
  final String productName;
  final void Function(Map<String, dynamic>) onSelected;
  const _NaverPickerSheet({required this.productName, required this.onSelected});

  @override
  State<_NaverPickerSheet> createState() => _NaverPickerSheetState();
}

class _NaverPickerSheetState extends State<_NaverPickerSheet> {
  List<Map<String, dynamic>>? _candidates;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ScanApi.getNaverCandidates(widget.productName);
      if (mounted) setState(() { _candidates = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat('#,###');
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (_, controller) => Column(children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('네이버 상품 선택', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('"${widget.productName}" 검색 결과에서 올바른 상품을 선택해주세요.',
                style: GoogleFonts.inter(fontSize: 13, color: kOnSurfaceVariant)),
          ]),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text('검색 실패: $_error', style: GoogleFonts.inter(color: kOnSurfaceVariant)))
                  : (_candidates == null || _candidates!.isEmpty)
                      ? Center(child: Text('검색 결과가 없어요.', style: GoogleFonts.inter(color: kOnSurfaceVariant)))
                      : ListView.separated(
                          controller: controller,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _candidates!.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                          itemBuilder: (_, i) {
                            final c = _candidates![i];
                            final name = c['product_name'] as String;
                            final price = c['price'] as int;
                            final imageUrl = c['image_url'] as String?;
                            final mallName = c['mall_name'] as String? ?? '';
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: imageUrl != null
                                    ? Image.network(imageUrl, width: 56, height: 56, fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _placeholder())
                                    : _placeholder(),
                              ),
                              title: Text(name,
                                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const SizedBox(height: 2),
                                Text('${nf.format(price)}원',
                                    style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: kPrimary)),
                                if (mallName.isNotEmpty)
                                  Text(mallName, style: GoogleFonts.inter(fontSize: 11, color: kOnSurfaceVariant)),
                              ]),
                              onTap: () {
                                Navigator.pop(context);
                                widget.onSelected(c);
                              },
                            );
                          },
                        ),
        ),
      ]),
    );
  }

  Widget _placeholder() => Container(
    width: 56, height: 56, color: Colors.grey.shade100,
    child: const Icon(Icons.image_outlined, color: Colors.grey),
  );
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

// ── 상품명은 있지만 가격 정보가 없을 때 ──────────────────

class _NoPriceView extends StatelessWidget {
  final String barcode;
  final String productName;
  const _NoPriceView({required this.barcode, required this.productName});

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
                color: kPrimary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.price_change_outlined,
                  size: 36, color: kPrimary),
            ),
            const SizedBox(height: 20),
            Text(
              productName,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kPrimaryDark,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Text(
              '온라인 가격 정보를 찾지 못했어요',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: kOnSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '네이버·쿠팡에 등록되지 않은 상품이에요.\n마트에서 직접 가격을 입력해두면\n다음번 비교에 활용할 수 있어요.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: kOnSurfaceVariant,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.push('/manual-price/$barcode'),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(
                  '마트 가격 직접 입력하기',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.pop(),
              child: Text(
                '다른 바코드 스캔하기',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: kOnSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

// ── 오프라인 가격 입력 바텀시트 ──────────────────────────────────────────

// API 호출 없는 순수 picker — 확인 시 부모 상태에 값 전달
class _OfflinePriceSheet extends StatefulWidget {
  final String? initialStore;
  final String? initialMemo;
  final int? initialPrice;
  final List<String> savedLocations;
  final void Function(int price, String? store, String? memo) onConfirmed;

  const _OfflinePriceSheet({
    this.initialStore,
    this.initialMemo,
    this.initialPrice,
    this.savedLocations = const [],
    required this.onConfirmed,
  });

  @override
  State<_OfflinePriceSheet> createState() => _OfflinePriceSheetState();
}

class _OfflinePriceSheetState extends State<_OfflinePriceSheet> {
  String _input = '';
  String _promotion = '없음';
  late final TextEditingController _storeCtrl;
  late final TextEditingController _memoCtrl;

  int get _unitPrice {
    if (_input.isEmpty) return 0;
    final price = int.parse(_input);
    switch (_promotion) {
      case '1+1': return (price / 2).round();
      case '2+1': return (price * 2 / 3).round();
      case '3+1': return (price * 3 / 4).round();
      default: return price;
    }
  }

  String get _displayPrice {
    if (_input.isEmpty) return '0';
    final n = int.tryParse(_input) ?? 0;
    return NumberFormat('#,###').format(n);
  }

  @override
  void initState() {
    super.initState();
    // 이전에 입력한 가격이 있으면 복원
    if (widget.initialPrice != null) {
      _input = widget.initialPrice.toString();
    }
    _storeCtrl = TextEditingController(text: widget.initialStore ?? '');
    _memoCtrl = TextEditingController(text: widget.initialMemo ?? '');
  }

  @override
  void dispose() {
    _storeCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  void _onKey(String key) {
    setState(() {
      if (key == '⌫') {
        if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
      } else if (_input.length < 8) {
        _input += key;
      }
    });
  }

  void _onConfirm() {
    if (_input.isEmpty) return;
    final storeHint = _storeCtrl.text.trim().isEmpty ? null : _storeCtrl.text.trim();
    final memo = _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim();
    Navigator.pop(context);
    widget.onConfirmed(_unitPrice, storeHint, memo);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  '오프라인 가격 직접 입력',
                  style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: kPrimaryDark),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              children: [
                Text(
                  '오프라인 현재 가격',
                  style: GoogleFonts.inter(fontSize: 13, color: kOnSurfaceVariant, fontWeight: FontWeight.w500, letterSpacing: 0.3),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _displayPrice,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        color: _input.isEmpty ? kOutlineVariant : kOnSurface.withValues(alpha: 0.6),
                        letterSpacing: -2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '원',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20, fontWeight: FontWeight.w700,
                        color: _input.isEmpty ? kOutlineVariant : kOnSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: ['없음', '1+1', '2+1', '3+1'].map((promo) {
                    final selected = _promotion == promo;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _promotion = promo),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: selected ? kPrimary : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: selected ? kPrimary : Colors.grey.shade200),
                          ),
                          child: Center(
                            child: Text(
                              promo,
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? Colors.white : kOnSurfaceVariant),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                if (widget.savedLocations.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: widget.savedLocations.map((loc) => GestureDetector(
                      onTap: () => setState(() => _storeCtrl.text = loc),
                      child: Chip(
                        label: Text(loc, style: GoogleFonts.inter(fontSize: 11)),
                        backgroundColor: kPrimary.withValues(alpha: 0.06),
                        side: BorderSide(color: kPrimary.withValues(alpha: 0.2)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _storeCtrl,
                        style: GoogleFonts.inter(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: '장소',
                          hintText: '이마트 왕십리점',
                          hintStyle: GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant),
                          labelStyle: GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant),
                          prefixIcon: const Icon(Icons.place_outlined, size: 16, color: kOnSurfaceVariant),
                          filled: true,
                          fillColor: kSurface,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _memoCtrl,
                        style: GoogleFonts.inter(fontSize: 13),
                        maxLength: 100,
                        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                        decoration: InputDecoration(
                          labelText: '메모 (선택)',
                          hintText: '1+1 행사 중',
                          hintStyle: GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant),
                          labelStyle: GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant),
                          prefixIcon: const Icon(Icons.notes, size: 16, color: kOnSurfaceVariant),
                          filled: true,
                          fillColor: kSurface,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_promotion != '없음' && _input.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(color: kPrimary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('개당 가격  ', style: GoogleFonts.inter(fontSize: 13, color: kPrimary, fontWeight: FontWeight.w600)),
                        Text(
                          NumberFormat('#,###').format(_unitPrice),
                          style: GoogleFonts.plusJakartaSans(fontSize: 32, fontWeight: FontWeight.w900, color: kPrimary, letterSpacing: -1),
                        ),
                        const SizedBox(width: 4),
                        Text('원', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: kPrimary)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: GridView.count(
              crossAxisCount: 3,
              childAspectRatio: 2.0,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                ...['1', '2', '3', '4', '5', '6', '7', '8', '9']
                    .map((k) => _SheetKeyButton(label: k, onTap: () => _onKey(k))),
                _SheetKeyButton(label: '⌫', onTap: () => _onKey('⌫'), backgroundColor: Colors.grey.shade100, textColor: kOnSurface, isIcon: true),
                _SheetKeyButton(label: '0', onTap: () => _onKey('0')),
                _SheetKeyButton(
                  label: _promotion != '없음' && _input.isNotEmpty
                      ? '${NumberFormat('#,###').format(_unitPrice)}원\n확인'
                      : '확인',
                  onTap: _onConfirm,
                  backgroundColor: _input.isEmpty ? kOutlineVariant : kPrimary,
                  textColor: Colors.white,
                  fontSize: _promotion != '없음' && _input.isNotEmpty ? 13 : 18,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetKeyButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final Color? textColor;
  final double fontSize;
  final bool isIcon;

  const _SheetKeyButton({
    required this.label,
    required this.onTap,
    this.backgroundColor,
    this.textColor,
    this.fontSize = 26,
    this.isIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? Colors.white;
    final fg = textColor ?? kOnSurface;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: kPrimary.withValues(alpha: 0.1),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: bg == Colors.white ? Colors.grey.shade200 : Colors.transparent),
          ),
          child: Center(
            child: isIcon
                    ? Icon(Icons.backspace_outlined, color: fg, size: 22)
                    : Text(
                        label,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(fontSize: fontSize, fontWeight: FontWeight.w700, color: fg, height: 1.3),
                      ),
          ),
        ),
      ),
    );
  }
}
