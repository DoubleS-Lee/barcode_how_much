import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final prefs = await SharedPreferences.getInstance();
    return AuthState(
      loginType: prefs.getString('social_login_type'),
      loginName: prefs.getString('social_login_name'),
      loginEmail: prefs.getString('social_login_email'),
    );
  }

  Future<void> setLogin(String type, String name, String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('social_login_type', type);
    await prefs.setString('social_login_name', name);
    await prefs.setString('social_login_email', email);
    state = AsyncValue.data(AuthState(loginType: type, loginName: name, loginEmail: email));
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('social_login_type');
    await prefs.remove('social_login_name');
    await prefs.remove('social_login_email');
    state = const AsyncValue.data(AuthState());
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
