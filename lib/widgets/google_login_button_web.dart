import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as gis;

/// 網頁版 Google 登入：Google Identity Services 官方按鈕。
/// 不用彈窗、不用轉址處理頁，iPhone/Safari 也可靠。
/// 按鈕由 Google 繪製；登入後拿 idToken 換 Firebase 憑證。

const _webClientId =
    '321894659059-37dheo53g2m7ocsbindla4jsi8tmu43g.apps.googleusercontent.com';

bool get gisSupported => true;

Future<void>? _initFuture;
bool _listening = false;

Future<void> _ensureInit() {
  _initFuture ??= GoogleSignIn.instance.initialize(clientId: _webClientId);
  if (!_listening) {
    _listening = true;
    GoogleSignIn.instance.authenticationEvents.listen((event) async {
      if (event is GoogleSignInAuthenticationEventSignIn) {
        final idToken = event.user.authentication.idToken;
        if (idToken != null) {
          // 換成 Firebase 登入（authStateChanges 會觸發自動同步）
          await FirebaseAuth.instance.signInWithCredential(
            GoogleAuthProvider.credential(idToken: idToken),
          );
        }
      }
    }, onError: (_) {});
  }
  return _initFuture!;
}

Widget googleLoginButton() => const _GisButton();

class _GisButton extends StatefulWidget {
  const _GisButton();

  @override
  State<_GisButton> createState() => _GisButtonState();
}

class _GisButtonState extends State<_GisButton> {
  late final Future<void> _ready = _ensureInit();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Google 登入初始化失敗：${snap.error}'),
          );
        }
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: gis.renderButton(),
        );
      },
    );
  }
}
