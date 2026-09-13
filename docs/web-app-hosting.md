# 앱을 홈페이지 안에서 (partychu.co.kr/app/)

출시 전이라 홈페이지용 등록 시스템을 새로 만들지 않는다. **party_app(Flutter Web)을
그대로** `/app/` 아래에 올려서, 앱과 같은 화면·같은 Firestore 문서·같은 rules·같은
Functions·같은 본인인증·같은 등록 제한·같은 임시저장을 쓴다.

## 배포 절차

```bash
bash tool/build-web-app.sh          # flutter build web --base-href /app/ → website/app/
firebase deploy --only hosting:website
```

`website/app/` 은 빌드 산출물이라 git에 넣지 않는다(`website/.gitignore`).
**배포 전에 스크립트를 돌리지 않으면 /app/ 이 낡은 채로 올라간다.**

## 왜 이 구조인가

한 도메인에는 Hosting 타깃을 하나만 붙일 수 있다. 별도 서브도메인을 만들지 않기로
했으므로, 앱 빌드를 홈페이지 타깃(`website`) 안의 `app/` 폴더로 **넣어서** 함께
올린다. 기존 정적 홈페이지·약관·개인정보·환불·계정삭제·`.well-known`·`/party/**`
랜딩 함수 rewrite는 그대로 남는다.

`firebase.json`에서 이 구조가 기대는 것은 두 줄뿐이다.

* rewrite `/app/** → /app/index.html`
  실제 파일이 있으면 파일이 우선이므로 `main.dart.js`·`canvaskit/`은 그대로 나가고,
  파일이 없는 앱 내부 경로(새로고침·직접 진입)만 index.html로 간다.
* ignore 예외 `!app/assets/.env`
  ignore의 `**/.*` 가 점으로 시작하는 파일을 전부 거르는데, Flutter가 `.env`를
  `assets/.env` 로 넣는다. 이 예외가 없으면 **배포본에서만** .env가 빠진다.
  (2차 방어로 `main.dart`가 .env 읽기 실패를 치명적으로 다루지 않는다.)

## 진입점

랜딩페이지 → 앱으로 넘길 때 쿼리로 지정한다.

| 주소 | 홈페이지 버튼 | 결과 |
| --- | --- | --- |
| `/app/` | (직접 진입) | 앱 첫 화면(파티·이벤트) |
| `/app/?tab=party` | 파티 찾기 | 상단탭 0 — 파티츄/이벤트 |
| `/app/?tab=venue` | 플레이스 | 상단탭 1 |
| `/app/?tab=place` | 장소대여 | 상단탭 2 |
| `/app/?tab=crew` | 파트너·파티크루 | 상단탭 3 |
| `/app/?register=1` | 등록하기 / 공간 등록하기 | 하단탭 '등록'(로그인 → 등록 종류 선택) |
| `/app/?login=1` | 로그인 | 비로그인이면 로그인 화면, 로그인 상태면 마이페이지 |
| `/app/?mypage=1` | 마이페이지 | 하단탭 '마이'(비로그인이면 로그인부터) |

`tab=` 대신 `?tab=register` `?tab=login` `?tab=mypage` 로도 같은 곳으로 간다.

셋 다 결국 `MainScreen._onBottomNavTap()`을 부른다 — 홈페이지에서 들어온 사람과
앱에서 하단탭을 누른 사람이 **완전히 같은 코드**를 지난다. 로그인 요구도,
본인확인 게이트도, 등록 안내 시트도 웹용으로 따로 만들지 않는다.

`/party/register`(옛 JS 등록 폼)는 `/app/?register=1` 로 보내는 표지판만 남았다 —
외부에 공유된 주소가 죽지 않게 파일 자체는 남겨 둔다.

## 홈페이지는 무엇을 갖고 무엇을 갖지 않는가

`website/`의 정적 페이지는 **소개와 진입점만** 갖는다.

* 남는 것 — 서비스 소개, 이용 방법, 앱 스크린샷, 고객센터, 약관·개인정보·환불·
  계정삭제, `.well-known`, `js/script.js`(모바일 메뉴 토글·연도 표시) 하나.
* 사라진 것 — `js/party-list.js` `party-format.js` `video-player.js`
  `party-register.js` `auth.js` `firebase-init.js`, `css/register.css`.
  홈페이지가 Firestore를 직접 읽고 쓰던 경로는 이제 **하나도 없다.**

왜 지웠나: 같은 기능을 두 벌 들고 있으면 규약이 조용히 갈라진다. 실제로
홈페이지 JS는 `favorites.createdAt`을 ISO 문자열로 저장했는데 앱은
`serverTimestamp()`를 쓴다 — 같은 컬렉션에 타입이 둘 섞였고, 마이페이지의
관심 목록은 `orderBy('createdAt')`으로 읽는다(Firestore 타입 정렬에서 문자열이
타임스탬프보다 뒤라, 내림차순이면 옛 문자열 문서가 목록 맨 위로 올라온다).
그리고 홈페이지의 "참가 신청" 버튼은 끝내 `alert('앱에서 신청해주세요')`였다.

> 이 쿼리는 **`runApp` 전에** `WebLaunchUrl.capture()`가 붙잡는다. Flutter가 경로
> 기반 URL 전략으로 첫 라우트를 세우면서 주소를 base href(`/app/`)로 덮어써
> 쿼리스트링이 사라지기 때문이다. 화면에서 `Uri.base`를 읽으면 이미 비어 있다.

## ⚠️ 아직 남은 외부 설정 — R2 버킷 CORS

**이걸 하기 전까지 웹에서 사진 업로드가 되지 않고, 이미 올라간 사진도 제대로 보이지
않는다.** 코드 문제가 아니라 Cloudflare 쪽 설정이다.

지금 상태(확인함):

```
$ curl -I -H "Origin: https://partychu.co.kr" https://pub-....r2.dev/party_images/...
HTTP/1.1 200 OK          ← Access-Control-Allow-Origin 없음

$ curl -X OPTIONS -H "Origin: https://partychu.co.kr" \
       -H "Access-Control-Request-Method: PUT" https://pub-....r2.dev/...
HTTP/1.1 403 Forbidden   ← preflight 거부
```

* **업로드**: 앱은 서버(`createUploadUrl`)가 발급한 presigned URL로
  `{accountId}.r2.cloudflarestorage.com` 에 PUT한다. 브라우저는 그 전에 preflight를
  보내는데 지금은 403이라 업로드가 시작조차 못 한다.
* **표시**: 공개 URL(`pub-*.r2.dev`)에 CORS 헤더가 없어 CanvasKit이 이미지를
  가져오지 못한다(일부만 `<img>` 폴백으로 보인다).

Cloudflare 대시보드 → R2 → 해당 버킷 → Settings → CORS Policy 에 넣을 값:

```json
[
  {
    "AllowedOrigins": ["https://partychu.co.kr"],
    "AllowedMethods": ["GET", "PUT", "HEAD"],
    "AllowedHeaders": ["content-type", "content-length"],
    "ExposeHeaders": ["etag"],
    "MaxAgeSeconds": 3600
  }
]
```

자격증명·업로드 정책(허용 폴더/크기/형식)은 건드리지 않는다 — 이 설정은
"어느 출처의 브라우저가 말을 걸 수 있는가"만 정한다.

동영상(Cloudflare Stream direct creator upload)은 브라우저 업로드를 전제로 만든
엔드포인트라 별도 설정이 필요 없다.
