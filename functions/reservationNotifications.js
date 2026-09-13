const admin = require('firebase-admin');

/**
 * 예약 계열(플레이스 방문예약 · 장소대여 예약)과 **파티 신청**이 함께 쓰는
 * 인앱 알림 한 건.
 *
 * 원래 placeVisitReservations.js 안에만 있던 함수를 그대로 꺼낸 것이다 —
 * 장소대여에도 승인/입금 알림이 필요해지면서 같은 문서를 두 곳에서 만들게
 * 됐는데, 필드 하나가 갈라지면 알림함이 한쪽만 열리는 사고가 난다.
 *
 * FCM 발송은 **여기서 하지 않는다.** 이 함수는 배치/트랜잭션 안에서 불리는데,
 * 트랜잭션은 충돌하면 처음부터 다시 실행되므로 그 안에서 보내면 재시도마다
 * 같은 푸시가 또 나간다(보낸 알림은 롤백되지 않는다). 문서가 커밋된 뒤
 * onNotificationCreated 트리거가 한 번만 받아 보낸다(pushDispatch.js).
 *
 * @param batchOrTx  WriteBatch 또는 Transaction — 호출부의 원자성에 그대로 얹는다.
 * @param {string} refCollection  알림을 눌렀을 때 열어야 할 예약 문서의 컬렉션.
 * @param {string} placeCollection  플레이스가 어느 컬렉션인지
 *   ('events' = 술집·바·카페 / 'places' = 공간대여·숙박).
 * @param {string} partyId  파티 계열 알림이 가리키는 파티. 예약 3종은 placeId로
 *   갈 곳을 정하므로 이 값이 없다. 파티 신청 알림이 생기면서 필요해졌는데,
 *   알림 문서 모양이 종류마다 갈리면 알림함과 라우팅이 각각 예외를 갖게 되므로
 *   문서를 만드는 자리는 계속 여기 하나로 둔다.
 */
function pushNotification(
  batchOrTx,
  db,
  {
    uid,
    type,
    title,
    body,
    role = 'guest',
    partyId = null,
    placeId = null,
    placeCollection = 'events',
    refCollection = null,
    refId = null,
  },
) {
  // 받는 사람이 없으면(예: hostId가 비어 있는 옛 문서) 알림을 만들지 않는다 —
  // uid가 빈 알림은 아무도 읽을 수 없어 쓰레기 문서만 남는다.
  if (!uid) return;
  const ref = db.collection('notifications').doc();
  batchOrTx.set(ref, {
    uid,
    type,
    title,
    body,
    role,
    // 파티 알림은 partyId를 쓰지만 예약 알림은 어디로 보낼지가 다르다 —
    // 알림함이 종류에 따라 이동할 수 있도록 참조를 함께 남긴다.
    partyId: partyId || null,
    placeId: placeId || null,
    placeCollection,
    refCollection,
    refId: refId || null,
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

module.exports = { pushNotification };
