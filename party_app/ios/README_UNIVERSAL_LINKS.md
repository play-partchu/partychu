# iOS Universal Links 설정 — Mac에서 진행할 절차

이 문서는 Windows 환경(Mac/Xcode 없음)에서는 완료할 수 없는 부분을 정리한 것입니다.
서버 쪽(`https://partychu.co.kr/.well-known/apple-app-site-association`)과 Flutter
딥링크 처리 코드(`lib/services/deep_link_service.dart`)는 이미 준비·배포되어 있습니다.
남은 건 Xcode에서 앱에 Associated Domains 권한을 붙이고 실제 iPhone에서 서명·설치·
테스트하는 것뿐입니다.

## 0. 준비물

- 유료 Apple Developer 계정(연 $99, App Links 자체는 무료지만 Associated Domains
  엔타이틀먼트는 실기기 서명이 필요해 유료 계정이 있어야 합니다)
- Apple Developer 사이트 로그인 → **Membership** 메뉴에서 **Team ID**(10자리
  영문+숫자) 확인

## 1. Xcode에서 Associated Domains 추가

1. `ios/Runner.xcworkspace`를 Xcode로 엽니다(`.xcodeproj`가 아니라 반드시
   `.xcworkspace`).
2. 좌측 네비게이터에서 **Runner** 프로젝트 → **Runner** 타겟 선택.
3. 상단 탭에서 **Signing & Capabilities** 클릭.
4. "Automatically manage signing"을 켜고 **Team**을 본인 Apple Developer 팀으로
   선택합니다(이때 Team ID가 자동으로 채워집니다).
5. 좌측 상단의 **+ Capability** 버튼 클릭 → **Associated Domains** 검색 후 추가.
6. Associated Domains 항목에 아래 한 줄을 입력합니다.
   ```
   applinks:partychu.co.kr
   ```
7. Xcode가 자동으로 `ios/Runner/Runner.entitlements` 파일을 만들고 빌드 설정에
   연결합니다 — 이 파일이 없다고 직접 만들 필요 없이 이 과정만 하면 됩니다.

## 2. apple-app-site-association의 TEAMID 채우기

현재 `website/.well-known/apple-app-site-association`은 아래처럼 자리표시자로
되어 있습니다.

```json
{
  "applinks": {
    "apps": [],
    "details": [
      { "appID": "TEAMID.com.example.partyApp", "paths": ["/party/*"] }
    ]
  }
}
```

1번에서 확인한 실제 Team ID를 `TEAMID` 자리에 넣어 알려주시면(또는 직접
이 파일을 고쳐 `firebase deploy --only hosting:website`로 배포하시면) 됩니다.
**패키지명을 나중에 `kr.co.partychu.app`으로 바꾸면 `com.example.partyApp` 부분도
함께 바꿔야 합니다** — `PACKAGE_RENAME_CHECKLIST.md` 참고.

## 3. 빌드 및 실기기 설치

```
flutter build ios --release
```
또는 Xcode에서 실기기를 선택하고 ▶ 버튼으로 바로 실행해도 됩니다. **iOS
시뮬레이터에서는 Universal Links가 안정적으로 동작하지 않으니 반드시 실제
iPhone에서 테스트하세요.**

## 4. 테스트 방법 (중요 — 흔한 오해)

**Safari 주소창에 직접 입력하면 Universal Links가 동작하지 않습니다** —
애플이 의도적으로 막아둔 동작입니다(주소창 타이핑은 항상 웹으로 감). 반드시
**다른 앱에서 링크를 탭**해서 테스트해야 합니다:

- 메모(Notes) 앱에 `https://partychu.co.kr/party/{실제파티ID}`를 입력하고 탭
- 카카오톡/문자로 링크를 받아서 탭
- Safari에서도 **검색 결과나 다른 페이지 안의 링크**를 탭하는 건 됨(주소창
  직접 입력만 예외)

정상 동작 시: 앱이 설치되어 있으면 Safari를 거치지 않고 바로 PartyChu 앱이
열리며 해당 파티 상세 화면으로 이동합니다. 링크를 길게 눌렀을 때 메뉴에
"PartyChu 앱에서 열기" 같은 옵션이 보이면 Universal Links가 정상 등록된
것입니다.

## 5. 등록 확인 (안 될 때 디버깅)

Mac 터미널에서:
```
swcutil dl -d partychu.co.kr
```
이 명령으로 실제로 apple-app-site-association을 내려받아 파싱했는지 확인할
수 있습니다. 실패한다면:
- `https://partychu.co.kr/.well-known/apple-app-site-association`를 브라우저로
  직접 열어 JSON이 정상 응답되는지 확인(Content-Type이 `application/json`이어야
  함 — 이미 Firebase Hosting에 설정해뒀습니다)
- Xcode의 Associated Domains 항목이 정확히 `applinks:partychu.co.kr`인지
  (오타/`https://` 접두사 없이) 확인
- 앱을 한 번 지웠다가 다시 설치(재검증은 설치 시점에 한 번 일어남)

## 6. 문제 있으면

TEAMID를 알려주시거나, `swcutil` 결과/Xcode 콘솔 로그를 보여주시면 이어서
진단하겠습니다.
