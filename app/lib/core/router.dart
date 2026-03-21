import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/scanner/scanner_screen.dart';
import '../features/price_result/price_result_screen.dart';
import '../features/manual_price/manual_price_screen.dart';
import '../features/scan_history/scan_history_screen.dart';
import '../features/statistics/statistics_screen.dart';
import '../features/settings/settings_screen.dart';

final routerProvider = Provider.family<GoRouter, String>((ref, initialRoute) {
  return GoRouter(
    initialLocation: initialRoute,
    routes: [
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/scanner', builder: (_, __) => const ScannerScreen()),
      GoRoute(
        path: '/price-result/:barcode',
        builder: (_, state) =>
            PriceResultScreen(barcode: state.pathParameters['barcode']!),
      ),
      GoRoute(
        path: '/manual-price/:scanId',
        builder: (_, state) => ManualPriceScreen(
          scanId: int.tryParse(state.pathParameters['scanId']!) ?? 0,
          lowestOnlinePrice: int.tryParse(state.uri.queryParameters['price'] ?? ''),
          productName: state.uri.queryParameters['name'],
        ),
      ),
      GoRoute(path: '/history', builder: (_, __) => const ScanHistoryScreen()),
      GoRoute(path: '/statistics', builder: (_, __) => const StatisticsScreen()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    ],
  );
});
