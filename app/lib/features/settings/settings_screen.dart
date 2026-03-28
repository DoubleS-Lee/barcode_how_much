import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/api/api_client.dart' as client;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_naver_login/flutter_naver_login.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import '../../core/theme.dart';
import '../../shared/api/scan_api.dart';
import '../scan_history/scan_history_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/device_provider.dart';
import '../../shared/providers/scan_settings_provider.dart';
import '../../shared/utils/device_id.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/providers/saved_locations_provider.dart';
import '../../shared/providers/nickname_provider.dart';

const _kSupportEmail = 'lss8825@gmail.com';

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

            // 닉네임 (로그인 상태에서만 표시)
            if (ref.watch(authProvider).valueOrNull?.isLoggedIn == true) ...[
              _NicknameSection(),
              const SizedBox(height: 28),
            ],

            // 즐겨찾기 장소
            _SectionTitle('즐겨찾기 장소'),
            const SizedBox(height: 6),
            Text('자주 가는 매장을 저장해 가격 입력 시 빠르게 선택해요',
                style: GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant)),
            const SizedBox(height: 10),
            _SavedLocationsSection(),
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
              subtitle: _kSupportEmail,
              onTap: () async {
                final uri = Uri(
                  scheme: 'mailto',
                  path: _kSupportEmail,
                  query: 'subject=얼마였지? 문의',
                );
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                } else if (context.mounted) {
                  _showSnackbar(context, '이메일 앱을 열 수 없습니다');
                }
              },
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

class _SocialLoginSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SocialLoginSection> createState() => _SocialLoginSectionState();
}

class _SocialLoginSectionState extends ConsumerState<_SocialLoginSection> {
  bool _loading = false;

  static final _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  /// 소셜 로그인 연동 → 닉네임 반환 (null이면 새 닉네임 입력 필요)
  Future<String?> _socialLink(String provider, String socialId) async {
    try {
      final uuid = await DeviceId.get();
      final resp = await client.dio.post('/api/v1/devices/social-link', data: {
        'device_uuid': uuid,
        'provider': provider,
        'social_id': socialId,
      });
      final nickname = resp.data['nickname'] as String?;
      final prefs = await SharedPreferences.getInstance();
      if (nickname != null && nickname.isNotEmpty) {
        await prefs.setString('device_nickname', nickname);
        await prefs.setBool('nickname_done', true);
      } else {
        await prefs.remove('device_nickname');
        await prefs.remove('nickname_done');
      }
      ref.invalidate(nicknameProvider);
      return nickname?.isNotEmpty == true ? nickname : null;
    } catch (_) {
      return null;
    }
  }

  /// 소셜 로그인 직후 닉네임 입력 다이얼로그
  Future<void> _showNicknameInputDialog() async {
    if (!mounted) return;
    final ctrl = TextEditingController();
    String? errorText;
    bool loading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('닉네임을 설정해주세요',
              style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('게시판에서 사용할 닉네임을 입력해주세요.',
                  style: GoogleFonts.inter(fontSize: 13, color: kOnSurfaceVariant, height: 1.5)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLength: 15,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '2~15자 (한글, 영문, 숫자, _)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  errorText: errorText,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: GoogleFonts.inter(fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                '설정한 닉네임은 바꿀 수 없습니다',
                style: GoogleFonts.inter(fontSize: 12, color: kError.withValues(alpha: 0.8), height: 1.4),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () async {
                final nickname = ctrl.text.trim();
                if (nickname.length < 2) {
                  setS(() => errorText = '2자 이상 입력해주세요');
                  return;
                }
                final regex = RegExp(r'^[가-힣a-zA-Z0-9_]+$');
                if (!regex.hasMatch(nickname)) {
                  setS(() => errorText = '한글, 영문, 숫자, _ 만 사용 가능합니다');
                  return;
                }
                setS(() { loading = true; errorText = null; });
                try {
                  final uuid = await DeviceId.get();
                  await client.dio.post('/api/v1/devices/nickname',
                      data: {'device_uuid': uuid, 'nickname': nickname});
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('device_nickname', nickname);
                  await prefs.setBool('nickname_done', true);
                  ref.invalidate(nicknameProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  String msg = '오류가 발생했습니다';
                  if (e is DioException) {
                    final data = e.response?.data;
                    if (data is Map && data['error'] == 'NICKNAME_TAKEN') {
                      msg = '이미 사용 중인 닉네임입니다';
                    }
                  }
                  setS(() { loading = false; errorText = msg; });
                }
              },
              child: Text('확인', style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700, color: kPrimary)),
            ),
          ],
        ),
      ),
    );
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
        await ref.read(authProvider.notifier).setLogin(
          'google', account.displayName ?? account.email, account.email);
        final nickname = await _socialLink('google', account.id);
        if (mounted && nickname == null) await _showNicknameInputDialog();
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
      if (mounted) {
        await ref.read(authProvider.notifier).setLogin('kakao', name, email);
        final nickname = await _socialLink('kakao', user.id.toString());
        if (mounted && nickname == null) await _showNicknameInputDialog();
      }
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
        await ref.read(authProvider.notifier).setLogin(
          'naver', account.name ?? '네이버 사용자', account.email ?? '');
        final socialId = account.id?.isNotEmpty == true
            ? account.id!
            : (account.email ?? '');
        final nickname = await _socialLink('naver', socialId);
        if (mounted && nickname == null) await _showNicknameInputDialog();
      }
    } catch (e) {
      if (mounted) _showSnack('네이버 로그인 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    final loginType = ref.read(authProvider).valueOrNull?.loginType;
    setState(() => _loading = true);
    try {
      if (loginType == 'google') await _googleSignIn.signOut();
      if (loginType == 'kakao') await kakao.UserApi.instance.logout();
      if (loginType == 'naver') await FlutterNaverLogin.logOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('device_nickname');
      await prefs.remove('nickname_done');
      ref.invalidate(nicknameProvider);
      if (mounted) await ref.read(authProvider.notifier).logout();
    } catch (_) {
      if (mounted) await ref.read(authProvider.notifier).logout();
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
    final auth = ref.watch(authProvider).valueOrNull;
    if (auth?.isLoggedIn == true) {
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
            _LoginIcon(auth!.loginType!),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(auth.loginName ?? '사용자',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15, fontWeight: FontWeight.w700, color: kOnSurface)),
              if (auth.loginEmail?.isNotEmpty == true) ...[
                const SizedBox(height: 2),
                Text(auth.loginEmail!,
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
    final uuidAsync = ref.watch(deviceUuidProvider);
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

// ── 닉네임 섹션 ─────────────────────────────────────────

class _NicknameSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nickname = ref.watch(nicknameProvider).valueOrNull;
    return _TileShell(
      icon: Icons.badge_outlined,
      iconColor: kPrimary,
      title: '닉네임',
      subtitle: nickname ?? '미설정',
      trailing: const SizedBox.shrink(),
    );
  }
}

// ── 즐겨찾기 장소 섹션 ────────────────────────────────────

class _SavedLocationsSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SavedLocationsSection> createState() =>
      _SavedLocationsSectionState();
}

class _SavedLocationsSectionState extends ConsumerState<_SavedLocationsSection> {
  Future<void> _showAddDialog() async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('장소 추가',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 50,
          decoration: InputDecoration(
            hintText: '이마트 왕십리점',
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
            child: Text('추가', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final loc = ctrl.text.trim();
    if (loc.isNotEmpty) {
      await ref.read(savedLocationsProvider.notifier).add(loc);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locations = ref.watch(savedLocationsProvider);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (locations.isEmpty)
            Text('저장된 장소가 없어요',
                style: GoogleFonts.inter(fontSize: 13, color: kOnSurfaceVariant))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: locations
                  .map((loc) => Chip(
                        label: Text(loc,
                            style: GoogleFonts.inter(
                                fontSize: 12, color: kOnSurface)),
                        backgroundColor: kPrimary.withValues(alpha: 0.06),
                        side: BorderSide(color: kPrimary.withValues(alpha: 0.2)),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        deleteIcon: Icon(Icons.close,
                            size: 14,
                            color: kOnSurfaceVariant.withValues(alpha: 0.7)),
                        onDeleted: () =>
                            ref.read(savedLocationsProvider.notifier).remove(loc),
                      ))
                  .toList(),
            ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _showAddDialog,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add_circle_outline, size: 16, color: kPrimary),
              const SizedBox(width: 4),
              Text('장소 추가',
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600, color: kPrimary)),
            ]),
          ),
        ],
      ),
    );
  }
}
