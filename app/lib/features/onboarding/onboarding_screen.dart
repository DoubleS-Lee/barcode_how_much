import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _termsAccepted = false;
  bool _privacyAccepted = false;
  bool _marketingAccepted = false;
  bool _allAccepted = false;

  void _toggleAll(bool? value) {
    final v = value ?? false;
    setState(() {
      _allAccepted = v;
      _termsAccepted = v;
      _privacyAccepted = v;
      _marketingAccepted = v;
    });
  }

  void _updateAll() {
    setState(() {
      _allAccepted = _termsAccepted && _privacyAccepted && _marketingAccepted;
    });
  }

  bool get _canProceed => _termsAccepted && _privacyAccepted;

  Future<void> _onStart() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (mounted) context.go('/scanner');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const Icon(Icons.barcode_reader, color: kPrimary, size: 22),
            const SizedBox(width: 6),
            Text(
              '얼마였지?',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: kPrimary,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hero headline
                    Text(
                      '더 똑똑한 소비,\n함께 시작해요',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: kOnSurface,
                        height: 1.2,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '원활한 서비스 이용을 위해\n약관 동의를 부탁드려요.',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: kOnSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // All agree
                    GestureDetector(
                      onTap: () => _toggleAll(!_allAccepted),
                      child: Row(
                        children: [
                          _StyledCheckbox(
                            value: _allAccepted,
                            onChanged: _toggleAll,
                          ),
                          const SizedBox(width: 14),
                          Text(
                            '모두 동의합니다',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: kOnSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Divider(color: Colors.grey.shade200, thickness: 1),
                    const SizedBox(height: 20),

                    // Individual terms
                    _TermsRow(
                      label: '서비스 이용약관',
                      badge: '필수',
                      isRequired: true,
                      value: _termsAccepted,
                      onChanged: (v) {
                        setState(() => _termsAccepted = v ?? false);
                        _updateAll();
                      },
                    ),
                    const SizedBox(height: 20),
                    _TermsRow(
                      label: '개인정보 처리방침',
                      badge: '필수',
                      isRequired: true,
                      value: _privacyAccepted,
                      onChanged: (v) {
                        setState(() => _privacyAccepted = v ?? false);
                        _updateAll();
                      },
                    ),
                    const SizedBox(height: 20),
                    _TermsRow(
                      label: '마케팅 정보 수신',
                      badge: '선택',
                      isRequired: false,
                      value: _marketingAccepted,
                      onChanged: (v) {
                        setState(() => _marketingAccepted = v ?? false);
                        _updateAll();
                      },
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      // Fixed bottom CTA
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _canProceed ? _onStart : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    disabledBackgroundColor: kOutlineVariant,
                    shape: const StadiumBorder(),
                    elevation: _canProceed ? 4 : 0,
                    shadowColor: kPrimary.withValues(alpha: 0.3),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '동의하고 시작하기',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _canProceed ? kOnPrimary : kOnSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.arrow_forward,
                        size: 18,
                        color: _canProceed ? kOnPrimary : kOnSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '본 서비스는 만 14세 이상부터 이용 가능합니다.',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: kOnSurfaceVariant.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StyledCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  const _StyledCheckbox({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: value ? kPrimary : Colors.transparent,
          border: Border.all(
            color: value ? kPrimary : kOutline,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: value
            ? const Icon(Icons.check, color: Colors.white, size: 16)
            : null,
      ),
    );
  }
}

class _TermsRow extends StatelessWidget {
  final String label;
  final String badge;
  final bool isRequired;
  final bool value;
  final ValueChanged<bool?> onChanged;

  const _TermsRow({
    required this.label,
    required this.badge,
    required this.isRequired,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          _StyledCheckbox(value: value, onChanged: onChanged),
          const SizedBox(width: 14),
          Expanded(
            child: Row(
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: kOnSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isRequired
                        ? kPrimary.withValues(alpha: 0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isRequired ? kPrimary : kOnSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: Colors.grey.shade300, size: 20),
        ],
      ),
    );
  }
}
