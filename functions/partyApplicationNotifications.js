const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

const { pushNotification } = require('./reservationNotifications');
const { isComboGeneratedApplication } = require('./hostInbox');

// ── 파티 신청 → 호스트 알림 ─────────────────────────────────────────────────
//
// 예약 3종(방문예약·장소대여·숙박+파티 콤보)은 예약이 만들어지는 순간 호스트에게
// "새 예약 신청" 알림을 만든다. **파티만 그게 없었다** — 호스트는 신청자가
// 생겨도 파티별 신청자 화면에 직접 들어가 보기 전까지 알 방법이 없었고,
// 승인제 파티의 pending 신청은 호스트가 승인하지 않으면 영영 확정되지 않으므로
// 이 누락이 가장 아팠다.
//
// ⚠️ 알림을 applyToParty **트랜잭션 안에서 만들지 않는다.**
//    트랜잭션은 충돌하면 처음부터 다시 실행된다 — 그 안에서 알림 문서를 만들면
//    재시도 횟수만큼 알림이 생기고, 그 문서 하나하나가 pushDispatch의 트리거를
//    깨워 같은 푸시를 여러 번 보낸다. 문서 생성은 커밋될 때 한 번만 일어나므로
//    이 트리거는 **신청 문서 1건당 정확히 한 번** 깨어난다.
//    (같은 이유로 pushDispatch.js도 발송을 문서 트리거로 받는다.)
//
// 알림 문서만 만들면 FCM 푸시는 onNotificationCreated가 알아서 보낸다 —
// 여기서 발송 코드를 부르지 않는다.

const REGION = 'asia-northeast3';
const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
const WEEKDAYS = ['일', '월', '화', '수', '목', '금', '토'];

/** '8월 22일(금) 오후 7시' — 알림 본문에 붙는 회차 날짜. */
function kstLabel(date) {
  if (!date) return '';
  const kst = new Date(date.getTime() + KST_OFFSET_MS);
  const month = kst.getUTCMonth() + 1;
  const day = kst.getUTCDate();
  const weekday = WEEKDAYS[kst.getUTCDay()];
  const hour24 = kst.getUTCHours();
  const minute = kst.getUTCMinutes();
  const ampm = hour24 < 12 ? '오전' : '오후';
  const hour = hour24 % 12 === 0 ? 12 : hour24 % 12;
  const time = minute === 0 ? `${hour}시` : `${hour}시 ${minute}분`;
  return `${month}월 ${day}일(${weekday}) ${ampm} ${time}`;
}

function toDate(value) {
  if (!value) return null;
  if (typeof value.toDate === 'function') return value.toDate();
  return null;
}

/**
 * 이 신청이 **어느 날짜의 것인지**.
 *
 * 정기 파티는 회차마다 신청 문서가 따로 있고 각자 occurrenceStartAt을 들고
 * 있다 — 파티 문서의 partyDateTime(등록 시점의 첫 회차 캐시)을 쓰면 8/22
 * 신청에 8/15가 찍힌다. 회차가 없는 파티만 partyDateTime으로 떨어진다.
 */
function applicationStartAt(appData) {
  return toDate(appData.occurrenceStartAt) || toDate(appData.partyDateTime);
}

/**
 * 신청 문서 하나가 호스트에게 만들 알림.
 *
 * 승인제(pending)와 즉시확정(applied)은 호스트가 **해야 하는 일이 다르다** —
 * 하나는 승인을 기다리는 일이고 하나는 알아두면 되는 일이라, 문구를 갈라
 * 알림함에서 구분되게 한다. 둘 중 하나만 만들어진다(신청 1건 = 알림 1건).
 */
function applicationNotification({ appData, partyTitle }) {
  const isPending = appData.status === 'pending';
  const when = kstLabel(applicationStartAt(appData));
  const where = partyTitle || '내 파티';
  return {
    type: isPending ? 'party_application_pending' : 'party_application_new',
    title: isPending
      ? '승인이 필요한 새 파티 신청이 들어왔어요'
      : '새 파티 신청이 들어왔어요',
    body: when ? `${where} · ${when}` : where,
  };
}

exports.onPartyApplicationCreated = onDocumentCreated(
  {
    document: 'parties/{partyId}/applications/{applicationId}',
    region: REGION,
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const appData = snap.data() || {};

    // 취소된 상태로 **생성되는** 신청은 없지만, 있더라도 알릴 것이 없다.
    if (appData.status === 'cancelled') return;

    // ⚠️ 숙박+파티 콤보는 예약 문서와 **파티 신청 문서를 함께** 만든다
    //    (packageBookings.js — 자리가 확정되는 순간 신청 문서를 넣는다).
    //    그쪽은 이미 "새 숙박+파티 예약 신청" 알림을 호스트에게 보내므로,
    //    여기서 또 만들면 예약 한 건에 알림이 두 번 간다. 콤보에서 나온
    //    판별은 통합 목록과 **같은 함수**를 쓴다(hostInbox.js) — 한쪽만 고치면
    //    알림은 두 번 가는데 목록에는 한 줄만 뜨는 식으로 어긋난다.
    if (isComboGeneratedApplication(appData)) return;

    const db = admin.firestore();
    const { partyId } = event.params;

    // 받는 사람은 신청 문서에 박힌 hostId가 정본이다. hostId가 없던 시절의
    // 신청은 이 트리거가 생기기 전 것이라 여기 오지 않지만, 파티 문서를 한 번
    // 더 읽어 제목과 함께 폴백을 잡는다(문서가 지워진 파티면 둘 다 없다).
    const partySnap = await db.collection('parties').doc(partyId).get();
    const party = partySnap.exists ? partySnap.data() : null;
    const hostId = appData.hostId || party?.hostId || party?.hostUid || null;
    if (!hostId) {
      console.warn(`[partyApplication] hostId 없음 — 알림 생략 party=${partyId}`);
      return;
    }
    // 호스트가 자기 파티에 신청하는 경우(테스트 계정 등)까지 알릴 필요는 없다.
    if (hostId === (appData.uid || '')) return;

    const { type, title, body } = applicationNotification({
      appData,
      partyTitle: party?.title || '',
    });

    const batch = db.batch();
    pushNotification(batch, db, {
      uid: hostId,
      type,
      title,
      body,
      role: 'host',
      partyId,
      // 예약 알림과 달리 플레이스가 없다 — 있지도 않은 컬렉션 이름을 넣으면
      // 알림함이 엉뚱한 곳을 열려고 한다.
      placeCollection: null,
      refCollection: 'applications',
      refId: snap.id,
    });
    await batch.commit();
  },
);

/**
 * 참가자가 '입금했어요'를 눌렀을 때 호스트에게 가는 알림.
 *
 * 예약 3종에는 이미 있는 알림인데(`*_deposit_sent`) 파티에만 없었다 — 호스트가
 * 입금을 확인해줘야 신청이 확정되므로, 알리지 않으면 참가자는 돈을 보내놓고
 * 기다리기만 한다.
 *
 * 트랜잭션 **밖에서**, 커밋이 끝난 뒤 한 번만 부른다(위 트리거와 같은 이유).
 */
async function notifyHostDepositSent(db, { hostId, partyId, applicationId, partyTitle }) {
  if (!hostId) return;
  const batch = db.batch();
  pushNotification(batch, db, {
    uid: hostId,
    type: 'party_deposit_sent',
    title: '입금 확인 요청이 왔어요',
    body: partyTitle ? `${partyTitle} 신청자가 입금을 알렸어요.` : '신청자가 입금을 알렸어요.',
    role: 'host',
    partyId,
    placeCollection: null,
    refCollection: 'applications',
    refId: applicationId,
  });
  await batch.commit();
}

module.exports.notifyHostDepositSent = notifyHostDepositSent;
module.exports.__helpers = { kstLabel, applicationStartAt, applicationNotification };
