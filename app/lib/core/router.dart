import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/scanner/scanner_screen.dart';
import '../features/price_result/price_result_screen.dart';
import '../features/manual_price/manual_price_screen.dart';
import '../features/scan_history/scan_history_screen.dart';
import '../features/community/community_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/legal_screen.dart';

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
        path: '/manual-price/:barcode',
        builder: (_, state) => ManualPriceScreen(
          barcode: state.pathParameters['barcode']!,
        ),
      ),
      GoRoute(path: '/history', builder: (_, __) => const ScanHistoryScreen()),
      GoRoute(path: '/community', builder: (_, __) => const CommunityScreen()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/privacy', builder: (_, __) => const PrivacyPolicyScreen()),
      GoRoute(path: '/terms', builder: (_, __) => const TermsScreen()),
      GoRoute(path: '/marketing', builder: (_, __) => const MarketingInfoScreen()),
    ],
  );
});
