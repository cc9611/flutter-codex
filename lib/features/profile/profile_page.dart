import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_provider.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  static const String _businessUrl = 'https://example.com/profile';

  UserScript _tokenScript(String token) {
    final escapedToken = token.replaceAll("'", r"\'");
    return UserScript(
      source: '''
        (function() {
          localStorage.setItem('token', '$escapedToken');
          localStorage.setItem('native_token', '$escapedToken');
          window.__NATIVE_TOKEN__ = '$escapedToken';
        })();
      ''',
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final token = authState.token ?? '';

    return SafeArea(
      child: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(_businessUrl)),
        initialUserScripts: UnmodifiableListView<UserScript>([
          if (token.isNotEmpty) _tokenScript(token),
        ]),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          transparentBackground: false,
        ),
        onWebViewCreated: (controller) {
          controller.addJavaScriptHandler(
            handlerName: 'logout',
            callback: (args) {
              ref.read(authProvider.notifier).logout();
              return {'success': true};
            },
          );
        },
        onLoadStart: (_, __) {
          EasyLoading.show(status: '加载中...');
        },
        onProgressChanged: (_, progress) {
          final value = progress.clamp(0, 100) / 100;
          EasyLoading.showProgress(value, status: '加载中...');
        },
        onLoadStop: (controller, _) async {
          if (token.isNotEmpty) {
            final escapedToken = token.replaceAll("'", r"\'");
            await controller.evaluateJavascript(
              source: "localStorage.setItem('token', '$escapedToken');",
            );
          }
          EasyLoading.dismiss();
        },
        onReceivedError: (_, __, ___) {
          EasyLoading.dismiss();
        },
      ),
    );
  }

  @override
  void dispose() {
    EasyLoading.dismiss();
    super.dispose();
  }
}
