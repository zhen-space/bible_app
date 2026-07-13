import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Firebase 專案設定（bible-app-c0eac）。
///
/// 目前只設定 **Web**（Render 部署用）。iOS/Android 之後在 Mac 上跑
/// `flutterfire configure` 產生完整版時，直接覆蓋這個檔案即可。
/// 這些值是公開的用戶端設定（非密鑰），存取安全由 Firestore 規則把關。
///
/// 登入採 Google Identity Services（google_sign_in_web）token 流程：
/// 直接拿 idToken 換 Firebase 憑證，不經過 __/auth/handler，也不依賴
/// authDomain 跨網域儲存——這是 iOS Safari 最可靠的方式。authDomain 用
/// 預設 firebaseapp.com 即可。
class DefaultFirebaseOptions {
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA4dw_HhBB6_qQ0MP5HfCAavlnHb2cNIoc',
    authDomain: 'bible-app-c0eac.firebaseapp.com',
    projectId: 'bible-app-c0eac',
    storageBucket: 'bible-app-c0eac.firebasestorage.app',
    messagingSenderId: '321894659059',
    appId: '1:321894659059:web:b0bc0b4374b5c4cc9bd886',
    measurementId: 'G-CRHXV0R3BT',
  );
}
