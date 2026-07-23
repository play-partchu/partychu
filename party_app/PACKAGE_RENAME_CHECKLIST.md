# 출시 전 패키지명 전환 체크리스트 (`com.example.party_app` → `kr.co.partychu.app`)

App Links는 지금 패키지명(`com.example.party_app`)을 기준으로 이미 완성·검증되어
있습니다. 아래는 나중에 `kr.co.partychu.app`(iOS는 동일한 `kr.co.partychu.app`을
Bundle ID로 권장)으로 정식 전환할 때 빠짐없이 해야 할 작업 목록입니다. 이 작업은
Firebase 연결이 끊길 위험이 있어 이번 세션에서는 진행하지 않았습니다.

## 1. Firebase 앱 재등록

- Firebase 콘솔 > 프로젝트 설정 > 내 앱 에서 Android/iOS 앱을 **새 패키지명으로
  새로 추가**합니다(기존 앱은 지우지 말고 그대로 둬도 무방).
- Android: 새 `google-services.json` 다운로드 → `android/app/google-services.json`
  교체.
- iOS: 새 `GoogleService-Info.plist` 다운로드 → Xcode에서 교체(기존 파일 참조
  제거 후 새 파일을 Runner 타겟에 추가).
- `flutterfire configure` 명령을 다시 실행하면 `lib/firebase_options.dart`의
  android/ios 블록(appId 등)을 자동으로 갱신해줍니다(권장) — 수동으로 고칠 거면
  `firebase_options.dart`의 `android`/`ios`/`macos` `FirebaseOptions`의 `appId`
  값을 새로 등록된 앱의 값으로 바꿔야 합니다.

## 2. Android

- `android/app/build.gradle.kts`의 `applicationId`와 `namespace`를
  `kr.co.partychu.app`으로 변경.
- Kotlin 패키지 디렉터리 이동: `android/app/src/main/kotlin/com/example/party_app/`
  → `android/app/src/main/kotlin/kr/co/partychu/app/`, `MainActivity.kt` 안의
  `package` 선언도 함께 변경.
- `android/app/src/main/AndroidManifest.xml`은 패키지명을 직접 참조하지 않아
  수정 불필요(App Links intent-filter 등 그대로 유지됨).

## 3. iOS

- Xcode에서 Runner 타겟 > General > **Bundle Identifier**를
  `kr.co.partychu.app`으로 변경.
- `ios/Runner/Info.plist`의 `CFBundleURLTypes` > `CFBundleURLName`도
  `kr.co.partychu.app`로 이미 맞춰뒀습니다(변경 불필요).

## 4. App Links / Universal Links 파일 갱신 (필수 — 안 하면 딥링크가 깨짐)

- `website/.well-known/assetlinks.json`의 `package_name`을
  `kr.co.partychu.app`으로 변경. `sha256_cert_fingerprints`는 **서명 키를
  그대로 쓴다면 안 바꿔도 됩니다**(SHA256은 서명 키 기준이지 패키지명 기준이
  아님) — 단, 배포 전 릴리즈 키를 새로 만든다면 그 키의 SHA256으로 다시
  갱신해야 합니다.
- `website/.well-known/apple-app-site-association`의 `appID`을
  `TEAMID.kr.co.partychu.app`으로 변경(TEAMID는 실제 Apple Team ID로 이미
  채워져 있어야 함 — `ios/README_UNIVERSAL_LINKS.md` 참고).
- 변경 후 반드시 재배포: `firebase deploy --only hosting:website`
- 앱을 한 번 삭제 후 재설치해야 OS가 새 패키지명 기준으로 도메인 소유권을
  다시 검증합니다.

## 5. 재검증

```
adb shell pm get-app-links kr.co.partychu.app
```
`partychu.co.kr: verified`가 다시 뜨는지 확인하세요(이번 세션에서
`com.example.party_app` 기준으로 확인했던 것과 동일한 절차).
