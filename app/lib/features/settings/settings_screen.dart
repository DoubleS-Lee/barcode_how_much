import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_naver_login/flutter_naver_login.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../shared/api/scan_api.dart';
import '../scan_history/scan_history_provider.dart';
import '../../shared/providers/scan_settings_provider.dart';
import '../../shared/utils/device_id.dart';
import '../../shared/widgets/app_bottom_nav.dart';

// 알림 설정 상태
final _notifyPriceDropProvider = StateProvider<bool>((ref) => true);

// 디바이스 UUID
final _deviceUuidProvider = FutureProvider<String>((ref) => DeviceId.get());

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '설정',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: kPrimaryDark,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 소셜 로그인
            _SocialLoginSection(),
            const SizedBox(height: 28),

            // 알림 설정
            _SectionTitle('알림'),
            const SizedBox(height: 10),
            _ToggleTile(
              icon: Icons.trending_down,
              iconColor: Colors.green.shade600,
              title: '가격 하락 알림',
              subtitle: '★ 찜한 상품 가격이 내려가면 알려드려요',
              provider: _notifyPriceDropProvider,
            ),
            const SizedBox(height: 28),

            // 스캔 피드백
            _SectionTitle('스캔 피드백'),
            const SizedBox(height: 10),
            _NotifierToggleTile(
              icon: Icons.volume_up_outlined,
              iconColor: Colors.blue.shade600,
              title: '스캔 소리',
              subtitle: '바코드 인식 시 삑 소리가 납니다',
              provider: scanSoundProvider,
            ),
            _NotifierToggleTile(
              icon: Icons.vibration,
              iconColor: Colors.purple.shade600,
              title: '진동',
              subtitle: '바코드 인식 시 진동이 울립니다',
              provider: scanVibrationProvider,
            ),
            const SizedBox(height: 28),

            // 데이터 관리
            _SectionTitle('데이터'),
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.delete_outline,
              iconColor: kError,
              title: '스캔 기록 전체 삭제',
              subtitle: '삭제한 기록은 복구할 수 없어요',
              onTap: () => _showDeleteDialog(context, ref),
            ),
            const SizedBox(height: 28),

            // 앱 정보
            _SectionTitle('앱 정보'),
            const SizedBox(height: 10),
            _InfoTile(
              icon: Icons.info_outline,
              title: '버전',
              trailing: '1.0.0',
            ),
            _DeviceUuidTile(),
            const SizedBox(height: 4),
            _ActionTile(
              icon: Icons.privacy_tip_outlined,
              iconColor: kOnSurfaceVariant,
              title: '개인정보처리방침',
              onTap: () => context.push('/privacy'),
            ),
            _ActionTile(
              icon: Icons.description_outlined,
              iconColor: kOnSurfaceVariant,
              title: '이용약관',
              onTap: () => context.push('/terms'),
            ),
            _ActionTile(
              icon: Icons.mail_outline,
              iconColor: kOnSurfaceVariant,
              title: '문의하기',
              subtitle: 'eolmaeossjeo@gmail.com',
              onTap: () => _showSnackbar(context, '이메일 앱으로 이동합니다'),
            ),
            _ActionTile(
              icon: Icons.star_outline,
              iconColor: kAmber,
              title: '앱 평가하기',
              onTap: () => _showSnackbar(context, '스토어로 이동합니다'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('스캔 기록 삭제',
            style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700)),
        content: Text('모든 스캔 기록이 삭제됩니다.\n삭제한 데이터는 복구할 수 없어요.',
            style: GoogleFonts.inter(fontSize: 14, height: 1.6)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소', style: GoogleFonts.inter(color: kOnSurfaceVariant)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final uuid = await DeviceId.get();
                final deleted = await ScanApi.deleteHistory(uuid);
                ref.invalidate(scanHistoryProvider);
                if (context.mounted) {
                  _showSnackbar(context, '스캔 기록 $deleted건이 삭제되었습니다');
                }
              } catch (e) {
                if (context.mounted) {
                  _showSnackbar(context, '삭제 실패: $e');
                }
              }
            },
            child: Text('삭제', style: GoogleFonts.inter(color: kError, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showSnackbar(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

// ── 소셜 로그인 섹션 ──────────────────────────────────────

class _SocialLoginSection extends StatefulWidget {
  @override
  State<_SocialLoginSection> createState() => _SocialLoginSectionState();
}

class _SocialLoginSectionState extends State<_SocialLoginSection> {
  String? _loginType;   // google / kakao / naver
  String? _loginName;
  String? _loginEmail;
  bool _loading = false;

  final _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _loginType = prefs.getString('social_login_type');
      _loginName = prefs.getString('social_login_name');
      _loginEmail = prefs.getString('social_login_email');
    });
  }

  Future<void> _saveLogin(String type, String name, String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('social_login_type', type);
    await prefs.setString('social_login_name', name);
    await prefs.setString('social_login_email', email);
    setState(() { _loginType = type; _loginName = name; _loginEmail = email; });
  }

  Future<void> _clearLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('social_login_type');
    await prefs.remove('social_login_name');
    await prefs.remove('social_login_email');
    setState(() { _loginType = null; _loginName = null; _loginEmail = null; });
  }

  Future<void> _loginGoogle() async {
    if (kIsWeb || (!defaultTargetPlatform.isMobileOrMac)) {
      _showNotSupported();
      return;
    }
    setState(() => _loading = true);
    try {
      final account = await _googleSignIn.signIn();
      if (account != null && mounted) {
        await _saveLogin('google', account.displayName ?? account.email, account.email);
      }
    } catch (e) {
      if (mounted) _showSnack('구글 로그인 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginKakao() async {
    if (kIsWeb || (!defaultTargetPlatform.isMobileOrMac)) {
      _showNotSupported();
      return;
    }
    setState(() => _loading = true);
    try {
      if (await kakao.isKakaoTalkInstalled()) {
        await kakao.UserApi.instance.loginWithKakaoTalk();
      } else {
        await kakao.UserApi.instance.loginWithKakaoAccount();
      }
      final user = await kakao.UserApi.instance.me();
      final name = user.kakaoAccount?.profile?.nickname ?? '카카오 사용자';
      final email = user.kakaoAccount?.email ?? '';
      if (mounted) await _saveLogin('kakao', name, email);
    } catch (e) {
      if (mounted) _showSnack('카카오 로그인 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginNaver() async {
    if (kIsWeb || (!defaultTargetPlatform.isMobileOrMac)) {
      _showNotSupported();
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await FlutterNaverLogin.logIn();
      final account = result.account;
      if (account != null && mounted) {
        await _saveLogin('naver', account.name ?? '네이버 사용자', account.email ?? '');
      }
    } catch (e) {
      if (mounted) _showSnack('네이버 로그인 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    setState(() => _loading = true);
    try {
      if (_loginType == 'google') await _googleSignIn.signOut();
      if (_loginType == 'kakao') await kakao.UserApi.instance.logout();
      if (_loginType == 'naver') await FlutterNaverLogin.logOut();
      if (mounted) await _clearLogin();
    } catch (_) {
      if (mounted) await _clearLogin();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showNotSupported() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('소셜 로그인은 모바일 앱에서만 사용 가능합니다')),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loginType != null) {
      // 로그인된 상태
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _LoginIcon(_loginType!),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_loginName ?? '사용자',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15, fontWeight: FontWeight.w700, color: kOnSurface)),
              if (_loginEmail?.isNotEmpty == true) ...[
                const SizedBox(height: 2),
                Text(_loginEmail!,
                    style: GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant)),
              ],
            ])),
            _loading
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(
                    onPressed: _logout,
                    child: Text('로그아웃',
                        style: GoogleFonts.inter(fontSize: 13, color: kError,
                            fontWeight: FontWeight.w600)),
                  ),
          ]),
        ]),
      );
    }

    // 비로그인 상태
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('계정 연결',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15, fontWeight: FontWeight.w700, color: kOnSurface)),
        const SizedBox(height: 4),
        Text('소셜 계정으로 로그인하면 기기 교체 시 데이터를 유지할 수 있어요',
            style: GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant, height: 1.5)),
        const SizedBox(height: 16),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else ...[
          _SocialButton(
            label: '구글로 로그인',
            color: Colors.white,
            borderColor: Colors.grey.shade300,
            textColor: kOnSurface,
            icon: _GoogleIcon(),
            onTap: _loginGoogle,
          ),
          const SizedBox(height: 10),
          _SocialButton(
            label: '카카오톡으로 로그인',
            color: const Color(0xFFFEE500),
            borderColor: const Color(0xFFFEE500),
            textColor: const Color(0xFF3A1D1D),
            icon: Text('K', style: GoogleFonts.plusJakartaSans(
                fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFF3A1D1D))),
            onTap: _loginKakao,
          ),
          const SizedBox(height: 10),
          _SocialButton(
            label: '네이버로 로그인',
            color: const Color(0xFF03C75A),
            borderColor: const Color(0xFF03C75A),
            textColor: Colors.white,
            icon: Text('N', style: GoogleFonts.plusJakartaSans(
                fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
            onTap: _loginNaver,
          ),
        ],
      ]),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color borderColor;
  final Color textColor;
  final Widget icon;
  final VoidCallback onTap;

  const _SocialButton({
    required this.label,
    required this.color,
    required this.borderColor,
    required this.textColor,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 24, height: 24, child: Center(child: icon)),
          const SizedBox(width: 10),
          Text(label, style: GoogleFonts.inter(
              fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
        ]),
      ),
    );
  }
}

class _LoginIcon extends StatelessWidget {
  final String type;
  const _LoginIcon(this.type);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42, height: 42,
      decoration: BoxDecoration(
        color: switch (type) {
          'kakao' => const Color(0xFFFEE500),
          'naver' => const Color(0xFF03C75A),
          _ => Colors.white,
        },
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(child: switch (type) {
        'kakao' => Text('K', style: GoogleFonts.plusJakartaSans(
            fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFF3A1D1D))),
        'naver' => Text('N', style: GoogleFonts.plusJakartaSans(
            fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
        _ => _GoogleIcon(),
      }),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Text('G', style: TextStyle(
      fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF4285F4)));
  }
}

extension on TargetPlatform {
  bool get isMobileOrMac =>
      this == TargetPlatform.android ||
      this == TargetPlatform.iOS ||
      this == TargetPlatform.macOS;
}


// ── 공통 위젯 ─────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: kOnSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _ToggleTile extends ConsumerWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final StateProvider<bool> provider;

  const _ToggleTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.provider,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(provider);
    return _TileShell(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      trailing: Switch(
        value: value,
        onChanged: (v) => ref.read(provider.notifier).state = v,
        activeColor: kPrimary,
      ),
    );
  }
}

class _NotifierToggleTile extends ConsumerWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final StateNotifierProvider<ScanSettingNotifier, bool> provider;

  const _NotifierToggleTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.provider,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(provider);
    return _TileShell(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      trailing: Switch(
        value: value,
        onChanged: (_) => ref.read(provider.notifier).toggle(),
        activeColor: kPrimary,
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _TileShell(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      trailing: Icon(Icons.chevron_right, color: Colors.grey.shade300),
      onTap: onTap,
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String trailing;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return _TileShell(
      icon: icon,
      iconColor: kOnSurfaceVariant,
      title: title,
      trailing: Text(
        trailing,
        style: GoogleFonts.inter(fontSize: 13, color: kOnSurfaceVariant),
      ),
    );
  }
}

// Device UUID 타일 (시드 스크립트 실행 시 필요)
class _DeviceUuidTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uuidAsync = ref.watch(_deviceUuidProvider);
    final uuid = uuidAsync.valueOrNull ?? '로딩 중...';
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: uuid));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('디바이스 ID가 복사되었습니다')),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kOnSurfaceVariant.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.fingerprint, color: kOnSurfaceVariant, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '디바이스 ID',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: kOnSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    uuid,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: kOnSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.copy, color: kOnSurfaceVariant, size: 16),
          ],
        ),
      ),
    );
  }
}

class _TileShell extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  const _TileShell({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: kOnSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: kOnSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
