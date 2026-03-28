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

  // Firebase + AdMob 병렬 초기화 (runApp 전 필수 작업만)
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS)) {
    try {
      await Future.wait([
        Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
        MobileAds.instance.initialize(),
      ]);
    } catch (e) {
      debugPrint('[Init] Firebase/AdMob 초기화 실패: $e');
    }
    KakaoSdk.init(nativeAppKey: kKakaoNativeAppKey);
  }

  final prefs = await SharedPreferences.getInstance();
  final onboardingDone = prefs.getBool('onboarding_done') ?? false;
  runApp(ProviderScope(
    child: EolmaeApp(initialRoute: onboardingDone ? '/scanner' : '/onboarding'),
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
