// ══════════════════════════════════════════════════════════════════════════
// 콘텐츠 삭제 콜러블 — 앱의 모든 삭제 버튼이 거치는 **단 하나의** 경로.
//
// 파티·장소(장소대여)·플레이스(events)·파티샵·파트너(크루)가 전부 이 함수
// 하나를 호출한다. 화면마다 doc.delete()를 따로 부르던 예전 방식은 두 가지
// 문제가 있었다:
//
//   1. 화면마다 정리하는 범위가 달랐다 — 어떤 화면은 룸까지 지우고, 어떤
//      화면은 본체 문서만 지웠다.
//   2. 클라이언트는 규칙상 parties/{id}/applications, 예약·주문 컬렉션을
//      아예 쓸 수 없다(allow write: if false). 그래서 클라이언트에서 지우면
//      연결 데이터가 반드시 고아로 남았다.
//
// 이 파일이 맡는 것은 **권한과 범위**뿐이다. 무엇을 지우고 무엇을 남길지는
// contentCleanup.js에 있고, 만료 콘텐츠 자동 삭제도 같은 모듈을 쓴다.
//
// ── 결제·예약이 남아 있으면 삭제하지 않는다 ────────────────────────────
// 결제 완료·승인된 신청이나 유효한 예약/주문이 하나라도 있으면
// failed-precondition으로 거절하고, 사용자에게 "먼저 취소·환불을 끝내라"고
// 안내한다. 삭제 버튼이 자동 환불을 실행하지는 않는다 — 환불은 기존
// 취소 경로(파티 상태를 '취소'로 바꾸면 onPartyCancelledByHost가 처리)가
// 담당한다. 돈이 걸린 처리를 삭제 버튼 하나에 묶지 않기 위해서다.
//
// 삭제가 끝난 뒤에도 주문·이용권·예약·결제된 신청서는 지우지 않고 남는다
// (전자상거래법상 거래기록 보존). 자세한 규칙은 contentCleanup.js 참고.
// ══════════════════════════════════════════════════════════════════════════

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const {
  readCloudflareCreds,
  MEDIA_CLEANUP_SECRETS,
} = require('./cloudflareCleanup');
const { TYPES, blockingReason, cleanupContentDoc } = require('./contentCleanup');

const LOG = 'contentDelete';

/// 문서의 소유자인가 — 컬렉션마다 hostId/hostUid 중 무엇을 쓰는지가 조금씩
/// 달라서 둘 다 본다(파티는 hostUid, 나머지는 hostId가 주 필드).
function isOwner(data, uid) {
  if (!uid) return false;
  return data.hostUid === uid || data.hostId === uid;
}

// ── 콜러블 ──────────────────────────────────────────────────────────────
//
// 입력: { type, id, scope }
//   type  — contentCleanup.js TYPES의 키
//   id    — 문서 id
//   scope — 'single'(기본) | 'series'
//           파티에서만 의미가 있다. 'series'면 같은 seriesId를 가진 날짜
//           문서를 전부 지운다(다중 날짜·정기 파티의 "전체 일정 삭제").
// 출력: { deletedCount, preservedCount }

exports.deleteContent = onCall(
  {
    region: 'asia-northeast3',
    secrets: MEDIA_CLEANUP_SECRETS,
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    }

    const type = String(request.data?.type || '');
    const id = String(request.data?.id || '');
    const scope = request.data?.scope === 'series' ? 'series' : 'single';
    const meta = TYPES[type];
    if (!meta || !id) {
      throw new HttpsError('invalid-argument', '삭제 대상이 올바르지 않습니다.');
    }

    const db = admin.firestore();
    const docRef = db.collection(meta.collection).doc(id);
    const snap = await docRef.get();
    if (!snap.exists) {
      throw new HttpsError('not-found', '이미 삭제된 항목입니다.');
    }
    const data = snap.data();

    const userDoc = await db.collection('users').doc(uid).get();
    const isAdmin = userDoc.exists && userDoc.data().role === 'admin';
    if (!isOwner(data, uid) && !isAdmin) {
      throw new HttpsError(
        'permission-denied',
        '등록한 본인 또는 관리자만 삭제할 수 있습니다.',
      );
    }

    // 삭제 대상 모으기 — 'series'면 같은 seriesId의 날짜 문서를 전부.
    let targets = [{ ref: docRef, data }];
    if (type === 'party' && scope === 'series') {
      const seriesId = data.seriesId || id;
      const siblings = await db
        .collection('parties')
        .where('seriesId', '==', seriesId)
        .get();
      const byId = new Map(targets.map((t) => [t.ref.id, t]));
      for (const sib of siblings.docs) {
        if (byId.has(sib.id)) continue;
        // 시리즈 안이라도 남의 문서는 건드리지 않는다(있을 수 없는 상황이지만
        // seriesId는 클라이언트가 쓰는 값이라 방어한다).
        if (!isOwner(sib.data(), uid) && !isAdmin) continue;
        byId.set(sib.id, { ref: sib.ref, data: sib.data() });
      }
      targets = [...byId.values()];
    }

    // 판정을 **먼저 전부** 돌린다 — 절반만 지우고 멈추면 사용자는 무엇이
    // 남았는지 알 수 없다.
    for (const target of targets) {
      const reason = await blockingReason(db, type, target.ref);
      if (reason) throw new HttpsError('failed-precondition', reason);
    }

    const creds = readCloudflareCreds(LOG);
    let preservedCount = 0;
    for (const target of targets) {
      const result = await cleanupContentDoc(
        db, type, target.ref, target.data, creds, LOG,
      );
      preservedCount += result.preserved;
    }

    return { deletedCount: targets.length, preservedCount };
  },
);
