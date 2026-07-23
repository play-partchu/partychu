// PartyChu CRM 전용 Google Sheets 생성/갱신 로직 — 순수 함수만 모아둔 파일
// (Cloud Functions는 export하지 않음, googleActivityHelpers.js와 동일한 컨벤션).
// crmExportFunction.js가 구조분해로 가져다 쓴다.
//
// ── 인증 방식: 서비스 계정(공유 드라이브) ─────────────────────────────────
// OAuth(사람 로그인) 대신, 이 Cloud Function 자체가
// partychu-crm-sheets@partychu-30c24.iam.gserviceaccount.com 서비스 계정으로
// 실행되도록 배포돼 있다(crmExportFunction.js의 `serviceAccount` 옵션).
// 서비스 계정은 자기 소유의 "내 드라이브"가 없으므로, partner@partychu.co.kr
// Workspace에 만든 "공유 드라이브"에 이 서비스 계정을 멤버로 추가해두면,
// 그 공유 드라이브 안에서 파일을 만들고 관리할 수 있다 — 사람의 로그인/동의
// 절차 자체가 필요 없고 토큰 만료도 없다.
//
// ── 재실행 시 데이터 보호 원칙(중요) ──────────────────────────────────────
// 친구와 함께 이 시트에서 직접 영업 활동을 기록해나갈 것이므로, "생성" 버튼을
// 다시 눌러도 사람이 입력한 영업 기록(연락 완료 여부/담당자명/연락 방법/
// 최초·최근 연락일/진행 상태/담당자/메모)은 절대 덮어쓰지 않는다.
// PartyChu 파티/플레이스 Document ID로 기존 행을 찾아 "원본 데이터" 칸만
// 최신값으로 갱신하고, 새 파티/플레이스는 새 행으로 추가한다. 수기로 추가한
// 리드(원본 Document ID가 없는 행)는 아예 건드리지 않는다.
const { google } = require('googleapis');
const { HttpsError } = require('firebase-functions/v2/https');
const { CRM_COLUMNS, PROGRESS_COLOR } = require('./crmExport');

const SPREADSHEET_TITLE = 'PartyChu CRM';
const SHEET_TITLE = 'CRM';
const SCOPES = [
  'https://www.googleapis.com/auth/spreadsheets',
  'https://www.googleapis.com/auth/drive',
];

// 재생성 시에도 사람이 입력해온 값을 보존해야 하는 컬럼(영업 진행 기록).
const PROTECTED_KEYS = new Set([
  'contactDone', 'contactPersonName', 'contactMethod',
  'firstContactDate', 'lastContactDate', 'progress', 'assignee', 'memo',
]);

function colLetter(index1based) {
  let n = index1based;
  let s = '';
  while (n > 0) {
    const rem = (n - 1) % 26;
    s = String.fromCharCode(65 + rem) + s;
    n = Math.floor((n - 1) / 26);
  }
  return s;
}

const DOC_ID_COL_INDEX = CRM_COLUMNS.findIndex((c) => c.key === 'docId') + 1;
const LAST_COL_INDEX = CRM_COLUMNS.length;
const LAST_COL_LETTER = colLetter(LAST_COL_INDEX);

function rowToArray(rowObj) {
  return CRM_COLUMNS.map((c) => {
    const v = rowObj[c.key];
    if (c.type === 'checkbox') return v === true;
    return v == null ? '' : v;
  });
}

function arrayToRowObject(arr) {
  const obj = {};
  CRM_COLUMNS.forEach((c, i) => {
    obj[c.key] = arr[i] ?? '';
  });
  return obj;
}

// ── 이 서비스 계정이 실행 시점에 자동으로 얻는 인증 클라이언트 ───────────
// 배포된 Cloud Function 자체가 partychu-crm-sheets 서비스 계정으로 도는
// 덕분에, 키 파일 없이 Application Default Credentials만으로 인증된다.
async function getServiceAccountClient() {
  const auth = new google.auth.GoogleAuth({ scopes: SCOPES });
  return auth.getClient();
}

// ── 서비스 계정이 멤버로 등록된 공유 드라이브를 찾는다 ────────────────────
// 공유 드라이브 ID를 코드에 하드코딩하지 않기 위해, 이 서비스 계정이 접근
// 가능한 공유 드라이브 중 "PartyChu"가 이름에 포함된 것을 우선 찾고, 하나뿐
// 이면 그것을 쓴다. 여러 개인데 이름 매칭이 안 되면 명확한 에러로 안내한다.
async function findTargetSharedDrive(drive) {
  const res = await drive.drives.list({ pageSize: 50, fields: 'drives(id,name)' });
  const drives = res.data.drives || [];
  if (drives.length === 0) {
    throw new HttpsError(
      'failed-precondition',
      '서비스 계정(partychu-crm-sheets@partychu-30c24.iam.gserviceaccount.com)이 접근 가능한 공유 드라이브가 없습니다. partner@partychu.co.kr에서 공유 드라이브를 만들고 이 서비스 계정을 멤버(콘텐츠 관리자 이상)로 추가해주세요.'
    );
  }
  const named = drives.find((d) => d.name.includes('PartyChu'));
  if (named) return named;
  if (drives.length === 1) return drives[0];
  throw new HttpsError(
    'failed-precondition',
    `서비스 계정이 접근 가능한 공유 드라이브가 여러 개(${drives.map((d) => d.name).join(', ')})인데 이름에 "PartyChu"가 포함된 것이 없습니다. 공유 드라이브 이름에 "PartyChu"를 포함시켜주세요.`
  );
}

// ── 공유 드라이브에서 기존 "PartyChu CRM" 스프레드시트 찾기 ──────────────
async function findExistingSpreadsheetId(drive, sharedDriveId) {
  const res = await drive.files.list({
    q: `name='${SPREADSHEET_TITLE}' and mimeType='application/vnd.google-apps.spreadsheet' and trashed=false`,
    fields: 'files(id,name)',
    corpora: 'drive',
    driveId: sharedDriveId,
    includeItemsFromAllDrives: true,
    supportsAllDrives: true,
  });
  const files = res.data.files || [];
  return files.length > 0 ? files[0].id : null;
}

// ── 공유 드라이브 안에 새 스프레드시트 생성 ───────────────────────────────
async function createSpreadsheet(drive, sheets, sharedDriveId) {
  const created = await drive.files.create({
    requestBody: {
      name: SPREADSHEET_TITLE,
      mimeType: 'application/vnd.google-apps.spreadsheet',
      parents: [sharedDriveId],
    },
    supportsAllDrives: true,
    fields: 'id',
  });
  const spreadsheetId = created.data.id;

  // Drive API로 만들면 기본 탭 이름이 "시트1"이라 CRM으로 바꿔준다.
  const meta = await sheets.spreadsheets.get({ spreadsheetId, fields: 'sheets.properties' });
  const defaultSheetId = meta.data.sheets[0].properties.sheetId;
  await sheets.spreadsheets.batchUpdate({
    spreadsheetId,
    requestBody: {
      requests: [{
        updateSheetProperties: {
          properties: { sheetId: defaultSheetId, title: SHEET_TITLE, gridProperties: { frozenRowCount: 1 } },
          fields: 'title,gridProperties.frozenRowCount',
        },
      }],
    },
  });

  return { spreadsheetId, sheetId: defaultSheetId };
}

async function getSheetId(sheets, spreadsheetId) {
  const res = await sheets.spreadsheets.get({ spreadsheetId, fields: 'sheets.properties' });
  const found = (res.data.sheets || []).find((s) => s.properties.title === SHEET_TITLE);
  if (found) return found.properties.sheetId;
  // 기존 스프레드시트인데 CRM 탭이 없다면(사람이 탭을 지웠거나 이름을 바꾼
  // 경우) 새로 하나 만든다 — 다른 탭은 손대지 않는다.
  const addRes = await sheets.spreadsheets.batchUpdate({
    spreadsheetId,
    requestBody: { requests: [{ addSheet: { properties: { title: SHEET_TITLE, gridProperties: { frozenRowCount: 1 } } } }] },
  });
  return addRes.data.replies[0].addSheet.properties.sheetId;
}

// ── 기존 시트의 현재 값을 읽어온다(있으면) ────────────────────────────────
async function readExistingRows(sheets, spreadsheetId) {
  try {
    const res = await sheets.spreadsheets.values.get({
      spreadsheetId,
      range: `${SHEET_TITLE}!A2:${LAST_COL_LETTER}`,
      valueRenderOption: 'UNFORMATTED_VALUE',
    });
    return res.data.values || [];
  } catch (e) {
    return []; // 탭이 방금 새로 만들어졌거나 비어있으면 빈 배열
  }
}

// ── 헤더 + 데이터 + 서식(고정행/자동필터/드롭다운/체크박스/조건부서식/열너비) ──
function buildFormattingRequests(sheetId, totalRowCount) {
  const lastRow = Math.max(totalRowCount + 1, 1000); // 앞으로 수기 추가할 행까지 대비
  const requests = [];

  requests.push({
    repeatCell: {
      range: { sheetId, startRowIndex: 0, endRowIndex: 1, startColumnIndex: 0, endColumnIndex: LAST_COL_INDEX },
      cell: {
        userEnteredFormat: {
          backgroundColor: { red: 0.29, green: 0.29, blue: 0.42 },
          textFormat: { bold: true, foregroundColor: { red: 1, green: 1, blue: 1 } },
          horizontalAlignment: 'CENTER',
          wrapStrategy: 'WRAP',
        },
      },
      fields: 'userEnteredFormat(backgroundColor,textFormat,horizontalAlignment,wrapStrategy)',
    },
  });

  requests.push({
    updateSheetProperties: {
      properties: { sheetId, gridProperties: { frozenRowCount: 1 } },
      fields: 'gridProperties.frozenRowCount',
    },
  });
  CRM_COLUMNS.forEach((col, idx) => {
    requests.push({
      updateDimensionProperties: {
        range: { sheetId, dimension: 'COLUMNS', startIndex: idx, endIndex: idx + 1 },
        properties: { pixelSize: Math.max(col.header.length * 14, col.type === 'text' ? 160 : 120) },
        fields: 'pixelSize',
      },
    });
  });

  requests.push({
    setBasicFilter: {
      filter: { range: { sheetId, startRowIndex: 0, endRowIndex: lastRow, startColumnIndex: 0, endColumnIndex: LAST_COL_INDEX } },
    },
  });

  CRM_COLUMNS.forEach((col, idx) => {
    const range = { sheetId, startRowIndex: 1, endRowIndex: lastRow, startColumnIndex: idx, endColumnIndex: idx + 1 };
    if (col.type === 'dropdown') {
      requests.push({
        setDataValidation: {
          range,
          rule: {
            condition: { type: 'ONE_OF_LIST', values: col.options.map((v) => ({ userEnteredValue: v })) },
            showCustomUi: true,
            strict: false,
          },
        },
      });
    } else if (col.type === 'checkbox') {
      requests.push({
        setDataValidation: {
          range,
          rule: { condition: { type: 'BOOLEAN' }, strict: true },
        },
      });
    }
  });

  const progressColIndex = CRM_COLUMNS.findIndex((c) => c.key === 'progress');
  Object.entries(PROGRESS_COLOR).forEach(([statusText, argb], i) => {
    const hex = argb.slice(2);
    const r = parseInt(hex.slice(0, 2), 16) / 255;
    const g = parseInt(hex.slice(2, 4), 16) / 255;
    const b = parseInt(hex.slice(4, 6), 16) / 255;
    requests.push({
      addConditionalFormatRule: {
        rule: {
          ranges: [{ sheetId, startRowIndex: 1, endRowIndex: lastRow, startColumnIndex: progressColIndex, endColumnIndex: progressColIndex + 1 }],
          booleanRule: {
            condition: { type: 'TEXT_EQ', values: [{ userEnteredValue: statusText }] },
            format: { backgroundColor: { red: r, green: g, blue: b } },
          },
        },
        index: i,
      },
    });
  });

  return requests;
}

// ── 메인: 있으면 갱신(사람이 입력한 영업 기록은 보존), 없으면 새로 생성 ────
async function upsertCrmSpreadsheet(rows) {
  const authClient = await getServiceAccountClient();
  const sheets = google.sheets({ version: 'v4', auth: authClient });
  const drive = google.drive({ version: 'v3', auth: authClient });

  const sharedDrive = await findTargetSharedDrive(drive);
  let spreadsheetId = await findExistingSpreadsheetId(drive, sharedDrive.id);
  let sheetId;
  let isNew = false;

  if (!spreadsheetId) {
    const created = await createSpreadsheet(drive, sheets, sharedDrive.id);
    spreadsheetId = created.spreadsheetId;
    sheetId = created.sheetId;
    isNew = true;
  } else {
    sheetId = await getSheetId(sheets, spreadsheetId);
  }

  const existingRaw = isNew ? [] : await readExistingRows(sheets, spreadsheetId);
  const existingByDocId = new Map();
  existingRaw.forEach((arr, i) => {
    const docId = arr[DOC_ID_COL_INDEX - 1];
    if (docId) existingByDocId.set(docId, { rowIndex: i, values: arr });
  });

  const updates = [];
  const appended = [];

  for (const freshRow of rows) {
    const existing = existingByDocId.get(freshRow.docId);
    if (existing) {
      const merged = arrayToRowObject(existing.values);
      for (const col of CRM_COLUMNS) {
        if (!PROTECTED_KEYS.has(col.key)) merged[col.key] = freshRow[col.key];
      }
      updates.push({ rowIndex: existing.rowIndex, values: rowToArray(merged) });
    } else {
      appended.push(rowToArray(freshRow));
    }
  }

  const dataRequests = [];
  if (isNew) {
    dataRequests.push({
      range: `${SHEET_TITLE}!A1:${LAST_COL_LETTER}1`,
      values: [CRM_COLUMNS.map((c) => c.header)],
    });
  }
  for (const u of updates) {
    dataRequests.push({
      range: `${SHEET_TITLE}!A${u.rowIndex + 2}:${LAST_COL_LETTER}${u.rowIndex + 2}`,
      values: [u.values],
    });
  }

  if (dataRequests.length > 0) {
    await sheets.spreadsheets.values.batchUpdate({
      spreadsheetId,
      requestBody: { valueInputOption: 'USER_ENTERED', data: dataRequests },
    });
  }

  if (appended.length > 0) {
    await sheets.spreadsheets.values.append({
      spreadsheetId,
      range: `${SHEET_TITLE}!A1:${LAST_COL_LETTER}1`,
      valueInputOption: 'USER_ENTERED',
      insertDataOption: 'INSERT_ROWS',
      requestBody: { values: appended },
    });
  }

  const totalRowCount = existingRaw.length + appended.length;
  const formattingRequests = buildFormattingRequests(sheetId, totalRowCount);
  await sheets.spreadsheets.batchUpdate({
    spreadsheetId,
    requestBody: { requests: formattingRequests },
  });

  return {
    spreadsheetId,
    url: `https://docs.google.com/spreadsheets/d/${spreadsheetId}/edit`,
    isNew,
    updatedCount: updates.length,
    appendedCount: appended.length,
    sharedDriveName: sharedDrive.name,
  };
}

module.exports = { upsertCrmSpreadsheet };
