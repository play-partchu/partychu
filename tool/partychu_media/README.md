# 파티추 운영 미디어 원본

운영 콘텐츠에 실제로 적용하는 이미지의 **원본**을 모아 두는 곳이다.
받은 이미지는 여기에 저장한 뒤 이 파일로 R2에 올린다.
(`tool/demo_media*` 는 심사용 데모 콘텐츠 스크립트 전용이라 따로 둔다.)

## 폴더 — 화면 이름 기준

화면 이름과 Firestore 컬렉션 이름이 다르니 주의한다.

| 폴더 | 화면 | 컬렉션 |
| --- | --- | --- |
| `party/` | 파티 | `parties` |
| `place/` | 플레이스 | `events` |
| `event/` | 이벤트 | `placePromotions` |
| `rental/` | 장소대여 | `places` |
| `room/` | 장소대여 룸 | `placeRooms` |
| `partyshop/` | 파티샵 | `partyShops` |

## 파일명

```
{종류}-{콘텐츠이름}-{용도}.{ext}

partyshop-cakeshop-cover.png
party-hongdae-wine-gallery-1.jpg
place-gangnam-club-detail.jpg
```

- 종류: 폴더 이름과 같게
- 콘텐츠이름: 영문 소문자·숫자·하이픈, 알아보기 쉬운 짧은 이름
- 용도: `cover`(대표) · `gallery-N`(갤러리, 1부터) · `detail`(상세 본문) · `block-N`(상세 이미지 블록)
- 같은 자리를 다시 교체하면 뒤에 `-v2`, `-v3` 을 붙인다(이전 파일은 지우지 않는다)
- 확장자 `jpg` `jpeg` `png` `webp`

## 적용 절차

1. 받은 이미지를 위 규칙대로 이 폴더에 저장한다.
2. 대상 문서를 조회로 정확히 특정한다(모호하면 쓰기 전에 확인).
3. R2 업로드 — 앱·서버와 같은 키 규칙 `party_images/{hostId}/{epochMs}-{12hex}.{ext}`
   (`functions/mediaUploads.js` 의 `buildObjectKey`). 업로드 도구는
   `functions/scripts/demoContentRewrite.js` 가 export 하는 `r2Config`/`r2Request` 를 쓴다.
4. 운영 문서에 적용 — `restGet`/`restPatch`(같은 파일). `updateMask` 에 바꿀 필드만 넣는다.
5. 적용 후 다시 읽어서 바뀐 필드가 계획한 것뿐인지 확인한다.
6. 아래 "적용 기록"에 한 줄 추가한다.

지키는 것:

- 변경 전 백업·롤백 파일은 만들지 않는다.
- 기존 R2 이미지는 따로 요청이 없으면 지우지 않는다.
- 요청받은 문서의 미디어 필드만 바꾼다. 다른 필드·문서·컬렉션은 건드리지 않는다.
- 에뮬레이터·앱 테스트는 하지 않는다. 코드상 노출 경로만 확인하고 화면 확인은 요청자가 한다.

### 대표 이미지 교체 시

대표는 앱 전체에서 `getPartyCoverMedia`(`party_app/lib/utils/party_utils.dart`) 하나가 정한다.
목록 카드·상세·찜·내 호스트 허브·지도가 모두 이 함수를 쓴다.
`coverMediaType` 이 있으면 그 값을 따르고(`image` → `coverImageUrl`, `video` → `coverVideoUrl`),
없으면 첫 사진(사진이 없으면 동영상)이 대표다.

그래서 `mainImageUrl`·`images[0]` 만 바꾸면 안 된다. 문서의 cover 필드까지 앱이 사진을 대표로
지정할 때(`MediaUploadService.resolveCoverFields`)와 같은 값으로 맞춘다:

```
coverMediaType: 'image', coverImageUrl: <새 URL>, coverThumbnailUrl: <새 URL>,
coverVideoUid: null, coverVideoUrl: null
```

- 사진 목록(파티 `images`, 플레이스·장소대여 `imageUrls`, 파티샵 `mainImageUrl`+`introImageUrls`)에서
  기존 대표 사진 자리가 있으면 그 자리만 새 URL로 바꾼다(순서 유지).
- 대표가 동영상이었어도 동영상 필드(`videoUrl` 등)는 지우지 않는다. 상세 갤러리에 계속 남는다.
- `basicCardPhotoCrops` 는 URL을 키로 쓴다. 새 URL은 크롭 값이 없어 중앙 기준으로 보인다.

## 적용 기록

| 날짜 | 파일 | 대상 문서 | 바꾼 필드 | R2 URL |
| --- | --- | --- | --- | --- |
| 2026-09-18 | `partyshop/partyshop-cakeshop-cover.png` | `partyShops/b9P0ewJo4vKrtVg235ZX` (케익샵) | `mainImageUrl`, `coverMediaType`, `coverImageUrl`, `coverThumbnailUrl`, `coverVideoUid`, `coverVideoUrl` | `https://pub-c00f710b36c24bdbbea4bb02247c9c5b.r2.dev/party_images/ws3COMBLLXPlI4IyhLnwtGF1evS2/1789718682896-8edddf9b6974.png` |
| 2026-09-18 | `place/place-chicken-cover.png` | `events/FnM1hXKiO6jcTy9rdMqz` (파티츄 치킨집, 신규 생성) | `mainImageUrl`, `coverImageUrl`, `coverThumbnailUrl` (`coverMediaType: image`) | `https://pub-c00f710b36c24bdbbea4bb02247c9c5b.r2.dev/party_images/ws3COMBLLXPlI4IyhLnwtGF1evS2/1789725207876-b02a6b52bd2a.png` |
| 2026-09-18 | `event/event-chicken-sports-cover.png` | `placePromotions/pzL5357vq4tZ1FshkQCn` (파티츄 치킨집 축구·야구 대형스크린 응원전, 신규 생성) | `imageUrl`, `coverImageUrl`, `coverThumbnailUrl` (`coverMediaType: image`) | `https://pub-c00f710b36c24bdbbea4bb02247c9c5b.r2.dev/party_images/ws3COMBLLXPlI4IyhLnwtGF1evS2/1789725209578-67adc11f81af.png` |
| 2026-09-18 | `partyshop/partyshop-cakeshop-flower-cake.png` | `partyShops/b9P0ewJo4vKrtVg235ZX/products/8yKT2HQBLCVtXTcw4eXu` (생화케이크, 신규 생성) | `imageUrls[0]` | `https://pub-c00f710b36c24bdbbea4bb02247c9c5b.r2.dev/party_images/ws3COMBLLXPlI4IyhLnwtGF1evS2/1789728848354-e25f44088cce.png` |
| 2026-09-18 | `partyshop/partyshop-cakeshop-flower-2tier-cake.png` | `partyShops/b9P0ewJo4vKrtVg235ZX/products/AKMhOTgYDhthY1iKbfSx` (생화 2단 케이크, 신규 생성) | `imageUrls[0]` | `https://pub-c00f710b36c24bdbbea4bb02247c9c5b.r2.dev/party_images/ws3COMBLLXPlI4IyhLnwtGF1evS2/1789728849579-602b00c3f4c7.png` |
