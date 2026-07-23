// PartyChu 영업 CRM 내보내기 — parties/places를 읽기 전용으로 조회해 영업용
// 스프레드시트 행으로 매핑하는 순수 로직만 모아둔 파일. 이 파일은 Firestore에
// 절대 쓰기를 하지 않는다(모든 함수가 db.collection(...).get()만 호출).
//
// 다른 순수 헬퍼 모듈(memberActivityHelpers.js, partyCapacity.js)과 동일한
// 컨벤션 — Cloud Functions를 직접 export하지 않으므로 index.js/crmExportFunction.js/
// scripts/exportCrmSheet.js가 전부 구조분해로만 가져다 쓴다.
//
// ── 필드 매핑 시 지킨 원칙 ────────────────────────────────────────────────
// 1) 존재하지 않는 필드(인스타그램, 담당자명 등)는 항상 빈 문자열로 둔다 —
//    절대 임의의 값을 채우지 않는다.
// 2) Firestore의 분류 체계(parties.category/partyTypes, places.type)가
//    CRM이 요구하는 드롭다운 값과 이름이 다를 때, "정확히 일치"하는 경우만
//    그대로 옮기고 나머지는 원본 값을 메모에 남겨 사람이 직접 분류하게 한다
//    (예: places.type='파티룸'은 CRM 유형 목록에 없으므로 유형 칸은 비우고
//    메모에 "원본 유형: 파티룸"만 남김).
// 3) isCombo:true(숙박+파티 콤보)는 parties/places 양쪽에 실제로 존재하는
//    필드라 "숙박+파티"로 확신 있게 매핑한다.

const REGION1_PREFIX_MAP = {
  '서울특별시': '서울',
  '부산광역시': '부산',
  '대구광역시': '대구',
  '인천광역시': '인천',
  '광주광역시': '광주',
  '대전광역시': '대전',
  '울산광역시': '울산',
  '세종특별자치시': '세종',
  '경기도': '경기',
  '강원특별자치도': '강원',
  '강원도': '강원',
  '충청북도': '충북',
  '충청남도': '충남',
  '전북특별자치도': '전북',
  '전라북도': '전북',
  '전라남도': '전남',
  '경상북도': '경북',
  '경상남도': '경남',
  '제주특별자치도': '제주',
};

// places.address는 "서울특별시 서초구 강남대로65길 12 ..." 형태의 도로명
// 전체 주소 문자열뿐이라(별도 region/district 필드 없음), 앞 두 토큰만
// 기계적으로 잘라 region1/region2로 근사한다 — 매칭되지 않으면 빈 문자열
// (추측해서 채우지 않음).
function parseRegionFromAddress(address) {
  if (!address || typeof address !== 'string') return '';
  const tokens = address.trim().split(/\s+/);
  if (tokens.length === 0) return '';
  const region1 = REGION1_PREFIX_MAP[tokens[0]];
  if (!region1) return '';
  const region2 = tokens[1] || '';
  return region2 ? `${region1} ${region2}` : region1;
}

// parties.partyTypes(다중 선택 태그, 예: 'DJ 파티', '풀파티', '하우스파티')를
// CRM 세부 유형 목록과 최대한 맞춰본다 — 공백/'파티' 접미사 차이만 제거한
// 정확 일치만 CRM 표기로 바꾸고, 목록에 없는 태그는 원본 그대로 남긴다
// (데이터 유실 방지 — 임의로 '기타'에 뭉뚱그리지 않음).
const CRM_SUBTYPE_OPTIONS = [
  '생일파티', 'DJ파티', '풀파티', '루프탑파티', '할로윈', '크리스마스',
  '신년파티', '공연', '라이브', '와인', '칵테일', '기타',
];

function normalizePartyTag(tag) {
  return String(tag).replace(/\s+/g, '').replace(/파티$/, '파티'); // 공백만 제거, '파티' 접미사는 유지한 채 비교
}

function mapPartySubType(partyTypes) {
  if (!Array.isArray(partyTypes) || partyTypes.length === 0) return '';
  const mapped = partyTypes.map((raw) => {
    const compact = String(raw).replace(/\s+/g, ''); // '루프탑 파티' -> '루프탑파티'
    const withoutSuffix = compact.replace(/파티$/, '');
    // CRM 목록 라벨과 접미사 유무만 다르게 정확히 일치하면 CRM 표기로 치환
    const exact = CRM_SUBTYPE_OPTIONS.find((opt) => opt === compact || opt === withoutSuffix);
    return exact || raw; // 매칭 안 되면 원본 표기 그대로(정보 유실 방지)
  });
  return mapped.join(', ');
}

const PLACE_TYPE_EXACT_MATCH = ['게스트하우스', '루프탑']; // places.type과 CRM 유형 목록 표기가 정확히 같은 값만

function buildAddressText(...parts) {
  return parts.filter((p) => p && String(p).trim().length > 0).join(' ').trim();
}

function toDateOnlyString(ts) {
  if (!ts || typeof ts.toDate !== 'function') return '';
  const d = ts.toDate();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

// ── parties/{id} 문서 1건 -> CRM 행 ──────────────────────────────────────
function buildRowFromParty(doc) {
  const d = doc.data();
  const isCombo = d.isCombo === true;
  const roadOrAddress = d.roadAddress || d.address || '';
  let memo = '';
  return {
    isMember: true,
    isRegistered: true,
    contactDone: false,
    businessName: d.title || '',
    type: isCombo ? '숙박+파티' : '파티',
    subType: mapPartySubType(d.partyTypes),
    region: buildAddressText(d.region, d.district),
    detailAddress: buildAddressText(roadOrAddress, d.detailAddress),
    phone: '',
    instagram: '',
    website: '',
    contactPersonName: '',
    contactMethod: '',
    firstContactDate: '',
    lastContactDate: '',
    progress: '등록 완료',
    memberUid: d.hostId || d.hostUid || '',
    docId: doc.id,
    docCollection: 'parties',
    assignee: '',
    memo,
  };
}

// ── places/{id} 문서 1건 -> CRM 행 ───────────────────────────────────────
function buildRowFromPlace(doc) {
  const d = doc.data();
  const isCombo = d.isCombo === true;
  let type = '';
  let memo = '';
  if (isCombo) {
    type = '숙박+파티';
  } else if (d.type && PLACE_TYPE_EXACT_MATCH.includes(d.type)) {
    type = d.type;
  } else if (d.type) {
    memo = `원본 유형: ${d.type}`; // CRM 목록과 표기가 달라 임의 매핑하지 않고 메모로만 남김
  }
  return {
    isMember: true,
    isRegistered: true,
    contactDone: false,
    businessName: d.name || '',
    type,
    subType: '',
    region: parseRegionFromAddress(d.address),
    detailAddress: buildAddressText(d.address, d.detailAddress),
    phone: d.contactPhone || '',
    instagram: '',
    website: d.bookingLink || '',
    contactPersonName: '',
    contactMethod: '',
    firstContactDate: '',
    lastContactDate: '',
    progress: '등록 완료',
    memberUid: d.hostId || '',
    docId: doc.id,
    docCollection: 'places',
    assignee: '',
    memo,
  };
}

// ── 중복 표시 — 업체명/연락처/인스타그램 중 값이 있는 항목이 다른 행과
// 겹치면 표시한다(값이 비어있는 항목끼리는 비교하지 않음 — 빈칸끼리를
// "같다"고 취급하면 사실상 모든 행이 중복으로 잘못 표시되기 때문).
function annotateDuplicates(rows) {
  const buckets = { businessName: new Map(), phone: new Map(), instagram: new Map() };
  const keyOf = (row, field) => {
    const raw = field === 'businessName' ? row.businessName : field === 'phone' ? row.phone : row.instagram;
    const v = String(raw || '').trim();
    return v.length > 0 ? v : null;
  };
  for (const row of rows) {
    for (const field of Object.keys(buckets)) {
      const key = keyOf(row, field);
      if (key == null) continue;
      if (!buckets[field].has(key)) buckets[field].set(key, []);
      buckets[field].get(key).push(row);
    }
  }
  const fieldLabel = { businessName: '업체명', phone: '연락처', instagram: '인스타그램' };
  for (const row of rows) {
    const dupLabels = [];
    for (const field of Object.keys(buckets)) {
      const key = keyOf(row, field);
      if (key == null) continue;
      if (buckets[field].get(key).length > 1) dupLabels.push(fieldLabel[field]);
    }
    row.duplicateFlag = dupLabels.length > 0 ? `중복(${dupLabels.join('/')})` : '';
  }
  return rows;
}

// ── 제외 조건 판정 — 테스트/진단/삭제 데이터 ─────────────────────────────
function isExcludedParty(d) {
  if (d.isTestAccount === true) return true;
  if (d.isDeleted === true) return true;
  if (d.status === 'deleted') return true;
  return false;
}

function isExcludedPlace(d) {
  if (d.isTestAccount === true) return true;
  if (d.isActive === false) return true; // 숨김(30일 유예 후 하드삭제) 상태
  return false;
}

// ── Firestore에서 읽기 전용으로 조회해 CRM 행 배열을 만든다 ──────────────
// db는 호출자가 admin.firestore()로 넘긴다 — 이 파일은 db.collection(...).get()
// 외에 그 어떤 쓰기도 하지 않는다.
async function fetchCrmRows(db) {
  const [partiesSnap, placesSnap] = await Promise.all([
    db.collection('parties').get(),
    db.collection('places').get(),
  ]);

  const rows = [];
  for (const doc of partiesSnap.docs) {
    if (isExcludedParty(doc.data())) continue;
    rows.push(buildRowFromParty(doc));
  }
  for (const doc of placesSnap.docs) {
    if (isExcludedPlace(doc.data())) continue;
    rows.push(buildRowFromPlace(doc));
  }
  annotateDuplicates(rows);

  return {
    rows,
    meta: {
      generatedAt: new Date().toISOString(),
      totalPartiesScanned: partiesSnap.size,
      totalPlacesScanned: placesSnap.size,
      partiesIncluded: rows.filter((r) => r.docCollection === 'parties').length,
      placesIncluded: rows.filter((r) => r.docCollection === 'places').length,
    },
  };
}

// ── 시트 컬럼 정의(순서 그대로) — writer(xlsx/csv)와 admin_app 양쪽이
// 동일한 정의를 참조해 헤더/타입이 어긋나지 않게 한다.
const CRM_COLUMNS = [
  { key: 'isMember', header: 'PartyChu 회원가입 여부', type: 'checkbox' },
  { key: 'isRegistered', header: 'PartyChu 파티/플레이스 등록 여부', type: 'checkbox' },
  { key: 'contactDone', header: '연락 완료 여부', type: 'checkbox' },
  { key: 'businessName', header: '업체명 / 파티명', type: 'text' },
  {
    key: 'type', header: '유형', type: 'dropdown',
    options: ['파티', '숙박', '숙박+파티', '공간대여', '클럽', '펍/주점', '라운지', '루프탑', '풀빌라', '게스트하우스', '기타'],
  },
  { key: 'subType', header: '세부 유형', type: 'text' }, // 복수 선택 값을 콤마로 저장(단일 셀 다중 드롭다운은 XLSX/Sheets 둘 다 미지원)
  { key: 'region', header: '지역', type: 'text' },
  { key: 'detailAddress', header: '상세 주소', type: 'text' },
  { key: 'phone', header: '연락처', type: 'text' },
  { key: 'instagram', header: '인스타그램 주소', type: 'text' },
  { key: 'website', header: '홈페이지 / 예약 링크', type: 'text' },
  { key: 'contactPersonName', header: '담당자명', type: 'text' },
  {
    key: 'contactMethod', header: '연락 방법', type: 'dropdown',
    options: ['전화', '문자', '인스타 DM', '이메일', '카카오톡', '기타'],
  },
  { key: 'firstContactDate', header: '최초 연락일', type: 'date' },
  { key: 'lastContactDate', header: '최근 연락일', type: 'date' },
  {
    key: 'progress', header: '진행 상태', type: 'dropdown',
    options: ['연락 전', '연락 예정', '연락 완료', '답변 대기', '가입 안내 중', '회원가입 완료', '등록 안내 중', '등록 완료', '보류', '거절'],
  },
  { key: 'memberUid', header: 'PartyChu 회원 UID', type: 'text' },
  { key: 'docId', header: 'PartyChu 파티/플레이스 Document ID', type: 'text' },
  { key: 'assignee', header: '담당자', type: 'dropdown', options: ['나', '친구'] },
  { key: 'memo', header: '메모', type: 'text' },
  // 아래는 사용자가 지정한 20개 컬럼 뒤에 추가한 것 — 중복 여부 표시용.
  { key: 'duplicateFlag', header: '중복 여부', type: 'text' },
];

const PROGRESS_COLOR = {
  '등록 완료': 'FFC6EFCE', // 초록
  '답변 대기': 'FFFFEB9C', // 노랑
  '거절': 'FFFFC7CE', // 빨강
  '연락 전': 'FFD9D9D9', // 회색
};

module.exports = {
  fetchCrmRows,
  CRM_COLUMNS,
  PROGRESS_COLOR,
  parseRegionFromAddress,
  mapPartySubType,
  buildRowFromParty,
  buildRowFromPlace,
  isExcludedParty,
  isExcludedPlace,
};
