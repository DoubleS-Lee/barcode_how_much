import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../shared/api/scan_api.dart';
import '../../shared/services/notification_service.dart';
import '../price_result/price_result_provider.dart';
import '../scan_history/scan_history_provider.dart';

class ManualPriceScreen extends ConsumerStatefulWidget {
  final String barcode;
  const ManualPriceScreen({super.key, required this.barcode});

  @override
  ConsumerState<ManualPriceScreen> createState() => _ManualPriceScreenState();
}

class _ManualPriceScreenState extends ConsumerState<ManualPriceScreen> {
  String _input = '';
  String _promotion = '없음';
  bool _isLoading = false;

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

  void _onKey(String key) {
    if (_isLoading) return;
    setState(() {
      if (key == '⌫') {
        if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
      } else if (_input.length < 8) {
        _input += key;
      }
    });
  }

  Future<void> _onSave() async {
    if (_input.isEmpty || _isLoading) return;

    final priceData = ref.read(priceResultProvider(widget.barcode)).valueOrNull;
    final scanId = priceData?['scan_id'] as String?;
    if (scanId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('가격 정보를 불러오는 중이에요. 잠시 후 다시 시도해주세요.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final offlinePrice = _unitPrice;
      await ScanApi.postOfflinePrice(scanId: scanId, price: offlinePrice);

      // 온라인이 더 싸면 알림
      final lowestOnlinePrice = priceData?['lowest_price'] as int?;
      if (lowestOnlinePrice != null && lowestOnlinePrice < offlinePrice) {
        final productName = priceData?['product_name'] as String? ?? '스캔한 상품';
        await NotificationService.showPriceDrop(
          productName: productName,
          onlinePrice: lowestOnlinePrice,
          offlinePrice: offlinePrice,
        );
      }

      // 마트 입력가를 PriceResult 화면과 공유
      ref.read(offlinePriceProvider(widget.barcode).notifier).state = offlinePrice;
      // 가격 이력 그래프 갱신
      ref.invalidate(priceHistoryProvider(widget.barcode));

      if (mounted) context.pushReplacement('/price-result/${widget.barcode}');
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('저장 실패: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  String get _displayPrice {
    if (_input.isEmpty) return '0';
    final n = int.tryParse(_input) ?? 0;
    return NumberFormat('#,###').format(n);
  }

  @override
  Widget build(BuildContext context) {
    final priceAsync = ref.watch(priceResultProvider(widget.barcode));
    final productName = priceAsync.valueOrNull?['product_name'] as String?;

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: Text(
          '마트 현재 가격 입력',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: kPrimaryDark,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pushReplacement('/price-result/${widget.barcode}'),
            child: Text(
              '건너뛰기',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: kOnSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 상품명 표시
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              color: kSurface,
              border: Border(bottom: BorderSide(color: kOutlineVariant, width: 1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    size: 16, color: kOnSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    productName ??
                        (priceAsync.isLoading ? '상품 정보 조회 중...' : '알 수 없는 상품'),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color:
                          productName != null ? kPrimaryDark : kOnSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (priceAsync.isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kPrimary),
                  ),
              ],
            ),
          ),

          // 가격 표시 + 프로모션 선택
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            decoration: const BoxDecoration(
              color: kSurface,
              border: Border(bottom: BorderSide(color: kOutlineVariant, width: 1)),
            ),
            child: Column(
              children: [
                Text(
                  '마트 현재 가격',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: kOnSurfaceVariant,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 10),
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
                        color: _input.isEmpty
                            ? kOutlineVariant
                            : kOnSurface.withValues(alpha: 0.6),
                        letterSpacing: -2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '원',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _input.isEmpty
                            ? kOutlineVariant
                            : kOnSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                // 행사 선택 버튼
                const SizedBox(height: 14),
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
                            border: Border.all(
                              color: selected ? kPrimary : Colors.grey.shade200,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              promo,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color:
                                    selected ? Colors.white : kOnSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                // 개당 가격 (행사 선택 시)
                if (_promotion != '없음' && _input.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '개당 가격  ',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: kPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          NumberFormat('#,###').format(_unitPrice),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: kPrimary,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '원',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: kPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 키패드
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.count(
                crossAxisCount: 3,
                childAspectRatio: 2.0,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  ...['1', '2', '3', '4', '5', '6', '7', '8', '9']
                      .map((k) => _KeyButton(label: k, onTap: () => _onKey(k))),
                  _KeyButton(
                    label: '⌫',
                    onTap: () => _onKey('⌫'),
                    backgroundColor: Colors.grey.shade100,
                    textColor: kOnSurface,
                    isIcon: true,
                  ),
                  _KeyButton(label: '0', onTap: () => _onKey('0')),
                  _KeyButton(
                    label: _promotion != '없음' && _input.isNotEmpty
                        ? '${NumberFormat('#,###').format(_unitPrice)}원\n저장'
                        : '저장',
                    onTap: _onSave,
                    backgroundColor:
                        (_input.isEmpty || _isLoading) ? kOutlineVariant : kPrimary,
                    textColor: Colors.white,
                    fontSize:
                        _promotion != '없음' && _input.isNotEmpty ? 13 : 18,
                    isLoading: _isLoading,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final Color? textColor;
  final double fontSize;
  final bool isIcon;
  final bool isLoading;

  const _KeyButton({
    required this.label,
    required this.onTap,
    this.backgroundColor,
    this.textColor,
    this.fontSize = 26,
    this.isIcon = false,
    this.isLoading = false,
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
            border: Border.all(
              color: bg == Colors.white
                  ? Colors.grey.shade200
                  : Colors.transparent,
            ),
          ),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: fg,
                    ),
                  )
                : isIcon
                    ? Icon(Icons.backspace_outlined, color: fg, size: 22)
                    : Text(
                        label,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w700,
                          color: fg,
                          height: 1.3,
                        ),
                      ),
          ),
        ),
      ),
    );
  }
}
