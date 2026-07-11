import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Firebase 專案設定（bible-app-c0eac）。
///
/// 目前只設定 **Web**（Render 部署用）。iOS/Android 之後在 Mac 上跑
/// `flutterfire configure` 產生完整版時，直接覆蓋這個檔案即可。
/// 這些值是公開的用戶端設定（非密鑰），存取安全由 Firestore 規則把關。
class DefaultFirebaseOptions {
  /// authDomain 用「目前網站自己的網域」：搭配 render.yaml 把 /__/auth/*
  /// 代理回 firebaseapp.com，登入全程同網域——iOS Safari 擋跨網域儲存
  /// 也不受影響（Firebase 官方建議做法）。
  /// 注意：該網域要加入 Firebase 授權網域，且要在 Google Cloud OAuth
  /// 用戶端加上 https://網域/__/auth/handler 為重新導向 URI。
  static FirebaseOptions get web => FirebaseOptions(
        apiKey: 'AIzaSyA4dw_HhBB6_qQ0MP5HfCAavlnHb2cNIoc',
        authDomain: kIsWeb && Uri.base.host.isNotEmpty
            ? Uri.base.host
            : 'bible-app-c0eac.firebaseapp.com',
        projectId: 'bible-app-c0eac',
        storageBucket: 'bible-app-c0eac.firebasestorage.app',
        messagingSenderId: '321894659059',
        appId: '1:321894659059:web:b0bc0b4374b5c4cc9bd886',
        measurementId: 'G-CRHXV0R3BT',
      );
}
