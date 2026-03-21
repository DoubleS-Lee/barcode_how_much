import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../shared/api/scan_api.dart';
import '../../shared/providers/scan_settings_provider.dart';
import '../../shared/utils/device_id.dart';
import '../../shared/widgets/app_bottom_nav.dart';

// 알림 설정 상태
final _notifyPriceDropProvider = StateProvider<bool>((ref) => true);
final _notifyWeeklyProvider = StateProvider<bool>((ref) => false);

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
            // 프리미엄 배너
            _PremiumBanner(),
            const SizedBox(height: 28),

            // 알림 설정
            _SectionTitle('알림'),
            const SizedBox(height: 10),
            _ToggleTile(
              icon: Icons.trending_down,
              iconColor: Colors.green.shade600,
              title: '가격 하락 알림',
              subtitle: '찜한 상품 가격이 내려가면 알려드려요',
              provider: _notifyPriceDropProvider,
            ),
            _ToggleTile(
              icon: Icons.calendar_today_outlined,
              iconColor: kPrimary,
              title: '주간 리포트',
              subtitle: '매주 월요일 절약 현황을 알려드려요',
              provider: _notifyWeeklyProvider,
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
              onTap: () => _showDeleteDialog(context),
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
              onTap: () => _showSnackbar(context, '개인정보처리방침 페이지 준비 중입니다'),
            ),
            _ActionTile(
              icon: Icons.description_outlined,
              iconColor: kOnSurfaceVariant,
              title: '이용약관',
              onTap: () => _showSnackbar(context, '이용약관 페이지 준비 중입니다'),
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

  void _showDeleteDialog(BuildContext context) {
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

// ── 프리미엄 배너 ──────────────────────────────────────────

class _PremiumBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0747AD), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: kPrimary.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: kAmber,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'PREMIUM',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '광고 없이, 더 스마트하게',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '광고 제거 · 가격 알림 · 무제한 기록',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('프리미엄 구독 기능 준비 중입니다')),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: kPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                '월 1,900원으로 시작하기',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
