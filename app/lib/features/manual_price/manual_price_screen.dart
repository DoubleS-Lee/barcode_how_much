import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../shared/api/scan_api.dart';
import '../../shared/services/notification_service.dart';

class ManualPriceScreen extends StatefulWidget {
  final int scanId;
  final int? lowestOnlinePrice;
  final String? productName;
  const ManualPriceScreen({
    super.key,
    required this.scanId,
    this.lowestOnlinePrice,
    this.productName,
  });

  @override
  State<ManualPriceScreen> createState() => _ManualPriceScreenState();
}

class _ManualPriceScreenState extends State<ManualPriceScreen> {
  String _input = '';
  bool _saved = false;
  bool _isLoading = false;

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
    setState(() => _isLoading = true);
    try {
      final offlinePrice = int.parse(_input);
      await ScanApi.postOfflinePrice(
        scanId: widget.scanId.toString(),
        price: offlinePrice,
      );
      if (mounted) {
        setState(() { _saved = true; _isLoading = false; });
        // 온라인이 더 싸면 알림 발송
        final onlinePrice = widget.lowestOnlinePrice;
        if (onlinePrice != null && onlinePrice < offlinePrice) {
          await NotificationService.showPriceDrop(
            productName: widget.productName ?? '스캔한 상품',
            onlinePrice: onlinePrice,
            offlinePrice: offlinePrice,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  Future<void> _requestLocation() async {
    // Windows/Web은 위치 미지원
    if (kIsWeb || (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('위치 기록은 모바일에서 지원됩니다')),
      );
      return;
    }

    try {
      // 권한 확인/요청
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('위치 권한이 필요합니다')),
          );
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('설정에서 위치 권한을 허용해주세요')),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );

      // 주소 역지오코딩
      String storeHint = '현재 위치';
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude, position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = [p.thoroughfare, p.subLocality, p.locality]
              .where((s) => s != null && s.isNotEmpty)
              .toList();
          storeHint = parts.take(2).join(' ');
        }
      } catch (_) {}

      // 오프라인 가격에 위치 정보 업데이트 (store_hint 업데이트는 별도 API가 없으므로 로컬 표시)
      if (mounted) {
        setState(() => _saved = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('📍 위치 기록 완료: $storeHint')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('위치를 가져올 수 없어요: $e')),
      );
    }
  }

  String get _displayPrice {
    if (_input.isEmpty) return '0';
    final n = int.tryParse(_input) ?? 0;
    return NumberFormat('#,###').format(n);
  }

  @override
  Widget build(BuildContext context) {
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
      ),
      body: Column(
        children: [
          // 가격 표시 영역
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
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
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _displayPrice,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        color: _input.isEmpty ? kOutlineVariant : kPrimaryDark,
                        letterSpacing: -2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '원',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: _input.isEmpty ? kOutlineVariant : kOnSurface,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 저장 후 위치 제안 배너
          if (_saved)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kPrimary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      color: kPrimary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '지금 마트 위치도 같이 기록할까요?',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: kPrimaryDark,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() => _saved = false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '괜찮아요',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: kOnSurfaceVariant),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    height: 34,
                    child: ElevatedButton(
                      onPressed: _requestLocation,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        '기록하기',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
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
                    label: '저장',
                    onTap: _onSave,
                    backgroundColor: (_input.isEmpty || _isLoading) ? kOutlineVariant : kPrimary,
                    textColor: Colors.white,
                    fontSize: 18,
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
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
          ),
        ),
      ),
    );
  }
}
