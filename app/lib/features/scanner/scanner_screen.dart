import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart' as ms;
import 'package:shimmer/shimmer.dart';
import '../../core/theme.dart';
import '../../shared/providers/scan_settings_provider.dart';
import '../../shared/utils/scan_feedback.dart';
import '../../shared/widgets/app_bottom_nav.dart';

/// 실제 카메라를 사용하는 플랫폼 여부
bool get _useRealCamera =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  String? _errorMessage;
  bool _flashOn = false;
  double _zoomLevel = 0.0;

  ms.MobileScannerController? _cameraController;

  String? _lastScannedBarcode;
  DateTime? _lastScannedAt;

  late AnimationController _scanLineController;
  late Animation<double> _scanLineAnim;

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scanLineAnim = Tween<double>(begin: 0, end: 1).animate(_scanLineController);

    if (_useRealCamera) {
      _cameraController = ms.MobileScannerController(
        detectionSpeed: ms.DetectionSpeed.noDuplicates,
        facing: ms.CameraFacing.back,
        torchEnabled: false,
      );
    }

  }

  @override
  void dispose() {
    _scanLineController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  bool _shouldSkip(String barcodeValue) {
    final now = DateTime.now();
    if (_lastScannedBarcode == barcodeValue &&
        _lastScannedAt != null &&
        now.difference(_lastScannedAt!).inSeconds < 3) {
      return true;
    }
    _lastScannedBarcode = barcodeValue;
    _lastScannedAt = now;
    return false;
  }

  bool _isProductBarcode(String format) {
    return ['ean13', 'ean8', 'upca', 'upce'].contains(format.toLowerCase());
  }

  Future<void> _onProductScanned(String barcode) async {
    if (_shouldSkip(barcode)) return;
    final sound = ref.read(scanSoundProvider);
    final vibration = ref.read(scanVibrationProvider);
    ScanFeedback.trigger(sound: sound, vibration: vibration);
    await _cameraController?.stop();
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        setState(() => _isLoading = false);
        await context.push('/price-result/$barcode');
        await _cameraController?.start();
      }
    } catch (e) {
      if (mounted) {
        String message;
        if (e is DioException && e.type == DioExceptionType.connectionTimeout ||
            e is DioException && e.type == DioExceptionType.receiveTimeout) {
          message = '서버 응답이 너무 느려요.\n잠시 후 다시 시도해주세요.';
        } else if (e is DioException && e.type == DioExceptionType.connectionError) {
          message = '인터넷 연결을 확인해주세요.\n마트 안이라면 조금 이동 후 다시 시도해보세요.';
        } else if (e is DioException && e.response?.statusCode == 404) {
          message = '등록되지 않은 상품이에요.\n다른 바코드를 스캔해주세요.';
        } else {
          message = '오류가 발생했어요.\n잠시 후 다시 시도해주세요.';
        }
        setState(() {
          _isLoading = false;
          _errorMessage = message;
        });
        await _cameraController?.start();
      }
    }
  }

  void _simulateScan(String value, String format) {
    if (_isProductBarcode(format)) {
      _onProductScanned(value);
    } else {
      setState(() => _errorMessage = '상품 바코드만 인식할 수 있어요.\n식품, 전자제품 등의 바코드를 사용해주세요.');
    }
  }

  void _onMobileScannerDetect(ms.BarcodeCapture capture) {
    if (_isLoading) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null) return;
    final rawValue = barcode.rawValue ?? '';
    if (rawValue.isEmpty) return;

    final format = switch (barcode.format) {
      ms.BarcodeFormat.ean13 => 'ean13',
      ms.BarcodeFormat.ean8 => 'ean8',
      ms.BarcodeFormat.upcA => 'upca',
      ms.BarcodeFormat.upcE => 'upce',
      _ => 'qrcode',
    };
    _simulateScan(rawValue, format);
  }

  void _showHelp() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '사용 방법',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            const SizedBox(height: 20),
            ...[
              (Icons.center_focus_strong_outlined, '바코드 인식',
                  '사각형 안에 바코드를 비추면 자동으로 인식됩니다.\n식품·생활용품·전자기기 바코드를 지원해요.'),
              (Icons.flashlight_on_outlined, '어두운 환경',
                  '좌측 상단 플래시 버튼을 켜면\n어두운 매장에서도 스캔할 수 있어요.'),
              (Icons.photo_library_outlined, '사진으로 스캔',
                  '아래 "사진에서 바코드 인식" 버튼으로\n갤러리 사진 속 바코드도 인식할 수 있어요.'),
              (Icons.price_check_outlined, '가격 비교',
                  '바코드 인식 후 마트 현재 가격을 입력하면\n온라인 최저가와 즉시 비교해드려요.'),
            ].map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(item.$1, color: kPrimary, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.$2,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, fontWeight: FontWeight.w700,
                            color: Colors.white)),
                        const SizedBox(height: 3),
                        Text(item.$3,
                          style: GoogleFonts.inter(
                            fontSize: 12, color: Colors.white.withValues(alpha: 0.6),
                            height: 1.5)),
                      ],
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleFlash() async {
    setState(() => _flashOn = !_flashOn);
    await _cameraController?.toggleTorch();
  }

  Future<void> _pickImageAndScan() async {
    if (_isLoading) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() { _isLoading = true; _errorMessage = null; });
    final scanner = BarcodeScanner(formats: [BarcodeFormat.all]);
    try {
      final inputImage = InputImage.fromFilePath(picked.path);
      final barcodes = await scanner.processImage(inputImage);
      if (!mounted) return;
      if (barcodes.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = '사진에서 바코드를 찾지 못했어요.\n바코드가 잘 보이는 사진을 선택해보세요.';
        });
        return;
      }
      final barcode = barcodes.first;
      setState(() => _isLoading = false);
      _simulateScan(barcode.rawValue ?? '', barcode.format.name.toLowerCase());
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '바코드 인식에 실패했어요. 다시 시도해보세요.';
        });
      }
    } finally {
      await scanner.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x55000000), Colors.transparent],
            ),
          ),
        ),
        leading: IconButton(
          icon: Icon(_flashOn ? Icons.flashlight_on : Icons.flashlight_off, color: Colors.white),
          onPressed: _useRealCamera ? _toggleFlash : () => setState(() => _flashOn = !_flashOn),
        ),
        title: Text('얼마였지?',
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.help_outline, color: Colors.white), onPressed: _showHelp),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_useRealCamera && _cameraController != null)
            ms.MobileScanner(controller: _cameraController!, onDetect: _onMobileScannerDetect)
          else
            Container(color: const Color(0xFF1A1A2E)),

          _ScannerOverlay(scanLineAnim: _scanLineAnim),

          // 가이드 텍스트
          Positioned(
            top: MediaQuery.of(context).size.height * 0.62,
            left: 0, right: 0,
            child: Text(
              _useRealCamera ? '바코드를 사각형 안에 비춰주세요' : '바코드를 사각형 안에 비춰주세요 (데모 모드)',
              style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.8), fontSize: 14, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),

          // 줌 슬라이더
          Positioned(
            bottom: 200,
            left: 32, right: 32,
            child: Row(children: [
              const Icon(Icons.remove, color: Colors.white, size: 18),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                    thumbColor: Colors.white,
                    overlayColor: Colors.white.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: _zoomLevel,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) {
                      setState(() => _zoomLevel = v);
                      _cameraController?.setZoomScale(v);
                    },
                  ),
                ),
              ),
              const Icon(Icons.add, color: Colors.white, size: 18),
            ]),
          ),

          // 하단 버튼 영역
          Positioned(
            bottom: 100,
            left: 24, right: 24,
            child: Column(
              children: [
                // Windows 데모 전용 버튼
                if (!_useRealCamera) ...[
                  _DemoButton(
                    icon: Icons.inventory_2_outlined,
                    label: '상품 바코드 스캔 (데모)',
                    color: Colors.white.withValues(alpha: 0.12),
                    onTap: () => _simulateScan('8801234567890', 'ean13'),
                  ),
                  const SizedBox(height: 8),
                ],
                // 갤러리 버튼 (모든 플랫폼 공통)
                _DemoButton(
                  icon: Icons.photo_library_outlined,
                  label: '사진에서 바코드 인식',
                  color: Colors.amber.withValues(alpha: 0.2),
                  onTap: _pickImageAndScan,
                ),
              ],
            ),
          ),

          if (_isLoading)
            Positioned(
              bottom: 180, left: 24, right: 24,
              child: Shimmer.fromColors(
                baseColor: Colors.grey.shade800,
                highlightColor: Colors.grey.shade600,
                child: Container(height: 80, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16))),
              ),
            ),

          if (_errorMessage != null)
            Positioned(
              bottom: 180, left: 24, right: 24,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFB45309), borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    Text(_errorMessage!, style: GoogleFonts.inter(color: Colors.white, fontSize: 14, height: 1.5), textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => setState(() => _errorMessage = null),
                      style: TextButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: Text('다시 시도', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    );
  }
}

// ── 스캐너 오버레이 ───────────────────────────────────────

class _ScannerOverlay extends StatelessWidget {
  final Animation<double> scanLineAnim;
  const _ScannerOverlay({required this.scanLineAnim});

  @override
  Widget build(BuildContext context) {
    const frameSize = 260.0;
    const cornerLength = 24.0;
    const cornerWidth = 3.0;
    final screenH = MediaQuery.of(context).size.height;
    final frameTop = screenH * 0.28;
    final sideW = (MediaQuery.of(context).size.width - frameSize) / 2;

    return Stack(children: [
      Positioned(top: 0, left: 0, right: 0, height: frameTop, child: const ColoredBox(color: Color(0x55000000))),
      Positioned(top: frameTop + frameSize, left: 0, right: 0, bottom: 0, child: const ColoredBox(color: Color(0x55000000))),
      Positioned(top: frameTop, left: 0, width: sideW, height: frameSize, child: const ColoredBox(color: Color(0x55000000))),
      Positioned(top: frameTop, right: 0, width: sideW, height: frameSize, child: const ColoredBox(color: Color(0x55000000))),
      Positioned(
        top: frameTop, left: sideW, width: frameSize, height: frameSize,
        child: Stack(children: [
          Positioned(top: 0, left: 0, child: _Corner(tl: true, length: cornerLength, width: cornerWidth)),
          Positioned(top: 0, right: 0, child: _Corner(tr: true, length: cornerLength, width: cornerWidth)),
          Positioned(bottom: 0, left: 0, child: _Corner(bl: true, length: cornerLength, width: cornerWidth)),
          Positioned(bottom: 0, right: 0, child: _Corner(br: true, length: cornerLength, width: cornerWidth)),
          AnimatedBuilder(
            animation: scanLineAnim,
            builder: (_, __) => Positioned(
              top: scanLineAnim.value * frameSize, left: 0, right: 0,
              child: Container(height: 1.5, decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  Colors.transparent,
                  kPrimary.withValues(alpha: 0.8),
                  Colors.white,
                  kPrimary.withValues(alpha: 0.8),
                  Colors.transparent,
                ]),
              )),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _Corner extends StatelessWidget {
  final bool tl, tr, bl, br;
  final double length, width;
  const _Corner({this.tl=false, this.tr=false, this.bl=false, this.br=false, required this.length, required this.width});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: length, height: length,
    child: CustomPaint(painter: _CornerPainter(tl: tl, tr: tr, bl: bl, br: br, strokeWidth: width)),
  );
}

class _CornerPainter extends CustomPainter {
  final bool tl, tr, bl, br;
  final double strokeWidth;
  const _CornerPainter({this.tl=false, this.tr=false, this.bl=false, this.br=false, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white..strokeWidth = strokeWidth..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    if (tl) { canvas.drawLine(Offset(0, size.height), Offset.zero, p); canvas.drawLine(Offset.zero, Offset(size.width, 0), p); }
    if (tr) { canvas.drawLine(Offset.zero, Offset(size.width, 0), p); canvas.drawLine(Offset(size.width, 0), Offset(size.width, size.height), p); }
    if (bl) { canvas.drawLine(Offset.zero, Offset(0, size.height), p); canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), p); }
    if (br) { canvas.drawLine(Offset(size.width, 0), Offset(size.width, size.height), p); canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), p); }
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}

// ── 데모 버튼 ─────────────────────────────────────────────

class _DemoButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _DemoButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 18),
            const SizedBox(width: 8),
            Text(label, style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.9), fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
