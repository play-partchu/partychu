/**
 * 예약 QR — **확정된 예약**에만 붙는 입장권.
 *
 * ── 어떤 예약이 있는가 ──────────────────────────────────────────────────────
 * 운영 중인 예약 컬렉션은 셋이고 셋 다 여기서 다룬다.
 *
 *   placeVisitReservations   플레이스 방문예약   확정 = status 'approved'
 *   placeReservationGroups   장소대여 예약       확정 = status 'confirmed'
 *   packageBookings          숙박+파티 콤보      확정 = status 'confirmed'
 *
 * 컬렉션마다 확정을 뜻하는 단어가 다르다(승인이냐 확정이냐). 그 표는
 * checkInRules.RESERVATION_QR_STATUS 하나에만 있고 이 파일은 표를 읽기만 한다 —
 * 판정이 두 벌이 되면 어느 예약은 QR이 나오고 어느 예약은 안 나오는 일이 생긴다.
 *
 * ── 콤보는 QR이 둘이다 ──────────────────────────────────────────────────────
 * 숙박+파티 콤보(packageBookings)는 예약 문서 하나로 **방과 파티 자리를 함께**
 * 잡는다. 그래서 QR도 둘이 나온다.
 *
 *   packageBookings/{id}                      → 숙소 체크인용
 *   parties/{partyId}/applications/{appId}    → 파티 입장용 (partyCheckIn.js)
 *
 * 하나로 합치지 않는 이유: 체크인 시각도 장소도 다르고, 무엇보다 호스트가
 * 파티 입구에서 찍을 때 보여야 하는 것은 객실이 아니라 파티 참가 상태다.
 * 두 QR은 서로 다른 원본을 가리키므로 하나를 쓴다고 다른 하나가 소진되지 않는다.
 *
 * ── 왜 트리거인가 / 재실행 안전 ─────────────────────────────────────────────
 * 예약이 확정되는 길도 취소되는 길도 여럿이다(자동승인·업주승인·입금확인 /
 * 본인취소·업주취소·거절·입금기한 만료·승인기한 만료). 콜러블마다 붙이면
 * 하나를 빠뜨린다. 문서의 최종 상태만 보고 판단하고, 발급은 멱등하다 —
 * 트리거가 몇 번 재실행돼도 살아 있는 토큰은 언제나 하나뿐이다
 * (checkInTokenStore.js).
 *
 * ── 숙박의 허용 구간 ────────────────────────────────────────────────────────
 * 발급 여부는 **확정 상태**만 보고, "지금 찍어도 되는 날인가"는 조회·사용
 * 시점에 checkInRules.reservationBlockReason이 본다(숙박은 체크인~체크아웃
 * 구간, 그 밖은 그날 하루). 두 축을 나눠 둔 덕에 현장결제 예약도 QR은 있고
 * 통과만 막힌다 — 호스트가 스캔해서 누가 왔는지 보고 그 자리에서 돈을 받는다.
 */

const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

const rules = require('./checkInRules');
const store = require('./checkInTokenStore');

const REGION = 'asia-northeast3';

/** 왜 QR이 죽었는지 — 감사용. 손님에게는 언제나 같은 문장이 나간다. */
function revokeReasonOf(doc) {
  const status = (doc && doc.status) || 'missing';
  return 'reservation_status_' + status;
}

/**
 * 예약 문서 한 건의 QR을 지금 상태에 맞춘다.
 *
 * 컬렉션 이름만 다르고 하는 일은 완전히 같아서 세 트리거가 이 함수를 공유한다.
 * 발급·무효화와 "값이 같으면 쓰지 않는다"는 루프 방지는 파티·상품과도 같은
 * 한 곳에 있다(checkInTokenStore.syncTokenField). db를 인자로 받는 이유는
 * self-check가 가짜 Firestore로 이 함수를 직접 부르기 위해서다.
 */
async function syncReservationToken(db, event, collection) {
  const after = event.data.after.exists ? event.data.after.data() : null;
  const refPath = `${collection}/${event.params.id}`;

  if (!after) {
    await store.revokeCheckInTokenFor(db, refPath, 'reservation_deleted');
    return;
  }

  await store.syncTokenField(db, {
    ref: event.data.after.ref,
    after,
    refPath,
    domain: rules.DOMAIN.reservation,
    hostId: after.hostId || '',
    guestUid: after.requesterId || after.guestId || '',
    active: rules.reservationQrActive(collection, after),
    revokeReason: revokeReasonOf(after),
  });
}

exports.onPlaceVisitReservationCheckIn = onDocumentWritten(
  { document: 'placeVisitReservations/{id}', region: REGION },
  (event) =>
    syncReservationToken(admin.firestore(), event, 'placeVisitReservations'),
);

exports.onPlaceReservationGroupCheckIn = onDocumentWritten(
  { document: 'placeReservationGroups/{id}', region: REGION },
  (event) =>
    syncReservationToken(admin.firestore(), event, 'placeReservationGroups'),
);

exports.onPackageBookingCheckIn = onDocumentWritten(
  { document: 'packageBookings/{id}', region: REGION },
  (event) => syncReservationToken(admin.firestore(), event, 'packageBookings'),
);

module.exports.__test = { revokeReasonOf, syncReservationToken };
