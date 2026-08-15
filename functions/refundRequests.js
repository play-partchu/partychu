const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const { REFUND_REQUEST_STATUS } = require('./refundAccounts');

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
        adminMemo: typeof memo === 'string' ? memo : null,
      });

      if (typeof data.applicationPath === 'string' && data.applicationPath) {
        tx.update(db.doc(data.applicationPath), {
          // 반려는 "아직 환불 안 됨"이므로 pending으로 되돌린다.
          refundStatus: reject ? 'pending' : 'completed',
          refundCompletedAt: reject
            ? null
            : admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    });

    return { success: true };
  },
);
