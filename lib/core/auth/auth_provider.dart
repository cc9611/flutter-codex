import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/auth_token_store.dart';

class AuthState {
  const AuthState({this.token});

  final String? token;

  bool get isLoggedIn => token != null && token!.isNotEmpty;
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState(token: AuthTokenStore.instance.token));

  void login(String token) {
    AuthTokenStore.instance.saveToken(token);
    state = AuthState(token: token);
  }

  void logout() {
    AuthTokenStore.instance.clear();
    state = const AuthState(token: null);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
