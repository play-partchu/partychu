const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');

const {
  REFUND_REQUEST_STATUS,
  COMPLETED_BY,
  COMPLETION_METHOD,
  OVERDUE_MS,
  buildRefundRequest,
  isOverdue,
} = require('./refundAccounts');
// 재제출에 쓸 계좌는 **인증된 것 하나뿐**이다 — 클라이언트가 보낸 값을
// 정규화해 쓰던 normalizeRefundAccount는 더 이상 이 파일에서 쓰지 않는다.
const { loadVerifiedRefundSnapshot } = require('./refundAccountVerify');

// 환불 요청 큐의 **처리** — 호스트가 기본, 관리자는 감시·개입.
//
// 참가자가 무통장입금한 돈은 파티츄가 아니라 **그 콘텐츠 호스트가 직접**
// 받는다(users/{uid}.payoutAccount — payoutAccounts.js). 받은 사람이 돌려주는
// 사람이므로 환불도 호스트가 자기 계좌에서 손으로 보낸다:
//
//   참가자 취소(환불액 발생) → refundRequests 접수(requested)
//   → **호스트**가 참가자 환불계좌로 송금 → 여기서 completed
//   → 참가자 화면도 '환불 완료'
//
// ⚠ '완료'는 **송금됐다는 증명이 아니다.** 시스템은 실제 이체를 확인할 수단이
//    없다 — 호스트가 "보냈다고 표시"한 것뿐이라, 문서에도 그렇게 적는다
//    (completionMethod: 'marked_manually'). 화면 문구도 자동 송금이나 PG 환불처럼
//    쓰면 안 된다. 분쟁은 그 표시와 참가자의 실제 입금 여부를 대조해 가린다.
//
// 관리자는 전체 큐를 보고 **개입**할 수 있다(장기 미처리·호스트 연락두절).
// 그 경우 completedByRole이 'admin'으로 남아 "누가 끝냈는지"가 구분된다.
//
// 접수(create)는 cancelApplication이 Admin SDK로만 하고, 상태 변경도 여기서만
// 한다 — 클라이언트는 규칙상 이 컬렉션에 아무것도 쓸 수 없다(firestore.rules).

const REGION = 'asia-northeast3';

async function isAdminUid(uid) {
  const snap = await admin.firestore().collection('users').doc(uid).get();
  return snap.exists && snap.data().role === 'admin';
}

/**
 * 이 환불 건을 처리할 수 있는 사람인가 — 그 건의 호스트 또는 관리자.
 *
 * 호스트 판정은 **요청 문서에 박힌 hostId**로 한다. 콘텐츠 문서를 다시 읽어
 * 판정하면, 호스트가 바뀌거나 콘텐츠가 삭제된 뒤에 처리 자체가 막힌다 —
 * 돈을 받은 사람은 접수 시점의 호스트다.
 *
 * @returns {Promise<'host'|'admin'>}
 */
async function resolveHandlerRole(uid, requestData) {
  if (requestData.hostId && requestData.hostId === uid) {
    return COMPLETED_BY.host;
  }
  if (await isAdminUid(uid)) return COMPLETED_BY.admin;
  throw new HttpsError(
    'permission-denied',
    '이 환불 건의 호스트 또는 관리자만 처리할 수 있어요.',
  );
}

/**
 * 송금을 끝낸 뒤 '환불 완료'로 표시한다(reject: true면 반려).
 *
 * 신청 문서의 refundStatus도 함께 바꾼다 — 참가자 화면이 보는 값이 그쪽이라,
 * 요청 큐만 바꾸면 참가자에게는 영영 '환불 대기'로 남는다.
 */
exports.completeRefundRequest = onCall(
  { region: REGION },
  async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');

    const { requestId, reject = false, memo = null } = request.data || {};
    if (typeof requestId !== 'string' || !requestId) {
      throw new HttpsError('invalid-argument', 'requestId가 필요합니다.');
    }
    // 반려는 **사유가 반드시 있어야 한다** — 참가자는 이 문구만 보고 무엇을
    // 고쳐 다시 내야 할지 판단한다. 사유 없는 반려는 참가자 입장에서
    // "이유 없이 막힌 상태"와 구분되지 않는다.
    const reason = typeof memo === 'string' ? memo.trim() : '';
    if (reject && !reason) {
      throw new HttpsError('invalid-argument', '반려 사유를 입력해주세요.');
    }

    const db = admin.firestore();
    const ref = db.collection('refundRequests').doc(requestId);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) {
        throw new HttpsError('not-found', '환불 요청을 찾을 수 없어요.');
      }
      const data = snap.data();
      // 권한은 문서를 읽은 **뒤에** 판정한다 — 이 건의 호스트인지 알아야 하기
      // 때문이다. 관리자 여부 조회는 트랜잭션 밖 읽기지만, 역할이 트랜잭션
      // 도중에 바뀔 일이 없어 문제되지 않는다.
      const role = await resolveHandlerRole(uid, data);

      // 두 번 눌러도 두 번 처리되지 않는다 — 송금이 두 번 나가는 것을 막는
      // 마지막 방어선이다.
      if (data.status !== REFUND_REQUEST_STATUS.requested) {
        throw new HttpsError('failed-precondition', '이미 처리된 환불 요청이에요.');
      }

      tx.update(ref, {
        status: reject
          ? REFUND_REQUEST_STATUS.rejected
          : REFUND_REQUEST_STATUS.completed,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        completedBy: uid,
        completedByRole: role,
        // 자동 송금이 아니라 **사람이 보냈다고 표시한 것**이다.
        completionMethod: reject ? null : COMPLETION_METHOD.markedManually,
        adminMemo: reason || null,
        rejectedReason: reject ? reason : null,
      });

      if (typeof data.applicationPath === 'string' && data.applicationPath) {
        tx.update(db.doc(data.applicationPath), {
          // 반려는 "아직 환불 안 됨"이므로 pending으로 되돌린다. 참가자는
          // 이 상태에서 계좌를 고쳐 재제출할 수 있다(resubmitRefundRequest).
          refundStatus: reject ? 'pending' : 'completed',
          refundCompletedAt: reject
            ? null
            : admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // 참가자에게 알린다 — 반려는 참가자가 **행동해야** 끝나는 상태라,
      // 알리지 않으면 아무도 다시 내지 않아 영영 멈춘다.
      tx.set(db.collection('notifications').doc(), {
        uid: data.requesterId,
        type: reject ? 'refund_rejected' : 'refund_completed',
        title: reject ? '환불 요청이 반려됐어요' : '환불이 완료됐어요',
        // 완료 문구도 "보냈다고 표시됨"에 맞춘다 — 시스템이 이체를 확인한
        // 것이 아니므로, 입금이 안 보이면 문의하라는 안내까지 함께 준다.
        body: reject
          ? `사유: ${reason}\n환불 정보를 다시 제출해주세요.`
          : `${data.refundAmount || 0}원을 보냈다고 확인됐어요.\n`
            + '입금이 보이지 않으면 문의해주세요.',
        refId: ref.id,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return { success: true };
  },
);

/**
 * 반려된 환불 요청을 **계좌를 고쳐 다시 낸다**(참가자 본인만).
 *
 * 기존 문서를 덮어쓰지 않고 **새 요청**을 만든다 — 반려된 건의 계좌 사본과
 * 반려 사유가 그대로 남아야 "어느 계좌로 보내려다 왜 막혔는지"를 나중에
 * 추적할 수 있다. 새 문서는 resubmittedFrom으로 앞 건을 가리키고 attempt가
 * 하나 올라간다.
 *
 * 서버가 막는 것 세 가지:
 *   1. 남의 요청 재제출      → 요청자 본인이 아니면 거절
 *   2. 이미 완료된 환불      → completed는 다시 낼 수 없다(중복 송금 방지)
 *   3. 중복 요청             → 같은 신청 건에 처리 대기(requested)가 이미 있으면 거절
 */
exports.resubmitRefundRequest = onCall(
  { region: REGION },
  async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');

    const { requestId } = request.data || {};
    if (typeof requestId !== 'string' || !requestId) {
      throw new HttpsError('invalid-argument', 'requestId가 필요합니다.');
    }

    const db = admin.firestore();

    // 계좌는 **인증된 것 하나뿐**이다 — 클라이언트가 보낸 값은 읽지 않는다.
    //
    // 예전에는 재제출 화면이 계좌를 자유 입력으로 받아 그 값을 새 요청 문서에
    // 그대로 박고 users/{uid}.refundAccount까지 덮어썼다. 반려된 요청을 고쳐
    // 다시 내는 자리라 계좌를 바꿀 수 있어야 하지만, 그 변경은 **환불계좌
    // 관리에서 다시 본인 인증을 받는 것**으로만 이뤄진다.
    const account = await loadVerifiedRefundSnapshot(db, uid);
    if (!account) {
      // 앱이 이 코드를 보고 환불계좌 인증 흐름을 띄운다(취소 흐름과 같은 코드).
      throw new HttpsError('failed-precondition', 'REFUND_ACCOUNT_REQUIRED');
    }
    const oldRef = db.collection('refundRequests').doc(requestId);
    let newId = null;

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(oldRef);
      if (!snap.exists) {
        throw new HttpsError('not-found', '환불 요청을 찾을 수 없어요.');
      }
      const prev = snap.data();

      // ① 남의 요청은 건드릴 수 없다.
      if (prev.requesterId !== uid) {
        throw new HttpsError('permission-denied', '본인의 환불 요청만 다시 낼 수 있어요.');
      }
      // ② 완료된 건은 재제출 대상이 아니다.
      if (prev.status === REFUND_REQUEST_STATUS.completed) {
        throw new HttpsError('failed-precondition', '이미 환불이 완료된 요청이에요.');
      }
      // ③ 반려된 건만 다시 낼 수 있다(처리 대기 중인 건은 그대로 기다린다).
      if (prev.status !== REFUND_REQUEST_STATUS.rejected) {
        throw new HttpsError('failed-precondition', '반려된 요청만 다시 낼 수 있어요.');
      }

      // ④ 같은 신청 건에 이미 대기 중인 요청이 있으면 또 만들지 않는다.
      //    tx.get(query)로 읽어야 트랜잭션이 이 조건까지 잠근다 — 평범한
      //    get()이면 두 번 연타했을 때 둘 다 통과해 요청이 두 개 생긴다.
      const dupe = await tx.get(
        db
          .collection('refundRequests')
          .where('applicationPath', '==', prev.applicationPath)
          .where('status', '==', REFUND_REQUEST_STATUS.requested)
          .limit(1),
      );
      if (!dupe.empty) {
        throw new HttpsError('failed-precondition', '이미 처리 대기 중인 환불 요청이 있어요.');
      }

      const newRef = db.collection('refundRequests').doc();
      newId = newRef.id;
      tx.set(
        newRef,
        buildRefundRequest({
          requesterId: uid,
          domain: prev.domain,
          refId: prev.refId,
          applicationPath: prev.applicationPath,
          refundAmount: prev.refundAmount,
          account,
          hostId: prev.hostId || null,
          title: prev.title || null,
          resubmittedFrom: requestId,
          attempt: (Number(prev.attempt) || 1) + 1,
        }),
      );
      // 앞 건에는 "이 건으로 이어졌다"만 남긴다 — 상태(rejected)와 계좌
      // 사본은 그대로 둔다.
      tx.update(oldRef, { resubmittedTo: newRef.id });

      // users/{uid}.refundAccount는 **여기서 쓰지 않는다** — 그 필드를 쓰는
      // 곳은 verifyRefundAccount 하나다. 여기서 다시 쓰면 인증 지문이 어긋나
      // 인증이 조용히 풀린다.

      if (typeof prev.applicationPath === 'string' && prev.applicationPath) {
        tx.update(db.doc(prev.applicationPath), { refundStatus: 'pending' });
      }
    });

    return { success: true, requestId: newId };
  },
);

/**
 * 장기 미처리 환불 재촉 — 하루 한 번.
 *
 * 자동 송금이 없는 구조에서 **호스트가 방치하면 참가자는 돈을 못 받은 채로
 * 끝난다.** 그걸 막는 유일한 안전망이라 별도 상태를 만들지 않고 접수 시각
 * 하나로 판정한다([isOverdue]) — 상태를 늘리면 화면·규칙·통계가 모두 갈린다.
 *
 * 하는 일은 둘이다.
 *   1. 호스트에게 다시 알린다(한 번만 — overdueNotifiedAt이 표시).
 *   2. 관리자 큐에 드러나도록 문서에 표시를 남긴다. 관리자 화면은 이 값으로
 *      "개입이 필요한 건"을 걸러 보고, 필요하면 직접 완료 처리할 수 있다
 *      (completedByRole: 'admin'으로 남는다).
 */
exports.notifyOverdueRefundRequests = onSchedule(
  {
    schedule: 'every day 10:00',
    timeZone: 'Asia/Seoul',
    region: REGION,
  },
  async () => {
    const db = admin.firestore();
    const nowMs = Date.now();
    const cutoff = admin.firestore.Timestamp.fromMillis(nowMs - OVERDUE_MS);

    // 아직 처리되지 않은 것 중 접수가 오래된 건만. 이미 재촉한 건은 아래에서
    // 걸러낸다(같은 알림이 매일 가면 알림함이 무의미해진다).
    const snap = await db
      .collection('refundRequests')
      .where('status', '==', REFUND_REQUEST_STATUS.requested)
      .where('createdAt', '<=', cutoff)
      .limit(200)
      .get();

    let notified = 0;
    for (const doc of snap.docs) {
      const data = doc.data();
      if (data.overdueNotifiedAt) continue;
      // 쿼리와 같은 판정을 한 번 더 — 기준이 갈리지 않게 정본은 isOverdue다.
      if (!isOverdue(data, nowMs)) continue;

      const batch = db.batch();
      batch.update(doc.ref, {
        overdueNotifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      if (data.hostId) {
        batch.set(db.collection('notifications').doc(), {
          uid: data.hostId,
          type: 'refund_overdue',
          title: '아직 보내지 않은 환불이 있어요',
          body: `${data.title || '취소된 신청'} · ${data.refundAmount || 0}원\n`
            + '참가자가 기다리고 있어요. 환불 요청 목록에서 처리해주세요.',
          refId: doc.id,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      notified += 1;
    }

    if (notified > 0) {
      console.log(`[refundRequests] 장기 미처리 환불 재촉 ${notified}건`);
    }
  },
);
