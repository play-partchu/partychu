const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

// ── 관리자 업무 알림 ─────────────────────────────────────────────────────────
//
// 운영자가 "처리해야 할 일이 생겼다"는 것을 관리자 웹에서 바로 알아채게 하는
// 자리다. 사용자 알림(notifications)과 **컬렉션부터 분리**한다 — 거기에 관리자
// uid로 쓰면 onNotificationCreated 트리거가 관리자 개인 폰으로 FCM을 쏘고,
// 관리자가 사용자 앱을 켰을 때 홈 종에 운영 전용 내용이 섞여 보인다.
//
// ── 왜 트리거인가 ────────────────────────────────────────────────────────────
// 신청서를 만드는 곳(hostPreRegistration.js의 receiveEntry)은 **트랜잭션 안**
// 이다. 트랜잭션은 충돌하면 처음부터 다시 실행되므로 그 안에서 알림을 만들면
// 재시도마다 중복된다. 문서가 커밋된 뒤 트리거가 받으면 그런 일이 없다.
// (pushDispatch.js가 사용자 알림에서 같은 판단을 한 이유와 동일하다.)
//
// ── 소급 알림을 막는 두 겹 ───────────────────────────────────────────────────
// 이 기능을 켜는 시점에 이미 쌓여 있던 신청서(운영 3건)가 알림으로 쏟아지면
// 안 된다. 그래서 두 가지를 동시에 건다.
//
//   ① **생성 이벤트에서만 알림을 만든다.** 이미 있는 문서는 create 이벤트가
//      영영 오지 않으므로, 그 문서를 나중에 수정·재저장해도 알림이 생기지
//      않는다.
//   ② **접수 시각이 NOTIFY_FROM 이후인 것만.** ①만으로도 충분하지만, 과거
//      신청을 어떤 이유로든 다시 write하게 되는 날을 대비한 안전장치다.
//
// 내용 보완(update) 경로는 **이미 있는 알림만 고친다.** 없으면 만들지 않는다 —
// 그래야 옛 문서를 손대도 신규 알림으로 오인되지 않는다.

const REGION = 'asia-northeast3';

const COLLECTION = 'adminNotifications';

/**
 * 이 시각 **이후**에 접수된 신청만 알림을 만든다.
 *
 * 관리자 알림센터를 붙이기 전에 접수된 신청서는 이미 관리자가 목록에서 보고
 * 처리하고 있던 것들이라, 알림으로 다시 띄우면 전부 '안 읽음'으로 쌓인다.
 * 운영에 남아 있는 마지막 과거 신청(FormHug #3, 2026-09-17T03:18Z)보다 뒤로
 * 잡는다.
 */
const NOTIFY_FROM_MS = Date.UTC(2026, 8, 18, 0, 0, 0); // 2026-09-18T00:00:00Z

/** 알림 종류 — 나중에 붙일 것들을 여기 한 곳에 모은다. */
const ADMIN_NOTIFICATION_TYPE = {
  hostPreRegistration: 'host_pre_registration',
  // 앞으로: businessDelegation(대표자 확인 필요), report(신고 접수),
  //         feedback(문의) … 전부 아래 buildNotification 한 곳에 붙인다.
};

/**
 * 알림 문서 id — **신청서 id에서 결정적으로 만든다.**
 *
 * 재시도·재전송이 몇 번 와도 같은 문서를 가리키므로 알림이 두 번 생기지
 * 않고, 내용 보완도 같은 문서를 고치면 된다(읽음 상태가 유지된다).
 */
function notificationIdFor(type, refId) {
  return `${type}__${refId}`;
}

/** Firestore Timestamp | Date | number → ms. 못 읽으면 null. */
function toMillis(value) {
  if (!value) return null;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (value instanceof Date) return value.getTime();
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value._seconds === 'number') return value._seconds * 1000;
  return null;
}

/**
 * 호스트 사전등록 신청 한 건 → 알림 본문.
 *
 * 신청서는 **두 단계로 채워진다.** 웹훅이 먼저 번호만 있는 문서를 만들고
 * (importState:'pending'), 그 다음 FormHug API에서 업체명 등을 가져온다
 * ('ok'). 그래서 처음에는 업체명 없이 알리고, 채워지면 문구만 보완한다 —
 * 늦게 정확히 알리는 것보다 **바로 알리고 나중에 정확해지는 쪽**이 낫다.
 */
function buildHostPreRegistrationBody(data) {
  const storeName = (data.storeName || '').toString().trim();
  return storeName
    ? `${storeName}에서 새로운 사전등록 신청이 들어왔습니다.`
    : '새로운 호스트 사전등록 신청이 들어왔습니다.';
}

function buildHostPreRegistrationNotification(preId, data) {
  return {
    type: ADMIN_NOTIFICATION_TYPE.hostPreRegistration,
    title: '새로운 사전등록 신청',
    body: buildHostPreRegistrationBody(data),
    // 눌렀을 때 어디로 갈지 — 관리자 앱의 라우팅 규칙이 이 두 칸만 본다
    // (admin_app/lib/utils/admin_notification_route.dart).
    refCollection: 'hostPreRegistrations',
    refId: preId,
  };
}

/**
 * 이 신청서가 알림 대상인가 — 소급 방지 ②.
 *
 * 접수 시각을 읽을 수 없는 문서는 **알리지 않는다.** 시각을 모르면 과거
 * 신청인지 아닌지 가릴 수 없는데, 틀렸을 때의 대가가 비대칭이다(안 알리면
 * 목록에서 보이지만, 잘못 알리면 과거 신청이 전부 안 읽음으로 쌓인다).
 */
function shouldNotifyForCreate(data, { notifyFromMs = NOTIFY_FROM_MS } = {}) {
  const at = toMillis(data.submittedAt) ?? toMillis(data.createdAt);
  if (at === null) return false;
  return at >= notifyFromMs;
}

/**
 * 트리거 본체에서 Firestore만 뺀 순수 결정 로직.
 *
 * 'create'  새 알림을 만든다(이미 있으면 그대로 둔다).
 * 'enrich'  이미 있는 알림의 문구만 고친다. 없으면 아무것도 하지 않는다.
 * 'skip'    아무것도 하지 않는다.
 */
function decide({ beforeExists, afterExists, afterData }, options = {}) {
  if (!afterExists) return { action: 'skip', reason: 'deleted' };
  if (!beforeExists) {
    return shouldNotifyForCreate(afterData, options)
      ? { action: 'create', reason: 'new' }
      : { action: 'skip', reason: 'beforeCutoff' };
  }
  return { action: 'enrich', reason: 'updated' };
}

/**
 * 호스트 사전등록 신청서가 쓰일 때마다 관리자 알림을 맞춘다.
 *
 * onDocumentWritten을 쓰는 이유: 생성(알림 만들기)과 수정(문구 보완)을 한
 * 트리거에서 다뤄야 "생성 직후 import가 끝나는" 흐름을 놓치지 않는다.
 */
exports.onHostPreRegistrationWriteNotifyAdmin = onDocumentWritten(
  { document: 'hostPreRegistrations/{preRegistrationId}', region: REGION },
  async (event) => {
    const before = event.data && event.data.before;
    const after = event.data && event.data.after;
    if (!after) return;

    const preId = event.params.preRegistrationId;
    const afterData = after.exists ? after.data() || {} : {};

    const { action, reason } = decide({
      beforeExists: Boolean(before && before.exists),
      afterExists: Boolean(after.exists),
      afterData,
    });
    if (action === 'skip') {
      console.log(`[adminNotif] 건너뜀 pre=${preId} reason=${reason}`);
      return;
    }

    const db = admin.firestore();
    const payload = buildHostPreRegistrationNotification(preId, afterData);
    const ref = db
      .collection(COLLECTION)
      .doc(notificationIdFor(payload.type, preId));

    // 트랜잭션으로 읽고 쓴다 — 트리거가 같은 문서에 대해 두 번 깨어나도
    // (Cloud Functions는 최소 1회 전달이다) 알림이 두 개가 되거나 readBy가
    // 지워지지 않는다.
    const outcome = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);

      if (action === 'create') {
        // 이미 있으면 **손대지 않는다.** 재전달로 다시 들어온 것이고,
        // 그 사이 관리자가 읽었을 수 있다.
        if (snap.exists) return 'alreadyExists';
        tx.set(ref, {
          ...payload,
          // 읽은 관리자들의 uid. 여럿일 때 한 사람이 읽어도 다른 사람의
          // 안 읽음이 그대로 남아야 해서 배열로 둔다.
          readBy: [],
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return 'created';
      }

      // enrich — 없으면 만들지 않는다(소급 방지의 핵심).
      if (!snap.exists) return 'noNotification';
      if (snap.get('title') === payload.title && snap.get('body') === payload.body) {
        return 'unchanged';
      }
      // title·body만 덮어쓴다. readBy·createdAt은 **건드리지 않는다** —
      // 내용이 보완됐다고 이미 읽은 사람의 읽음이 풀리면 안 된다.
      tx.set(
        ref,
        {
          title: payload.title,
          body: payload.body,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return 'enriched';
    });

    console.log(`[adminNotif] pre=${preId} action=${action} result=${outcome}`);
  },
);

exports.__helpers = {
  ADMIN_NOTIFICATION_TYPE,
  NOTIFY_FROM_MS,
  buildHostPreRegistrationBody,
  buildHostPreRegistrationNotification,
  decide,
  notificationIdFor,
  shouldNotifyForCreate,
  toMillis,
};
