import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../shared/api/scan_api.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import 'scan_history_provider.dart';
import 'price_graph_widget.dart';

class ScanHistoryScreen extends ConsumerStatefulWidget {
  const ScanHistoryScreen({super.key});

  @override
  ConsumerState<ScanHistoryScreen> createState() => _ScanHistoryScreenState();
}

class _ScanHistoryScreenState extends ConsumerState<ScanHistoryScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(scanHistoryProvider);

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('스캔 기록',
              style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w800, color: kOnSurface)),
            Text('최근 스캔 내역입니다.',
              style: GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant)),
          ],
        ),
        toolbarHeight: 64,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: kPrimary),
            onPressed: () => ref.invalidate(scanHistoryProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 검색바 ──
          Container(
            color: kSurface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
              decoration: InputDecoration(
                hintText: '상품명으로 검색',
                hintStyle: GoogleFonts.inter(fontSize: 13, color: kOnSurfaceVariant),
                prefixIcon: const Icon(Icons.search, color: kOnSurfaceVariant, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: kOnSurfaceVariant),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: kBackground,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              style: GoogleFonts.inter(fontSize: 13),
            ),
          ),
          // ── 히스토리 바디 ──
          Expanded(
            child: historyAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 56, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text('이력을 불러오지 못했어요',
                      style: GoogleFonts.inter(fontSize: 15, color: kOnSurfaceVariant)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(scanHistoryProvider),
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              ),
              data: (history) => _HistoryBody(history: history, searchQuery: _searchQuery),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }
}

// ── 바코드별 그룹 데이터 구조 ─────────────────────────────

class _ProductGroup {
  final String barcode;
  final String name;
  final String? imageUrl;
  final List<Map<String, dynamic>> scans; // newest first

  _ProductGroup({
    required this.barcode,
    required this.name,
    this.imageUrl,
    required this.scans,
  });

  int? get latestOnlinePrice => scans.first['lowest_online_price'] as int?;
  DateTime get latestScannedAt => DateTime.parse(scans.first['scanned_at'] as String);

  int? get allTimeLowestPrice {
    final prices = scans
        .map((s) => s['lowest_online_price'] as int?)
        .whereType<int>()
        .toList();
    if (prices.isEmpty) return null;
    return prices.reduce((a, b) => a < b ? a : b);
  }
}

// ── 바디 ─────────────────────────────────────────────────

class _HistoryBody extends ConsumerWidget {
  final List<Map<String, dynamic>> history;
  final String searchQuery;
  const _HistoryBody({required this.history, this.searchQuery = ''});

  bool _isProduct(String scanType) => scanType == 'product' || scanType == 'isbn';

  IconData _iconFor(String scanType) => switch (scanType) {
    'qr_url' => Icons.qr_code_2,
    'qr_wifi' => Icons.wifi,
    'qr_contact' => Icons.person_outline,
    'qr_email' => Icons.email_outlined,
    'qr_phone' => Icons.phone_outlined,
    _ => Icons.text_snippet_outlined,
  };

  /// 상품 스캔을 바코드별로 묶어서 반환 (최근 스캔 순 정렬)
  List<_ProductGroup> _groupProducts(List<Map<String, dynamic>> items) {
    final map = <String, _ProductGroup>{};
    for (final item in items) {
      if (!_isProduct(item['scan_type'] as String)) continue;
      final product = item['product'] as Map?;
      final barcode = (product?['barcode'] as String?) ?? 'unknown';
      final name = (product?['name'] as String?) ?? barcode;
      final imageUrl = product?['image_url'] as String?;

      if (map.containsKey(barcode)) {
        map[barcode]!.scans.add(item);
      } else {
        map[barcode] = _ProductGroup(
          barcode: barcode,
          name: name,
          imageUrl: imageUrl,
          scans: [item],
        );
      }
    }
    // 최근 스캔 순으로 정렬
    final groups = map.values.toList()
      ..sort((a, b) => b.latestScannedAt.compareTo(a.latestScannedAt));
    return groups;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nf = NumberFormat('#,###');
    final allProductGroups = _groupProducts(history);
    // 검색 필터 적용 (상품명 대소문자 무시)
    final productGroups = searchQuery.isEmpty
        ? allProductGroups
        : allProductGroups
            .where((g) =>
                g.name.toLowerCase().contains(searchQuery.toLowerCase()))
            .toList();
    final nonProductItems = searchQuery.isNotEmpty
        ? <Map<String, dynamic>>[]
        : history.where((i) => !_isProduct(i['scan_type'] as String)).toList();

    final totalItems = productGroups.length + nonProductItems.length;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: totalItems == 0
              ? SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(
                        children: [
                          Icon(
                            searchQuery.isNotEmpty ? Icons.search_off : Icons.history,
                            size: 64,
                            color: Colors.grey.shade200,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            searchQuery.isNotEmpty ? '검색 결과가 없어요' : '아직 스캔 이력이 없어요',
                            style: GoogleFonts.inter(fontSize: 15, color: kOnSurfaceVariant),
                          ),
                          if (searchQuery.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              '다른 상품명으로 검색해보세요',
                              style: GoogleFonts.inter(fontSize: 13, color: kOnSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      // 상품 그룹 먼저, 이후 비상품
                      if (i < productGroups.length) {
                        final group = productGroups[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _GroupedProductCard(group: group, nf: nf, ref: ref),
                        );
                      } else {
                        final item = nonProductItems[i - productGroups.length];
                        final scanType = item['scan_type'] as String;
                        final scannedAt = DateTime.parse(item['scanned_at'] as String);
                        final dateLabel = DateFormat('MM.dd HH:mm').format(scannedAt.toLocal());
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _NonProductHistoryCard(
                            item: item,
                            iconData: _iconFor(scanType),
                            dateLabel: dateLabel,
                          ),
                        );
                      }
                    },
                    childCount: totalItems,
                  ),
                ),
        ),

        // 절약 통계
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('절약 현황',
                  style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: kOnSurface)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _SavingsCard(
                      icon: Icons.savings_outlined,
                      iconColor: kAmber,
                      backgroundColor: kPrimary,
                      title: '이번 달 절약 가능 금액',
                      value: '12,800원',
                      valueColor: Colors.white,
                      titleColor: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SavingsCard(
                      icon: Icons.trending_down,
                      iconColor: kPrimary,
                      backgroundColor: kSurface,
                      title: '스캔 상품 종류',
                      value: '${productGroups.length}종',
                      valueColor: kPrimary,
                      titleColor: kOnSurface,
                      bordered: true,
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── 상품명 편집 다이얼로그 ────────────────────────────────

Future<void> _showEditNameDialog(
  BuildContext context,
  WidgetRef ref,
  String barcode,
  String currentName,
) async {
  final controller = TextEditingController(text: currentName);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        '상품명 편집',
        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 200,
        decoration: InputDecoration(
          hintText: '상품명 입력',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        style: GoogleFonts.plusJakartaSans(fontSize: 15),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('취소', style: GoogleFonts.inter(color: kOnSurfaceVariant)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('저장', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );

  if (confirmed != true) return;
  final newName = controller.text.trim();
  if (newName.isEmpty || newName == currentName) return;

  try {
    await ScanApi.patchProductName(barcode: barcode, name: newName);
    ref.invalidate(scanHistoryProvider);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상품명 저장에 실패했어요. 다시 시도해주세요.')),
      );
    }
  }
}

// ── 상품 이미지 / 아바타 ──────────────────────────────────

class _ProductAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double size;

  const _ProductAvatar({required this.imageUrl, required this.name, this.size = 52});

  Color _avatarColor() {
    const colors = [kPrimary, kAmber, Color(0xFF16A34A), Color(0xFF7C3AED), Color(0xFF0891B2)];
    if (name.isEmpty) return kPrimary;
    return colors[name.codeUnitAt(0) % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final color = _avatarColor();
    final letter = name.isNotEmpty ? name[0] : '?';

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildLetter(color, letter),
        ),
      );
    }
    return _buildLetter(color, letter);
  }

  Widget _buildLetter(Color color, String letter) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          letter,
          style: GoogleFonts.plusJakartaSans(
            fontSize: size * 0.42,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
    );
  }
}

// ── 그룹화된 상품 카드 ────────────────────────────────────

class _GroupedProductCard extends StatelessWidget {
  final _ProductGroup group;
  final NumberFormat nf;
  final WidgetRef ref;

  const _GroupedProductCard({required this.group, required this.nf, required this.ref});

  @override
  Widget build(BuildContext context) {
    final latestPrice = group.latestOnlinePrice;
    final scanCount = group.scans.length;

    final priceHistoryAsync = ref.watch(priceHistoryProvider(group.barcode));

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
          childrenPadding: EdgeInsets.zero,
          shape: const Border(),
          collapsedShape: const Border(),
          title: Row(children: [
            Expanded(
              child: Text(
                group.name,
                style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: kOnSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            // 상품명 편집 버튼
            GestureDetector(
              onTap: () => _showEditNameDialog(context, ref, group.barcode, group.name),
              child: Icon(Icons.edit_outlined, size: 15, color: kOnSurfaceVariant.withValues(alpha: 0.6)),
            ),
            const SizedBox(width: 8),
            // 스캔 횟수 뱃지
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: kOnSurfaceVariant.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$scanCount회 스캔',
                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: kOnSurfaceVariant),
              ),
            ),
          ]),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              if (latestPrice != null) ...[
                Text(
                  '최근 ${nf.format(latestPrice)}원',
                  style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w800, color: kPrimary),
                ),
                if (group.allTimeLowestPrice != null && group.allTimeLowestPrice != latestPrice) ...[
                  const SizedBox(width: 8),
                  Text(
                    '최저가 ${nf.format(group.allTimeLowestPrice)}원',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF16A34A)),
                  ),
                ],
              ],
              const Spacer(),
              Text(
                DateFormat('MM.dd').format(group.latestScannedAt.toLocal()),
                style: GoogleFonts.inter(fontSize: 11, color: kOnSurfaceVariant),
              ),
            ]),
          ),
          children: [
            // 가격 추이 그래프
            priceHistoryAsync.when(
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              error: (_, __) => const SizedBox.shrink(),
              data: (priceHistory) => priceHistory.length >= 2
                  ? PriceGraphWidget(priceHistory: priceHistory)
                  : const SizedBox.shrink(),
            ),

            // 개별 스캔 이력 목록
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: Colors.grey.shade100, height: 20),
                  Text('스캔 이력',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: kOnSurfaceVariant)),
                  const SizedBox(height: 8),
                  ...group.scans.map((scan) => _ScanHistoryRow(scan: scan, nf: nf)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 개별 스캔 행 ──────────────────────────────────────────

class _ScanHistoryRow extends StatelessWidget {
  final Map<String, dynamic> scan;
  final NumberFormat nf;
  const _ScanHistoryRow({required this.scan, required this.nf});

  @override
  Widget build(BuildContext context) {
    final scannedAt = DateTime.parse(scan['scanned_at'] as String).toLocal();
    final dateLabel = DateFormat('yy.MM.dd HH:mm').format(scannedAt);
    final onlinePrice = scan['lowest_online_price'] as int?;
    final offlinePrice = scan['offline_price'] as int?;
    final platform = scan['lowest_online_platform'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Container(
          width: 6, height: 6,
          margin: const EdgeInsets.only(right: 10, top: 2),
          decoration: BoxDecoration(color: kOutlineVariant, shape: BoxShape.circle),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(dateLabel, style: GoogleFonts.inter(fontSize: 11, color: kOnSurfaceVariant)),
            if (onlinePrice != null || offlinePrice != null)
              Wrap(spacing: 8, children: [
                if (onlinePrice != null)
                  Text(
                    '${_platformLabel(platform)} ${nf.format(onlinePrice)}원',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: kPrimary),
                  ),
                if (offlinePrice != null)
                  Text(
                    '마트 ${nf.format(offlinePrice)}원',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: kAmber),
                  ),
              ]),
          ]),
        ),
      ]),
    );
  }

  String _platformLabel(String? platform) => switch (platform) {
    'coupang' => '쿠팡',
    'naver' => '네이버',
    _ => '온라인',
  };
}

// ── 비상품 카드 ───────────────────────────────────────────

class _NonProductHistoryCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final IconData iconData;
  final String dateLabel;

  const _NonProductHistoryCard({
    required this.item, required this.iconData, required this.dateLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scanType = item['scan_type'] as String;
    final content = item['barcode_content'] as Map?;
    final parsed = content?['parsed_data'] as Map?;
    final subtitle = switch (scanType) {
      'qr_url' => parsed?['domain'] as String? ?? '',
      'qr_wifi' => parsed?['ssid'] as String? ?? '',
      _ => '',
    };
    final displayText = subtitle.isNotEmpty ? subtitle : '$scanType 스캔';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
          child: Icon(iconData, color: kOnSurfaceVariant, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(displayText,
              style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: kOnSurface),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text(dateLabel, style: GoogleFonts.inter(fontSize: 11, color: kOnSurfaceVariant)),
          ]),
        ),
        if (scanType == 'qr_url')
          Icon(Icons.open_in_new, color: Colors.grey.shade400, size: 18),
      ]),
    );
  }
}

// ── 절약 카드 ─────────────────────────────────────────────

class _SavingsCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor, backgroundColor, valueColor, titleColor;
  final String title, value;
  final bool bordered;

  const _SavingsCard({
    required this.icon, required this.iconColor, required this.backgroundColor,
    required this.title, required this.value, required this.valueColor,
    required this.titleColor, this.bordered = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: bordered ? Border.all(color: kPrimary.withValues(alpha: 0.2)) : null,
        boxShadow: bordered ? null : [BoxShadow(color: kPrimary.withValues(alpha: 0.15), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: iconColor, size: 24),
        const SizedBox(height: 10),
        Text(title, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: titleColor)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w800, color: valueColor)),
      ]),
    );
  }
}
