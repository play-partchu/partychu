// admin_app Firebase 설정 — 같은 Firebase 프로젝트(partychu-30c24)를 공유한다.
//
//   web     party_app/lib/firebase_options.dart(FlutterFire CLI 생성분)의 web
//           설정을 그대로 가져온 것(관리자 웹 Hosting)
//   android 관리자 전용 Android 앱 "PartyChu Admin"(kr.co.partychu.admin) —
//           사용자 앱(kr.co.partychu.app)과 다른 Firebase 앱이다.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    if (defaultTargetPlatform == TargetPlatform.android) return android;
    throw UnsupportedError('관리자 앱은 웹과 Android만 지원합니다.');
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBW-MoTttcXT7ge8bo3wNpeXoHzjSrlM5Y',
    appId: '1:494588817221:web:e09942e141a6f1e1df182c',
    messagingSenderId: '494588817221',
    projectId: 'partychu-30c24',
    authDomain: 'partychu-30c24.firebaseapp.com',
    storageBucket: 'partychu-30c24.firebasestorage.app',
    measurementId: 'G-3J6CZ02T7Y',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCOeBA3K6T_PQF56xirshTalwGpdsHxdpY',
    appId: '1:494588817221:android:cfbfb0c0c762a7c1df182c',
    messagingSenderId: '494588817221',
    projectId: 'partychu-30c24',
    storageBucket: 'partychu-30c24.firebasestorage.app',
  );
}
