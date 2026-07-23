// PartyChu 영업 CRM 내보내기 — 1회성 로컬 스크립트. parties/places를 읽기
// 전용으로 조회해(crmExport.js) .xlsx/.csv를 만든다. Firestore에는 어떤
// 수정·삭제·쓰기도 하지 않는다 — 매핑 로직(crmExport.js)이 db.collection(...).get()
// 만 호출한다.
//
// admin.firestore()는 이 프로젝트의 로컬 실행 방식(서비스 계정 키 파일 없이
// gcloud 로그인 계정 토큰을 그대로 쓰는 커스텀 Credential)을 거부하므로
// (backfillUserFields.js와 동일한 이유), Firestore REST API로 직접 조회해
// Admin SDK와 같은 모양(.collection(name).get() -> {docs:[{id, data()}]})의
// 최소 shim을 통해 crmExport.js를 그대로 재사용한다.
//
// 실행 전 준비:
//   gcloud auth login   (프로젝트 조회 권한 필요 — 쓰기는 전혀 하지 않음)
//
// 실행:
//   cd functions
//   node scripts/exportCrmSheet.js [출력폴더 경로 — 생략 시 scripts/output]

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'partychu-30c24';
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

function getAccessToken() {
  return execSync('gcloud auth print-access-token', { encoding: 'utf8' }).trim();
}

function fsValueToJs(f) {
  if (f == null) return undefined;
  if ('stringValue' in f) return f.stringValue;
  if ('booleanValue' in f) return f.booleanValue;
  if ('integerValue' in f) return Number(f.integerValue);
  if ('doubleValue' in f) return Number(f.doubleValue);
  if ('timestampValue' in f) {
    const iso = f.timestampValue;
    return { toDate: () => new Date(iso) };
  }
  if ('arrayValue' in f) return (f.arrayValue.values || []).map(fsValueToJs);
  if ('mapValue' in f) {
    const out = {};
    for (const [k, v] of Object.entries(f.mapValue.fields || {})) out[k] = fsValueToJs(v);
    return out;
  }
  if ('nullValue' in f) return null;
  return undefined;
}

// Admin SDK의 db.collection(name).get() 과 동일한 모양만 흉내낸 읽기 전용
// shim — 오직 :runQuery(GET 성격의 조회)만 호출하고, 쓰기 관련 메서드는
// 아예 만들지 않는다.
const db = {
  collection(name) {
    return {
      async get() {
        const token = getAccessToken();
        const body = { structuredQuery: { from: [{ collectionId: name }] } };
        const res = await fetch(`${BASE}:runQuery`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${token}`, 'x-goog-user-project': PROJECT_ID, 'Content-Type': 'application/json' },
          body: JSON.stringify(body),
        });
        const arr = await res.json();
        if (!Array.isArray(arr)) throw new Error(`Firestore 조회 실패(${name}): ${JSON.stringify(arr)}`);
        const docs = arr
          .filter((r) => r.document)
          .map((r) => {
            const id = r.document.name.split('/').pop();
            const fields = r.document.fields || {};
            const data = {};
            for (const [k, v] of Object.entries(fields)) data[k] = fsValueToJs(v);
            return { id, data: () => data };
          });
        return { docs, size: docs.length };
      },
    };
  },
};

const { fetchCrmRows } = require('../crmExport');
const { buildCrmWorkbookBuffer, buildCrmCsv } = require('../crmExportWriters');

async function main() {
  const outDir = process.argv[2] || path.join(__dirname, 'output');
  fs.mkdirSync(outDir, { recursive: true });

  console.log('parties/places를 읽기 전용으로 조회합니다(쓰기 없음)...');
  const { rows, meta } = await fetchCrmRows(db);
  console.log('조회 결과:', JSON.stringify(meta, null, 2));
  console.log(`포함된 행 수: ${rows.length}`);

  const xlsxBuffer = await buildCrmWorkbookBuffer(rows, meta);
  const csv = buildCrmCsv(rows);

  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const xlsxPath = path.join(outDir, `partychu_crm_${stamp}.xlsx`);
  const csvPath = path.join(outDir, `partychu_crm_${stamp}.csv`);

  fs.writeFileSync(xlsxPath, xlsxBuffer);
  fs.writeFileSync(csvPath, csv, 'utf8');

  console.log('\n생성 완료:');
  console.log(' -', xlsxPath);
  console.log(' -', csvPath);
}

main().catch((err) => {
  console.error('CRM 내보내기 실패:', err);
  process.exit(1);
});
