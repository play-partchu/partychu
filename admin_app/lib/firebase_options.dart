// party_app/lib/firebase_options.dart(FlutterFire CLI 생성분)의 web 설정을
// 그대로 가져온 것 — admin_app은 웹 전용이라 다른 플랫폼 블록은 두지 않는다.
// 같은 Firebase 프로젝트(partychu-30c24)를 공유한다.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => web;

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBW-MoTttcXT7ge8bo3wNpeXoHzjSrlM5Y',
    appId: '1:494588817221:web:e09942e141a6f1e1df182c',
    messagingSenderId: '494588817221',
    projectId: 'partychu-30c24',
    authDomain: 'partychu-30c24.firebaseapp.com',
    storageBucket: 'partychu-30c24.firebasestorage.app',
    measurementId: 'G-3J6CZ02T7Y',
  );
}
