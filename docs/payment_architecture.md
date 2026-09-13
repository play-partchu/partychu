# 파티츄 결제 구조

파티츄의 모든 결제는 **다섯 도메인이 하나의 모델·하나의 상태 머신**을 공유한다.
이 문서는 그 구조를 정리한 개발 문서다 — 동작을 바꾸지 않고 현재 상태를 설명한다.

> **PG 계약 전이다.** 지금 실제로 받을 수 있는 수단은 무통장입금과 현장결제뿐이고,
> 카드·간편결제·실시간계좌이체·가상계좌는 화면에 '준비중'으로만 보인다.
> 사용자가 도달할 수 있는 PortOne 경로는 없다(서버 코드는 옛 앱 호환용으로만 남아 있다).

> 결제 이후의 입장·사용 처리(통합 QR 체크인)는
> [checkin_qr_contract.md](checkin_qr_contract.md) 참고.

---

## 1. 공용 결제 모델

세 조각이 서버와 앱에서 **키가 1:1로 일치**한다. 한쪽만 고치면 안 된다.

| 개념 | 서버 | 앱 |
|---|---|---|
| 결제수단 | `functions/paymentInfo.js` | `lib/models/payment_method.dart` |
| 결제상태 | `functions/depositFlow.js` (`STATUS`) | `lib/models/payment_status.dart` |
| 결제정보 묶음 | `buildPaymentInfo()`가 만드는 맵 | `PaymentInfo` |

### PaymentMethod

| key | 라벨 | 지금 쓸 수 있나 |
|---|---|---|
| `bank_transfer` | 무통장입금 | ✅ |
| `on_site` | 현장결제 | ✅ |
| `card` | 카드결제 | ❌ 준비중 |
| `transfer` | 실시간 계좌이체 | ❌ 준비중 |
| `virtual_account` | 가상계좌 | ❌ 준비중 |
| `easy_pay` | 간편결제(카카오페이·네이버페이·토스페이) | ❌ 준비중 |

- 앱: `PaymentMethod.available` 하나로 '선택 가능 / 준비중'이 갈린다.
- 서버: `ENABLED_METHODS` / `PREPARING_METHODS`. 준비중 수단이 들어오면
  `failed-precondition`으로 **거절**한다(가짜 성공을 만들지 않는다).
- 준비중 수단에는 결제 로직이 **아예 없다.** PG를 흉내 내면 "결제됐다"는 잘못된
  상태가 실제 주문에 남는다.

### PaymentStatus

| key | 라벨 | 뜻 |
|---|---|---|
| `awaiting_approval` | 승인대기 | 승인제 흐름에서 승인을 기다리는 중. **입금 요구 전** |
| `awaiting_deposit` | 입금대기 | 계좌 안내 완료, 기한 카운트 시작 |
| `deposit_pending` | 입금확인중 | 이용자가 '입금했어요'를 눌렀고 대조 전 |
| `on_site_scheduled` | 현장결제 예정 | 방문/수령 시 결제 |
| `paid` | 결제완료 | **돈이 실제로 확인된 유일한 상태** |
| `cancelled` / `refunded` / `expired` | 결제취소 / 환불완료 / 기한만료 | 종료 |

`isUnpaid`는 `awaiting_approval`·`awaiting_deposit`·`deposit_pending`·`on_site_scheduled`를
모두 포함한다 — 이 넷은 전부 **아직 안 받은 돈**이다.

### PaymentInfo

문서의 `payment` 필드에 저장되는 맵. 결제수단 선택 결과이면서 이후 계속 자라는 그릇이다.

```
method, status, amount, createdAtMs
depositorName?, depositDeadlineMs?, depositedAtMs?, paidAtMs?, cancelledAtMs?, confirmedBy?
bankName, accountNumber, accountHolder   ← 안내 시점 계좌 스냅샷(무통장입금만)
```

- 시각은 전부 `...Ms`(epoch milliseconds)로 적는다 — Functions와 Firestore Timestamp
  사이에서 형식이 갈리지 않게.
- 앱 모델에 아직 없는 서버 필드는 `PaymentInfo.extra`에 실려 그대로 오간다(유실 방지).

### PaymentPolicy — 호스트가 정하는 결제 방식 (예약금)

`PaymentMethod`(어떤 수단으로 받나 · 구매자 선택)와 **직교하는 별개의 축**이다:
얼마를 미리 받나 · **호스트 선택**.

| 서버 | 앱 |
|---|---|
| `functions/paymentPolicy.js` | `lib/models/payment_policy.dart` |

```
paymentMode: prepaid | partial | onsite
upfrontType: percentage | fixed      ← partial일 때만
upfrontPercent / upfrontFixedAmount
```

> ⚠ **`upfront`와 `deposit`은 다른 것이다.**
> `upfront` = 예약금(총액 중 미리 받는 몫), `deposit` = 무통장입금(수단).
> `paymentMode: 'partial'`인 예약이 `payment.status: 'awaiting_deposit'`인 상태가
> 정상이다. 사용자 화면에는 `upfront`를 전부 **'예약금'**으로만 쓴다.

| 방식 | 지금 | 현장 | 허용 수단 |
|---|---|---|---|
| `prepaid` | 전액 | 0원 | `bank_transfer` |
| `partial` | 예약금 | 잔금 | `bank_transfer` |
| `onsite` | 0원 | 전액 | `on_site` |
| **없음(legacy)** | — | — | **둘 다** (지금까지의 동작) |

- **설정이 없는 기존 문서는 건드리지 않는다.** `normalizePolicy`가 null을 돌려주고
  구매자가 수단을 자유롭게 고르던 동작이 그대로 유지된다. 임의로 `prepaid`로
  간주하면 현장결제로 신청하던 사용자가 갑자기 막힌다.
- **비율 예약금은 "예약 당시 최종 이용요금" 기준**이다. 숙박일수·요일가격·옵션이
  모두 반영된 뒤의 금액을 `computeBreakdown`에 넘겨야 한다.
- **총액이 확정되지 않는 예약**(플레이스 좌석 — 음식은 현장 주문)에서는 `%`와
  `prepaid`를 아예 만들 수 없고, 잔금은 0이 아니라 **null**(모름)로 둔다.
  방문예약은 새 필드 없이 기존 `visitReservation.depositPerPerson`에서
  정책을 유도한다(0 → `onsite`, >0 → `partial`+`fixed`) — 마이그레이션이 없다.
- **금액 스냅샷**: 예약 생성 시 `amounts`(`snapshotOf`)를 문서에 얼려 둔다.
  호스트가 나중에 비율·가격을 바꿔도 기존 예약의 금액은 변하지 않는다.
  **어떤 화면도 호스트 설정을 다시 읽어 재계산하지 않는다.**

### 핵심 원칙 두 가지

1. **수단은 클라이언트가 고르고, 상태는 서버가 정한다.** 앱이 보낸 `status`는 통째로
   버린다(그렇지 않으면 `paid`를 보내 결제한 척할 수 있다).
2. **금액도 서버가 계산한다.** 앱이 보낸 금액은 받지 않는다. 서버가 상품·요금·쿠폰
   문서를 다시 읽어 계산한 값이 정본이다.

```js
// 모든 도메인이 이 한 함수로 payment 맵을 만든다
buildPaymentInfo(raw, { amount, nowMs, requireApproval, useAtMs })
// → 금액이 0이면 null (결제 없음)
// → 준비중 수단이면 throw
```

`useAtMs`를 넘기면 입금기한이 **이용 시각을 넘지 않게 잘린다** — 방문이 6시간 뒤인데
기한이 24시간이면 기한이 뜻을 잃기 때문이다. 파티 신청처럼 이용 시각을 넘기지 않는
도메인은 24시간 그대로다.

---

## 2. depositFlow — 상태 전이의 단일 소유자

`functions/depositFlow.js`는 **어떤 상태에서 무엇을 할 수 있는가**만 판정한다.
Firestore를 모르는 순수 함수라 자체 검증에서 그대로 부를 수 있다.

```
     (승인제만) 승인대기 awaiting_approval
          │  호스트/업주 승인 ─ approvePatch()
          ▼
     입금대기 awaiting_deposit ──────── 기한 초과 ──▶ expired
          │  이용자 '입금했어요' ─ assertCanMarkSent() → markSentPatch()
          ▼
     입금확인중 deposit_pending          ※ 자동 만료 대상 아님
          │  호스트/업주 '입금 확인' ─ assertCanConfirm() → confirmPatch()
          ▼
     결제완료 paid

     현장결제 on_site_scheduled ─ assertCanConfirmReceived() ─▶ paid
```

| 함수 | 역할 |
|---|---|
| `assertCanMarkSent(payment, ctx)` | 이용자가 '입금했어요'를 누를 수 있는 상태인지. 중복 클릭 차단이 이 규칙 하나에 걸려 있다 |
| `assertCanConfirm(payment, ctx)` | 호스트가 '입금 확인'을 누를 수 있는지. **무통장입금 전용** |
| `assertCanConfirmReceived(payment, ctx)` | 위와 같되 **현장결제도 함께** 받는다. QR처럼 "돈을 받아야 발급되는" 도메인용 |
| `approvePatch(payment, nowMs, {notAfterMs})` | 승인 순간 `awaiting_approval → awaiting_deposit` + 기한 시작 |
| `markSentPatch` / `confirmPatch` / `expirePatch` | 각 전이 후 문서에 반영할 값 |
| `isExpirable(payment, nowMs)` | 자동 정리 대상인지 — **`awaiting_deposit`만** |
| `isPaid(payment)` | 돈이 실제로 들어왔는지. 매출·QR의 단 하나의 기준 |
| `bankPaymentOf(payment)` | 무통장입금 건인지 (아니면 null) |

### 왜 `deposit_pending`은 자동 만료되지 않는가

이용자는 입금했다고 알렸는데 확인이 늦은 것뿐일 수 있다. 자동 취소하면 **이미 돈을 낸
사람의 자리를 뺏게 된다.** 그 건은 호스트가 목록에서 직접 처리한다.
`isExpirable()`이 이 상태를 제외하고, 자리를 잡는 도메인(장소대여·콤보)은 슬롯의 만료
기한까지 함께 지워 두 겹으로 막는다.

### 승인 전에는 왜 입금을 요구하지 않는가

PG가 없어 자동 환불이 불가능하다. 승인 전에 받으면 거절 시 계좌로 수동 환불해야 한다.
그래서 승인제 흐름은 `awaiting_approval`로 시작하고, 승인되는 **그 순간**에야
`awaiting_deposit`이 되며 기한이 시작된다.

### 보조 모듈

- `functions/placeReservationFlow.js` — 장소대여·콤보 전용. 결제 상태 머신이 **아니라**,
  "이 상태 조합에서 시간 슬롯을 언제까지 잡고 있어야 하나"(`slotHoldOf`)와 승인
  방식·기한을 정한다.
- `functions/reservationNotifications.js` — 예약 계열 인앱 알림 생성 한 곳.
  FCM을 붙일 때 이 함수 안에서만 토큰 발송을 더하면 된다.

---

## 3. 도메인별 결제 흐름

다섯 도메인이 **같은 상태 머신**을 쓰고, 다른 것은 세 가지뿐이다:
어느 문서인가 / 승인 단계가 있는가 / 무엇을 선점하고 어떻게 되돌리는가.

| 도메인 | 문서 | 승인 | 선점 대상 | 확인되면 |
|---|---|---|---|---|
| 파티 신청 | `parties/{id}/applications/{uid}` | 없음 | 파티 정원 | `status: approved` |
| 플레이스 방문예약 | `placeVisitReservations/{id}` | 매장별 auto/manual | 시간대 좌석 수 | 예약 상태 그대로 |
| 장소대여 | `placeReservationGroups/{id}` | 룸별 auto/manual | 시간 슬롯 | 예약 상태 그대로 |
| 파티샵 주문 | `orders/{id}` | 없음 | 상품 재고 | `status: paid` |
| 플레이스 상품·이용권 | `placeProductOrders/{id}` | 없음 | 상품 재고 | `status: paid`/`usable` + **QR 발급** |
| 숙박+파티 콤보 | `packageBookings/{id}` | 룸별 auto/manual | 시간 슬롯 **+** 파티 정원 **+** 신청 문서 | 예약 상태 그대로 |

### 파티 신청

`applyToParty`가 정원을 선점하고 `applications` 문서를 `status: 'applied'`로 만든다.
결제는 `payment` 맵이 따로 표현한다. `confirmPartyDeposit`이 **결제와 신청을 함께**
넘긴다 — 돈이 확인된 순간이 곧 확정(`approved`)이다.

### 플레이스 방문예약

매장 설정(`events/{id}.visitReservation.approvalMode`)이 auto면 신청 즉시 `approved`,
manual이면 `requested`로 시작한다. 예약금은 1인당 금액 × 인원(0원이면 결제 자체가 없다).
**입금 확인은 승인이 아니다** — 승인은 이미 끝났고 여기서는 돈만 확인하므로
`status: approved`는 그대로 둔다.

### 장소대여 (숙박 / 시간제 / 패키지)

세 예약 방식은 **결제 흐름이 완전히 같다.** `computeWindows()`가 어떤 방식이든
"자정 기준 분 좌표의 시간 구간" 배열로 바꾸고, 그 구간이 `reservationSlots` 문서로
펼쳐진다. 그래서 재고 복구도 세 방식에서 동일하다(`reservationIds`를 훑어 상태만 바꾼다).

슬롯 점유 기간은 `slotHoldOf()`가 정한다:

| 상태 | 슬롯 |
|---|---|
| 승인대기 | `pending`, 업주 응답 기한까지 |
| 확정 + 입금대기 | `pending`, **입금기한까지** (지나면 자리가 풀린다) |
| 확정 + 입금확인중 | `confirmed`, 기한 없음 |
| 확정 + 결제완료/현장결제/무료 | `confirmed`, 기한 없음 |

### 파티샵 주문

승인 단계가 없다 — 상품 주문은 판매자가 받아줄지 고르는 절차가 아니라 재고가 있으면
성립하는 거래다. 주문 즉시 재고 선점 + 입금대기, 판매자 확인 시 `status: 'paid'`.

### 플레이스 상품·이용권 (QR)

다른 도메인과 같되 **QR 이용권 발급 조건**이 추가된다 → [7. QR 발급 및 사용 조건](#7-qr-발급-및-사용-조건)

### 숙박+파티 콤보

**콤보에만 있는 불변식**: 장소 슬롯·파티 정원·파티 신청 문서 셋이 항상 함께 잡히고
함께 풀린다. 하나만 풀리면 "방은 비었는데 파티 정원은 찬" 상태가 되고, 그건 어떤
화면에서도 고칠 수 없다.

- 반납은 반드시 `prepareBundleRelease()` + `applyBundleRelease()` 한 쌍으로만 한다.
  거절·취소·승인기한 만료·입금기한 만료 네 경로가 모두 이 함수를 부른다.
- 파티 정원 롤백은 파티 단독 취소와 **같은 헬퍼**(`releaseApplicantSlot`)를 쓴다.
- 신청 문서는 **자리가 확정되는 시점**에 만든다(자동승인=예약 즉시 / 승인제=승인 시).
  결제 확정까지 기다리면 정원 카운터만 +1이고 신청자 목록은 비어 있는 구간이 생긴다.
- 콤보 신청 문서에는 **`payment`를 복사하지 않는다** → [9. 절대 지켜야 하는 규칙](#9-절대-지켜야-하는-규칙)

---

## 4. Cloud Functions 목록

### 공통 (모듈)

| 파일 | 역할 |
|---|---|
| `depositFlow.js` | 결제 상태 전이 판정 (순수 함수) |
| `paymentInfo.js` | 결제수단 검증 + 초기 상태 결정 + 계좌 스냅샷 |
| `placeReservationFlow.js` | 장소대여·콤보의 슬롯 점유·승인 규칙 (순수 함수) |
| `reservationNotifications.js` | 예약 계열 인앱 알림 생성 |

### 파티 신청 — `index.js`, `partyDeposits.js`

| 함수 | 종류 | 역할 |
|---|---|---|
| `applyToParty` | callable | 정원 선점 + 신청 문서 생성 + `payment` 맵 |
| `cancelApplication` | callable | 취소 + 정원 반납 + 환불 계산 |
| `markPartyDepositSent` | callable | 참가자 '입금했어요' |
| `confirmPartyDeposit` | callable | 호스트 '입금 확인' → `paid` + 신청 `approved` |
| `expirePartyDeposits` | 10분 | 입금기한 초과 → 취소 + 정원 반납 |

### 플레이스 방문예약 — `placeVisitReservations.js`

| 함수 | 종류 | 역할 |
|---|---|---|
| `createVisitReservation` | callable | 좌석 선점 + 예약 생성 |
| `decideVisitReservation` | callable | 업주 승인/거절 (승인 시 입금대기 시작) |
| `markVisitDepositSent` / `confirmVisitDeposit` | callable | 입금 알림 / 입금 확인 |
| `cancelVisitReservation` | callable | 취소 + 좌석 반납 |
| `expireVisitDeposits` | 10분 | 입금기한 초과 |
| `expireStaleVisitReservations` | 10분 | 업주 무응답 만료 |

### 장소대여 — `placeReservations.js`

| 함수 | 종류 | 역할 |
|---|---|---|
| `createPendingReservation` | callable | 겹침 검증 + 슬롯 선점 + 예약 생성 |
| `decidePlaceReservation` | callable | 업주 승인/거절 |
| `markPlaceDepositSent` / `confirmPlaceDeposit` | callable | 입금 알림 / 입금 확인 |
| `cancelReservation` | callable | 취소 + 슬롯 반납 (예약자·업주 모두 가능) |
| `expirePlaceReservationDeposits` | 10분 | 입금기한 초과 → 취소 + 슬롯 반납 |
| `expireStalePlaceReservationApprovals` | 10분 | 업주 무응답 만료 |
| `expireStalePlaceReservations` | 5분 | 옛 PortOne 10분 대기 정리 |
| `verifyAndConfirmReservation` | callable | **옛 PortOne 경로** (무통장 건은 멱등 통과) |

### 파티샵 주문 — `shopOrders.js`

| 함수 | 종류 | 역할 |
|---|---|---|
| `createPendingShopOrder` | callable | 재고 선점 + 금액·쿠폰 서버 계산 |
| `markShopDepositSent` / `confirmShopDeposit` | callable | 입금 알림 / 입금 확인 → `paid` |
| `cancelShopOrder` | callable | 취소 + 재고 복구 |
| `expireShopOrderDeposits` | 10분 | 입금기한 초과 |
| `expireStaleShopOrders` | 5분 | 옛 PortOne 10분 대기 정리 |
| `verifyAndConfirmShopOrder` | callable | **옛 PortOne 경로** |

### 플레이스 상품·이용권 — `placeProductOrders.js`

| 함수 | 종류 | 역할 |
|---|---|---|
| `createPendingProductOrder` | callable | 재고 선점 + 1인 한도 검증. **QR 발급 안 함** |
| `markPlaceProductDepositSent` | callable | 구매자 '입금했어요'. **QR 발급 안 함** |
| `confirmPlaceProductDeposit` | callable | 판매자 '입금/결제 확인' → `paid` + **QR 발급** |
| `expirePlaceProductDeposits` | 10분 | 입금기한 초과 + 재고 복구 |
| `cancelProductOrder` | callable | 취소/환불 + 재고 복구 + QR 무력화 |
| `redeemProductVoucher` | callable | QR 확인/사용 처리 (**`paid` 재확인**) |
| `expireStaleProductOrders` | 5분 | 옛 PortOne 10분 대기 정리 |
| `verifyAndConfirmProductOrder` | callable | **옛 PortOne 경로** |

### 숙박+파티 콤보 — `packageBookings.js`

| 함수 | 종류 | 역할 |
|---|---|---|
| `createPendingPackageBooking` | callable | 슬롯 + 파티 정원을 **한 트랜잭션**에서 선점 |
| `decidePackageBooking` | callable | 업주 승인/거절 (거절 시 셋 다 반납) |
| `markPackageDepositSent` / `confirmPackageDeposit` | callable | 입금 알림 / 입금 확인 |
| `cancelPackageBooking` | callable | 취소 + 셋 다 반납 + 환불 계산 |
| `expirePackageBookingDeposits` | 10분 | 입금기한 초과 |
| `expireStalePackageBookingApprovals` | 10분 | 업주 무응답 만료 |
| `expireStalePackageBookings` | 5분 | 옛 PortOne 10분 대기 정리 |
| `verifyAndConfirmPackageBooking` | callable | **옛 PortOne 경로** |

### 통계 트리거 — `memberManagement.js`

`onPlaceReservationGroupWrite` / `onPackageBookingWrite`는 **건수**를 확정 시점에 세고,
**금액**은 `becamePaid(before, after)`가 참일 때만 센다.

---

## 5. 공용 UI

### `PaymentMethodScreen` (`lib/screens/payment_method_screen.dart`)

결제수단을 고르는 화면. **도메인 분기가 없다** — 화면은 `PaymentOrderSummary` 하나만
받고, "무엇에 대한 결제인가"는 각 도메인이 만들기 함수로 정한다.

```dart
PaymentOrderSummary.party(...)        // 파티명 / 참가일 / 인원 / 참가비
PaymentOrderSummary.placeVisit(...)   // 매장명 / 방문일시 / 인원
PaymentOrderSummary.placeRental(...)  // 장소명 / 이용일시 / 룸·상품
PaymentOrderSummary.shopOrder(...)    // 상품명 / 수량 / 옵션
```

선택 가능한 수단과 준비중 수단은 `PaymentMethod.usable` / `.preparing`이 나눈다.
결과로 `PaymentInfo`를 돌려주고, 호출부는 그것을 서버로 **수단만** 실어 보낸다.

### `DepositPanel` (`lib/widgets/deposit_panel.dart`)

결제 상태 + 무통장입금 안내(계좌·기한·복사 버튼) + '입금했어요' 버튼 한 덩어리.
다섯 도메인의 목록 화면이 **같은 위젯**을 쓴다 — 따로 그리면 "여기서는 계좌가 보이는데
저기서는 안 보인다" 같은 차이가 곧 생긴다.

- 도메인마다 다른 것은 **'입금했어요'를 누르면 무엇을 부르는가**(`onMarkSent`) 하나뿐이다.
- 버튼은 `PaymentStatus.canMarkDepositSent`일 때만 뜬다(= `awaiting_deposit`).
  이미 알린 뒤에는 사라지고, 서버도 같은 조건을 다시 확인한다.
- 승인 전(`awaiting_approval`)에는 계좌도 버튼도 띄우지 않는다.
- `onMarkSent: null`이면 보기 전용(호스트 화면).
- `depositErrorMessage(e)`는 서버가 돌려준 한국어 문구를 그대로 쓴다.

### 도메인별 화면

이용자 쪽 목록은 더 이상 도메인마다 별도 화면이 아니다 — `my_guest_hub_screen.dart`
한 곳이 파티츄·플레이스·공간대여·파티크루 탭으로 나눠 보여주고, 카드와 결제
패널은 아래 공용 위젯을 그대로 쓴다. 업주 쪽은 도메인별 관리 화면이 그대로다.

| 화면 | 역할 |
|---|---|
| `my_page_screen.dart` | 역할 허브 2개(게스트/호스트)로만 보내는 진입점 |
| `my_guest_hub_screen.dart` | 이용자: 파티 신청 · 방문예약 · 장소대여 · 콤보 · 이용권 **전부** |
| `my_host_hub_screen.dart` | 호스트: 등록물 목록 + 도메인별 관리 화면 진입 |
| `party_applicants_screen.dart` | 호스트: 파티 신청자 + 입금 확인 |
| `visit_reservation_manage_screen.dart` | 업주: 방문예약 승인·거절 |
| `place_reservation_manage_screen.dart` | 업주: 장소대여 승인·입금 확인(콤보 포함) |
| `place_sales_dashboard_screen.dart` | 사장님: 이용권 판매 통계·결제 확인 |
| `my_visit_reservations_screen.dart` | 이용자: 방문예약 목록 — **알림 딥링크 전용** 잔존 경로 |
| `widgets/place_rental_reservation_card.dart` | 장소대여·콤보 카드(이용자/업주 공용) |
| `widgets/visit_reservation_card.dart` | 방문예약 카드(이용자/업주 공용) |
| `widgets/voucher_card.dart` | 이용권 카드 |
| `widgets/shop_order_list.dart` | 파티샵 구매/판매 목록 |

---

## 6. 결제 상태와 주문·예약 상태를 분리한 이유

**두 값은 서로 다른 질문에 답한다.**

- 주문/예약 상태(`status`) = "이 건이 **어디까지 갔는가**" (신청됨·확정됨·취소됨)
- 결제 상태(`payment.status`) = "**돈이 어디까지 갔는가**" (입금대기·입금확인중·결제완료)

한 값에 섞으면 표현할 수 없는 상태가 생긴다. 예를 들어 **"예약은 확정인데 입금은 아직"**
은 완전히 정상적인 구간인데, 값이 하나면 `confirmed`라고 쓰는 순간 돈을 받은 것처럼
보이고 `awaiting_deposit`이라고 쓰는 순간 자리가 안 잡힌 것처럼 보인다.

실제로 이 분리가 막아준 사고:

- **매출 과다 집계** — 예약 확정 시점에 금액을 세면 입금 없이 만료될 건까지 매출로
  잡히고, 그 숫자로 정산하면 실제로 들어오지 않은 돈을 지급하게 된다.
- **QR 조기 발급** — 주문 상태만 보면 입금 전 이용권이 열린다.
- **잘못된 안내** — "확정됐어요"만 띄우면 아직 돈이 안 들어왔다는 사실이 가려진다.

그래서 화면도 두 축을 함께 보여준다: 상태 배지는 예약/주문 진행을, `DepositPanel`은
결제를 각각 말한다.

---

## 7. QR 발급 및 사용 조건

`placeProductOrders`에만 있는 규칙이다.

### 발급

이용권 코드(`voucherCode`)는 **주문 생성 시점에 만들지 않는다**(`''`로 시작).
코드가 결제 전에 존재하면 결제 없이 스캔을 시도할 여지가 생긴다.

코드가 생기는 지점은 **오직 하나** — `issueVoucherPatch()`이고, 이 함수는 결제가 확인된
뒤에만 호출된다.

| 경로 | 발급 시점 |
|---|---|
| 무통장입금 | 판매자 '입금 확인' → `paid` → 발급 |
| 현장결제 | 판매자 '결제 확인' → `paid` → 발급 |
| 옛 PortOne | PortOne 조회 검증 통과 → 발급 |

따라서 `awaiting_deposit` · `deposit_pending` · `on_site_scheduled` 세 상태에서는
**이용권이 아예 만들어지지 않고, 만들어질 수 없으므로 사용도 불가능하다.**

발급과 동시에 `resolveConfirmedStatus()`가 상태를 정한다 — 이용 시작일이 아직 안 왔으면
`paid`, 이미 이용 가능 기간이면 `usable`. QR 사용 처리는 `usable`에서만 통과하므로,
이 구분이 "다음 주 티켓을 오늘 쓰지 못하게" 막는 장치다.

### 사용 (검증)

`redeemProductVoucher` → `redeemBlockReason()`이 **두 축을 모두** 본다.

```
① 주문 상태  : used / cancelled / refunded / expired / payment_pending → 차단
② 결제 상태  : payment.status !== 'paid' → 차단   ← 마지막 방어선
③ 이용 기간  : useStartAt 전 / useEndAt 후 → 차단
④ 이용 예정일: 날짜 지정 상품은 그날(KST)이 아니면 차단
⑤ 최종       : status === 'usable' 이어야 통과
```

②는 코드가 어떤 경로로든 먼저 생긴 문서·수기 수정·옛 데이터가 있어도 돈을 받지 않은
이용권이 통과하지 않게 하는 **마지막 방어선**이다. 결제 정보가 없는 건(`payment == null`)은
옛 PortOne 흐름이라 이미 검증이 끝난 주문이므로 예전 규칙을 유지한다.

사용 처리는 트랜잭션 안에서 상태를 다시 확인해, 두 기기에서 동시에 스캔해도 한 번만
소진된다.

---

## 8. 확장 방법 — 카드결제·간편결제(PG)를 붙일 때

PG가 붙어도 **도메인 코드는 손대지 않는다.** 순서는 다음과 같다.

### ① 결제수단 열기

```dart
// lib/models/payment_method.dart
card(key: 'card', ..., available: true),   // false → true
```

```js
// functions/paymentInfo.js
const ENABLED_METHODS = ['bank_transfer', 'on_site', 'card'];
const PREPARING_METHODS = ['transfer', 'virtual_account', 'easy_pay'];
const INITIAL_STATUS = {
  bank_transfer: 'awaiting_deposit',
  on_site: 'on_site_scheduled',
  card: 'payment_in_progress',   // ← 새 상태가 필요하면 여기서 정한다
};
```

이 두 곳만 바꾸면 **다섯 도메인의 결제수단 화면이 동시에 열린다.** 화면에는 어떤 수단이
켜져 있는지에 대한 분기가 없기 때문이다.

### ② 필요하면 새 결제 상태를 추가

`PaymentStatus`(Dart)와 `depositFlow.STATUS`(JS)에 **같은 키로** 추가하고, `isUnpaid` 같은
분류 게터를 갱신한다. 예: `payment_in_progress`(결제창 진행 중), `partially_refunded`.

### ③ 전이 규칙을 depositFlow에 추가

PG는 "확인" 주체가 사람이 아니라 웹훅/조회다. 그래도 **판정은 depositFlow에 둔다.**

```js
// 예시 — 실제 구현 시 이 자리에 넣는다
function assertCanCapture(payment, ctx) { ... }
function capturePatch(nowMs, pgTransactionId) {
  return { status: STATUS.paid, paidAtMs: nowMs, pgTransactionId };
}
```

도메인은 이 함수를 부르기만 한다. **도메인 파일에 새 상태 머신을 만들지 않는다.**

### ④ 검증 함수를 도메인에 연결

각 도메인에는 이미 `verifyAndConfirm*` 자리가 있다(옛 PortOne 경로). PG 웹훅/조회 검증을
그 자리에 연결하고, 성공 시 `capturePatch()` 결과를 반영한다. 이용권 도메인은
`issueVoucherPatch()`를 그대로 부르면 QR 발급 규칙이 자동으로 지켜진다.

### ⑤ 환불 경로

지금은 `refundStatus: 'pending'`으로 저장만 하고 실제 환불은 하지 않는다
(`partyCapacity.computeRefund`). PG가 붙으면 이 필드를 구독/폴링하는 처리에서 취소 API를
호출하고 `refunded`로 넘긴다. **환불 금액 계산 규칙(호스트가 입력한 `refundPolicy`)은
바꾸지 않는다.**

### ⑥ 자체 검증 추가

```
npm run check:payment   # paymentInfo — 수단 검증·초기 상태
npm run check:rental    # 장소대여 승인·슬롯 점유
npm run check:package   # 콤보 선점/반납 불변식
npm run check:shop      # 파티샵 만료 경로 분리
npm run check:products  # QR 발급·사용 조건
npm run check           # 전체
```

새 수단·새 상태를 추가하면 **반드시 여기에 케이스를 더한다.** 돈이 걸린 규칙은 주석이
아니라 실행되는 검증으로 고정한다.

### 주의 — `expiresAt` 함정

옛 PortOne 10분 만료 스케줄러는 `status == '...pending' && expiresAt < now`로 대상을
찾는다. Firestore 타입 순서상 **`null`은 어떤 Timestamp보다 작다.** 무통장입금 주문에
`expiresAt: null`을 넣으면 24시간짜리 주문이 10분 만에 만료된다. 그래서 무통장 건에는
필드를 **아예 만들지 않는다**(필드가 없으면 색인에서 빠진다). 새 흐름을 추가할 때도
같은 함정을 확인할 것.

---

## 9. 절대 지켜야 하는 규칙

> 이 여섯 줄은 협상 대상이 아니다. 어기면 돈이 어긋나거나, 받지 않은 돈으로 서비스가
> 제공된다.

1. **매출은 `payment.status == 'paid'` 기준으로만 계산한다.**
   예약·신청·주문의 `approved`/`confirmed` 상태를 매출 기준으로 쓰지 않는다.
   판정은 `memberManagement.becamePaid()` 또는 `depositFlow.isPaid()`를 쓴다.

2. **QR 이용권은 `payment.status == 'paid'` 이후에만 발급한다.**
   발급 지점은 `issueVoucherPatch()` 하나뿐이다.

3. **QR 사용 시에도 서버에서 `payment.status == 'paid'`를 다시 확인한다.**
   클라이언트 표시나 주문 상태만 믿지 않는다(`redeemBlockReason`).

4. **`applications`에는 `payment`를 복사하지 않는다.**
   콤보 결제의 진실 소스는 `packageBookings.payment` 하나다. 복사하면
   `expirePartyDeposits`가 신청만 취소해 **파티 정원만 반납하고 장소 슬롯은 남기는**
   사고가 난다. 추적은 `source: 'combo'` + `bundleBookingId` 연결 필드로 한다.

5. **결제 상태 변경은 반드시 `depositFlow`를 통해서만 이루어진다.**
   도메인 파일에서 `payment.status`를 직접 문자열로 쓰지 않는다. 전이 판정은
   `assertCan*`, 반영 값은 `*Patch`를 쓴다.

6. **각 도메인은 공용 결제 모델을 우선 사용하며, 중복 결제 로직을 새로 만들지 않는다.**
   새 도메인에 결제를 붙일 때는 `paymentInfo` + `depositFlow`를 그대로 부르고,
   도메인마다 다른 것(어느 문서인가 / 확정되면 무슨 상태가 되나 / 자리를 어떻게
   돌려주나)만 얇은 껍데기로 감싼다.

---

## 참고 파일

```
functions/
  depositFlow.js                 상태 전이 판정 (순수)
  paymentInfo.js                 수단 검증 + 초기 상태
  placeReservationFlow.js        장소대여·콤보 슬롯 점유 규칙 (순수)
  reservationNotifications.js    예약 알림
  partyDeposits.js               파티 신청 결제
  placeVisitReservations.js      방문예약
  placeReservations.js           장소대여
  packageBookings.js             숙박+파티 콤보
  shopOrders.js                  파티샵 주문
  placeProductOrders.js          플레이스 상품·QR 이용권
  memberManagement.js            통계 트리거 (becamePaid)
  *.selfcheck.js                 규칙 자체 검증

party_app/lib/
  models/payment_method.dart     PaymentMethod + 입금 계좌
  models/payment_status.dart     PaymentStatus + PaymentInfo
  models/payment_order_summary.dart  결제 화면 주문 요약
  screens/payment_method_screen.dart 공용 결제수단 선택 화면
  widgets/deposit_panel.dart     공용 결제 상태·입금 안내 위젯
```
