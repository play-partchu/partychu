// 닉네임 예약(nicknames/{normalized}) 백필 — 배포되는 Cloud Function이 아니라
// 로컬에서 직접 실행한다.
//
// 닉네임 중복방지(functions/nicknames.js)가 생기기 **전에** 가입한 회원들은
// 예약 문서가 없다. 그대로 두면 남이 그 닉네임을 먼저 선점할 수 있고, 원래
// 주인은 자기 닉네임을 저장하려 할 때 "이미 사용 중"으로 막힌다. 이 스크립트가
// 기존 users.nickname을 읽어 예약 문서만 만들어 준다.
//
// ── 안전장치 ────────────────────────────────────────────────────────────
//   · 기본이 dry-run이다 — `--apply` 없이는 아무것도 쓰지 않는다.
//   · idempotent — 여러 번 실행해도 결과가 같다(이미 있으면 건드리지 않는다).
//   · 덮어쓰기 금지 — documentId를 지정한 POST라 이미 있으면 409로 실패한다.
//     다른 uid가 선점한 건은 '충돌'로 보고만 하고 절대 덮어쓰지 않는다.
//   · users.nickname은 **읽기만 한다.** 이 스크립트는 nicknames만 만든다.
//
// 인증: 다른 백필 스크립트와 같이 로컬 gcloud 사용자 자격 증명을 쓴다
// (`gcloud auth print-access-token`). 소유자/편집자 권한이 있어야 한다.
//
// 실행:
//   cd functions
//   node scripts/backfillNicknameReservations.js            # dry-run
//   node scripts/backfillNicknameReservations.js --apply    # 실제 생성

const { execSync } = require('child_process');

const PROJECT_ID = 'partychu-30c24';
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const APPLY = process.argv.includes('--apply');

function getAccessToken() {
  return execSync('gcloud auth print-access-token', { encoding: 'utf8' }).trim();
}

const TOKEN = getAccessToken();
const H = { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' };

// ⚠️ functions/nicknames.js의 sanitize/normalize와 **같은 규칙**이어야 한다.
// 한쪽만 바뀌면 백필이 만든 키와 서버가 찾는 키가 어긋나 중복방지가 뚫린다.
const sanitize = (s) => String(s == null ? '' : s).trim().normalize('NFC');
const normalize = (s) => sanitize(s).toLowerCase();

async function runQuery(collectionId) {
  const r = await fetch(`${BASE}:runQuery`, {
    method: 'POST',
    headers: H,
    body: JSON.stringify({ structuredQuery: { from: [{ collectionId }], limit: 1000 } }),
  });
  if (!r.ok) throw new Error(`runQuery ${collectionId} ${r.status}: ${await r.text()}`);
  return (await r.json()).filter((x) => x.document);
}

async function getDoc(path) {
  const r = await fetch(`${BASE}/${path}`, { headers: H });
  if (r.status === 404) return null;
  if (!r.ok) throw new Error(`get ${path} ${r.status}: ${await r.text()}`);
  return r.json();
}

/** 문서가 없을 때만 만든다 — 이미 있으면 409를 받고 그대로 둔다. */
async function createIfAbsent(docId, fields) {
  const url = `${BASE}/nicknames?documentId=${encodeURIComponent(docId)}`;
  const r = await fetch(url, { method: 'POST', headers: H, body: JSON.stringify({ fields }) });
  if (r.status === 409) return 'exists';
  if (!r.ok) throw new Error(`create ${docId} ${r.status}: ${await r.text()}`);
  return 'created';
}

(async () => {
  console.log(APPLY ? '=== 실제 백필 (--apply) ===' : '=== DRY-RUN (아무것도 쓰지 않음) ===');

  const users = await runQuery('users');
  const rows = [];
  for (const u of users) {
    const uid = u.document.name.split('/').pop();
    const raw = u.document.fields && u.document.fields.nickname
      ? u.document.fields.nickname.stringValue
      : null;
    if (!raw || !sanitize(raw)) continue;
    rows.push({ uid, nickname: sanitize(raw), key: normalize(raw) });
  }
  console.log(`닉네임 보유 계정: ${rows.length}건\n`);

  // ── ① 기존 사용자들끼리 정규화가 겹치는지 먼저 본다 ──────────────────
  // 겹치면 둘 중 누구를 주인으로 삼을지 이 스크립트가 정할 수 없다. 임의로
  // 한쪽을 고르면 다른 한쪽은 자기 닉네임을 잃으므로, 보고만 하고 멈춘다.
  const byKey = new Map();
  for (const r of rows) byKey.set(r.key, [...(byKey.get(r.key) || []), r]);
  const conflicts = [...byKey.entries()].filter(([, v]) => v.length > 1);
  if (conflicts.length) {
    console.log('*** 기존 사용자끼리 정규화 충돌 — 백필을 중단합니다 ***');
    for (const [k, v] of conflicts) {
      console.log(`  '${k}' ← ${v.map((x) => `${x.uid}('${x.nickname}')`).join(' , ')}`);
    }
    process.exit(1);
  }
  console.log('사용자 간 정규화 충돌: 없음\n');

  // ── ② 건별 분류 ──────────────────────────────────────────────────────
  const plan = { create: [], exists: [], conflict: [], skip: [] };
  for (const r of rows) {
    const existing = await getDoc(`nicknames/${encodeURIComponent(r.key)}`);
    if (!existing) {
      plan.create.push(r);
      continue;
    }
    const f = existing.fields || {};
    const ownerUid = f.uid && f.uid.stringValue;
    const ownerNick = f.nickname && f.nickname.stringValue;
    if (ownerUid === r.uid && sanitize(ownerNick) === r.nickname) plan.exists.push(r);
    else if (ownerUid === r.uid) {
      plan.skip.push({ ...r, note: `uid는 같지만 nickname 불일치(예약='${ownerNick}')` });
    } else {
      plan.conflict.push({ ...r, note: `이미 ${ownerUid} 가 선점('${ownerNick}')` });
    }
  }

  const show = (label, arr) => {
    console.log(`${label}: ${arr.length}건`);
    for (const x of arr) {
      console.log(`   ${x.uid.slice(0, 8)}  '${x.nickname}'  → nicknames/${x.key}${x.note ? '  — ' + x.note : ''}`);
    }
  };
  show('생성 예정', plan.create);
  show('이미 존재(일치)', plan.exists);
  show('충돌', plan.conflict);
  show('건너뜀', plan.skip);

  if (!APPLY) {
    console.log('\n(dry-run입니다 — 실제로 만들려면 --apply)');
    return;
  }
  if (plan.conflict.length) {
    console.log('\n*** 충돌이 있어 실행하지 않습니다 ***');
    process.exit(1);
  }

  // ── ③ 실행 ───────────────────────────────────────────────────────────
  console.log('\n=== 생성 실행 ===');
  let created = 0;
  let already = 0;
  for (const r of plan.create) {
    const res = await createIfAbsent(r.key, {
      uid: { stringValue: r.uid },
      nickname: { stringValue: r.nickname },
      createdAt: { timestampValue: new Date().toISOString() },
    });
    console.log(`  ${res === 'created' ? '생성' : '이미존재'}  nicknames/${r.key}`);
    if (res === 'created') created += 1;
    else already += 1;
  }
  console.log(`\n생성 ${created}건 / 이미존재 ${already}건 / 건드리지 않음 ${plan.exists.length}건`);
})().catch((e) => {
  console.error('실패:', e.message);
  process.exit(1);
});
