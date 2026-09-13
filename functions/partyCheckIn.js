/**
 * 파티 참가권 QR과 **현장 출석 통계** — 신청 문서 하나를 지켜보는 트리거.
 *
 * ── 왜 트리거인가 ───────────────────────────────────────────────────────────
 * 파티 신청이 확정되는 길은 하나가 아니다.
 *
 *   · decidePartyApplication  (호스트가 승인 버튼)
 *   · confirmPartyDeposit     (호스트가 입금 확인 → 그 자리에서 approved)
 *   · confirmPackageDeposit   (콤보 예약의 입금 확인 → 파티 신청도 approved)
 *   · applyToParty            (즉시확정 파티는 접수가 곧 확정 'applied')
 *
 * 콜러블마다 발급을 붙이면 넷 중 하나를 빠뜨리는 날 그 경로의 참가자만 QR을
 * 못 받는다. 취소되는 길은 더 많다(본인 취소·호스트 취소·거절·입금기한 만료·
 * 최소인원 미달·파티 삭제). 그래서 **신청 문서의 최종 상태 하나**만 보고
 * 판단한다 — 어떤 경로로 그 상태가 됐는지는 알 필요가 없다.
 *
 * ── 두 가지 일을 한다 ───────────────────────────────────────────────────────
 *   ① QR 토큰 발급·무효화   (status가 정본)
 *   ② 현장 출석 통계        (checkedInAt이 정본)
 *
 * 둘을 한 트리거에 둔 이유는 둘 다 같은 문서의 같은 쓰기에서 갈리기 때문이다.
 * 나누면 같은 경로에 트리거가 하나 더 붙고, 서로의 쓰기에 또 깨어난다.
 *
 * ── 출석 통계를 옮긴 이유 ───────────────────────────────────────────────────
 * 지금까지 "실제 참여"는 신청 상태 `attended`로 셌는데, **그 값을 쓰는 코드가
 * 서버·앱 어디에도 없다**(전수 확인함). 그래서 totalAttended · dailyStats.attended ·
 * regionStats.totalAttended · hourlyStats.attended는 전부 0에 머물러 있었다.
 * 이제 호스트가 현장에서 QR을 찍으면 checkedInAt이 남으므로 **그것**을 출석의
 * 정본으로 삼는다.
 *
 * 승인 통계(totalConfirmed · dailyStats.confirmed)는 그대로 approved 기준이다 —
 * "몇 명을 받았나"와 "몇 명이 실제로 왔나"는 다른 질문이다. 지역·시간대의
 * **신청** 집계(totalApplications · applications)도 신청 시점 그대로다.
 *
 * `attended` 상태는 지우지 않았다. onApplicationStatusWrite의 카운터 표에 그대로
 * 남아 있어 옛 문서가 그 상태로 전이하면 예전처럼 집계된다 — 다만 **새로 그
 * 값을 쓰는 코드는 없다**. 지금 쓰이지 않는 값을 지우는 것과, 옛 데이터를 읽을
 * 수 없게 만드는 것은 다른 일이다.
 *
 * ── 되돌리기 ────────────────────────────────────────────────────────────────
 * 체크인은 되돌릴 수 있다(revokeCheckIn). 그래서 집계는 "+1"이 아니라 **차분**
 * 으로 움직인다(checkInRules.attendanceDelta). 되돌리면 늘렸던 칸이 정확히 그
 * 만큼 줄어든다 — dailyStats는 **체크인한 날**의 문서를 줄인다(되돌린 날이
 * 아니다). 그러지 않으면 자정을 넘긴 되돌리기가 엉뚱한 날짜를 깎는다.
 */

const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

const rules = require('./checkInRules');
const store = require('./checkInTokenStore');
const { kstDateStr, KST_OFFSET_MS } = require('./kstTime');
const { logUserActivity, isTestAccountUid } = require('./memberActivityHelpers');

const REGION = 'asia-northeast3';

/**
 * 왜 QR이 죽었는지 — 감사용으로만 남긴다.
 *
 * 조회 응답에는 언제나 같은 문장이 나간다. 남의 QR을 주운 사람에게 사유를
 * 알려 주면 그 자체가 정보다.
 */
function revokeReasonOf(app) {
  const status = (app && app.status) || 'missing';
  if (status === 'rejected') return 'application_rejected';
  if (status === 'cancelled') return 'application_cancelled';
  if (status === 'no_show') return 'application_no_show';
  if (status === 'pending') return 'application_pending';
  return 'application_status_' + status;
}

// ── 출석 통계 ───────────────────────────────────────────────────────────────

/**
 * 체크인 시각이 속한 KST 날짜 키('2026-08-30').
 *
 * dailyStats는 "그 날 무슨 일이 있었나"라서, 되돌리기도 **원래 찍힌 날**을
 * 줄여야 짝이 맞는다.
 */
function dateKeyOfCheckIn(before, after, delta) {
  const ms =
    delta > 0
      ? rules.tsToMs(after && after.checkedInAt)
      : rules.tsToMs(before && before.checkedInAt);
  return ms === null ? null : kstDateStr(ms);
}

/** 파티 시작 시각(KST)이 몇 시였나 — 시간대별 통계의 칸. */
function hourKeyOf(app) {
  if (app.partyStartHour != null) return String(app.partyStartHour);
  const startMs =
    rules.tsToMs(app.occurrenceStartAt) ?? rules.tsToMs(app.partyDateTime);
  if (startMs === null) return null;
  return String(new Date(startMs + KST_OFFSET_MS).getUTCHours());
}

/**
 * 출석 카운터를 delta(+1 / -1)만큼 움직인다.
 *
 * 대상은 onApplicationStatusWrite가 'attended' 전이에 올리던 칸 **그대로**다 —
 * 기준만 status에서 checkedInAt으로 바뀌었고, 어느 칸을 세는지는 그대로다.
 */
async function applyAttendance(db, { app, uid, delta, dateKey }) {
  const inc = admin.firestore.FieldValue.increment(delta);

  await db
    .collection('userStats')
    .doc(uid)
    .set(
      {
        totalAttended: inc,
        lastParticipationAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

  // 여기서부터는 서비스 KPI다 — 테스트 계정 활동은 섞지 않는다
  // (onApplicationStatusWrite와 같은 규칙). 신청 문서에 이미 찍혀 있는
  // isTestAccount를 먼저 보고, 없는 옛 문서만 users를 한 번 읽는다.
  const isTest =
    app.isTestAccount === true ||
    (app.isTestAccount !== false && (await isTestAccountUid(db, uid)));
  if (isTest) return;

  if (dateKey) {
    await db
      .collection('dailyStats')
      .doc(dateKey)
      .set({ attended: inc }, { merge: true });
  }

  const regionKey = `${app.region || '기타'}_${app.district || '기타'}`;
  await db
    .collection('regionStats')
    .doc(regionKey)
    .set(
      {
        region1: app.region || null,
        region2: app.district || null,
        totalAttended: inc,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

  const hourKey = hourKeyOf(app);
  if (hourKey != null) {
    await db
      .collection('hourlyStats')
      .doc(hourKey)
      .set({ hour: Number(hourKey), attended: inc }, { merge: true });
  }
}

// ── 트리거 ──────────────────────────────────────────────────────────────────

/**
 * 트리거 본체 — 트리거 껍데기와 나눠 둔 이유는 self-check가 **이 함수를 직접**
 * 부르기 위해서다(가짜 Firestore로 재실행·취소·되돌리기를 전부 돌려 본다).
 */
async function handlePartyApplicationWrite(db, event) {
  const before = event.data.before.exists ? event.data.before.data() : null;
  const after = event.data.after.exists ? event.data.after.data() : null;
  const refPath =
    `parties/${event.params.partyId}` +
    `/applications/${event.params.applicationId}`;

  // 문서가 사라졌으면 QR도 함께 죽인다. 그 QR로 조회되는 것은 이미 없지만,
  // 토큰이 남아 있을 이유도 없다.
  if (!after) {
    await store.revokeCheckInTokenFor(db, refPath, 'application_deleted');
    return;
  }

  // ── ① QR 토큰 — status가 정본이다 ─────────────────────────────────────
  // 발급·무효화와 루프 방지는 예약·상품과 **같은 한 곳**이 한다.
  await store.syncTokenField(db, {
    ref: event.data.after.ref,
    after,
    refPath,
    domain: rules.DOMAIN.party,
    hostId: after.hostId || '',
    guestUid: after.uid || event.params.applicationId,
    active: rules.partyQrActive(after),
    revokeReason: revokeReasonOf(after),
  });

  // ── ② 현장 출석 — checkedInAt이 정본이다 ──────────────────────────────
  const delta = rules.attendanceDelta(before, after);
  if (delta === 0) return;

  const uid = after.uid || event.params.applicationId;
  if (!uid) return;

  await applyAttendance(db, {
    app: after,
    uid,
    delta,
    dateKey: dateKeyOfCheckIn(before, after, delta),
  });

  await logUserActivity(db, {
    uid,
    // 되돌리기도 기록에 남긴다 — 지운 흔적이 없으면 분쟁이 났을 때 무슨 일이
    // 있었는지 아무도 모른다(체크인 감사 기록과 같은 이유).
    activityType: delta > 0 ? 'party_attended' : 'party_check_in_revoked',
    refCollection: 'applications',
    refId: event.params.partyId,
    actorType: 'host',
    actorUid: (delta > 0 ? after.checkedInBy : after.checkInRevokedBy) || null,
  });
}

exports.onPartyApplicationCheckIn = onDocumentWritten(
  {
    document: 'parties/{partyId}/applications/{applicationId}',
    region: REGION,
  },
  (event) => handlePartyApplicationWrite(admin.firestore(), event),
);

module.exports.__test = {
  revokeReasonOf,
  dateKeyOfCheckIn,
  hourKeyOf,
  applyAttendance,
  handlePartyApplicationWrite,
};
