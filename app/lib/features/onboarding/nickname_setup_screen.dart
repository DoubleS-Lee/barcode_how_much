import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../shared/api/api_client.dart' as client;
import '../../shared/providers/device_provider.dart';

class NicknameSetupScreen extends ConsumerStatefulWidget {
  const NicknameSetupScreen({super.key});

  @override
  ConsumerState<NicknameSetupScreen> createState() => _NicknameSetupScreenState();
}

class _NicknameSetupScreenState extends ConsumerState<NicknameSetupScreen> {
  final _ctrl = TextEditingController();
  String? _error;
  bool? _available; // null=미확인, true=사용가능, false=사용불가
  bool _loading = false;
  Timer? _debounce;

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() {
      _available = null;
      _error = null;
    });
    if (value.trim().length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 500), () => _checkAvailability(value.trim()));
  }

  Future<void> _checkAvailability(String nickname) async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final res = await client.dio.get('/api/v1/devices/nickname/check',
          queryParameters: {'nickname': nickname});
      if (!mounted) return;
      setState(() {
        _available = res.data['available'] as bool;
        _error = _available == false ? '이미 사용 중인 닉네임입니다' : null;
      });
    } catch (_) {
      if (mounted) setState(() => _available = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final nickname = _ctrl.text.trim();
    if (nickname.isEmpty) return;

    // 글자 수 검증
    if (nickname.length < 2 || nickname.length > 15) {
      setState(() => _error = '2~15자 사이로 입력해주세요');
      return;
    }
    final regex = RegExp(r'^[가-힣a-zA-Z0-9_]+$');
    if (!regex.hasMatch(nickname)) {
      setState(() => _error = '한글, 영문, 숫자, _ 만 사용 가능합니다');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      final uuid = await ref.read(deviceUuidProvider.future);
      await client.dio.post('/api/v1/devices/nickname', data: {
        'device_uuid': uuid,
        'nickname': nickname,
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('nickname_done', true);
      await prefs.setString('device_nickname', nickname);
      if (mounted) context.go('/scanner');
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('NICKNAME_TAKEN')
          ? '이미 사용 중인 닉네임입니다'
          : '오류가 발생했습니다. 다시 시도해주세요';
      setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _canSubmit =>
      _ctrl.text.trim().length >= 2 && _available != false && !_loading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(children: [
          const Icon(Icons.barcode_reader, color: kPrimary, size: 22),
          const SizedBox(width: 6),
          Text('얼마였지?',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 20, fontWeight: FontWeight.w800, color: kPrimary)),
        ]),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('닉네임을 설정해주세요',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 28, fontWeight: FontWeight.w800,
                      color: kOnSurface, height: 1.2)),
              const SizedBox(height: 10),
              Text('커뮤니티에서 사용할 이름이에요.\n나중에 설정에서 변경할 수 있어요.',
                  style: GoogleFonts.inter(
                      fontSize: 15, color: kOnSurfaceVariant, height: 1.6)),
              const SizedBox(height: 40),
              TextField(
                controller: _ctrl,
                onChanged: _onChanged,
                maxLength: 15,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '닉네임 (2~15자)',
                  hintStyle: GoogleFonts.inter(color: kOnSurfaceVariant),
                  filled: true,
                  fillColor: kBackground,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: kPrimary, width: 2)),
                  errorText: _error,
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)))
                      : _available == true
                          ? const Icon(Icons.check_circle, color: Color(0xFF16A34A))
                          : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                style: GoogleFonts.inter(fontSize: 16),
              ),
              if (_available == true) ...[
                const SizedBox(height: 6),
                Text('사용 가능한 닉네임입니다',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: const Color(0xFF16A34A))),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _canSubmit ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    disabledBackgroundColor: kOutlineVariant,
                    shape: const StadiumBorder(),
                    elevation: _canSubmit ? 4 : 0,
                  ),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('시작하기',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 17, fontWeight: FontWeight.w700,
                              color: _canSubmit ? kOnPrimary : kOnSurfaceVariant)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
