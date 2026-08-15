const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const {
  REFUND_REQUEST_STATUS,
  normalizeRefundAccount,
  buildRefundRequest,
} = require('./refundAccounts');

// 환불 요청 큐의 **운영자 처리**.
//
// 자동 송금(PG 환불 API)이 아직 없으므로 실제 돈은 운영자가 손으로 보낸다.
// 이 함수는 그 "보냈다"를 시스템에 반영하는 단 하나의 경로다:
//
//   참가자 취소(환불액 발생) → refundRequests 접수(requested)
//   → 운영자가 계좌로 송금 → 여기서 completed → 참가자 화면도 '환불 완료'
//
// 접수(create)는 cancelApplication이 Admin SDK로만 하고, 상태 변경도 여기서만
// 한다 — 클라이언트는 규칙상 이 컬렉션에 아무것도 쓸 수 없다(firestore.rules).

const REGION = 'asia-northeast3';

async function assertAdmin(uid) {
  const snap = await admin.firestore().collection('users').doc(uid).get();
  if (!snap.exists || snap.data().role !== 'admin') {
    throw new HttpsError('permission-denied', '관리자만 처리할 수 있어요.');
  }
}

/**
 * 운영자가 송금을 끝낸 뒤 '환불 완료'로 넘긴다(reject: true면 반려).
 *
 * 신청 문서의 refundStatus도 함께 바꾼다 — 참가자 화면이 보는 값이 그쪽이라,
 * 요청 큐만 바꾸면 참가자에게는 영영 '환불 대기'로 남는다.
 */
exports.completeRefundRequest = onCall(
  { region: REGION },
  async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    await assertAdmin(uid);

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
        body: reject
          ? `사유: ${reason}\n환불 정보를 다시 제출해주세요.`
          : `${data.refundAmount || 0}원을 보내드렸어요.`,
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

    const { requestId, refundAccount } = request.data || {};
    if (typeof requestId !== 'string' || !requestId) {
      throw new HttpsError('invalid-argument', 'requestId가 필요합니다.');
    }
    const account = normalizeRefundAccount(refundAccount);
    if (!account) {
      throw new HttpsError('invalid-argument', '환불계좌를 정확히 입력해주세요.');
    }

    const db = admin.firestore();
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

      // 다음에 또 쓰도록 본인 문서의 환불계좌도 갱신한다.
      tx.set(
        db.collection('users').doc(uid),
        {
          refundAccount: {
            ...account,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true },
      );

      if (typeof prev.applicationPath === 'string' && prev.applicationPath) {
        tx.update(db.doc(prev.applicationPath), { refundStatus: 'pending' });
      }
    });

    return { success: true, requestId: newId };
  },
);
