import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart' as ms;
import 'package:share_plus/share_plus.dart' show Share, ShareParams;
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
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

  String _classifyScanType(String rawValue, String format) {
    if (['ean13', 'ean8', 'upca', 'upce'].contains(format.toLowerCase())) {
      if (rawValue.startsWith('978') || rawValue.startsWith('979')) return 'isbn';
      return 'product';
    }
    if (rawValue.startsWith('http://') || rawValue.startsWith('https://')) return 'qr_url';
    if (rawValue.startsWith('WIFI:')) return 'qr_wifi';
    if (rawValue.startsWith('BEGIN:VCARD') || rawValue.startsWith('MECARD:')) return 'qr_contact';
    if (rawValue.startsWith('mailto:')) return 'qr_email';
    if (rawValue.startsWith('tel:')) return 'qr_phone';
    return 'qr_text';
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
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '마트 안이라 인터넷이 느려요!\n조금 이동해서 다시 찍어볼까요?';
        });
        await _cameraController?.start();
      }
    }
  }

  void _onNonProductScanned(String rawValue, String scanType) async {
    final sound = ref.read(scanSoundProvider);
    final vibration = ref.read(scanVibrationProvider);
    ScanFeedback.trigger(sound: sound, vibration: vibration);
    await _cameraController?.stop();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NonProductBottomSheet(rawValue: rawValue, scanType: scanType),
    ).then((_) => _cameraController?.start());
  }

  void _simulateScan(String value, String format) {
    final scanType = _classifyScanType(value, format);
    if (scanType == 'product' || scanType == 'isbn') {
      _onProductScanned(value);
    } else {
      _onNonProductScanned(value, scanType);
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
              colors: [Color(0x99000000), Colors.transparent],
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
          IconButton(icon: const Icon(Icons.help_outline, color: Colors.white), onPressed: () {}),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 카메라: 모바일은 실제 카메라, Windows는 배경 플레이스홀더
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
                // Windows 데모 전용 버튼들
                if (!_useRealCamera) ...[
                  _DemoButton(
                    icon: Icons.inventory_2_outlined,
                    label: '상품 바코드 스캔 (데모)',
                    color: Colors.white.withValues(alpha: 0.12),
                    onTap: () => _simulateScan('8801234567890', 'ean13'),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _DemoButton(
                      icon: Icons.qr_code_2, label: 'QR URL',
                      color: Colors.blue.withValues(alpha: 0.2),
                      onTap: () => _simulateScan('https://naver.com/event', 'qrcode'),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: _DemoButton(
                      icon: Icons.wifi, label: 'QR WiFi',
                      color: Colors.green.withValues(alpha: 0.2),
                      onTap: () => _simulateScan('WIFI:S:HomeNetwork;T:WPA;P:pass1234;;', 'qrcode'),
                    )),
                  ]),
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
      Positioned(top: 0, left: 0, right: 0, height: frameTop, child: const ColoredBox(color: Color(0x99000000))),
      Positioned(top: frameTop + frameSize, left: 0, right: 0, bottom: 0, child: const ColoredBox(color: Color(0x99000000))),
      Positioned(top: frameTop, left: 0, width: sideW, height: frameSize, child: const ColoredBox(color: Color(0x99000000))),
      Positioned(top: frameTop, right: 0, width: sideW, height: frameSize, child: const ColoredBox(color: Color(0x99000000))),
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

// ── QR 바텀시트 ───────────────────────────────────────────

class _NonProductBottomSheet extends StatelessWidget {
  final String rawValue;
  final String scanType;
  const _NonProductBottomSheet({required this.rawValue, required this.scanType});

  IconData get _iconData => switch (scanType) {
    'qr_url' => Icons.link,
    'qr_wifi' => Icons.wifi,
    'qr_contact' => Icons.person_outline,
    'qr_email' => Icons.email_outlined,
    'qr_phone' => Icons.phone_outlined,
    _ => Icons.text_snippet_outlined,
  };

  String get _title => switch (scanType) {
    'qr_url' => '웹사이트 주소가 감지되었습니다',
    'qr_wifi' => 'WiFi 정보가 감지되었습니다',
    'qr_contact' => '연락처가 감지되었습니다',
    'qr_email' => '이메일 주소가 감지되었습니다',
    'qr_phone' => '전화번호가 감지되었습니다',
    _ => '텍스트가 감지되었습니다',
  };

  String get _actionLabel => switch (scanType) {
    'qr_url' => '웹사이트 방문',
    'qr_wifi' => 'WiFi 정보 복사',
    'qr_contact' => '내용 복사',
    'qr_email' => '이메일 열기',
    'qr_phone' => '전화 걸기',
    _ => '텍스트 복사',
  };

  Map<String, String> _parseWifi(String raw) {
    final result = <String, String>{};
    final segments = raw.replaceAll('WIFI:', '').split(';');
    for (final seg in segments) {
      if (seg.startsWith('S:')) result['ssid'] = seg.substring(2);
      if (seg.startsWith('P:')) result['password'] = seg.substring(2);
      if (seg.startsWith('T:')) result['type'] = seg.substring(2);
    }
    return result;
  }

  Future<void> _onAction(BuildContext context) async {
    switch (scanType) {
      case 'qr_url':
        final uri = Uri.tryParse(rawValue);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          await Clipboard.setData(ClipboardData(text: rawValue));
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL이 복사되었습니다')));
        }
      case 'qr_wifi':
        final info = _parseWifi(rawValue);
        final text = 'SSID: ${info['ssid'] ?? ''}\n비밀번호: ${info['password'] ?? ''}';
        await Clipboard.setData(ClipboardData(text: text));
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WiFi 정보가 복사되었습니다')));
      case 'qr_email':
        final uri = Uri.tryParse(rawValue);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      case 'qr_phone':
        final uri = Uri.tryParse(rawValue);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      default:
        await Clipboard.setData(ClipboardData(text: rawValue));
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('복사되었습니다')));
    }
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final wifiInfo = scanType == 'qr_wifi' ? _parseWifi(rawValue) : null;

    return Container(
      decoration: const BoxDecoration(color: kSurface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 48, height: 4,
              decoration: BoxDecoration(color: kOutlineVariant, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: kPrimary.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(_iconData, color: kPrimary, size: 26),
            ),
            const SizedBox(height: 16),
            Text(_title, style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: kOnSurface), textAlign: TextAlign.center),
            const SizedBox(height: 16),

            if (wifiInfo != null)
              _WifiInfoCard(ssid: wifiInfo['ssid'], password: wifiInfo['password'])
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kSurfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kOutlineVariant.withValues(alpha: 0.4)),
                ),
                child: Text(
                  rawValue.length > 80 ? '${rawValue.substring(0, 80)}...' : rawValue,
                  style: GoogleFonts.inter(fontSize: 14, color: kPrimary, fontWeight: FontWeight.w500),
                ),
              ),
            const SizedBox(height: 20),

            Row(children: [
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(_actionLabel),
                    onPressed: () => _onAction(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _IconActionButton(
                icon: Icons.content_copy,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: rawValue));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('클립보드에 복사되었습니다')));
                    Navigator.pop(context);
                  }
                },
              ),
              const SizedBox(width: 8),
              _IconActionButton(
                icon: Icons.share,
                onTap: () async {
                  await Share.share(rawValue);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ]),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('닫기', style: GoogleFonts.inter(color: kOnSurfaceVariant, fontSize: 14)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// WiFi 정보 카드
class _WifiInfoCard extends StatelessWidget {
  final String? ssid;
  final String? password;
  const _WifiInfoCard({this.ssid, this.password});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kOutlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _WifiRow(label: '네트워크 이름', value: ssid ?? '-'),
        const SizedBox(height: 10),
        _WifiRow(label: '비밀번호', value: password ?? '-', obscure: true),
      ]),
    );
  }
}

class _WifiRow extends StatefulWidget {
  final String label;
  final String value;
  final bool obscure;
  const _WifiRow({required this.label, required this.value, this.obscure = false});

  @override
  State<_WifiRow> createState() => _WifiRowState();
}

class _WifiRowState extends State<_WifiRow> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.label, style: GoogleFonts.inter(fontSize: 11, color: kOnSurfaceVariant)),
          const SizedBox(height: 2),
          Text(
            widget.obscure && !_show ? '••••••••' : widget.value,
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: kOnSurface),
          ),
        ]),
      ),
      if (widget.obscure)
        IconButton(
          icon: Icon(_show ? Icons.visibility_off : Icons.visibility, size: 18, color: kOnSurfaceVariant),
          onPressed: () => setState(() => _show = !_show),
        )
      else
        IconButton(
          icon: const Icon(Icons.copy, size: 18, color: kOnSurfaceVariant),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: widget.value));
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('복사되었습니다')));
          },
        ),
    ]);
  }
}

class _IconActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconActionButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52, height: 52,
        decoration: BoxDecoration(color: kSurfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: kPrimary, size: 20),
      ),
    );
  }
}
