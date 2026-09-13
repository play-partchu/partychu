// 통합 QR 토큰 백필 — 배포되는 Cloud Function이 아니라 **로컬에서 직접 실행**한다.
//
// ── 왜 필요한가 ──────────────────────────────────────────────────────────────
// QR 발급은 Firestore 트리거가 한다(partyCheckIn.js · reservationCheckIn.js ·
// productCheckIn.js). 트리거는 **배포 이후의 쓰기**에만 반응하므로, 이미
// 승인된 신청과 확정된 예약은 문서가 다시 쓰이기 전까지 checkInToken이 없다 —
// 게스트 화면에 QR 버튼이 아예 뜨지 않는다. 이 스크립트가 그 격차를 한 번 메운다.
//
// ── 원칙 ─────────────────────────────────────────────────────────────────────
//   · **기본이 dry-run이다.** `--apply` 없이는 한 글자도 쓰지 않는다.
//   · **토큰 생성 로직을 복제하지 않는다.** 발급은 checkInTokenStore의
//     issueCheckInToken 정본을 그대로 부른다 — "원본 1건당 살아 있는 토큰 하나"
//     불변식이 백필에도 똑같이 걸린다.
//   · **멱등이다.** 이미 활성 토큰이 있으면 정본이 그 토큰을 그대로 돌려주므로
//     (created:false) 몇 번을 다시 돌려도 QR이 늘지 않는다.
//   · **상태만 보고 발급하지 않는다.** 쿼리는 후보를 좁힐 뿐이고, 발급 여부는
//     트리거와 **같은 판정 함수**(checkInRules.*QrActive)가 문서 전체를 보고
//     정한다. 쿼리와 판정이 갈리면 백필만 다른 기준으로 QR을 뿌리게 된다.
//   · **이미 지난 일정은 건너뛴다.** 쓸 수 있는 시점이 지난 QR을 만들어 봐야
//     스캔 시점에 어차피 막히고 죽은 토큰만 쌓인다(--include-past로 포함 가능).
//
// ── 인증 ─────────────────────────────────────────────────────────────────────
// 다른 백필 스크립트는 REST + `gcloud auth print-access-token`을 쓰지만, 이
// 스크립트는 **Admin SDK가 필요하다** — 발급 정본이 트랜잭션을 쓰기 때문이다.
// 그래서 애플리케이션 기본 자격증명을 쓴다:
//
//   gcloud auth application-default login      (소유자/편집자 권한 필요)
//   또는  GOOGLE_APPLICATION_CREDENTIALS=<서비스계정 키 경로>
//
// 에뮬레이터로 예행 연습하려면 FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 를 준다.
//
// ── 어느 프로젝트에 쓰는가 (안전장치) ────────────────────────────────────────
// dry-run은 아무것도 쓰지 않으므로 편하게 돌린다 — 대상 프로젝트만 크게 찍는다.
//
// **--apply는 --project=<id>를 반드시 함께 줘야 한다.** 이유:
//   · 기본값으로 운영을 고르면, 테스트할 생각으로 --apply를 붙인 순간 운영에
//     쓰인다. 그래서 apply의 대상은 **코드가 정하지 않는다** — 사람이 적는다.
//   · 환경변수(GOOGLE_CLOUD_PROJECT 등)가 다른 곳을 가리키면 거절한다. 자격증명은
//     그쪽인데 --project만 운영으로 적는 사고를 막는다.
//   · 쓰기 전에 대상 프로젝트로 **읽기 한 번**을 해 본다. 자격증명이 그 프로젝트에
//     닿지 못하면 여기서 멈춘다(문서는 한 건도 건드리지 않은 상태).
// 확인 프롬프트나 카운트다운은 두지 않는다 — 비대화형에서 무력하다.
//
// ── 실행 ─────────────────────────────────────────────────────────────────────
//   cd functions
//   node scripts/backfillCheckInTokens.js                    # dry-run(전체)
//   node scripts/backfillCheckInTokens.js --source=party     # 한 종류만
//   node scripts/backfillCheckInTokens.js --limit=50         # 종류별 상한
//   node scripts/backfillCheckInTokens.js --include-past     # 지난 일정도 포함
//   node scripts/backfillCheckInTokens.js --apply --project=partychu-30c24
//
// 이 파일은 자동으로 실행되지 않는다. 배포에도 포함되지 않는다(Cloud Function을
// 하나도 export하지 않는다).

const admin = require('firebase-admin');

const rules = require('../checkInRules');
const store = require('../checkInTokenStore');
const { KST_OFFSET_MS, kstDateStr } = require('../kstTime');

const ARGS = process.argv.slice(2);
const argOf = (name) =>
  (ARGS.find((a) => a.startsWith(`--${name}=`)) || '').split('=').slice(1).join('=') || null;

const APPLY = ARGS.includes('--apply');
const INCLUDE_PAST = ARGS.includes('--include-past');
const ONLY = argOf('source');
const LIMIT = Number(argOf('limit')) || 0;
const WANTED_PROJECT = argOf('project');
const PAGE = 300;

/** 자격증명·환경이 가리키는 프로젝트. 비어 있을 수 있다. */
const ENV_PROJECT =
  process.env.GOOGLE_CLOUD_PROJECT || process.env.GCLOUD_PROJECT || '';

/**
 * dry-run이 아무 인자 없이도 돌도록 두는 **읽기 전용** 기본값.
 *
 * apply에는 절대 쓰이지 않는다(아래 resolveTarget이 --project를 요구한다) —
 * 운영 프로젝트가 암묵적으로 쓰기 대상이 되는 일을 막는 지점이 여기다.
 */
const READONLY_FALLBACK_PROJECT = 'partychu-30c24';

/**
 * 이번 실행이 향할 프로젝트를 정한다. 정할 수 없으면 {error}를 돌려준다.
 *
 * dry-run: --project → 환경변수 → 읽기 전용 기본값
 * apply  : **--project만**, 그리고 환경변수가 있으면 그것과 같아야 한다.
 */
function resolveTarget() {
  if (!APPLY) {
    return { project: WANTED_PROJECT || ENV_PROJECT || READONLY_FALLBACK_PROJECT };
  }
  if (!WANTED_PROJECT) {
    return {
      error:
        '--apply 에는 --project=<projectId> 가 반드시 필요합니다.\n' +
        '   쓰기 대상을 코드 기본값으로 고르지 않습니다 — 사람이 명시해야 합니다.\n' +
        '   예) node scripts/backfillCheckInTokens.js --apply --project=' +
        READONLY_FALLBACK_PROJECT,
    };
  }
  if (ENV_PROJECT && ENV_PROJECT !== WANTED_PROJECT) {
    return {
      error:
        `--project(${WANTED_PROJECT}) 와 환경변수 프로젝트(${ENV_PROJECT})가 다릅니다.\n` +
        '   자격증명은 환경 쪽을 가리키는데 다른 프로젝트를 적은 상태라 중단합니다.',
    };
  }
  return { project: WANTED_PROJECT };
}

// ── 시간 판정 ────────────────────────────────────────────────────────────────

/** 그 시각이 속한 KST 하루의 마지막 밀리초. */

// ── 시간 판정 ────────────────────────────────────────────────────────────────

/** 그 시각이 속한 KST 하루의 마지막 밀리초. */
function endOfKstDay(ms) {
  const day = Math.floor((ms + KST_OFFSET_MS) / 86400000);
  return (day + 1) * 86400000 - KST_OFFSET_MS - 1;
}

const ts = (v) => rules.tsToMs(v);

// ── 대상 종류 ────────────────────────────────────────────────────────────────
//
// query   : 후보를 좁히는 쿼리(발급 여부를 정하지 않는다)
// active  : 트리거와 **같은** 판정 — 이것이 발급 여부의 정본이다
// usableUntil : 이 QR을 쓸 수 있는 마지막 시각(null이면 기한 없음)
// blockNow    : 지금 스캔하면 막힐 사유(있어도 발급은 한다 — 미리보기용)

const SOURCES = [
  {
    key: 'party',
    label: '파티 신청',
    domain: rules.DOMAIN.party,
    query: (db) =>
      db
        .collectionGroup('applications')
        .where('status', 'in', [...rules.PARTY_QR_STATUSES]),
    active: (d) => rules.partyQrActive(d),
    hostOf: (d) => d.hostId,
    guestOf: (d, id) => d.uid || id,
    usableUntil: (d) => {
      const start = ts(d.occurrenceStartAt) ?? ts(d.partyDateTime);
      return start === null ? null : endOfKstDay(start);
    },
    blockNow: (d, now) => rules.partyBlockReason(d, {}, now),
  },
  {
    key: 'visit',
    label: '플레이스 방문예약',
    collection: 'placeVisitReservations',
    domain: rules.DOMAIN.reservation,
    active: (d) => rules.reservationQrActive('placeVisitReservations', d),
    hostOf: (d) => d.hostId,
    guestOf: (d) => d.requesterId || d.guestId,
    usableUntil: (d) => {
      const start = ts(d.visitAt);
      return start === null ? null : endOfKstDay(start);
    },
    blockNow: (d, now) => rules.reservationBlockReason(d, now),
  },
  {
    key: 'rental',
    label: '장소대여 예약',
    collection: 'placeReservationGroups',
    domain: rules.DOMAIN.reservation,
    active: (d) => rules.reservationQrActive('placeReservationGroups', d),
    hostOf: (d) => d.hostId,
    guestOf: (d) => d.requesterId || d.guestId,
    usableUntil: (d) => {
      const end = ts(d.useEndAt);
      if (end !== null) return end;
      const start = ts(d.useStartAt) ?? ts(d.startAt);
      return start === null ? null : endOfKstDay(start);
    },
    blockNow: (d, now) =>
      rules.reservationBlockReason(
        { ...d, useStartAt: d.useStartAt ?? d.startAt },
        now,
      ),
  },
  {
    key: 'package',
    label: '숙박+파티 콤보',
    collection: 'packageBookings',
    domain: rules.DOMAIN.reservation,
    active: (d) => rules.reservationQrActive('packageBookings', d),
    hostOf: (d) => d.hostId,
    guestOf: (d) => d.requesterId || d.guestId,
    usableUntil: (d) => {
      const end = ts(d.useEndAt);
      if (end !== null) return end;
      const start = ts(d.useStartAt);
      return start === null ? null : endOfKstDay(start);
    },
    blockNow: (d, now) =>
      rules.reservationBlockReason(
        { ...d, useStartAt: d.useStartAt ?? d.startAt },
        now,
      ),
  },
  {
    // 현장결제 상품만 대상이다 — 무통장입금 주문은 결제 전에 QR을 주지 않는
    // 정책 그대로다(productQrActive가 그렇게 판정한다).
    key: 'product',
    label: '현장결제 상품 주문',
    collection: 'placeProductOrders',
    domain: rules.DOMAIN.voucher,
    query: (db) =>
      db
        .collection('placeProductOrders')
        .where('status', 'in', ['payment_pending', 'paid', 'usable', 'used']),
    active: (d) => rules.productQrActive(d),
    hostOf: (d) => d.hostId,
    guestOf: (d) => d.buyerId,
    usableUntil: (d) => {
      const end = ts(d.useEndAt);
      if (end !== null) return end;
      const useAt = ts(d.useAt);
      return useAt === null ? null : endOfKstDay(useAt);
    },
    blockNow: (d, now) =>
      rules.voucherBlockReason(d, now, {
        dateBoundTypes: new Set(['seat', 'ticket', 'bottle', 'experience']),
      }),
  },
];

// ── 훑기 ─────────────────────────────────────────────────────────────────────

function baseQuery(db, source) {
  if (source.query) return source.query(db);
  const confirmed = rules.RESERVATION_QR_STATUS[source.collection];
  return db.collection(source.collection).where('status', '==', confirmed);
}

async function* iterate(db, source) {
  let cursor = null;
  let seen = 0;
  for (;;) {
    let q = baseQuery(db, source).orderBy('__name__').limit(PAGE);
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.get();
    if (snap.empty) return;
    for (const doc of snap.docs) {
      yield doc;
      seen += 1;
      if (LIMIT && seen >= LIMIT) return;
    }
    if (snap.size < PAGE) return;
    cursor = snap.docs[snap.docs.length - 1];
  }
}

// ── 본체 ─────────────────────────────────────────────────────────────────────

async function runSource(db, source, now) {
  const stat = {
    scanned: 0,
    already: 0,
    toIssue: 0,
    issued: 0,
    skippedInactive: 0,
    skippedPast: 0,
    errors: [],
  };
  const preview = [];

  for await (const doc of iterate(db, source)) {
    stat.scanned += 1;
    const d = doc.data();
    const refPath = doc.ref.path;

    try {
      // 쿼리는 후보만 좁혔다 — 발급 여부는 트리거와 같은 판정이 정한다.
      if (!source.active(d)) {
        stat.skippedInactive += 1;
        continue;
      }

      // 쓸 수 있는 시점이 이미 지난 건은 QR을 만들어도 스캔에서 막힌다.
      const until = source.usableUntil(d);
      if (!INCLUDE_PAST && until !== null && until < now) {
        stat.skippedPast += 1;
        continue;
      }

      const existing = d[store.TOKEN_FIELD];

      if (!APPLY) {
        // dry-run은 아무것도 쓰지 않는다 — 활성 토큰이 이미 있는지만 본다.
        const idx = await db
          .collection(store.TOKEN_INDEX)
          .doc(store.tokenIndexKey(refPath))
          .get();
        let live = false;
        if (idx.exists && idx.data().token) {
          const t = await db.collection(store.TOKENS).doc(idx.data().token).get();
          live = t.exists && store.isTokenActive(t.data());
        }
        if (live && existing) {
          stat.already += 1;
        } else {
          stat.toIssue += 1;
          if (preview.length < 10) {
            preview.push({
              path: refPath,
              until: until === null ? '기한 없음' : kstDateStr(until),
              block: source.blockNow(d, now),
            });
          }
        }
        continue;
      }

      // 발급은 **정본**이 한다 — 이미 살아 있으면 같은 토큰을 그대로 돌려준다.
      const { token, created } = await store.issueCheckInToken(db, {
        domain: source.domain,
        refPath,
        hostId: source.hostOf(d) || '',
        guestUid: source.guestOf(d, doc.id) || '',
      });
      if (created) stat.issued += 1;
      else stat.already += 1;
      // 게스트 화면이 읽는 필드도 맞춰 준다(값이 같으면 쓰지 않는다).
      if (existing !== token) {
        await doc.ref.set({ [store.TOKEN_FIELD]: token }, { merge: true });
      }
    } catch (e) {
      stat.errors.push(`${refPath}: ${e.message}`);
    }
  }

  return { stat, preview };
}

async function main() {
  // ── 대상 프로젝트 결정 — 여기를 통과하지 못하면 쓰기는 0건이다 ────────────
  const target = resolveTarget();
  if (target.error) {
    console.error(`\n❌ ${target.error}\n`);
    process.exitCode = 1;
    return;
  }
  const PROJECT_ID = target.project;

  const sources = SOURCES.filter((s) => !ONLY || s.key === ONLY);
  if (sources.length === 0) {
    console.error(`--source 값이 올바르지 않습니다. 가능: ${SOURCES.map((s) => s.key).join(', ')}`);
    process.exitCode = 1;
    return;
  }

  // 대상이 어디인지가 제일 먼저, 제일 크게 보여야 한다.
  console.log('');
  console.log('╔══════════════════════════════════════════════════════════╗');
  console.log(`  대상 프로젝트 : ${PROJECT_ID}`);
  console.log(`  모드         : ${APPLY ? '⚠️  APPLY — 실제로 씁니다' : 'DRY-RUN — 아무것도 쓰지 않습니다'}`);
  if (process.env.FIRESTORE_EMULATOR_HOST) {
    console.log(`  ⚠️  에뮬레이터 : ${process.env.FIRESTORE_EMULATOR_HOST}`);
  }
  console.log('╚══════════════════════════════════════════════════════════╝');
  if (INCLUDE_PAST || LIMIT || ONLY) {
    console.log(
      `옵션: ${[
        ONLY ? `source=${ONLY}` : null,
        LIMIT ? `limit=${LIMIT}` : null,
        INCLUDE_PAST ? '지난 일정 포함' : null,
      ].filter(Boolean).join(' · ')}`,
    );
  }

  admin.initializeApp({ projectId: PROJECT_ID });
  const db = admin.firestore();
  const now = Date.now();

  // 초기화된 대상이 정말 --project인지 되읽어 확인한다.
  const initialized = admin.app().options.projectId;
  if (APPLY && initialized !== PROJECT_ID) {
    console.error(
      `\n❌ 초기화된 프로젝트(${initialized})가 --project(${PROJECT_ID})와 다릅니다. 중단합니다.\n`,
    );
    process.exitCode = 1;
    return;
  }

  // 쓰기 전에 읽기 한 번 — 자격증명이 이 프로젝트에 닿는지 확인한다.
  // 이 스크립트가 실제로 읽고 쓰는 컬렉션을 그대로 찔러 본다(권한까지 같이
  // 확인된다). 여기서 실패하면 문서는 한 건도 건드리지 않은 상태로 멈춘다.
  if (APPLY) {
    try {
      await db.collection(store.TOKEN_INDEX).limit(1).get();
    } catch (e) {
      console.error(
        `\n❌ ${PROJECT_ID} 에 접근하지 못했습니다 — 자격증명을 확인하세요.\n   ${e.message}\n`,
      );
      process.exitCode = 1;
      return;
    }
  }

  const total = {
    scanned: 0, already: 0, toIssue: 0, issued: 0,
    skippedInactive: 0, skippedPast: 0, errors: 0,
  };

  for (const source of sources) {
    console.log(`\n── ${source.label} (${source.key}) ${'─'.repeat(40 - source.label.length)}`);
    const { stat, preview } = await runSource(db, source, now);

    console.log(`  대상 조회      ${stat.scanned}건`);
    console.log(`  이미 발급됨    ${stat.already}건`);
    console.log(`  ${APPLY ? '신규 발급     ' : '신규 발급 예정'} ${APPLY ? stat.issued : stat.toIssue}건`);
    console.log(`  제외(자격 없음) ${stat.skippedInactive}건`);
    console.log(`  제외(지난 일정) ${stat.skippedPast}건${INCLUDE_PAST ? ' (포함 모드)' : ''}`);
    console.log(`  오류           ${stat.errors.length}건`);

    if (!APPLY && preview.length) {
      console.log('  미리보기:');
      for (const p of preview) {
        console.log(
          `    - ${p.path}\n      이용 가능 ~${p.until}` +
            `${p.block ? ` · 지금 스캔하면: ${p.block}` : ''}`,
        );
      }
    }
    for (const e of stat.errors.slice(0, 10)) console.log(`    ! ${e}`);

    total.scanned += stat.scanned;
    total.already += stat.already;
    total.toIssue += stat.toIssue;
    total.issued += stat.issued;
    total.skippedInactive += stat.skippedInactive;
    total.skippedPast += stat.skippedPast;
    total.errors += stat.errors.length;
  }

  console.log(`\n${'═'.repeat(56)}`);
  console.log(
    `합계 — 대상 ${total.scanned} / 이미 발급 ${total.already} / ` +
      `${APPLY ? `신규 발급 ${total.issued}` : `신규 발급 예정 ${total.toIssue}`} / ` +
      `제외 ${total.skippedInactive + total.skippedPast} / 오류 ${total.errors}`,
  );
  if (!APPLY) {
    // 실제로 적용할 때 쓸 명령을 그대로 찍어 준다 — 손으로 다시 조립하다
    // --project를 빠뜨리거나 다른 프로젝트를 적는 일을 줄인다.
    const cmd = [
      'node scripts/backfillCheckInTokens.js',
      '--apply',
      `--project=${PROJECT_ID}`,
      ONLY ? `--source=${ONLY}` : null,
      LIMIT ? `--limit=${LIMIT}` : null,
      INCLUDE_PAST ? '--include-past' : null,
    ].filter(Boolean).join(' ');
    console.log('\nDRY-RUN이라 아무것도 쓰지 않았습니다.');
    console.log('실제로 발급하려면 (functions 디렉터리에서):');
    console.log(`\n  ${cmd}\n`);
  }
  if (total.errors > 0) process.exitCode = 1;
}

main().catch((err) => {
  console.error('백필 실패:', err);
  process.exit(1);
});
