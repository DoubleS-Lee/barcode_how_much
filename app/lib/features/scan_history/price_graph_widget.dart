import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';

class PriceGraphWidget extends StatelessWidget {
  final List<Map<String, dynamic>> priceHistory;

  const PriceGraphWidget({super.key, required this.priceHistory});

  @override
  Widget build(BuildContext context) {
    if (priceHistory.isEmpty) {
      return _EmptyGraph(message: '스캔 이력이 없어요');
    }

    final nf = NumberFormat('#,###');
    final onlineSpots = <FlSpot>[];
    final offlineSpots = <FlSpot>[];
    final dateLabels = <int, String>{};

    for (int i = 0; i < priceHistory.length; i++) {
      final item = priceHistory[i];
      final date = DateTime.tryParse(item['scanned_at'] as String? ?? '');
      dateLabels[i] = date != null ? DateFormat('MM/dd').format(date.toLocal()) : '';

      final onlinePrice = item['online_lowest_price'];
      if (onlinePrice != null) {
        onlineSpots.add(FlSpot(i.toDouble(), (onlinePrice as int).toDouble()));
      }
      final offlinePrice = item['offline_price'];
      if (offlinePrice != null) {
        offlineSpots.add(FlSpot(i.toDouble(), (offlinePrice as int).toDouble()));
      }
    }

    // 데이터 1개: 그래프 대신 요약 카드
    if (onlineSpots.length <= 1 && offlineSpots.isEmpty) {
      final price = onlineSpots.isNotEmpty ? onlineSpots.first.y.toInt() : null;
      return _EmptyGraph(
        message: '한 번 더 스캔하면\n가격 추이를 볼 수 있어요',
        hint: price != null ? '현재 온라인 최저가: ${nf.format(price)}원' : null,
      );
    }

    final allPrices = [
      ...onlineSpots.map((s) => s.y),
      ...offlineSpots.map((s) => s.y),
    ];
    final minY = allPrices.reduce((a, b) => a < b ? a : b);
    final maxY = allPrices.reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.2 + 500;

    // 절약 요약
    int? latestOnline;
    int? latestOffline;
    if (onlineSpots.isNotEmpty) latestOnline = onlineSpots.last.y.toInt();
    if (offlineSpots.isNotEmpty) latestOffline = offlineSpots.last.y.toInt();
    final savedAmount = (latestOffline != null && latestOnline != null && latestOffline > latestOnline)
        ? latestOffline - latestOnline
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 절약 요약 배너
          if (savedAmount != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.savings_outlined, size: 16, color: Colors.green.shade600),
                  const SizedBox(width: 8),
                  Text(
                    '온라인이 마트보다 ',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.green.shade700),
                  ),
                  Text(
                    '${nf.format(savedAmount)}원 저렴',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 범례
          Row(
            children: [
              _LegendDot(color: kPrimary, label: '온라인 최저가'),
              const SizedBox(width: 16),
              if (offlineSpots.isNotEmpty)
                _LegendDot(color: kAmber, label: '마트 직접 입력가'),
            ],
          ),
          const SizedBox(height: 12),

          // 그래프
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: minY - padding,
                maxY: maxY + padding,
                lineBarsData: [
                  // 파랑(kPrimary): 온라인 최저가
                  LineChartBarData(
                    spots: onlineSpots,
                    color: kPrimary,
                    isCurved: onlineSpots.length > 2,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                        radius: 4,
                        color: kPrimary,
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: kPrimary.withValues(alpha: 0.06),
                    ),
                  ),
                  // 주황(kAmber): 마트 직접 입력가
                  if (offlineSpots.isNotEmpty)
                    LineChartBarData(
                      spots: offlineSpots,
                      color: kAmber,
                      isCurved: offlineSpots.length > 2,
                      barWidth: 2.5,
                      dotData: FlDotData(
                        getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                          radius: 4,
                          color: kAmber,
                          strokeWidth: 2,
                          strokeColor: Colors.white,
                        ),
                      ),
                    ),
                ],
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: priceHistory.length > 5 ? (priceHistory.length / 4).ceilToDouble() : 1,
                      getTitlesWidget: (value, _) {
                        final label = dateLabels[value.toInt()];
                        if (label == null || label.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            label,
                            style: GoogleFonts.inter(fontSize: 10, color: kOnSurfaceVariant),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 60,
                      getTitlesWidget: (value, _) => Text(
                        nf.format(value.toInt()),
                        style: GoogleFonts.inter(fontSize: 10, color: kOnSurfaceVariant),
                      ),
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => kPrimaryDark,
                    tooltipRoundedRadius: 10,
                    getTooltipItems: (spots) => spots.map((spot) {
                      final isOnline = spot.barIndex == 0;
                      return LineTooltipItem(
                        '${isOnline ? "온라인" : "마트"}\n${nf.format(spot.y.toInt())}원',
                        GoogleFonts.inter(
                          color: isOnline ? Colors.blue.shade200 : Colors.amber.shade200,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList(),
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant),
        ),
      ],
    );
  }
}

class _EmptyGraph extends StatelessWidget {
  final String message;
  final String? hint;
  const _EmptyGraph({required this.message, this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          Icon(Icons.show_chart, size: 40, color: Colors.grey.shade200),
          const SizedBox(height: 10),
          Text(
            message,
            style: GoogleFonts.inter(fontSize: 13, color: kOnSurfaceVariant, height: 1.6),
            textAlign: TextAlign.center,
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint!,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: kPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
