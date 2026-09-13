// ── 파티 오픈 상태 (오픈예정 → 모집중 전환 + 오픈 알림) ────────────────────
//
// recruitStatus('모집중'/'마감'/'취소')에는 손대지 않는다. 그 문자열은 앱과
// 서버 10여 곳에 하드코딩돼 있어서 값을 하나 더 늘리면 한 군데만 놓쳐도
// 신청이 뚫린다. 대신 독립 필드 openState를 둔다:
//
//   openState: 'preopen'  — 오픈예정. 신청·예약·결제 전부 불가. 오픈 알림만 받는다.
//              'open'     — 정상 파티. 기존 recruitStatus 로직이 그대로 적용된다.
//   (필드 없음)           — 'open'으로 간주. **기존 파티는 전부 무영향.**
//
// 오픈 권한:
//   · 사업자 인증 완료 호스트          → 언제든 오픈 가능
//   · 미인증(개인) 호스트              → appConfig/policy.individualHostOpeningEnabled
//                                        가 true일 때만 오픈 가능
//   정책이 true로 바뀌어도 기존 오픈예정 파티가 자동으로 열리지는 않는다 —
//   호스트가 이 함수를 직접 호출해야 한다.
//
// 오픈 알림은 파티당 1회만 나간다. openAlertsSentAt을 트랜잭션 안에서
// 확인·기록("선점")한 뒤 그 밖에서 팬아웃하므로, 동시에 두 번 눌러도
// 두 번째 호출은 선점에 실패해 알림을 만들지 않는다.

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { isRecurringParty } = require('./partySchedule');
const { isBusinessVerified } = require('./businessVerification');

const POLICY_DOC_PATH = 'appConfig/policy';
const NOTIFICATION_BATCH_SIZE = 400;

// ── 상태 헬퍼 (클라이언트 PartyOpenState와 같은 규칙) ──────────────────
function openStateOf(data) {
  const raw = data && data.openState;
  return raw === 'preopen' ? 'preopen' : 'open';
}

function isPreopen(data) {
  return openStateOf(data) === 'preopen';
}

// ── 필수정보 완성 검사 (순수 함수 — 셀프체크 가능) ─────────────────────
//
// 오픈예정으로 사전등록할 때는 날짜를 안 받았으므로, 실제 오픈 전에 날짜와
// 나머지 필수 항목이 채워졌는지 여기서 확인한다. 반환값은 비어 있으면 통과.
function missingFieldsForOpen(data) {
  const missing = [];
  const d = data || {};

  if (!String(d.title || '').trim()) missing.push('파티명');

  // 날짜 — 정기 파티는 요일 스케줄로, 일회성은 partyDateTime으로 판정한다.
  if (d.dateTbd === true) {
    missing.push('파티 날짜');
  } else if (!isRecurringParty(d) && !d.partyDateTime) {
    missing.push('파티 날짜');
  }

  const hasAddress = String(d.address || d.roadAddress || d.jibunAddress || '').trim();
  if (!hasAddress) missing.push('장소');

  const people = Number(d.people ?? d.maxParticipants ?? 0);
  if (!Number.isFinite(people) || people <= 0) missing.push('모집 인원');

  return missing;
}

// ── 오픈 권한 판정 (순수 함수 — 셀프체크 가능) ─────────────────────────
//
// 반환: { allowed, reason }
function evaluateOpenPermission({ businessVerified, individualHostOpeningEnabled }) {
  if (businessVerified) return { allowed: true, reason: null };
  if (individualHostOpeningEnabled === true) return { allowed: true, reason: null };
  return { allowed: false, reason: 'individualHostOpeningDisabled' };
}

async function readIndividualHostOpeningEnabled(db) {
  const snap = await db.doc(POLICY_DOC_PATH).get();
  if (!snap.exists) return false; // 문서가 없으면 잠긴 상태가 기본값이다.
  return snap.data().individualHostOpeningEnabled === true;
}

// ── 생성 권한 판정 (순수 함수 — 셀프체크 가능) ─────────────────────────
//
// 오픈 권한과 **다른 질문**이다. 오픈은 "이미 만든 파티의 모집을 여는가"이고
// 이쪽은 "파티를 만들 수 있는가"다. 개인(사업자 미인증) 호스트의 파티 등록은
// 준비 중이라 지금은 생성부터 잠겨 있고, 열리면 그 다음 단계로 오픈이 남는다.
//
// 정책 문서는 같은 appConfig/policy 하나를 쓰되 **키가 다르다**
// (individualHostPartyCreateEnabled). 두 값을 한 키로 묶으면 "만들 수는 있는데
// 못 여는" 중간 단계를 표현할 수 없다.
//
// 반환: { allowed, reason }
function evaluatePartyCreatePermission({
  businessVerified,
  individualHostPartyCreateEnabled,
}) {
  if (businessVerified) return { allowed: true, reason: null };
  if (individualHostPartyCreateEnabled === true) {
    return { allowed: true, reason: null };
  }
  return { allowed: false, reason: 'individualHostPartyCreateDisabled' };
}

/// 문서가 없거나 값이 없으면 **잠긴 것으로 본다**(fail-closed) —
/// firestore.rules의 individualPartyCreateEnabled()와 같은 판정이다.
async function readIndividualHostPartyCreateEnabled(db) {
  const snap = await db.doc(POLICY_DOC_PATH).get();
  if (!snap.exists) return false;
  return snap.data().individualHostPartyCreateEnabled === true;
}

/// 개인 호스트에게 보여줄 안내 — 앱 시트와 같은 말을 쓴다.
const INDIVIDUAL_PARTY_CREATE_BLOCKED_MESSAGE =
  '개인 파티 등록은 준비 중이에요. 사업자가 아닌 개인 호스트의 파티 등록 기능은 ' +
  '약 한 달 후 이용할 수 있도록 준비하고 있어요.';

// ── 오픈 알림 팬아웃 ───────────────────────────────────────────────────
//
// 기존 notifications 컬렉션과 기존 딥링크를 그대로 쓴다. partyId만 실으면
// notifications_screen.dart가 PartyDetailScreen(docId: partyId)로 보낸다.
async function fanoutOpenAlerts(db, partyId, partyTitle) {
  const subs = await db
    .collection('partyOpenAlerts')
    .where('partyId', '==', partyId)
    .get();

  if (subs.empty) return 0;

  const title = partyTitle || '파티';
  let sent = 0;
  let batch = db.batch();
  let inBatch = 0;

  for (const doc of subs.docs) {
    const targetUid = doc.data().userId;
    if (!targetUid) continue;

    batch.set(db.collection('notifications').doc(), {
      uid: targetUid,
      type: 'party_open',
      title: '오픈 알림 신청한 파티가 열렸어요',
      body: `${title} 모집이 시작됐어요. 지금 신청할 수 있어요.`,
      role: 'guest',
      partyId,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    sent += 1;
    inBatch += 1;

    if (inBatch >= NOTIFICATION_BATCH_SIZE) {
      await batch.commit();
      batch = db.batch();
      inBatch = 0;
    }
  }

  if (inBatch > 0) await batch.commit();
  return sent;
}

// ── 콜러블: 모집 오픈 ──────────────────────────────────────────────────
exports.openPartyRecruiting = onCall(
  { region: 'asia-northeast3', timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    }
    const uid = request.auth.uid;
    const partyId = String((request.data || {}).partyId || '').trim();
    if (!partyId) {
      throw new HttpsError('invalid-argument', '파티를 찾을 수 없습니다.');
    }

    const db = admin.firestore();

    // 정책값과 사업자 인증은 트랜잭션 밖에서 먼저 읽는다 — 트랜잭션 안의
    // 읽기는 파티 문서 하나로 줄여 재시도 비용을 낮춘다. 두 값 모두 이
    // 호출 동안 바뀔 여지가 사실상 없다(정책은 관리자 수동 변경).
    const [verified, policyEnabled] = await Promise.all([
      isBusinessVerified(db, uid),
      readIndividualHostOpeningEnabled(db),
    ]);

    const permission = evaluateOpenPermission({
      businessVerified: verified,
      individualHostOpeningEnabled: policyEnabled,
    });
    if (!permission.allowed) {
      throw new HttpsError(
        'permission-denied',
        '지금은 개인 호스트 모집 오픈이 열려 있지 않습니다. '
        + '사업자 인증을 완료하시면 바로 오픈할 수 있어요.',
      );
    }

    const partyRef = db.collection('parties').doc(partyId);

    // 트랜잭션: 권한·상태·필수정보를 확인하고 openState를 뒤집으면서
    // 알림 발송권을 같이 선점한다.
    const result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(partyRef);
      if (!snap.exists) {
        throw new HttpsError('not-found', '파티를 찾을 수 없습니다.');
      }
      const data = snap.data();

      if (data.hostId !== uid) {
        throw new HttpsError('permission-denied', '본인이 등록한 파티만 오픈할 수 있습니다.');
      }
      if (data.isDeleted === true || data.status === 'deleted') {
        throw new HttpsError('failed-precondition', '삭제된 파티입니다.');
      }
      if (!isPreopen(data)) {
        throw new HttpsError('failed-precondition', '이미 오픈된 파티입니다.');
      }

      const missing = missingFieldsForOpen(data);
      if (missing.length > 0) {
        throw new HttpsError(
          'failed-precondition',
          `오픈 전에 ${missing.join(', ')}을(를) 먼저 입력해주세요.`,
        );
      }

      // 알림 발송권 선점 — 이미 보낸 적이 있으면 다시 보내지 않는다.
      const alreadySent = !!data.openAlertsSentAt;

      const patch = {
        openState: 'open',
        dateTbd: false,
        openedAt: admin.firestore.FieldValue.serverTimestamp(),
        hostBusinessVerified: verified,
      };
      if (!alreadySent) {
        patch.openAlertsSentAt = admin.firestore.FieldValue.serverTimestamp();
      }
      tx.update(partyRef, patch);

      return { shouldNotify: !alreadySent, title: data.title || '' };
    });

    let notified = 0;
    if (result.shouldNotify) {
      try {
        notified = await fanoutOpenAlerts(db, partyId, result.title);
      } catch (err) {
        // 파티는 이미 열렸다. 알림 실패로 오픈을 되돌리지는 않는다 —
        // 되돌리면 "열렸다 닫혔다" 하는 더 나쁜 상태가 된다.
        console.error(`[partyOpen] 오픈 알림 발송 실패. partyId=${partyId} err=${err.message}`);
      }
    }

    console.log(
      `[partyOpen] 모집 오픈. partyId=${partyId} host=${uid} `
      + `verified=${verified} policy=${policyEnabled} notified=${notified}`,
    );

    return { success: true, notified };
  },
);

module.exports.openStateOf = openStateOf;
module.exports.isPreopen = isPreopen;
module.exports.missingFieldsForOpen = missingFieldsForOpen;
module.exports.evaluateOpenPermission = evaluateOpenPermission;
module.exports.evaluatePartyCreatePermission = evaluatePartyCreatePermission;
module.exports.readIndividualHostPartyCreateEnabled =
  readIndividualHostPartyCreateEnabled;
module.exports.INDIVIDUAL_PARTY_CREATE_BLOCKED_MESSAGE =
  INDIVIDUAL_PARTY_CREATE_BLOCKED_MESSAGE;
