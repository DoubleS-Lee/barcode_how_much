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
import 'shared/services/notification_service.dart';
import 'shared/services/fcm_service.dart';
import 'shared/utils/device_id.dart';

/// ✅ Kakao Native App Key — developers.kakao.com에서 발급 후 교체
const kKakaoNativeAppKey = '112bf6f973f8f0f99d0ac2b277b46525';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  // Firebase 초기화 — Android/iOS에서만 실행
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS)) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    KakaoSdk.init(nativeAppKey: kKakaoNativeAppKey);
    // 임시: 카카오 키 해시 확인용 (등록 후 삭제)
    final keyHash = await KakaoSdk.origin;
    debugPrint('🔑 Kakao Key Hash: $keyHash');
    await MobileAds.instance.initialize();
  }

  // 로컬 알림 초기화 (Android/iOS/macOS/Linux)
  await NotificationService.init();

  // FCM 초기화 (모바일 빌드에서만 활성화)
  // 활성화 방법: pubspec.yaml의 firebase 패키지 주석 해제 후 flutterfire configure 실행
  final deviceUuid = await DeviceId.get();
  await FcmService.init(deviceUuid);

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
