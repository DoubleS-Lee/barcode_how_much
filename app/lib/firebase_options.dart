// ⚠️  Firebase 미설정 상태 (Windows 개발용 스텁)
// 모바일 빌드 시 아래 명령어로 이 파일을 교체하세요:
//   dart pub global activate flutterfire_cli
//   flutterfire configure
// 그 후 pubspec.yaml의 firebase_core / firebase_messaging 주석을 해제하세요.

class DefaultFirebaseOptions {
  static Never get currentPlatform {
    throw UnsupportedError('Firebase not configured. Run flutterfire configure.');
  }
}
