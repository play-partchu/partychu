const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');

const { releaseApplicantSlot, applicationDocId } = require('./partyCapacity');
const flow = require('./depositFlow');
// 호스트에게 "입금 확인 요청이 왔어요"를 알린다. 알림 문서를 만드는 자리는
// 파티 계열 한 곳으로 모아 둔다(partyApplicationNotifications.js).
const { notifyHostDepositSent } = require('./partyApplicationNotifications');

/**
 * 파티 신청의 **무통장입금 흐름**.
 *
 *   신청(applied) + 입금대기(awaiting_deposit)
 *        │  참가자가 '입금했어요'          → markPartyDepositSent
 *        ▼
 *   입금확인중(deposit_pending)
 *        │  호스트가 '입금 확인'            → confirmPartyDeposit
 *        ▼
 *   결제완료(paid) + 신청 확정(approved)
 *
 *   기한이 지나도록 입금대기면 → expirePartyDeposits 가 결제 expired +
 *   신청 cancelled(정원 반납)로 정리한다.
 *
 * 원칙
 * - `status`(신청 진행)와 `payment.status`(결제)는 끝까지 **다른 축**이다.
 *   '입금확인중'이라고 신청이 확정되지 않고, 확정은 호스트가 돈을 확인한
 *   뒤에만 일어난다.
 * - 결제 상태 전이는 전부 **서버에서만** 일어난다. 클라이언트는 "눌렀다"는
 *   사실만 보내고, 어떤 상태가 되는지는 여기서 정한다.
 * - 모든 전이는 트랜잭션 안에서 현재 상태를 다시 읽고 확인한다 — 버튼을 두 번
 *   눌러도 두 번 처리되지 않는다.
 */

const REGION = 'asia-northeast3';

// 상태 전이 규칙은 플레이스 방문예약과 **같은 모듈**(depositFlow)을 쓴다 —
// 규칙이 갈라지면 한쪽만 고쳐 두 화면이 다르게 동작하는 사고가 난다. 여기에는
// 그 규칙에 신청 문서를 끼워 넣는 얇은 껍데기만 둔다.
const assertCanMarkSent = (appData) =>
  flow.assertCanMarkSent(appData?.payment, {
    cancelled: appData?.status === 'cancelled',
  });

const assertCanConfirm = (appData) =>
  flow.assertCanConfirm(appData?.payment, {
    cancelled: appData?.status === 'cancelled',
  });

// ── ① 참가자: "입금했어요" ────────────────────────────────────────────
// awaiting_deposit → deposit_pending. 이미 확인중이거나 확인이 끝난 건은
// 다시 누를 수 없다(중복 방지).
exports.markPartyDepositSent = onCall({ region: REGION }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  const { partyId, occurrenceId } = request.data || {};
  if (!partyId || typeof partyId !== 'string') {
    throw new HttpsError('invalid-argument', 'partyId가 필요합니다.');
  }
  if (occurrenceId !== undefined && occurrenceId !== null &&
      typeof occurrenceId !== 'string') {
    throw new HttpsError('invalid-argument', 'occurrenceId가 올바르지 않습니다.');
  }

  const uid = request.auth.uid;
  const db = admin.firestore();
  const applicationsRef = db.collection('parties').doc(partyId).collection('applications');
  // 회차별 신청은 결제도 회차별이다 — 8/15 입금을 알린다고 8/22 건의 상태가
  // 바뀌면 안 된다. 회차가 없거나 회차 문서가 아직 없으면(구조 변경 전 신청)
  // 예전 문서(id=uid)로 폴백한다.
  const scopedRef = applicationsRef.doc(applicationDocId(uid, occurrenceId || null));
  const legacyRef = applicationsRef.doc(uid);

  // 트랜잭션이 실제로 상태를 바꿨을 때만 알린다 — 알림에 필요한 값을 여기에
  // 담아 두고, **커밋이 끝난 뒤** 밖에서 한 번 보낸다. 트랜잭션은 충돌하면
  // 처음부터 다시 실행되므로 그 안에서 알림 문서를 만들면 재시도마다 같은
  // 푸시가 또 나간다(partyApplicationNotifications.js 상단 주석 참고).
  let notify = null;

  await db.runTransaction(async (transaction) => {
    const [scopedSnap, legacySnap] = await Promise.all([
      transaction.get(scopedRef),
      occurrenceId ? transaction.get(legacyRef) : Promise.resolve(null),
    ]);
    const legacyUsable =
      legacySnap && legacySnap.exists &&
      (legacySnap.data().occurrenceId || occurrenceId) === occurrenceId;
    const snap = scopedSnap.exists ? scopedSnap : (legacyUsable ? legacySnap : scopedSnap);
    if (!snap.exists) throw new HttpsError('not-found', '신청 내역을 찾을 수 없어요.');
    const appRef = snap.ref;

    // 트랜잭션 안에서 **다시 읽은** 값으로 판정한다 — 버튼을 두 번 눌러도
    // 두 번째는 여기서 걸린다.
    assertCanMarkSent(snap.data());

    const patch = flow.markSentPatch(Date.now());
    transaction.update(appRef, {
      'payment.status': patch.status,
      'payment.depositedAtMs': patch.depositedAtMs,
      statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    notify = { hostId: snap.data().hostId || null, applicationId: appRef.id };
  });

  // 알림 실패로 입금 표시까지 되돌리지 않는다 — 상태 전이는 이미 끝났고,
  // 호스트는 신청자 관리 화면에서 같은 건을 그대로 볼 수 있다.
  if (notify?.hostId) {
    try {
      const partySnap = await db.collection('parties').doc(partyId).get();
      await notifyHostDepositSent(db, {
        hostId: notify.hostId,
        partyId,
        applicationId: notify.applicationId,
        partyTitle: partySnap.exists ? (partySnap.data().title || '') : '',
      });
    } catch (e) {
      console.error(`[partyDeposit] 호스트 알림 실패 party=${partyId}:`, e.message);
    }
  }

  return { success: true, status: flow.STATUS.depositPending };
});

// ── ② 호스트/관리자: "입금 확인" ──────────────────────────────────────
// deposit_pending → paid + 신청 확정(approved).
// 참가자가 '입금했어요'를 누르지 않았어도(awaiting_deposit) 실제로 돈이
// 들어왔다면 호스트가 바로 확인할 수 있어야 하므로 그 상태도 받아준다.
exports.confirmPartyDeposit = onCall({ region: REGION }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  const { partyId, applicantUid, applicationId } = request.data || {};
  if (!partyId || typeof partyId !== 'string') {
    throw new HttpsError('invalid-argument', 'partyId가 필요합니다.');
  }
  // 호스트 화면은 getApplicants가 내려준 applicationId를 그대로 되돌려 보낸다
  // — 회차별 신청을 정확히 한 건만 지목하기 위해서다(같은 사람이 8/15·8/22를
  // 둘 다 신청했으면 uid만으로는 어느 건인지 알 수 없다).
  // applicantUid는 회차 개념이 없던 옛 앱 호환용 폴백이다.
  const targetId = typeof applicationId === 'string' && applicationId
    ? applicationId
    : applicantUid;
  if (!targetId || typeof targetId !== 'string') {
    throw new HttpsError('invalid-argument', 'applicationId가 필요합니다.');
  }

  const uid = request.auth.uid;
  const db = admin.firestore();
  const partyRef = db.collection('parties').doc(partyId);
  const appRef = partyRef.collection('applications').doc(targetId);

  await db.runTransaction(async (transaction) => {
    const [partySnap, appSnap] = await Promise.all([
      transaction.get(partyRef),
      transaction.get(appRef),
    ]);
    if (!partySnap.exists) throw new HttpsError('not-found', '파티를 찾을 수 없어요.');
    if (!appSnap.exists) throw new HttpsError('not-found', '신청 내역을 찾을 수 없어요.');

    // 돈이 들어왔다고 표시할 수 있는 사람은 그 파티의 호스트뿐이다.
    if (partySnap.data().hostId !== uid) {
      throw new HttpsError('permission-denied', '이 파티의 호스트만 확인할 수 있어요.');
    }

    // 같은 이유로 확인 버튼도 트랜잭션 안에서 다시 판정한다(두 번 눌러도
    // 두 번 확정되지 않는다).
    assertCanConfirm(appSnap.data());

    const patch = flow.confirmPatch(Date.now(), uid);
    transaction.update(appRef, {
      // 결제와 신청을 **함께** 넘긴다 — 돈이 확인된 순간이 곧 확정이다.
      'payment.status': patch.status,
      'payment.paidAtMs': patch.paidAtMs,
      'payment.confirmedBy': patch.confirmedBy,
      status: 'approved',
      confirmedAt: admin.firestore.FieldValue.serverTimestamp(),
      statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return { success: true, status: flow.STATUS.paid };
});

// ── ③ 기한 만료 정리 ──────────────────────────────────────────────────
// 입금기한이 지나도록 **입금대기**인 신청은 결제 expired + 신청 cancelled로
// 정리하고 정원을 반납한다.
//
// '입금확인중'은 건드리지 않는다 — 참가자는 입금했다고 알렸는데 호스트 확인이
// 늦은 것뿐일 수 있어, 자동 취소하면 이미 낸 돈이 있는 사람을 떨어뜨리게 된다.
// 그 건은 호스트가 목록에서 직접 처리한다.
exports.expirePartyDeposits = onSchedule(
  { schedule: 'every 10 minutes', timeZone: 'Asia/Seoul', region: REGION },
  async () => {
    const db = admin.firestore();
    const now = Date.now();
    const snap = await db
      .collectionGroup('applications')
      .where('payment.status', '==', 'awaiting_deposit')
      .where('payment.depositDeadlineMs', '<', now)
      .get();

    console.log(`[expirePartyDeposits] 만료 대상 ${snap.size}건`);

    for (const doc of snap.docs) {
      try {
        const partyRef = doc.ref.parent.parent;
        if (!partyRef) continue;
        await db.runTransaction(async (transaction) => {
          const [freshApp, partySnap] = await Promise.all([
            transaction.get(doc.ref),
            transaction.get(partyRef),
          ]);
          if (!freshApp.exists || !partySnap.exists) return;
          const appData = freshApp.data();
          // 그 사이에 입금했다고 알렸거나 확인이 끝났으면 건드리지 않는다
          // (판정은 방문예약과 같은 flow.isExpirable을 쓴다).
          if (!flow.isExpirable(appData.payment, now)) return;
          if (appData.status === 'cancelled') return;

          // 정원·카운터 반납 — 신청 취소와 같은 헬퍼를 쓴다.
          const updateData = releaseApplicantSlot(partySnap.data(), {
            uid: appData.uid || doc.id,
            gender: appData.gender,
            selectedRounds: appData.selectedRounds,
            occurrenceId: appData.occurrenceId || null,
            roundCounterScope: appData.roundCounterScope || null,
          });
          transaction.update(partyRef, updateData);
          const expired = flow.expirePatch(now);
          transaction.update(doc.ref, {
            'payment.status': expired.status,
            'payment.cancelledAtMs': expired.cancelledAtMs,
            status: 'cancelled',
            cancelledBy: 'system',
            cancelReason: 'deposit_expired',
            // 입금 자체가 없었으므로 환불할 것도 없다.
            refundPercent: 0,
            refundAmount: 0,
            refundStatus: 'not_applicable',
            statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        });
      } catch (e) {
        console.error(`[expirePartyDeposits] ${doc.ref.path} 실패: ${e.message}`);
      }
    }
  },
);

// 상태 판정 규칙은 자체 검증(paymentInfo.selfcheck.js)에서 그대로 부른다.
exports.assertCanMarkSent = assertCanMarkSent;
exports.assertCanConfirm = assertCanConfirm;
