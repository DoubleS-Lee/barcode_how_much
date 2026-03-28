import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kakao_flutter_sdk_share/kakao_flutter_sdk_share.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme.dart';
import 'core/router.dart';
import 'firebase_options.dart';

/// ✅ Kakao Native App Key — developers.kakao.com에서 발급 후 교체
const kKakaoNativeAppKey = '112bf6f973f8f0f99d0ac2b277b46525';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  // Firebase + AdMob 초기화
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS)) {
    try {
      // Firebase만 awaiting (FCM 등 사용 전 필수)
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } catch (e) {
      debugPrint('[Init] Firebase 초기화 실패: $e');
    }
    // AdMob은 non-blocking — 광고 로드 전에 완료되면 충분
    // ignore: unawaited_futures
    MobileAds.instance.initialize();
    KakaoSdk.init(nativeAppKey: kKakaoNativeAppKey);
  }

  final prefs = await SharedPreferences.getInstance();
  final onboardingDone = prefs.getBool('onboarding_done') ?? false;
  final initialRoute = onboardingDone ? '/scanner' : '/onboarding';
  runApp(ProviderScope(
    child: EolmaeApp(initialRoute: initialRoute),
  ));
}

class EolmaeApp extends ConsumerWidget {
  final String initialRoute;
  const EolmaeApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider(initialRoute));
    return MaterialApp.router(
      title: '얼마였지?',
      theme: eolmaeTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
