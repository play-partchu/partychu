# 파티츄 통합 QR 체크인 계약

호스트에게 **스캐너는 하나뿐**이다. 손님이 내미는 QR이 파티 참가권인지 예약인지
상품 이용권인지 미리 알 필요가 없다 — 종류 판별·권한 검증·정보 조합을 전부
서버가 한다.

이 문서는 그 구조를 정리한 **개발 문서**다. 현재 구현을 설명할 뿐 새 동작을
정의하지 않는다 — 문서와 코드가 어긋나면 **코드가 정본**이고, 이 문서를 고쳐야 한다.

각 절 끝의 `정본:` 이 그 정책이 실제로 구현된 파일이다.

> 결제 구조 전반은 [payment_architecture.md](payment_architecture.md) 참고.

---

## 0. 두 가지 원칙

### 스캔(resolve)과 사용(consume)은 다른 호출이다

```
QR 스캔 → resolveCheckInToken   (조회만, 상태 안 바뀜)
        → 호스트가 눈으로 확인
        → consumeCheckIn        (여기서만 상태가 바뀐다)
```

다른 날짜 QR을 잘못 찍거나 손님이 화면을 잘못 열었을 수 있다. 조회는 몇 번을
해도 아무것도 변하지 않는다. 이 분리는 타협하지 않는다.

정본: `functions/checkInTokens.js` (`resolveCheckInToken` / `consumeCheckIn`),
`party_app/lib/services/check_in_service.dart`

### QR 문자열에는 개인정보를 넣지 않는다

QR에 담기는 값은 **난수 토큰 하나**뿐이다. 이름도 예약번호도 파티 id도 넣지
않는다. QR 이미지가 유출돼도 그 자체로는 아무 정보가 아니고, 호스트가 아닌
사람이 서버에 물어봐도 권한 검사에서 막힌다.

정본: `functions/checkInTokenStore.js` (`newToken`),
`party_app/lib/widgets/check_in_qr_card.dart` (`data: p.token` 하나뿐 — 테스트가 고정)

---

## 1. 발급 조건

트리거가 **문서의 최종 상태만** 보고 판단한다. 어떤 콜러블을 거쳐 그 상태가
됐는지는 보지 않는다 — 승인 경로가 넷, 취소 경로는 그보다 많아서 콜러블마다
붙이면 반드시 하나를 빠뜨린다.

| 도메인 | 컬렉션 | 발급 조건 | 무효화 조건 |
|---|---|---|---|
| 파티 신청 | `parties/{id}/applications/{id}` | `status ∈ {approved, applied}` | 그 밖의 상태(`pending`·`rejected`·`cancelled`·`no_show`) 또는 문서 삭제 |
| 플레이스 방문예약 | `placeVisitReservations` | `status == approved` | 그 밖 또는 삭제 |
| 장소대여 예약 | `placeReservationGroups` | `status == confirmed` | 그 밖 또는 삭제 |
| 숙박+파티 콤보 | `packageBookings` | `status == confirmed` | 그 밖 또는 삭제 |
| 상품 주문 | `placeProductOrders` | `useQrCheck == true` **및** `payment.method == on_site` **및** `status ∉ {cancelled, refunded, expired}` | 취소·환불·만료 또는 삭제 |

- `applied`가 파티 발급 조건에 들어 있는 이유: **즉시확정 파티에는 승인 단계가
  없다.** 접수가 곧 자리 확정이라 `approved`가 되지 않으므로, 여기서 빼면 그
  파티 참가자는 QR을 영영 못 받는다.
- 상품의 `used`는 **살려 둔다.** 죽이면 다시 찍었을 때 "이미 사용한 이용권"이
  아니라 "없는 QR"로 보여서 호스트가 무슨 일이 있었는지 알 수 없다.
- 무통장입금 상품 주문에는 `checkInToken`을 발급하지 않는다 → 5절.

정본: `functions/checkInRules.js`
(`PARTY_QR_STATUSES` · `partyQrActive` / `RESERVATION_QR_STATUS` ·
`reservationQrActive` / `PRODUCT_QR_DEAD_STATUSES` · `productQrActive`)
트리거: `functions/partyCheckIn.js` · `reservationCheckIn.js` · `productCheckIn.js`

### 원본 1건당 활성 토큰은 최대 1개

트리거는 재실행된다. 같은 승인이 두 번 들어와 토큰이 두 개가 되면, 손님 화면에는
하나가 뜨는데 다른 하나도 서버에서 통과한다 — **취소한 QR로 입장하는 길**이
열린다. 그래서 원본 경로마다 포인터 문서를 둔다.

```
checkInTokenIndex/{sha256(refPath)}  → { token, domain, refPath }
checkInTokens/{token}                → { domain, refPath, hostId, guestUid, active }
```

포인터 id가 refPath에서 결정되므로 조회에 색인도 쿼리도 필요 없고, 트랜잭션
하나로 "이미 있으면 그대로, 없으면 새로"가 성립한다(멱등).

정본: `functions/checkInTokenStore.js` (`tokenIndexKey` · `issueCheckInToken`)

### 재승인 시 옛 QR을 살리지 않고 새 토큰을 발급한다

무효화된 토큰은 `active: false`로 **영구히** 죽는다. 취소됐다가 다시 승인되면
새 난수가 발급되고 포인터가 그쪽을 가리킨다.

되살리지 않는 이유: 취소 기간에 퍼진 QR 캡처본이 함께 살아난다. 새 토큰을 쓰면
어느 순간에도 살아 있는 토큰은 0개 아니면 1개다.

토큰 문서를 **지우지는 않는다.** 지우면 그 QR을 다시 찍었을 때 "없는 QR"이 되어
손님도 호스트도 무슨 일이 있었는지 모른다. 죽은 채로 남겨 두면 조회가
"더 이상 사용할 수 없는 QR"이라고 분명히 답할 수 있고 감사 기록도 남는다.

정본: `functions/checkInTokenStore.js` (`revokeCheckInTokenFor` · `isTokenActive`)

### 게스트가 자기 QR을 받는 경로

게스트는 `checkInTokens` / `checkInTokenIndex`를 **읽을 수 없다.** 자기 QR을 받는
유일한 경로는 **자기 신청·예약·주문 문서의 `checkInToken` 필드**이고, 그 문서는
본인·호스트·관리자만 읽을 수 있으며 클라이언트 쓰기는 막혀 있다.

정본: `firestore.rules` (`checkInTokens` · `checkInTokenIndex` 전면 차단),
`functions/checkInTokenStore.js` (`TOKEN_FIELD` · `syncTokenField`)

---

## 2. 조회(resolve) 조건

| 조건 | 결과 |
|---|---|
| 토큰이 없음 | `등록되지 않은 QR이에요.` |
| 토큰이 죽음(`active: false`) | `더 이상 사용할 수 없는 QR이에요.` |
| 요청자가 **원본 문서의 호스트가 아님** | `이 QR을 확인할 권한이 없어요.` |
| 그 밖 | 신원 + 이용 정보 전체 |

세 실패는 **사유 문장만 다르고 모양이 같다** — `guest: null`이고 `title`·`atMs`·
`paymentAmount`·`detail` 키가 아예 없다. 구분해서 알려 주면 남의 QR을 주운 사람이
그 차이만으로 무언가를 알게 된다. 게스트 본인이 자기 토큰을 넣어도 신원은 오지
않는다(호스트만 조회할 수 있다).

권한은 **원본 문서의 `hostId`**로 본다. 토큰 문서에 적힌 값을 믿으면 콘솔에서
손댄 토큰 하나로 남의 이용을 열어볼 수 있다.

차단된 건도 **조회는 된다.** 결제 전이거나 날짜가 다른 QR도 정보는 보여주고
차단 사유를 함께 내려보낸다 — 호스트가 현장에서 상황을 알아야 하기 때문이다.

호스트에게 실리는 신원은 파티 신청자 목록과 **같은 정본**이다: 본인확인을 마친
계정의 실명·성별·생년월일뿐이고 **전화번호·CI는 애초에 들어 있지 않다.** 만
나이는 서버가 계산하지 않고 화면이 생년월일로 그린다(해가 바뀌면 저장값이 틀린다).

정본: `functions/checkInTokens.js` (`locate` · `open` · `resolveCheckInToken`),
`functions/checkInRules.js` (`emptyCheckInResult` · `buildCheckInResult`),
`functions/applicantIdentity.js` (`buildApplicantIdentity`)

---

## 3. 사용(consume) 조건

조회 조건을 통과하고 + 아직 처리되지 않았고 + 차단 사유가 없을 때만.

**공통** — 결제 미완이면 막는다. `bank_transfer` 미입금(`awaiting_deposit` ·
`deposit_pending`), `on_site` 미확인(`on_site_scheduled`). 결제 정보가 없는 건
(무료·옛 PG)은 이 축에서 막지 않는다.

| 도메인 | 추가 차단 사유 |
|---|---|
| 파티 | 취소·거절·노쇼·승인 대기 / **오늘 파티가 아님** |
| 예약 | 거절·만료·취소·승인 대기·결제 미완 / **예약일이 아님** |
| 상품 | 이미 사용·취소·환불·만료·결제 미완 / 이용 기간 밖 / 날짜 지정 상품인데 그날이 아님 |

판정은 **트랜잭션 안에서 한 번 더** 한다. 같은 QR을 두 기기에서 동시에 들이대도
한 번만 통과한다(바깥의 검사는 빨리 알려주기 위한 것이다).

원본 문서가 취소됐는데 토큰만 살아 있는 상황에서도 안전하다 — 조회·사용은
토큰의 `active`만 믿지 않고 **원본 문서 상태를 매번 다시 읽어** 판정한다.

### 상태 전이

| 도메인 | consume이 바꾸는 것 |
|---|---|
| 파티 | `checkedInAt` · `checkedInBy`만. **`status`는 건드리지 않는다** |
| 예약 | `checkedInAt` · `checkedInBy`만. 예약 진행 상태는 그대로 |
| 상품 | `status: usable → used` + `usedAt` · `usedBy` |

파티·예약이 `status`를 바꾸지 않는 이유: 승인 상태와 출석은 다른 축이다. 섞으면
승인 통계가 출석과 뒤엉키고, 되돌리기가 "무슨 상태로" 돌아갈지 알 수 없어진다.
상품만 예외인 것은 재고·매출이 `status`에 걸려 있어서다.

**현장 출석의 정본은 `checkedInAt`이다.** 신청 상태 `attended`는 레거시이고 새로
쓰는 코드가 없다(옛 문서 호환으로만 남아 있다).

정본: `functions/checkInRules.js`
(`paymentBlockReason` · `partyBlockReason` · `reservationBlockReason` · `voucherBlockReason`),
`functions/checkInTokens.js` (`CONSUMERS` · `consumeCheckIn`),
`functions/partyCheckIn.js` (`attendanceDelta` 기반 출석 집계)

---

## 4. KST 날짜 판정

서버는 UTC로 돈다. 9시간을 더한 뒤 **UTC 게터로** 읽는다 — 로컬 타임존에
의존하면 배포 지역이 바뀌는 순간 하루가 어긋난다.

| 대상 | 판정 |
|---|---|
| 파티 | 파티 시작이 **오늘(KST)** 인가 — 하루 단위 |
| 방문예약 | 방문 시각이 오늘(KST)인가 |
| 숙박·장소대여 | **체크인~체크아웃 구간** 안인가(시작·종료가 다르면 구간, 같으면 하루) |
| 날짜 지정 상품 | 이용 예정일이 오늘(KST)인가 |
| 기간제 상품 | `useStartAt` ~ `useEndAt` 구간(분 단위) |

하루 단위로 비교하는 이유: 분 단위로 막으면 조금 일찍 온 손님을 돌려보내게
되고, 그건 현장에서 호스트가 판단할 몫이다.

출석 통계의 `dailyStats`는 **체크인한 날**의 문서를 증감한다. 되돌리기가 자정을
넘겨도 늘렸던 날의 칸을 줄인다 — 되돌린 날을 깎으면 엉뚱한 날짜가 틀어진다.

정본: `functions/kstTime.js` (`kstDateStr` · `isSameKstDay`),
`functions/partyCheckIn.js` (`dateKeyOfCheckIn`)

---

## 5. 되돌리기(revoke) 범위

| 조건 | 값 |
|---|---|
| 대상 | 파티 · 예약만 |
| 권한 | **호스트만** |
| 기한 | **체크인한 날(KST) 안에서만** |
| 이용권 | **불가** |

- 왜 필요한가: 줄이 길 때 옆 사람 QR을 먼저 찍는 실수가 실제로 난다. 되돌릴 수
  없으면 손님은 입장했는데 기록은 다른 사람에게 남는다.
- 게스트는 못 한다 — 스스로 체크인을 지울 수 있으면 기록이 무의미해진다.
- 다음 날 되돌리기는 실수 정정이 아니라 기록 수정이다. 사람이 개입할 일이지
  버튼이 할 일이 아니다.
- 이용권은 `used → usable`로 돌리면 이미 내준 상품을 다시 쓸 수 있게 되고
  재고·매출과 얽힌다. 잘못 판 건은 주문 취소(`cancelProductOrder`)가 따로 있다.

되돌리면 출석 통계가 정확히 역반영되고(`+1 → -1`), **같은 QR로 다시 체크인할 수
있다**. 되돌린 사실도 감사 기록에 남는다(`checkInTokens/{token}/events`,
`userActivityLogs`의 `party_check_in_revoked`).

정본: `functions/checkInTokens.js` (`revokeCheckIn` · `REVOKE_SAME_DAY_ONLY`),
`functions/partyCheckIn.js` (출석 역반영)

---

## 6. 도메인별 토큰 종류

| 도메인 | QR에 실리는 값 |
|---|---|
| 파티 · 예약 3종 | `checkInToken` 하나 |
| 상품 — 현장결제 | `checkInToken`(주문 생성 시) + `voucherCode`(결제 확인 시). **QR 값은 언제나 `checkInToken`** |
| 상품 — 무통장입금 | `voucherCode` 하나(결제 확인 후) |
| 상품 — 옛 주문 | `voucherCode` 하나 |

### `checkInToken`은 결제 증명이 아니다

|  | `checkInToken` | `voucherCode` |
|---|---|---|
| 뜻 | 이 이용 건을 **안전하게 조회**하기 위한 QR 식별자 | **돈이 들어왔고 쓸 수 있다**는 이용권 코드 |
| 결제 증명인가 | ❌ | ✅ |
| 발급 시점 | 발급 조건 충족 시(현장결제는 결제 **전**) | 결제가 확인된 시점에만 |
| 발급 지점 | `checkInTokenStore.issueCheckInToken` | `voucherIssue.issueVoucherPatch` |
| 개수 보장 | 원본 1건당 활성 1개(포인터로 강제) | 주문당 1개 |
| 재발급 | 무효화 후 재승인 시 **새 값** | 없음 |

**두 값의 역할을 섞지 않는다.** `checkInToken`을 결제 증명처럼 다루면 결제 없이
통과하는 길이 열린다 — 조회가 열린 것이지 사용이 열린 것이 아니다.

### 현장결제 상품이 결제 전에 QR을 갖는 이유

현장결제는 "손님이 와서 QR을 보여주고 → 호스트가 누가 무엇을 사러 왔는지 확인하고
→ 돈을 받고 → 사용 처리"가 한 흐름이다. QR이 없으면 그 첫 걸음이 성립하지 않는다.

QR 값이 `checkInToken`이라 **결제 전후로 바뀌지 않는다.** 호스트가 스캔하고,
결제를 확인하고(`confirmCheckInPayment`), 같은 화면에서 다시 조회해 사용
처리까지 가는 동안 손님은 화면을 새로 열 필요가 없다.

정본: `functions/productCheckIn.js`, `functions/checkInRules.js` (`productQrActive`),
`party_app/lib/widgets/place_product/voucher_qr_dialog.dart` (`voucherPass`)

### 무통장입금 상품은 그대로 `voucherCode`

입금 대기 주문에는 `checkInToken`을 만들지 않는다. 입금은 현장이 아니라 계좌에서
확인되므로 사전 스캔이 필요 없고, **"입금 확인 전에는 쓸 수 있는 QR을 노출하지
않는다"는 기존 정책**을 흔들지 않기 위해서다. 입금이 확인되면 그때 `voucherCode`가
생기고 그것이 QR이 된다.

정본: `functions/checkInRules.js` (`productQrActive`가 `on_site`만 통과시킨다),
`functions/placeProductOrders.js` (`confirmPlaceProductDeposit`)

### 기존 `voucherCode` 호환

이미 손님 폰에 있는 QR과 옛 앱을 깨뜨리지 않는다.

- 통합 스캐너는 토큰 문서를 못 찾으면 `placeProductOrders.voucherCode`로 **한 번
  더** 찾는다. 옛 QR도 새 스캐너에서 그대로 조회·사용된다.
- 옛 앱이 부르는 `redeemProductVoucher` 콜러블도 그대로 남아 있다. 판정은
  `checkInRules.voucherBlockReason` **하나를 공유**하므로 어느 경로로 찍히든
  같은 결과가 나온다.

정본: `functions/checkInTokens.js` (`locate`의 호환 경로),
`functions/placeProductOrders.js` (`redeemBlockReason` → `rules.voucherBlockReason`)

---

## 7. 콤보는 QR이 두 장이다

숙박+파티 콤보(`packageBookings`)는 예약 문서 하나로 방과 파티 자리를 함께 잡는다.
그래도 QR은 둘이다.

```
packageBookings/{id}                      → 숙소 체크인용
parties/{partyId}/applications/{appId}    → 파티 입장용
```

하나로 합치지 않는 이유: **체크인 시각도 장소도 다르다.** 무엇보다 호스트가 파티
입구에서 찍을 때 보여야 하는 것은 객실 정보가 아니라 파티 참가 상태다. 두 QR은
서로 다른 원본을 가리키므로 하나를 써도 다른 하나가 소진되지 않는다.

손님 화면의 숙소 QR에는 "숙소 체크인용 QR이에요. 파티 입장 QR은 참가 목록에 따로
있어요."가 함께 뜬다.

정본: `functions/reservationCheckIn.js` (파일 상단 주석),
`party_app/lib/models/place_rental_reservation.dart` (`checkInPass`)

---

## 8. 화면

| 보는 사람 | 화면 | 규칙 |
|---|---|---|
| 게스트 | `CheckInQrCard` / `showCheckInQrSheet` | 파티·예약·상품이 **같은 카드 한 벌**. 유형별로 다른 값은 `CheckInPass` DTO에만 있다 |
| 호스트 | `CheckInScanScreen` | 앱 전체에 **스캐너 하나**. 플레이스를 먼저 고르지 않는다 — 파티 참가권은 어느 플레이스에도 속하지 않으므로 |

두 화면 모두 **유효성을 스스로 판단하지 않는다.** 화면이 "쓸 수 있다"고 말하면
서버 판정과 어긋나는 순간 손님이 현장에서 거절당한다. 게스트 카드는 토큰이
있는지만 보고, 호스트 화면은 서버가 내려준 결과 하나를 그린다.

이 두 가지는 테스트가 구조적으로 고정한다 — `QrImageView`를 그리는 위젯이 하나뿐,
`MobileScanner`를 그리는 화면이 하나뿐.

정본: `party_app/lib/widgets/check_in_qr_card.dart`,
`party_app/lib/screens/check_in_scan_screen.dart`,
테스트: `party_app/test/check_in_qr_card_ui_test.dart` · `check_in_single_scanner_test.dart`

---

## 9. 검증

| 무엇 | 어디 |
|---|---|
| 판정 규칙(순수 함수) | `functions/checkInTokens.selfcheck.js` — `npm run check:checkin` |
| 발급 생명주기(가짜 Firestore) | `functions/checkInIssue.selfcheck.js` — `npm run check:checkin-issue` |
| 게스트 QR DTO·위젯 | `party_app/test/check_in_pass_test.dart` · `check_in_qr_card_ui_test.dart` |
| 기존 QR 문서 백필 | `functions/scripts/backfillCheckInTokens.js` — 기본 dry-run, `--apply`는 `--project=<id>` 필수 |

전체 서버 검증은 `cd functions && npm run check`.
