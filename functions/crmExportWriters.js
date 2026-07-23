// crmExport.js가 만든 행 배열을 실제 파일(.xlsx / .csv)로 직렬화한다.
// 이 파일도 Firestore를 전혀 건드리지 않는다 — 순수 변환 로직만 있다.

const ExcelJS = require('exceljs');
const { CRM_COLUMNS, PROGRESS_COLOR } = require('./crmExport');

const MAX_TEMPLATE_ROWS = 1000; // 드롭다운/체크박스/조건부서식을 앞으로 추가될 행까지 미리 적용해두는 범위

function excelColumnLetter(index1based) {
  let n = index1based;
  let s = '';
  while (n > 0) {
    const rem = (n - 1) % 26;
    s = String.fromCharCode(65 + rem) + s;
    n = Math.floor((n - 1) / 26);
  }
  return s;
}

// ── .xlsx 생성 ────────────────────────────────────────────────────────────
async function buildCrmWorkbookBuffer(rows, meta) {
  const workbook = new ExcelJS.Workbook();
  workbook.creator = 'PartyChu Admin';
  workbook.created = new Date();

  const sheet = workbook.addWorksheet('CRM', {
    views: [{ state: 'frozen', ySplit: 1 }], // 헤더 행 고정
  });

  sheet.columns = CRM_COLUMNS.map((col) => ({
    header: col.header,
    key: col.key,
    width: Math.max(col.header.length * 1.6, col.type === 'text' ? 18 : 14),
  }));

  // 헤더 스타일
  const headerRow = sheet.getRow(1);
  headerRow.font = { bold: true, color: { argb: 'FFFFFFFF' } };
  headerRow.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF4A4A6A' } };
  headerRow.alignment = { vertical: 'middle', horizontal: 'center', wrapText: true };
  headerRow.height = 28;

  for (const row of rows) {
    sheet.addRow(row);
  }

  const lastRow = Math.max(rows.length + 1, MAX_TEMPLATE_ROWS);
  const lastCol = excelColumnLetter(CRM_COLUMNS.length);

  // 자동 필터
  sheet.autoFilter = { from: 'A1', to: `${lastCol}1` };

  // 드롭다운/체크박스 데이터 유효성 검사 — 앞으로 수기로 추가할 행까지
  // 대비해 MAX_TEMPLATE_ROWS까지 미리 적용한다.
  CRM_COLUMNS.forEach((col, idx) => {
    const colLetter = excelColumnLetter(idx + 1);
    for (let r = 2; r <= lastRow; r++) {
      const cell = sheet.getCell(`${colLetter}${r}`);
      if (col.type === 'dropdown') {
        cell.dataValidation = {
          type: 'list',
          allowBlank: true,
          formulae: [`"${col.options.join(',')}"`],
          showErrorMessage: false, // 기존 값(예: 원본 필드 그대로 옮긴 값)이 목록에 없어도 막지 않음
        };
      } else if (col.type === 'checkbox') {
        // XLSX 표준에는 실제 클릭형 체크박스 컨트롤이 없다 — TRUE/FALSE
        // 불리언 값 + 목록형 유효성 검사로 최대한 근접하게 만든다. Google
        // Sheets에 옮긴 뒤 해당 열을 선택해 삽입 > 체크박스를 적용하면
        // 실제 체크박스로 바뀐다(안내 시트에 동일 안내 기재).
        cell.dataValidation = {
          type: 'list',
          allowBlank: false,
          formulae: ['"TRUE,FALSE"'],
        };
      }
    }
  });

  // 진행 상태 조건부 서식(색상)
  const progressColIndex = CRM_COLUMNS.findIndex((c) => c.key === 'progress') + 1;
  const progressColLetter = excelColumnLetter(progressColIndex);
  for (const [statusText, argb] of Object.entries(PROGRESS_COLOR)) {
    sheet.addConditionalFormatting({
      ref: `${progressColLetter}2:${progressColLetter}${lastRow}`,
      rules: [
        {
          type: 'cellIs',
          operator: 'equal',
          formulae: [`"${statusText}"`],
          style: { fill: { type: 'pattern', pattern: 'solid', bgColor: { argb } } },
          priority: 1,
        },
      ],
    });
  }

  // 안내 시트 — 어떤 Firestore 컬렉션/필드를 썼는지, 생성 시각, 사용법 메모.
  // 매번 새로 내보낼 때마다 함께 생성되므로 항상 실제 파일과 내용이 일치한다.
  const info = workbook.addWorksheet('안내');
  info.columns = [{ width: 100 }];
  const lines = [
    'PartyChu 영업 CRM 내보내기 안내',
    `생성 시각: ${meta.generatedAt}`,
    `조회한 parties 문서 수(테스트/삭제 포함 전체): ${meta.totalPartiesScanned} → 포함된 행: ${meta.partiesIncluded}`,
    `조회한 places 문서 수(테스트/삭제 포함 전체): ${meta.totalPlacesScanned} → 포함된 행: ${meta.placesIncluded}`,
    '',
    '사용한 Firestore 컬렉션/필드',
    '- parties: title, region, district, roadAddress/address, detailAddress, hostId/hostUid, isCombo, partyTypes, isDeleted, status, isTestAccount',
    '- places: name, type, address, detailAddress, hostId, isCombo, contactPhone(콤보 전용), bookingLink(콤보 전용), isActive, isTestAccount',
    '',
    '제외한 데이터',
    '- isTestAccount == true 인 문서(관리자 웹에서 테스트 계정으로 지정된 호스트가 만든 파티/플레이스)',
    '- parties.isDeleted == true 또는 status == "deleted"',
    '- places.isActive == false(숨김/삭제 대기)',
    '',
    '임의로 채우지 않은 칸',
    '- 인스타그램 주소, 담당자명: 두 필드 모두 현재 앱에 저장하는 곳이 없어 항상 빈칸입니다.',
    '- 연락처/홈페이지: "숙박+파티" 콤보로 등록된 곳만 값이 있고, 나머지는 빈칸입니다.',
    '- 유형: places.type이 CRM 목록과 정확히 같은 값(게스트하우스, 루프탑)일 때만 채웠고, 그 외(파티룸/펜션/호텔 등)는 빈칸으로 두고 메모에 원본 값을 남겼습니다 — 사람이 직접 분류해주세요.',
    '- 세부 유형(파티만 해당): parties.partyTypes 태그를 최대한 CRM 표기에 맞춰 옮겼고, 목록에 없는 태그는 원본 표기를 그대로 두었습니다.',
    '- 연락 완료 여부/최초·최근 연락일/담당자/진행상태 외 영업 관련 칸은 실제 영업 이력이 없어 기본값(미체크/빈칸)입니다 — 진행 상태만 "등록 완료"로 기본 설정했습니다(이미 플랫폼에 등록된 데이터이므로).',
    '',
    '체크박스 칸 사용법',
    '- XLSX 표준에는 진짜 클릭형 체크박스가 없어 TRUE/FALSE 값 + 목록 유효성 검사로 대체했습니다.',
    '- Google Sheets로 옮긴 뒤 해당 열을 선택하고 삽입 > 체크박스를 적용하면 실제 체크박스로 바뀝니다.',
    '',
    '중복 여부 칸',
    '- 업체명/연락처/인스타그램 중 값이 있는 항목이 다른 행과 겹치면 표시됩니다(빈칸끼리는 비교하지 않음).',
  ];
  lines.forEach((line, i) => {
    const cell = info.getCell(`A${i + 1}`);
    cell.value = line;
    if (i === 0) cell.font = { bold: true, size: 13 };
  });

  const buffer = await workbook.xlsx.writeBuffer();
  return buffer;
}

// ── .csv 생성 (UTF-8 BOM 포함 — 엑셀/시트에서 한글 깨짐 방지) ────────────
function csvEscape(value) {
  const s = value == null ? '' : String(value);
  if (/[",\n\r]/.test(s)) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
}

function buildCrmCsv(rows) {
  const headerLine = CRM_COLUMNS.map((c) => csvEscape(c.header)).join(',');
  const dataLines = rows.map((row) =>
    CRM_COLUMNS.map((c) => {
      const v = row[c.key];
      if (c.type === 'checkbox') return v ? 'TRUE' : 'FALSE';
      return csvEscape(v);
    }).join(',')
  );
  const csvBody = [headerLine, ...dataLines].join('\r\n');
  const BOM = '﻿';
  return BOM + csvBody;
}

module.exports = {
  buildCrmWorkbookBuffer,
  buildCrmCsv,
};
