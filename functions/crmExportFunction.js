// 관리자 웹 "Google Sheets 내보내기" 버튼이 호출하는 onCall — parties/places를
// 읽기 전용으로 조회해 CRM용 .xlsx/.csv를 만들어 base64로 돌려준다. Firestore에
// 쓰기는 전혀 하지 않는다(crmExport.js가 전부 .get()만 호출).
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { fetchCrmRows } = require('./crmExport');
const { buildCrmWorkbookBuffer, buildCrmCsv } = require('./crmExportWriters');
const { upsertCrmSpreadsheet } = require('./googleSheetsCrm');

const REGION = 'asia-northeast3';
// PartyChu CRM 시트 생성/갱신 전용 서비스 계정 — partner@partychu.co.kr
// Workspace의 공유 드라이브에 멤버로 추가해두면, 이 서비스 계정으로 실행되는
// 함수 안에서 키 파일 없이(ADC) 곧바로 Sheets/Drive API를 쓸 수 있다.
const CRM_SHEETS_SERVICE_ACCOUNT = 'partychu-crm-sheets@partychu-30c24.iam.gserviceaccount.com';

async function requireAdminCaller(db, uid) {
  if (!uid) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  const callerSnap = await db.collection('users').doc(uid).get();
  if (callerSnap.data()?.role !== 'admin') {
    throw new HttpsError('permission-denied', '관리자만 사용할 수 있습니다.');
  }
}

exports.adminExportCrmData = onCall({ region: REGION, timeoutSeconds: 120, memory: '512MiB' }, async (request) => {
  const db = admin.firestore();
  await requireAdminCaller(db, request.auth?.uid);

  const { rows, meta } = await fetchCrmRows(db);
  const [xlsxBuffer, csv] = await Promise.all([
    buildCrmWorkbookBuffer(rows, meta),
    Promise.resolve(buildCrmCsv(rows)),
  ]);

  return {
    rowCount: rows.length,
    meta,
    xlsxBase64: Buffer.from(xlsxBuffer).toString('base64'),
    csvBase64: Buffer.from(csv, 'utf8').toString('base64'),
  };
});

// ── 관리자 웹 "Google Sheets 생성" 버튼 — partner@partychu.co.kr Workspace의
// 공유 드라이브(서비스 계정이 멤버로 추가돼 있어야 함) 안에 "PartyChu CRM"
// 시트를 만들거나(없으면) 갱신한다(있으면). Firestore는 fetchCrmRows가 읽기
// 전용으로만 조회한다. 재실행 시 사람이 입력한 영업 기록은 googleSheetsCrm.js가
// 보존한다(파일 상단 주석 참고). 사람의 로그인/OAuth 동의 절차가 필요 없다 —
// 이 함수 자체가 서비스 계정으로 실행되도록 `serviceAccount` 옵션을 지정했다.
exports.adminGenerateCrmGoogleSheet = onCall(
  { region: REGION, timeoutSeconds: 120, memory: '512MiB', serviceAccount: CRM_SHEETS_SERVICE_ACCOUNT },
  async (request) => {
    const db = admin.firestore();
    await requireAdminCaller(db, request.auth?.uid);

    const { rows } = await fetchCrmRows(db);
    const result = await upsertCrmSpreadsheet(rows);

    return { ...result, rowCount: rows.length };
  }
);
