// ── 기존 호스트 데이터 조사 (읽기 전용) ─────────────────────────────────────
//
// 사업자 인증 체계를 새로 넣기 전에 "지금 누가 어떤 상태인가"를 파악하기 위한
// 조사 스크립트다.
//
// ⚠️ 이 스크립트는 **아무것도 쓰지 않는다.** get/where 조회만 하고, 기존
//    사용자를 verified로 만들거나 파티 상태를 바꾸는 코드는 들어 있지 않다.
//    (실수로도 그렇게 되지 않도록 Admin SDK 쓰기 메서드를 아예 호출하지 않는다.)
//
// 실행:
//   1) 서비스 계정 키를 받아 환경변수로 지정한다
//        export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
//        (Windows PowerShell: $env:GOOGLE_APPLICATION_CREDENTIALS="C:\path\to\key.json")
//   2) node auditHostVerification.js
//
// 출력은 집계 수치와, 개인정보가 아닌 식별자(uid 앞 6자리·파티 id)까지만
// 보여준다 — 실명·연락처·사업자번호는 찍지 않는다.

const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

// uid는 통째로 찍지 않는다 — 로그가 어디로 흘러가든 계정을 특정하지 못하게.
const shortUid = (uid) => `${String(uid || '').slice(0, 6)}…`;

function isPersonalPartyDoc(d) {
  // 앱이 실제로 개인/사업자를 가르는 기준은 등록 진입점이고, 파티 문서에
  // 남는 흔적은 콤보 연결 필드다(models/combo_place_type.dart 참고).
  if (d.isCombo === true) return false;
  if (d.comboPlaceType) return false;
  if (d.linkedEventId) return false;
  if (d.linkedPlaceId) return false;
  return true;
}

function acceptsApplicationsNow(d, now) {
  if (d.isDeleted === true) return false;
  if (d.status && d.status !== 'active') return false;
  if (d.isActive === false) return false;
  // 새 필드 — 없으면 'open'으로 간주(기존 문서 전부).
  if (d.openState === 'preopen') return false;
  if ((d.recruitStatus || '모집중') !== '모집중') return false;

  const deadline = d.recruitDeadlineAt && d.recruitDeadlineAt.toDate
    ? d.recruitDeadlineAt.toDate()
    : null;
  if (deadline && deadline < now) return false;

  // 정기 파티는 회차가 계속 열리므로 날짜만으로 지난 파티라 단정하지 않는다.
  if (d.scheduleType === 'recurring') return true;

  const start = d.partyDateTime && d.partyDateTime.toDate
    ? d.partyDateTime.toDate()
    : null;
  if (start && start < now) return false;

  return true;
}

async function main() {
  const now = new Date();
  console.log(`\n조사 시각: ${now.toISOString()}`);
  console.log('※ 이 스크립트는 읽기만 합니다. 아무 문서도 수정하지 않습니다.\n');

  // ── 1. 사용자 쪽 ─────────────────────────────────────────────────────
  const usersSnap = await db.collection('users').get();

  let totalUsers = 0;
  let selfDeclaredBusiness = 0;
  let selfDeclaredBusinessWithNumber = 0;
  let alreadyVerified = 0;
  let isHostCount = 0;
  const businessDeclaredUids = [];

  usersSnap.forEach((doc) => {
    const d = doc.data();
    totalUsers += 1;
    if (d.isHost === true) isHostCount += 1;

    const si = d.settlementInfo || {};
    if (si.hostType === 'business') {
      selfDeclaredBusiness += 1;
      businessDeclaredUids.push(doc.id);
      if (String(si.businessNumber || '').trim()) {
        selfDeclaredBusinessWithNumber += 1;
      }
    }

    const bv = d.businessVerification;
    if (bv && bv.status === 'verified') alreadyVerified += 1;
  });

  console.log('── 사용자 ─────────────────────────────────────────────');
  console.log(`전체 사용자                       : ${totalUsers}`);
  console.log(`호스트 경험 있음(isHost)          : ${isHostCount}`);
  console.log(`자칭 사업자(hostType == business) : ${selfDeclaredBusiness}`);
  console.log(`  └ 사업자번호까지 입력한 사람    : ${selfDeclaredBusinessWithNumber}`);
  console.log(`이미 businessVerification=verified: ${alreadyVerified}`
    + (alreadyVerified === 0 ? '  (정상 — 새 체계는 전원 미인증에서 시작)' : '  ⚠️ 확인 필요'));

  // ── 2. 파티 쪽 ───────────────────────────────────────────────────────
  const partiesSnap = await db.collection('parties').get();

  let totalParties = 0;
  let openParties = 0;
  let preopenParties = 0;
  const openPersonal = [];
  const openBusinessPath = [];
  const affectedHostUids = new Set();

  partiesSnap.forEach((doc) => {
    const d = doc.data();
    totalParties += 1;
    if (d.openState === 'preopen') preopenParties += 1;
    if (!acceptsApplicationsNow(d, now)) return;

    openParties += 1;
    const entry = {
      id: doc.id,
      hostId: d.hostId || '',
      title: String(d.title || '').slice(0, 20),
      fee: d.maleFee ?? d.femaleFee ?? d.fee ?? 0,
    };
    if (isPersonalPartyDoc(d)) {
      openPersonal.push(entry);
      if (d.hostId) affectedHostUids.add(d.hostId);
    } else {
      openBusinessPath.push(entry);
      if (d.hostId) affectedHostUids.add(d.hostId);
    }
  });

  console.log('\n── 파티 ───────────────────────────────────────────────');
  console.log(`전체 파티 문서                    : ${totalParties}`);
  console.log(`현재 신청/결제 가능               : ${openParties}`);
  console.log(`  ├ 개인 경로(파티 등록)          : ${openPersonal.length}`);
  console.log(`  └ 사업자 경로(콤보/플레이스 연결): ${openBusinessPath.length}`);
  console.log(`이미 오픈예정(openState=preopen)  : ${preopenParties}`);

  // ── 3. 새 인증 대상 ──────────────────────────────────────────────────
  const declaredSet = new Set(businessDeclaredUids);
  const affected = [...affectedHostUids];
  const affectedDeclaredBusiness = affected.filter((u) => declaredSet.has(u));

  console.log('\n── 새 인증 대상 ───────────────────────────────────────');
  console.log(`현재 신청 가능한 파티를 가진 호스트: ${affected.length}명`);
  console.log(`  └ 그중 자칭 사업자              : ${affectedDeclaredBusiness.length}명`);
  console.log(`  └ 그중 자칭 개인/미설정         : ${affected.length - affectedDeclaredBusiness.length}명`);
  console.log(
    '\n이 호스트들은 새 체계에서 전원 미인증 상태로 시작합니다.\n'
    + '기존 파티는 openState 필드가 없어 계속 \'open\'으로 동작하므로 지금 열려 있는\n'
    + '신청·결제는 그대로 유지됩니다. 앞으로 새로 등록하는 파티만 오픈예정이 됩니다.',
  );

  // ── 4. 개인 경로로 지금 신청 가능한 파티 목록 (판단 근거) ────────────
  if (openPersonal.length > 0) {
    console.log('\n── 개인 경로 · 현재 신청 가능한 파티 ──────────────────');
    openPersonal
      .sort((a, b) => (b.fee || 0) - (a.fee || 0))
      .slice(0, 50)
      .forEach((p) => {
        console.log(`  ${p.id}  host=${shortUid(p.hostId)}  참가비=${p.fee}  ${p.title}`);
      });
    if (openPersonal.length > 50) {
      console.log(`  … 외 ${openPersonal.length - 50}건 (상위 50건만 표시)`);
    }
  }

  console.log('\n조사 완료 — 변경된 문서: 0건\n');
}

main().catch((err) => {
  console.error('조사 실패:', err.message);
  process.exit(1);
});
