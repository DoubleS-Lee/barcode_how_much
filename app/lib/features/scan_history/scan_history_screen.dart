import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../shared/api/scan_api.dart';
import '../../shared/utils/device_id.dart';
import '../../shared/utils/image_utils.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../price_result/recommend_provider.dart';
import 'scan_history_provider.dart';
import 'price_graph_widget.dart';
import '../../shared/providers/saved_locations_provider.dart';


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
  String? get latestOnlineUrl => scans.first['lowest_online_url'] as String?;
  DateTime get latestScannedAt => DateTime.parse(scans.first['scanned_at'] as String);

  int? get latestOfflinePrice {
    for (final scan in scans) {
      if ((scan['offline_price'] as int?) != null) return scan['offline_price'] as int;
    }
    return null;
  }

  Map<String, dynamic>? get _latestOfflineScan {
    for (final scan in scans) {
      if ((scan['offline_price'] as int?) != null) return scan;
    }
    return null;
  }

  String? get latestOfflineStoreHint => _latestOfflineScan?['store_hint'] as String?;
  String? get latestOfflineMemo => _latestOfflineScan?['memo'] as String?;

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

        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }
}

// ── 상품 그룹 전체 삭제 ───────────────────────────────────

Future<void> _confirmGroupDelete(
  BuildContext context,
  WidgetRef ref,
  _ProductGroup group,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('상품 기록 삭제',
          style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700)),
      content: Text(
        '"${group.name}"\n총 ${group.scans.length}건의 스캔 기록을 모두 삭제할까요?',
        style: GoogleFonts.inter(fontSize: 14, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('취소', style: GoogleFonts.inter(color: kOnSurfaceVariant)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('삭제', style: GoogleFonts.inter(color: kError, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  try {
    for (final scan in group.scans) {
      final scanId = scan['scan_id'] as String?;
      if (scanId != null) await ScanApi.deleteScan(scanId);
    }
    ref.invalidate(scanHistoryProvider);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: $e'), backgroundColor: Colors.red.shade700),
      );
    }
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

// ── 이름 기반 가격 재검색 (네이버 후보 선택) ──────────────

Future<void> _repricingByName(
  BuildContext context,
  WidgetRef ref,
  String barcode,
  String productName,
) async {
  // 후보 로딩 중 바텀시트
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => _NaverCandidateSheet(
      barcode: barcode,
      productName: productName,
      onSelected: () {
        ref.invalidate(scanHistoryProvider);
      },
    ),
  );
}

class _NaverCandidateSheet extends StatefulWidget {
  final String barcode;
  final String productName;
  final VoidCallback onSelected;

  const _NaverCandidateSheet({
    required this.barcode,
    required this.productName,
    required this.onSelected,
  });

  @override
  State<_NaverCandidateSheet> createState() => _NaverCandidateSheetState();
}

class _NaverCandidateSheetState extends State<_NaverCandidateSheet> {
  List<Map<String, dynamic>>? _candidates;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final candidates = await ScanApi.getNaverCandidates(widget.productName);
      if (mounted) setState(() { _candidates = candidates; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _select(Map<String, dynamic> candidate) async {
    final deviceUuid = await DeviceId.get();
    if (!mounted) return;
    Navigator.pop(context);
    try {
      await ScanApi.relinkNaver(
        deviceUuid: deviceUuid,
        barcode: widget.barcode,
        productName: widget.productName, // 사용자가 설정한 상품명 그대로 유지
        price: candidate['price'] as int,
        shoppingUrl: candidate['shopping_url'] as String,
        imageUrl: candidate['image_url'] as String?,
      );
      widget.onSelected();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('가격이 업데이트됐어요!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('업데이트 실패: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat('#,###');
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('네이버 상품 선택', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('"${widget.productName}" 검색 결과에서 올바른 상품을 선택해주세요.',
                style: GoogleFonts.inter(fontSize: 13, color: kOnSurfaceVariant)),
            ]),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('검색 실패: $_error', style: GoogleFonts.inter(color: kOnSurfaceVariant)))
                    : _candidates == null || _candidates!.isEmpty
                        ? Center(child: Text('검색 결과가 없어요.', style: GoogleFonts.inter(color: kOnSurfaceVariant)))
                        : ListView.separated(
                            controller: controller,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _candidates!.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                            itemBuilder: (_, i) {
                              final c = _candidates![i];
                              final name = c['product_name'] as String;
                              final price = c['price'] as int;
                              final imageUrl = c['image_url'] as String?;
                              final mallName = c['mall_name'] as String? ?? '';
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: imageUrl != null
                                      ? Image.network(imageUrl, width: 56, height: 56, fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => _imagePlaceholder())
                                      : _imagePlaceholder(),
                                ),
                                title: Text(name,
                                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  const SizedBox(height: 2),
                                  Text('${nf.format(price)}원',
                                    style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: kPrimary)),
                                  if (mallName.isNotEmpty)
                                    Text(mallName, style: GoogleFonts.inter(fontSize: 11, color: kOnSurfaceVariant)),
                                ]),
                                onTap: () => _select(c),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder() => Container(
    width: 56, height: 56,
    color: Colors.grey.shade100,
    child: const Icon(Icons.image_outlined, color: Colors.grey),
  );
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

class _GroupedProductCard extends StatefulWidget {
  final _ProductGroup group;
  final NumberFormat nf;
  final WidgetRef ref;

  const _GroupedProductCard({required this.group, required this.nf, required this.ref});

  @override
  State<_GroupedProductCard> createState() => _GroupedProductCardState();
}

enum _ImageMenuOption { camera, gallery, autoMatch, delete }

class _GroupedProductCardState extends State<_GroupedProductCard> {
  bool _showHistory = false;
  bool _uploadingImage = false;

  Future<void> _pickProductImage() async {
    final option = await showModalBottomSheet<_ImageMenuOption>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined, color: kPrimary),
            title: Text('자동으로 매칭', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: kPrimary)),
            subtitle: Text('네이버 쇼핑에서 상품 이미지 가져오기', style: GoogleFonts.inter(fontSize: 12)),
            onTap: () => Navigator.pop(ctx, _ImageMenuOption.autoMatch),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: Text('카메라로 촬영', style: GoogleFonts.inter()),
            onTap: () => Navigator.pop(ctx, _ImageMenuOption.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text('갤러리에서 선택', style: GoogleFonts.inter()),
            onTap: () => Navigator.pop(ctx, _ImageMenuOption.gallery),
          ),
          if (widget.group.imageUrl != null)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text('사진 삭제', style: GoogleFonts.inter(color: Colors.red)),
              onTap: () => Navigator.pop(ctx, _ImageMenuOption.delete),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted) return;

    switch (option) {
      case _ImageMenuOption.autoMatch:
        _repricingByName(context, widget.ref, widget.group.barcode, widget.group.name);
        return;
      case _ImageMenuOption.delete:
        return; // 미구현
      case _ImageMenuOption.camera:
      case _ImageMenuOption.gallery:
        final source = option == _ImageMenuOption.camera ? ImageSource.camera : ImageSource.gallery;
        final picker = ImagePicker();
        final picked = await picker.pickImage(source: source, imageQuality: 90);
        if (picked == null || !mounted) return;
        setState(() => _uploadingImage = true);
        try {
          final compressed = await compressImage(File(picked.path));
          await ScanApi.uploadProductImage(barcode: widget.group.barcode, imageFile: compressed);
          widget.ref.invalidate(scanHistoryProvider);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('이미지 업로드 실패: $e'), backgroundColor: Colors.red.shade700),
            );
          }
        } finally {
          if (mounted) setState(() => _uploadingImage = false);
        }
        return;
      case null:
        return;
    }
  }

  Future<void> _launchUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
  }

  void _showOfflineInfo(BuildContext context, String? storeHint, String? memo) {
    if (storeHint == null && memo == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.store_outlined, color: kAmber, size: 20),
          const SizedBox(width: 8),
          Text('오프라인 정보', style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (storeHint != null) ...[
              Row(children: [
                const Icon(Icons.place_outlined, size: 16, color: kOnSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text(storeHint, style: GoogleFonts.inter(fontSize: 14))),
              ]),
              if (memo != null) const SizedBox(height: 8),
            ],
            if (memo != null)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.notes, size: 16, color: kOnSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text(memo, style: GoogleFonts.inter(fontSize: 14))),
              ]),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('확인', style: GoogleFonts.inter(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final nf = widget.nf;
    final ref = widget.ref;
    final latestOnlinePrice = group.latestOnlinePrice;
    final latestOfflinePrice = group.latestOfflinePrice;
    final latestPrice = latestOnlinePrice ?? latestOfflinePrice;
    final scanCount = group.scans.length;

    // 헤더에서 더 싼 쪽 판별
    final int? headerDiff = (latestOnlinePrice != null && latestOfflinePrice != null)
        ? latestOfflinePrice - latestOnlinePrice
        : null;
    final bool headerOnlineCheaper = headerDiff != null && headerDiff > 0;
    final bool headerOfflineCheaper = headerDiff != null && headerDiff < 0;

    final priceHistoryAsync = ref.watch(priceHistoryProvider(group.barcode));
    final isFav = ref.watch(favoritesProvider).contains(group.barcode);

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
          leading: GestureDetector(
            onTap: _pickProductImage,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _ProductAvatar(imageUrl: group.imageUrl, name: group.name, size: 48),
                if (_uploadingImage)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: const ColoredBox(
                        color: Colors.black38,
                        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
                      ),
                    ),
                  ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: kPrimary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: const Icon(Icons.camera_alt, size: 10, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          title: Row(children: [
            Expanded(
              child: Text(
                group.name,
                style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: kOnSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: () => _showEditNameDialog(context, ref, group.barcode, group.name),
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.edit_outlined, size: 14, color: kOnSurfaceVariant.withValues(alpha: 0.5)),
              ),
            ),
            GestureDetector(
              onTap: () => _confirmGroupDelete(context, ref, group),
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.delete_outline, size: 14, color: kError.withValues(alpha: 0.5)),
              ),
            ),
          ]),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 가격 (탭 가능)
                Row(children: [
                  Flexible(child: Wrap(spacing: 6, runSpacing: 4, children: [
                    // 온라인 가격
                    if (latestOnlinePrice != null)
                      GestureDetector(
                        onTap: () => _launchUrl(group.latestOnlineUrl),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: headerOnlineCheaper
                                ? kPrimary.withValues(alpha: 0.10)
                                : Colors.grey.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: kPrimary.withValues(alpha: headerOnlineCheaper ? 0.3 : 0.15),
                              width: 1,
                            ),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(
                              '온라인 ${nf.format(latestOnlinePrice)}원',
                              style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800, color: kPrimary),
                            ),
                            const SizedBox(width: 3),
                            Icon(Icons.open_in_new, size: 11, color: kPrimary.withValues(alpha: 0.6)),
                          ]),
                        ),
                      ),
                    // 오프라인 가격
                    if (latestOfflinePrice != null)
                      GestureDetector(
                        onTap: () => _showOfflineInfo(
                          context,
                          group.latestOfflineStoreHint,
                          group.latestOfflineMemo,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: headerOfflineCheaper
                                ? kAmber.withValues(alpha: 0.12)
                                : Colors.grey.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: kAmber.withValues(alpha: headerOfflineCheaper ? 0.4 : 0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(
                              '오프라인 ${nf.format(latestOfflinePrice)}원',
                              style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800, color: kAmber),
                            ),
                            if (group.latestOfflineStoreHint != null || group.latestOfflineMemo != null) ...[
                              const SizedBox(width: 3),
                              Icon(Icons.info_outline, size: 11, color: kAmber.withValues(alpha: 0.7)),
                            ],
                          ]),
                        ),
                      ),
                    // 온/오프 모두 없을 때 대비
                    if (latestOnlinePrice == null && latestOfflinePrice == null && latestPrice != null)
                      Text(
                        '최근 ${nf.format(latestPrice)}원',
                        style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800, color: kPrimary),
                      ),
                  ])),
                ]),
                const SizedBox(height: 6),
                // 액션 버튼 행
                Row(children: [
                  // 찜 버튼
                  GestureDetector(
                    onTap: () => ref.read(favoritesProvider.notifier).toggle(group.barcode),
                    child: Icon(
                      isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 18,
                      color: isFav ? kAmber : kOnSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 가격 재검색 버튼
                  GestureDetector(
                    onTap: () => _repricingByName(context, ref, group.barcode, group.name),
                    child: Icon(Icons.search, size: 16, color: kPrimary.withValues(alpha: 0.7)),
                  ),
                  const Spacer(),
                  // 스캔 횟수 뱃지
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: kOnSurfaceVariant.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$scanCount회 스캔',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: kOnSurfaceVariant),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    DateFormat('MM.dd').format(group.latestScannedAt.toLocal()),
                    style: GoogleFonts.inter(fontSize: 10, color: kOnSurfaceVariant),
                  ),
                ]),
              ],
            ),
          ),
          children: [
            // 절약 요약 배너 (즉각 반영: 로컬 편집값 우선, 없으면 서버 데이터)
            Builder(builder: (context) {
              final latestOnline = group.latestOnlinePrice;
              final liveOffline = ref.watch(liveOfflinePriceProvider(group.barcode));
              final latestOffline = liveOffline ?? group.latestOfflinePrice;
              if (latestOnline == null || latestOffline == null) return const SizedBox.shrink();
              final diff = latestOffline - latestOnline;
              if (diff == 0) return const SizedBox.shrink();
              final isOnlineCheaper = diff > 0;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(children: [
                  Icon(
                    isOnlineCheaper ? Icons.savings_outlined : Icons.store_outlined,
                    size: 14,
                    color: kOnSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '차액 ${nf.format(diff.abs())}원',
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: kOnSurface),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isOnlineCheaper ? '(온라인이 저렴)' : '(오프라인이 저렴)',
                    style: GoogleFonts.inter(fontSize: 11, color: kOnSurfaceVariant),
                  ),
                ]),
              );
            }),

            // 가격 추이 그래프
            priceHistoryAsync.when(
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              error: (_, __) => const SizedBox.shrink(),
              data: (priceHistory) => priceHistory.length >= 2
                  ? PriceGraphWidget(priceHistory: priceHistory)
                  : const SizedBox.shrink(),
            ),

            // 상세보기 / 접기 토글 버튼
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: GestureDetector(
                onTap: () => setState(() => _showHistory = !_showHistory),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _showHistory ? '접기' : '상세보기',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: kOnSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      _showHistory ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 16,
                      color: kOnSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),

            // 개별 스캔 이력 목록 (토글)
            if (_showHistory)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(color: Colors.grey.shade100, height: 20),
                    Text('스캔 이력',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: kOnSurfaceVariant)),
                    const SizedBox(height: 8),
                    ...group.scans.map((scan) => _ScanHistoryRow(scan: scan, nf: nf, barcode: group.barcode)),
                  ],
                ),
              )
            else
              const SizedBox(height: 12),

            // 유사 상품 추천 (추후 활성화)
            // _HistoryRecommendSection(barcode: group.barcode, productName: group.name, nf: nf, ref: ref),
          ],
        ),
      ),
    );
  }
}

// ── 개별 스캔 행 ──────────────────────────────────────────

class _ScanHistoryRow extends ConsumerStatefulWidget {
  final Map<String, dynamic> scan;
  final NumberFormat nf;
  final String barcode;
  const _ScanHistoryRow({required this.scan, required this.nf, required this.barcode});

  @override
  ConsumerState<_ScanHistoryRow> createState() => _ScanHistoryRowState();
}

class _ScanHistoryRowState extends ConsumerState<_ScanHistoryRow> {
  late int? _offlinePrice;
  late String? _storeHint;
  late String? _memo;

  @override
  void initState() {
    super.initState();
    _offlinePrice = widget.scan['offline_price'] as int?;
    _storeHint = widget.scan['store_hint'] as String?;
    _memo = widget.scan['memo'] as String?;
  }

  @override
  void didUpdateWidget(_ScanHistoryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 서버 재요청으로 새 데이터가 들어오면 로컬 상태 갱신
    // (skipLoadingOnRefresh=true 기본값으로 인해 재요청 중에도 이 위젯이 유지됨)
    if (oldWidget.scan != widget.scan) {
      _offlinePrice = widget.scan['offline_price'] as int?;
      _storeHint = widget.scan['store_hint'] as String?;
      _memo = widget.scan['memo'] as String?;
    }
  }

  String _platformLabel(String? platform) => switch (platform) {
    'coupang' => '쿠팡',
    'naver' => '네이버',
    _ => '온라인',
  };

  Future<void> _launchUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
  }

  void _showOfflineInfoDialog() {
    if (_storeHint == null && _memo == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.store_outlined, color: kAmber, size: 20),
          const SizedBox(width: 8),
          Text('오프라인 정보', style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_storeHint != null) ...[
              Row(children: [
                const Icon(Icons.place_outlined, size: 16, color: kOnSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text(_storeHint!, style: GoogleFonts.inter(fontSize: 14))),
              ]),
              if (_memo != null) const SizedBox(height: 8),
            ],
            if (_memo != null)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.notes, size: 16, color: kOnSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text(_memo!, style: GoogleFonts.inter(fontSize: 14))),
              ]),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('확인', style: GoogleFonts.inter(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final scanId = widget.scan['scan_id'] as String?;
    if (scanId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('스캔 기록 삭제',
            style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text('이 스캔 기록을 삭제할까요?',
            style: GoogleFonts.inter(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소', style: GoogleFonts.inter(color: kOnSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('삭제', style: GoogleFonts.inter(color: kError, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ScanApi.deleteScan(scanId);
      ref.invalidate(scanHistoryProvider);
      ref.invalidate(priceHistoryProvider(widget.barcode));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  Future<void> _showEditDialog() async {
    final priceCtrl = TextEditingController(
        text: _offlinePrice != null ? _offlinePrice.toString() : '');
    final storeCtrl = TextEditingController(text: _storeHint ?? '');
    final memoCtrl = TextEditingController(text: _memo ?? '');

    final savedLocations = ref.read(savedLocationsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('오프라인 정보 수정',
            style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: priceCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '오프라인 가격 (원)',
              hintText: '예: 12900',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: GoogleFonts.inter(fontSize: 14),
          ),
          const SizedBox(height: 10),
          if (savedLocations.isNotEmpty) ...[
            StatefulBuilder(builder: (_, setS) => Wrap(
              spacing: 6,
              runSpacing: 4,
              children: savedLocations.map((loc) => GestureDetector(
                onTap: () { storeCtrl.text = loc; setS(() {}); },
                child: Chip(
                  label: Text(loc, style: GoogleFonts.inter(fontSize: 11)),
                  backgroundColor: kPrimary.withValues(alpha: 0.06),
                  side: BorderSide(color: kPrimary.withValues(alpha: 0.2)),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              )).toList(),
            )),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: storeCtrl,
            decoration: InputDecoration(
              labelText: '장소',
              hintText: '예: 이마트 왕십리점',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              prefixIcon: const Icon(Icons.place_outlined, size: 18),
            ),
            style: GoogleFonts.inter(fontSize: 14),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: memoCtrl,
            decoration: InputDecoration(
              labelText: '메모',
              hintText: '예: 1+1 행사 중',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              prefixIcon: const Icon(Icons.notes, size: 18),
            ),
            style: GoogleFonts.inter(fontSize: 14),
            maxLength: 100,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          ),
        ]),
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

    final newPrice = int.tryParse(priceCtrl.text.trim());
    final newStore = storeCtrl.text.trim().isEmpty ? null : storeCtrl.text.trim();
    final newMemo = memoCtrl.text.trim().isEmpty ? null : memoCtrl.text.trim();

    if (newPrice == null && _offlinePrice == null) return;

    final scanId = widget.scan['scan_id'] as String?;
    if (scanId == null) return;

    try {
      await ScanApi.patchOfflinePrice(
        scanId: scanId,
        price: newPrice ?? _offlinePrice,
        storeHint: newStore,
        memo: newMemo,
      );
      setState(() {
        if (newPrice != null) _offlinePrice = newPrice;
        _storeHint = newStore;
        _memo = newMemo;
      });
      // 배너 즉각 반영 (서버 재요청 완료 전에도 바로 업데이트)
      ref.read(liveOfflinePriceProvider(widget.barcode).notifier).state =
          newPrice ?? _offlinePrice;
      ref.invalidate(scanHistoryProvider);
      ref.invalidate(priceHistoryProvider(widget.barcode));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scan = widget.scan;
    final nf = widget.nf;
    final scannedAt = DateTime.parse(scan['scanned_at'] as String).toLocal();
    final dateLabel = DateFormat('yy.MM.dd HH:mm').format(scannedAt);
    final onlinePrice = scan['lowest_online_price'] as int?;
    final platform = scan['lowest_online_platform'] as String?;
    final onlineUrl = scan['lowest_online_url'] as String?;

    // 이 scanId에 방금 저장된 가격이 있으면 우선 표시 (프로모션 단가 포함 즉각 반영)
    final scanId = scan['scan_id'] as String? ?? '';
    final livePrice = ref.watch(liveScanOfflinePriceProvider(scanId));
    final displayOfflinePrice = livePrice ?? _offlinePrice;

    // 온/오프 비교
    int? diff;
    if (onlinePrice != null && displayOfflinePrice != null) {
      diff = displayOfflinePrice - onlinePrice; // 양수 = 오프라인 더 비쌈(온라인 유리), 음수 = 오프라인 더 쌈
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 6, height: 6,
          margin: const EdgeInsets.only(right: 10, top: 5),
          decoration: BoxDecoration(color: kOutlineVariant, shape: BoxShape.circle),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 날짜 + 수정/삭제 버튼
            Row(children: [
              Text(dateLabel, style: GoogleFonts.inter(fontSize: 11, color: kOnSurfaceVariant)),
              const Spacer(),
              GestureDetector(
                onTap: _showEditDialog,
                child: Icon(Icons.edit_outlined, size: 14, color: kOnSurfaceVariant.withValues(alpha: 0.5)),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _confirmDelete,
                child: Icon(Icons.delete_outline, size: 14, color: kError.withValues(alpha: 0.4)),
              ),
            ]),
            const SizedBox(height: 3),

            // 온라인/오프라인 가격 (탭 가능)
            if (onlinePrice != null || displayOfflinePrice != null)
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (onlinePrice != null)
                  GestureDetector(
                    onTap: () => _launchUrl(onlineUrl),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: (diff != null && diff > 0)
                            ? kPrimary.withValues(alpha: 0.10)
                            : Colors.grey.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: kPrimary.withValues(alpha: 0.2), width: 1),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          '${_platformLabel(platform)} ${nf.format(onlinePrice)}원',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: kPrimary),
                        ),
                        if (onlineUrl != null) ...[
                          const SizedBox(width: 2),
                          Icon(Icons.open_in_new, size: 10, color: kPrimary.withValues(alpha: 0.6)),
                        ],
                      ]),
                    ),
                  ),
                if (displayOfflinePrice != null)
                  GestureDetector(
                    onTap: (_storeHint != null || _memo != null) ? _showOfflineInfoDialog : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: (diff != null && diff < 0)
                            ? kAmber.withValues(alpha: 0.12)
                            : Colors.grey.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: kAmber.withValues(alpha: 0.25), width: 1),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          '오프라인 ${nf.format(displayOfflinePrice)}원',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: kAmber),
                        ),
                        if (_storeHint != null || _memo != null) ...[
                          const SizedBox(width: 2),
                          Icon(Icons.info_outline, size: 10, color: kAmber.withValues(alpha: 0.7)),
                        ],
                      ]),
                    ),
                  ),
              ]),

            // 차액 표시
            if (diff != null && diff != 0) ...[
              const SizedBox(height: 3),
              Text(
                '차액 ${nf.format(diff.abs())}원',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: kOnSurface,
                ),
              ),
            ],

            // 장소
            if (_storeHint != null && _storeHint!.isNotEmpty) ...[
              const SizedBox(height: 3),
              Row(children: [
                Icon(Icons.place_outlined, size: 11, color: kOnSurfaceVariant.withValues(alpha: 0.7)),
                const SizedBox(width: 3),
                Text(_storeHint!, style: GoogleFonts.inter(fontSize: 11, color: kOnSurfaceVariant)),
              ]),
            ],

            // 메모
            if (_memo != null && _memo!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(children: [
                Icon(Icons.notes, size: 11, color: kOnSurfaceVariant.withValues(alpha: 0.7)),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    _memo!,
                    style: GoogleFonts.inter(fontSize: 11, color: kOnSurfaceVariant, fontStyle: FontStyle.italic),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
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

// ── 유사 상품 추천 섹션 ───────────────────────────────────

class _HistoryRecommendSection extends StatelessWidget {
  final String barcode;
  final String productName;
  final NumberFormat nf;
  final WidgetRef ref;

  const _HistoryRecommendSection({
    required this.barcode,
    required this.productName,
    required this.nf,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final recommendAsync = ref.watch(
      recommendProvider(RecommendArgs(barcode: barcode, productName: productName)),
    );

    return recommendAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) {
        final items = (data['recommendations'] as List? ?? []).cast<Map<String, dynamic>>();
        if (items.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Divider(color: Colors.grey.shade100, height: 20),
              Row(children: [
                Text(
                  '이런 상품도 있어요',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: kOnSurfaceVariant),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: kPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '쿠팡·네이버',
                    style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: kPrimary),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.take(6).length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final price = (item['price'] as num).toInt();
                    final name = item['product_name'] as String;
                    final imageUrl = item['image_url'] as String?;
                    final url = item['shopping_url'] as String;
                    return GestureDetector(
                      onTap: () async {
                        final uri = Uri.tryParse(url);
                        if (uri != null && await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                      child: Container(
                        width: 120,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: kSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade100),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            height: 60,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: imageUrl != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      imageUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Icon(Icons.inventory_2_outlined, color: Colors.grey.shade300, size: 22),
                                    ),
                                  )
                                : Icon(Icons.inventory_2_outlined, color: Colors.grey.shade300, size: 22),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            name,
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: kOnSurface),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),
                          Text(
                            '${nf.format(price)}원',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800, color: kPrimary),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── 배너 광고 위젯 ─────────────────────────────────────────

class _BannerAdWidget extends StatefulWidget {
  const _BannerAdWidget();

  @override
  State<_BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<_BannerAdWidget> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    // 실제 배포 시 ca-app-pub-XXXXX/YYYYY 형태의 실제 광고 ID로 교체하세요.
    final adUnitId = Platform.isAndroid
        ? 'ca-app-pub-3940256099942544/6300978111' // Google 테스트 ID
        : 'ca-app-pub-3940256099942544/2934735716'; // Google 테스트 ID (iOS)
    _ad = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          _ad = null;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return Container(
      alignment: Alignment.center,
      width: _ad!.size.width.toDouble(),
      height: _ad!.size.height.toDouble(),
      child: AdWidget(ad: _ad!),
    );
  }
}

