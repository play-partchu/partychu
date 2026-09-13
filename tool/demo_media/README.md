# 데모용 가상 장소 이미지

`functions/scripts/demoContentRewrite.js` 가 여기서 파일을 읽어 R2에 올리고
문서의 이미지 URL을 갈아 끼운다.

## 명명 규칙

파일명은 드라이런이 만들어 주는 **슬러그**를 그대로 쓴다
(`functions/scripts/.demo-out/demo-plan.json` 의 `requiredFiles`).

```
party-01-cover.jpg        파티 대표
party-01-gallery-1.jpg    파티 갤러리 (1부터)
party-01-detail.jpg       파티 상세 본문 세로 이미지
party-01-block-1.jpg      파티 상세페이지 이미지 블록
place-01-cover.jpg        플레이스(events) 대표
place-01-gallery-1.jpg    플레이스 갤러리
rental-01-cover.jpg       장소대여(places) 대표
rental-01-gallery-1.jpg   장소대여 갤러리
room-01-1.jpg             장소대여 룸 사진
event-01-cover.jpg        이벤트(placePromotions) 대표
event-01-gallery-1.jpg    이벤트 갤러리
menu-01.jpg               플레이스 메뉴
product-01.jpg            플레이스 상품·이용권
```

- 확장자: `jpg` `jpeg` `png` `webp` (heic·gif는 넣지 말 것 — 심사 스크린샷에서
  깨지는 경우가 있다)
- 장당 20MB 미만. 실제로는 1~2MB 권장.
- **파일이 없는 슬롯은 기존 이미지를 그대로 둔다.** 조용히 빈 이미지가 되지
  않는다 — 드라이런이 `MISSING` 으로 알려 준다.
- 같은 `seriesId` 파티는 슬러그를 공유하므로 이미지도 한 벌만 준비하면 된다.

## 확인

```
cd functions
node scripts/demoContentRewrite.js --uid <UID> --with-media
```

`MISSING`(플랜이 원하는데 없는 파일)과 `EXTRA`(플랜에 없는 파일)를 표로 보여준다.

## 주의

실제 업체 사진을 넣지 말 것. 이 폴더의 목적은 그 반대다.
