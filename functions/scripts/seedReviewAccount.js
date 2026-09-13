// Google Play 심사용 계정 1개에만 본인확인 상태를 시드하는 스크립트.
//
// 배포되는 Cloud Function이 아니라 로컬에서 직접 실행한다
// (createTestAccounts.js와 완전히 같은 패턴 — 인증 방식·REST 쓰기까지 동일).
//
// ── 왜 필요한가 ──────────────────────────────────────────────────────────
// 파티츄는 로그인한 계정이 NICE 본인확인을 마치지 않으면 루트 게이트가
// MainScreen 자체를 만들지 않는다(party_app/lib/utils/root_gate.dart).
// 그래서 심사자가 Google 로그인만 해서는 본인확인 화면에 갇혀 아무 기능도
// 볼 수 없다. 그런데 NICE는 CI 유일성을 강제하므로(functions/identityLink.js의
// duplicateError) 운영자가 자기 신분으로 심사용 계정을 한 번 더 인증할 수도
// 없다.
//
// 남는 길은 하나다 — **그 계정의 users/{uid} 하나에만** 인증 상태를 Admin SDK로
// 넣는 것. host@test.com / guest@test.com이 이미 이 방식으로 만들어져 있고
// (verificationProvider: 'test_seed'), 이 스크립트는 그것을 계정 하나에 대해
// 다시 하는 것뿐이다.
//
// ── 무엇을 하지 않는가 ───────────────────────────────────────────────────
//   · 일반 사용자의 NICE 경로·firestore.rules·서버 게이트를 건드리지 않는다.
//     바뀌는 것은 지정한 uid의 users 문서 **한 개**뿐이다.
//   · Auth 계정을 만들지 않는다 — 심사자용 Gmail로 앱에서 Google 로그인을
//     이미 한 번 해서 계정과 users 문서가 생겨 있어야 한다.
//   · Email/Password provider 설정을 건드리지 않는다(이미 켜져 있고, 심사는
//     Google 로그인으로 진행한다).
//   · **사업자 인증(businessVerifications)은 시드하지 않는다.** 그건 국세청
//     실제 판정이라 위조하지 않는다 — 심사 노트에 "사업자 인증이 필요한
//     기능은 심사 계정에서 제외"라고 적는 편이 맞다.
//   · ci / di 를 쓰지 않는다. 실제 신분과 연결되지 않으므로 CI 유일성
//     검사(identityLink.js)와 충돌하지 않는다.
//
// ── 안전장치 ─────────────────────────────────────────────────────────────
// 기본은 **드라이런**이다. 현재 문서와 적용할 패치를 보여주기만 하고 아무것도
// 쓰지 않는다. 실제로 쓰려면 --apply 를 명시해야 한다.
// 그리고 아래 조건 중 하나라도 걸리면 즉시 중단한다(fail-closed):
//   · users/{uid} 문서가 없다            → 아직 앱에서 로그인하지 않은 것
//   · verificationProvider가 nice_* 이다 → 실제 NICE를 통과한 운영 사용자
//   · ci 또는 di 필드가 있다             → 위와 같음
//   · role이 비어 있지 않다              → 관리자 등 특수 계정
//
// 인증: createTestAccounts.js와 동일 — 로컬 gcloud 사용자 자격증명을
// firebase-admin의 커스텀 Credential로 연결한다(프로젝트 소유자/편집자 권한 필요).
//
// 실행:
//   cd functions
//   node scripts/seedReviewAccount.js --email review@example.com          # 드라이런
//   node scripts/seedReviewAccount.js --email review@example.com --apply  # 실제 쓰기
//
//   uid를 이미 안다면 --uid <uid> 로 대신 지정할 수 있다.
//   --no-profile 을 주면 표시용 프로필(nickname/name/gender/birthYear)을 빼고
//   인증 상태만 넣는다. 다만 성별·연령 제한이 걸린 파티는 gender/birthYear가
//   없으면 신청이 막히므로(functions/index.js applyToParty), 심사용으로는
//   기본값(넣는 쪽)을 권한다.

const { execSync } = require('child_process');
const admin = require('firebase-admin');

const PROJECT_ID = 'partychu-30c24';

// 심사 계정의 표시용 프로필. 실제 사람의 정보가 아니라 **심사용 더미**다.
// 성별·연령 제한이 걸린 파티까지 심사자가 신청해 볼 수 있도록 채워 둔다.
const REVIEW_PROFILE = {
  nickname: '심사테스트(REVIEW)',
  name: '심사테스트(REVIEW)',
  gender: 'male',
  birthYear: 1995,
};

function getAccessToken() {
  return execSync('gcloud auth print-access-token', { encoding: 'utf8' }).trim();
}

admin.initializeApp({
  credential: {
    getAccessToken: async () => ({
      access_token: getAccessToken(),
      expires_in: 3600,
    }),
  },
  projectId: PROJECT_ID,
});

// ── 인자 파싱 ────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const args = { apply: false, withProfile: true, email: null, uid: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--apply') args.apply = true;
    else if (a === '--no-profile') args.withProfile = false;
    else if (a === '--email') args.email = argv[++i];
    else if (a === '--uid') args.uid = argv[++i];
    else throw new Error(`알 수 없는 인자: ${a}`);
  }
  if (!args.email && !args.uid) {
    throw new Error('--email 또는 --uid 중 하나는 반드시 주어야 합니다.');
  }
  return args;
}

// ── uid 확인 ─────────────────────────────────────────────────────────────

async function resolveUid(args) {
  if (args.uid) {
    const user = await admin.auth().getUser(args.uid).catch((e) => {
      if (e.code === 'auth/user-not-found') return null;
      throw e;
    });
    if (!user) throw new Error(`Auth에 uid=${args.uid} 계정이 없습니다.`);
    return user;
  }
  const user = await admin.auth().getUserByEmail(args.email).catch((e) => {
    if (e.code === 'auth/user-not-found') return null;
    throw e;
  });
  if (!user) {
    throw new Error(
      `Auth에 ${args.email} 계정이 없습니다.\n` +
      '  → 심사용 Gmail을 만든 뒤 **릴리스 앱에서 그 계정으로 Google 로그인을 1회** 해주세요.\n' +
      '    (본인확인 화면에서 멈추는 것이 정상입니다 — 그 시점에 계정과 users 문서가 만들어집니다.)',
    );
  }
  return user;
}

// ── 현재 users 문서 읽기 (REST — admin.firestore()는 커스텀 Credential 거부) ──

async function readUserDoc(uid) {
  const token = getAccessToken();
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/users/${uid}`,
    {
      headers: {
        Authorization: `Bearer ${token}`,
        'x-goog-user-project': PROJECT_ID,
      },
    },
  );
  if (res.status === 404) return null;
  const body = await res.json();
  if (!res.ok) {
    throw new Error(`users/${uid} 읽기 실패: ${res.status} ${JSON.stringify(body)}`);
  }
  return body.fields || {};
}

/// Firestore REST 값에서 사람이 읽을 수 있는 값 하나만 꺼낸다(표시용).
function plain(field) {
  if (!field) return undefined;
  const key = Object.keys(field)[0];
  return field[key];
}

// ── 안전장치 ─────────────────────────────────────────────────────────────

function assertSafeToSeed(uid, fields) {
  if (fields === null) {
    throw new Error(
      `users/${uid} 문서가 없습니다.\n` +
      '  → 릴리스 앱에서 그 계정으로 Google 로그인을 1회 해주세요. 로그인 시점에 문서가 만들어집니다.',
    );
  }

  const provider = plain(fields.verificationProvider);
  if (provider && provider !== 'test_seed') {
    throw new Error(
      `중단 — 이 계정은 실제 본인확인을 통과한 사용자입니다 (verificationProvider='${provider}').\n` +
      '  운영 사용자 문서는 건드리지 않습니다. uid를 다시 확인해주세요.',
    );
  }

  if (fields.ci || fields.di) {
    throw new Error(
      '중단 — 이 계정에는 NICE 인증 결과(ci/di)가 들어 있습니다. 실제 사용자 문서입니다.',
    );
  }

  const role = plain(fields.role);
  if (role) {
    throw new Error(
      `중단 — 이 계정에는 role='${role}'이 설정돼 있습니다(관리자 등 특수 계정).\n` +
      '  심사용 계정은 role이 비어 있어야 합니다.',
    );
  }

  const alreadySeeded =
    plain(fields.identityVerified) === true &&
    plain(fields.isTestAccount) === true &&
    provider === 'test_seed';
  return { alreadySeeded };
}

// ── 패치 만들기 ──────────────────────────────────────────────────────────

function buildPatch(withProfile) {
  const now = new Date();
  const patch = {
    // 본인확인 상태 — 루트 게이트·서버 게이트·firestore.rules가 보는 값.
    identityVerified: true,
    identityVerifiedAt: now,
    isVerified: true, // firestore.rules 하위 호환 (niceIntcResult 핸들러와 동일)
    verifiedAt: now,
    profileCompleted: true,
    // NICE를 거치지 않고 시드된 계정임을 남긴다 — 나중에 이 계정을 찾아
    // 되돌릴 수 있는 유일한 표식이다.
    verificationProvider: 'test_seed',
    // 통계·CRM 제외용. 게이트를 우회하지 않는다(admin_firestore_service.dart,
    // crmExport.js가 이 플래그로 실사용자만 센다).
    isTestAccount: true,
    // 관리자가 아니다. 심사자에게 관리 권한이 가지 않도록 명시적으로 비운다.
    role: '',
  };
  if (withProfile) Object.assign(patch, REVIEW_PROFILE);
  return patch;
}

function fsValue(v) {
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return { integerValue: String(v) };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  throw new Error(`지원하지 않는 Firestore 값 타입: ${typeof v}`);
}

// ── 쓰기 (updateMask로 나열한 필드만 — 나머지는 그대로 둔다) ─────────────

async function applyPatch(uid, patch) {
  const token = getAccessToken();
  const fields = {};
  const maskParams = [];
  for (const [key, value] of Object.entries(patch)) {
    fields[key] = fsValue(value);
    maskParams.push(`updateMask.fieldPaths=${key}`);
  }

  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/users/${uid}?${maskParams.join('&')}`,
    {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${token}`,
        'x-goog-user-project': PROJECT_ID,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ fields }),
    },
  );
  const body = await res.json();
  if (!res.ok) {
    throw new Error(`users/${uid} 시드 실패: ${res.status} ${JSON.stringify(body)}`);
  }
}

// ── 메인 ─────────────────────────────────────────────────────────────────

async function main() {
  const args = parseArgs(process.argv.slice(2));

  const user = await resolveUid(args);
  const providers = user.providerData.map((p) => p.providerId).join(', ') || '(없음)';
  console.log('── 대상 계정 ──────────────────────────────────────────');
  console.log(`  uid          : ${user.uid}`);
  console.log(`  email        : ${user.email || '(없음)'}`);
  console.log(`  displayName  : ${user.displayName || '(없음)'}`);
  console.log(`  로그인 수단  : ${providers}`);
  console.log(`  disabled     : ${user.disabled}`);

  const fields = await readUserDoc(user.uid);
  console.log('── 현재 users 문서 ────────────────────────────────────');
  if (fields === null) {
    console.log('  (문서 없음)');
  } else {
    for (const key of [
      'identityVerified', 'isVerified', 'verificationProvider', 'isTestAccount',
      'role', 'nickname', 'name', 'gender', 'birthYear', 'accountStatus',
    ]) {
      console.log(`  ${key.padEnd(20)}: ${plain(fields[key]) ?? '(없음)'}`);
    }
  }

  const { alreadySeeded } = assertSafeToSeed(user.uid, fields);
  if (alreadySeeded) {
    console.log('\n✅ 이미 심사용으로 준비된 계정입니다. 할 일이 없습니다.');
    return;
  }

  const patch = buildPatch(args.withProfile);
  console.log('── 적용할 패치 (이 필드들만 바뀝니다) ─────────────────');
  for (const [k, v] of Object.entries(patch)) {
    console.log(`  ${k.padEnd(20)}: ${v instanceof Date ? v.toISOString() : JSON.stringify(v)}`);
  }

  if (!args.apply) {
    console.log('\n🔍 드라이런입니다 — 아무것도 쓰지 않았습니다.');
    console.log('   실제로 적용하려면 같은 명령에 --apply 를 붙여 다시 실행하세요.');
    return;
  }

  await applyPatch(user.uid, patch);
  console.log(`\n✅ users/${user.uid} 시드 완료.`);
  console.log('   앱에서 로그아웃 후 다시 Google 로그인하면 홈 화면까지 들어갑니다.');
  console.log('   (출시 뒤에는 Firebase Auth에서 이 계정을 disabled 처리하는 것을 권합니다.)');
}

main().catch((err) => {
  console.error('\n❌ 실패:', err.message);
  process.exitCode = 1;
});
