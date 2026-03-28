import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

const _kLoginType  = 'social_login_type';
const _kLoginName  = 'social_login_name';
const _kLoginEmail = 'social_login_email';

class AuthState {
  final String? loginType;  // 'google' | 'kakao' | 'naver' | null
  final String? loginName;
  final String? loginEmail;

  const AuthState({this.loginType, this.loginName, this.loginEmail});

  bool get isLoggedIn => loginType != null;
}

class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    return AuthState(
      loginType:  await _storage.read(key: _kLoginType),
      loginName:  await _storage.read(key: _kLoginName),
      loginEmail: await _storage.read(key: _kLoginEmail),
    );
  }

  Future<void> setLogin(String type, String name, String email) async {
    await _storage.write(key: _kLoginType,  value: type);
    await _storage.write(key: _kLoginName,  value: name);
    await _storage.write(key: _kLoginEmail, value: email);
    state = AsyncValue.data(AuthState(loginType: type, loginName: name, loginEmail: email));
  }

  Future<void> logout() async {
    await _storage.delete(key: _kLoginType);
    await _storage.delete(key: _kLoginName);
    await _storage.delete(key: _kLoginEmail);
    state = const AsyncValue.data(AuthState());
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
