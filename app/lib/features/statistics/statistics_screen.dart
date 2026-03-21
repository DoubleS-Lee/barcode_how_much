import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../scan_history/scan_history_provider.dart';

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(scanHistoryProvider);

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '통계',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: kPrimaryDark,
          ),
        ),
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text('데이터를 불러오지 못했어요',
                  style: GoogleFonts.inter(color: kOnSurfaceVariant)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => ref.invalidate(scanHistoryProvider),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
        data: (items) => _StatisticsBody(items: items),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
    );
  }
}

class _StatisticsBody extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _StatisticsBody({required this.items});

  @override
  Widget build(BuildContext context) {
    final stats = _StatsCalculator(items);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 이번 달 요약 카드
          _SectionTitle('이번 달 요약'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  icon: Icons.qr_code_scanner,
                  label: '스캔 횟수',
                  value: '${stats.thisMonthScans}회',
                  color: kPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  icon: Icons.savings_outlined,
                  label: '절약 가능 금액',
                  value: stats.thisMonthSavings > 0
                      ? '${NumberFormat('#,###').format(stats.thisMonthSavings)}원'
                      : '-',
                  color: Colors.green.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  icon: Icons.inventory_2_outlined,
                  label: '총 상품 종류',
                  value: '${stats.uniqueProducts}종',
                  color: kAmber,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  icon: Icons.trending_down,
                  label: '평균 절약률',
                  value: stats.avgSavingRate > 0
                      ? '${stats.avgSavingRate.toStringAsFixed(1)}%'
                      : '-',
                  color: Colors.purple.shade400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // 플랫폼 최저가 비율
          if (stats.coupangWins + stats.naverWins > 0) ...[
            _SectionTitle('플랫폼별 최저가 비율'),
            const SizedBox(height: 12),
            _PlatformChart(
              coupangWins: stats.coupangWins,
              naverWins: stats.naverWins,
            ),
            const SizedBox(height: 28),
          ],

          // 스캔 시간대
          if (stats.hourlyScans.values.any((v) => v > 0)) ...[
            _SectionTitle('스캔 시간대'),
            const SizedBox(height: 12),
            _HourlyChart(hourlyScans: stats.hourlyScans),
            const SizedBox(height: 28),
          ],

          // 자주 스캔한 상품
          if (stats.topProducts.isNotEmpty) ...[
            _SectionTitle('자주 스캔한 상품'),
            const SizedBox(height: 12),
            ...stats.topProducts.take(5).toList().asMap().entries.map((e) {
              final rank = e.key + 1;
              final product = e.value;
              return _TopProductTile(rank: rank, product: product);
            }),
          ],

          if (items.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Column(
                  children: [
                    Icon(Icons.bar_chart, size: 64, color: Colors.grey.shade200),
                    const SizedBox(height: 16),
                    Text(
                      '아직 스캔 기록이 없어요\n상품을 스캔하면 통계가 나타나요',
                      style: GoogleFonts.inter(
                        color: kOnSurfaceVariant,
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 통계 계산 ──────────────────────────────────────────────

class _StatsCalculator {
  final List<Map<String, dynamic>> items;
  late int thisMonthScans;
  late int thisMonthSavings;
  late int uniqueProducts;
  late double avgSavingRate;
  late int coupangWins;
  late int naverWins;
  late Map<String, int> hourlyScans;
  late List<Map<String, dynamic>> topProducts;

  _StatsCalculator(this.items) {
    final now = DateTime.now();
    final thisMonthItems = items.where((item) {
      final scannedAt = DateTime.tryParse(item['scanned_at'] as String? ?? '');
      return scannedAt != null &&
          scannedAt.year == now.year &&
          scannedAt.month == now.month;
    }).toList();

    thisMonthScans = thisMonthItems.length;

    // 절약 금액: 오프라인 가격 - 온라인 최저가
    int totalSavings = 0;
    int savingsCount = 0;
    for (final item in thisMonthItems) {
      final offlinePrice = item['offline_price'] as int?;
      final lowestOnline = item['lowest_price'] as int?;
      if (offlinePrice != null && lowestOnline != null && offlinePrice > lowestOnline) {
        totalSavings += offlinePrice - lowestOnline;
        savingsCount++;
      }
    }
    thisMonthSavings = totalSavings;

    // 평균 절약률
    if (savingsCount > 0) {
      double totalRate = 0;
      for (final item in thisMonthItems) {
        final offlinePrice = item['offline_price'] as int?;
        final lowestOnline = item['lowest_price'] as int?;
        if (offlinePrice != null && lowestOnline != null && offlinePrice > 0) {
          totalRate += (offlinePrice - lowestOnline) / offlinePrice * 100;
        }
      }
      avgSavingRate = totalRate / savingsCount;
    } else {
      avgSavingRate = 0;
    }

    // 고유 상품 수
    final barcodes = items.map((e) => e['barcode'] as String?).whereType<String>().toSet();
    uniqueProducts = barcodes.length;

    // 플랫폼 최저가 카운트
    coupangWins = 0;
    naverWins = 0;
    for (final item in items) {
      final platform = item['lowest_platform'] as String?;
      if (platform == 'coupang') coupangWins++;
      if (platform == 'naver') naverWins++;
    }

    // 시간대별 스캔
    hourlyScans = {'아침\n6-9시': 0, '오전\n9-12시': 0, '오후\n12-18시': 0, '저녁\n18-24시': 0};
    for (final item in items) {
      final scannedAt = DateTime.tryParse(item['scanned_at'] as String? ?? '');
      if (scannedAt == null) continue;
      final h = scannedAt.hour;
      if (h >= 6 && h < 9) hourlyScans['아침\n6-9시'] = hourlyScans['아침\n6-9시']! + 1;
      else if (h >= 9 && h < 12) hourlyScans['오전\n9-12시'] = hourlyScans['오전\n9-12시']! + 1;
      else if (h >= 12 && h < 18) hourlyScans['오후\n12-18시'] = hourlyScans['오후\n12-18시']! + 1;
      else hourlyScans['저녁\n18-24시'] = hourlyScans['저녁\n18-24시']! + 1;
    }

    // 자주 스캔한 상품 Top 5
    final countMap = <String, Map<String, dynamic>>{};
    for (final item in items) {
      final barcode = item['barcode'] as String?;
      if (barcode == null) continue;
      if (!countMap.containsKey(barcode)) {
        countMap[barcode] = {
          'barcode': barcode,
          'product_name': item['product_name'] ?? barcode,
          'count': 0,
          'lowest_price': item['lowest_price'],
        };
      }
      countMap[barcode]!['count'] = (countMap[barcode]!['count'] as int) + 1;
    }
    topProducts = countMap.values.toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
  }
}

// ── 위젯 ──────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: kPrimaryDark,
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: kPrimaryDark,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: kOnSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatformChart extends StatelessWidget {
  final int coupangWins;
  final int naverWins;
  const _PlatformChart({required this.coupangWins, required this.naverWins});

  @override
  Widget build(BuildContext context) {
    final total = coupangWins + naverWins;
    final coupangPct = total > 0 ? coupangWins / total * 100 : 0.0;
    final naverPct = total > 0 ? naverWins / total * 100 : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: PieChart(
              PieChartData(
                sectionsSpace: 3,
                centerSpaceRadius: 30,
                sections: [
                  PieChartSectionData(
                    value: coupangWins.toDouble(),
                    color: const Color(0xFFE8131B),
                    radius: 28,
                    title: '',
                  ),
                  PieChartSectionData(
                    value: naverWins.toDouble(),
                    color: const Color(0xFF03C75A),
                    radius: 28,
                    title: '',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LegendRow(
                  color: const Color(0xFFE8131B),
                  label: '쿠팡',
                  count: coupangWins,
                  pct: coupangPct,
                ),
                const SizedBox(height: 12),
                _LegendRow(
                  color: const Color(0xFF03C75A),
                  label: '네이버',
                  count: naverWins,
                  pct: naverPct,
                ),
                const SizedBox(height: 12),
                Text(
                  '총 $total회 비교',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: kOnSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  final double pct;
  const _LegendRow({
    required this.color,
    required this.label,
    required this.count,
    required this.pct,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: kOnSurface)),
        const Spacer(),
        Text(
          '${pct.toStringAsFixed(0)}% ($count회)',
          style: GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant),
        ),
      ],
    );
  }
}

class _HourlyChart extends StatelessWidget {
  final Map<String, int> hourlyScans;
  const _HourlyChart({required this.hourlyScans});

  @override
  Widget build(BuildContext context) {
    final maxVal = hourlyScans.values.fold(0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 120,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal > 0 ? maxVal.toDouble() * 1.3 : 5,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, _) {
                        final labels = hourlyScans.keys.toList();
                        if (value.toInt() >= labels.length) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            labels[value.toInt()],
                            style: GoogleFonts.inter(fontSize: 9, color: kOnSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: Colors.grey.shade100,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: hourlyScans.values.toList().asMap().entries.map((e) {
                  return BarChartGroupData(x: e.key, barRods: [
                    BarChartRodData(
                      toY: e.value.toDouble(),
                      color: kPrimary,
                      width: 28,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    ),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopProductTile extends StatelessWidget {
  final int rank;
  final Map<String, dynamic> product;
  const _TopProductTile({required this.rank, required this.product});

  @override
  Widget build(BuildContext context) {
    final price = product['lowest_price'] as int?;
    final count = product['count'] as int;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: rank <= 3 ? kPrimary.withValues(alpha: 0.1) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '$rank',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: rank <= 3 ? kPrimary : kOnSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product['product_name'] as String,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: kOnSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '$count회 스캔',
                  style: GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant),
                ),
              ],
            ),
          ),
          if (price != null && price > 0)
            Text(
              '${NumberFormat('#,###').format(price)}원',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: kPrimaryDark,
              ),
            ),
        ],
      ),
    );
  }
}
