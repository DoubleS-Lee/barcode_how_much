import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';

class AppBottomNav extends StatelessWidget {
  /// 0=스캔, 1=기록, 2=공유 게시판, 3=설정
  final int currentIndex;
  const AppBottomNav({super.key, required this.currentIndex});

  static const _items = [
    (icon: Icons.center_focus_strong, label: '스캔', route: '/scanner'),
    (icon: Icons.receipt_long, label: '상품 기록', route: '/history'),
    (icon: Icons.campaign_outlined, label: '공유 게시판', route: '/community'),
    (icon: Icons.settings, label: '설정', route: '/settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: Colors.grey.shade100, width: 1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A003280),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final isActive = i == currentIndex;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (isActive) return;
                  if (item.route != null) {
                    context.go(item.route!);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('준비 중입니다'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                  decoration: BoxDecoration(
                    color: isActive ? kPrimary : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        color: isActive ? Colors.white : Colors.grey.shade500,
                        size: 22,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isActive ? Colors.white : Colors.grey.shade500,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
