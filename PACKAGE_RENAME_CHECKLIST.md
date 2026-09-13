# 패키지명 전환 (`com.example.party_app` → `kr.co.partychu.app`)

Android 전환은 **완료**되었습니다. 아래에 코드로 끝난 것과, 사람이 콘솔에서
해야 남은 것을 나눠 적습니다. iOS는 아직 `com.example.partyApp` 그대로입니다.

## 완료 — Android

- **Firebase Android 앱 신규 등록**
  `kr.co.partychu.app` / App ID `1:494588817221:android:4af49b9d5f39c069df182c`.
  기존 `com.example.party_app` 앱은 지우지 않고 그대로 뒀습니다 — 구 패키지를
  깔아둔 기기가 남아 있을 수 있고, 지워도 되돌릴 수 없기 때문입니다.
- `android/app/google-services.json` 교체. Firebase가 프로젝트의 두 Android
  앱을 함께 내려주므로 **구 패키지 항목이 파일 안에 같이 들어 있는 게 정상**
  입니다. Gradle은 `applicationId`와 일치하는 client 블록만 골라 씁니다.
- `android/app/build.gradle.kts` — `namespace`, `applicationId` 변경.
  Flutter 템플릿이 남긴 `// TODO: Specify your own unique Application ID`
  주석도 함께 제거했습니다.
- Kotlin 패키지 이동:
  `android/app/src/main/kotlin/com/example/party_app/MainActivity.kt`
  → `.../kr/co/partychu/app/MainActivity.kt`, `package` 선언 변경.
- `lib/firebase_options.dart` — `android` 블록의 `appId`를 새 앱 값으로.
  `apiKey`·`messagingSenderId`·`projectId`는 프로젝트 단위라 그대로입니다.
- `lib/services/map_directions_service.dart` — 네이버 길찾기 호출자 식별용
  폴백 상수 `_kFallbackAndroidAppId`. 평소에는 실행 중인 앱에서 직접 읽지만,
  그 조회가 실패하면 이 값이 쓰이므로 같이 바꿔야 합니다.
- `website/.well-known/assetlinks.json` — `package_name` 변경.
  `sha256_cert_fingerprints`는 **서명 키 기준이라 패키지명이 바뀌어도 그대로**
  입니다.

`AndroidManifest.xml`은 수정하지 않았습니다 — 액티비티를 `.MainActivity`로
상대 참조하므로 `namespace`를 따라가고, 카카오 리다이렉트 스킴은 네이티브 앱
키에서 나오는 값이라 패키지명과 무관합니다.

## 남은 작업 — 사람이 콘솔에서 해야 함

- **Firebase에 릴리즈 서명 SHA 등록 (B-2)**
  새로 만든 Android 앱에는 인증서 지문이 하나도 등록돼 있지 않습니다. 등록
  전까지 **Google 로그인이 동작하지 않습니다.** 업로드 키와 Play 앱 서명 키의
  SHA-1을 모두 넣어야 합니다.
- **카카오 개발자 콘솔** — Android 플랫폼의 패키지명을 `kr.co.partychu.app`으로
  변경하고 키 해시를 다시 등록.
- **네이버 개발자 콘솔** — 안드로이드 앱 패키지명 변경.
- **`website/` 재배포** — assetlinks.json이 반영돼야 App Links가 다시 검증
  됩니다. `firebase deploy --only hosting:website`.
  배포 후 앱을 삭제·재설치해야 OS가 도메인 소유권을 다시 확인합니다.
- **App Links 재검증**
  ```
  adb shell pm get-app-links kr.co.partychu.app
  ```
  `partychu.co.kr: verified`가 뜨는지 확인.

## 아직 안 한 것 — iOS

iOS Bundle ID는 `com.example.partyApp` 그대로입니다. App Store에 내려면 Android와
같은 이유로 바꿔야 하고, 그때 함께 해야 하는 것들:

- Xcode Runner 타겟 > General > Bundle Identifier → `kr.co.partychu.app`
- Firebase iOS 앱 신규 등록 → `GoogleService-Info.plist` 교체
  (이 파일은 저장소에 없습니다 — 별도로 관리 중)
- `lib/firebase_options.dart`의 `ios`/`macos` 블록 `appId`·`iosBundleId`
- `website/.well-known/apple-app-site-association`의 `appID`를
  `TEAMID.kr.co.partychu.app`으로 (`ios/README_UNIVERSAL_LINKS.md` 참고)
- `lib/services/map_directions_service.dart`의 `_kFallbackIosBundleId`
- `macos/Runner/Configs/AppInfo.xcconfig`
