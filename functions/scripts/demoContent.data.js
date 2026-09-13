// App Store / Play 심사·데모용 샘플 콘텐츠 사전.
//
// demoContentRewrite.js 가 읽는 **유일한 문구 원본**이다. 이름·소개문구·지역을
// 고치고 싶으면 이 파일만 고치면 된다(로직은 건드릴 필요 없다).
//
// ── 원칙 ────────────────────────────────────────────────────────────────
//   · 실제 업체명·제휴처명·실제 사업장 상세주소(층/호수/번지)를 절대 쓰지 않는다.
//   · 이름은 전부 `파티츄 {지역} {유형}` 형태의 **브랜드 기반 가상 상호**다.
//     "(데모)"·"(테스트)" 같은 접미사는 붙이지 않는다 — 대신 상세 설명 하단에
//     [DEMO_NOTICE] 한 줄을 넣어 예시 콘텐츠임을 밝힌다.
//   · 좌표·주소는 **상권 중심**(지하철역 좌표)과 동/도로명까지만 쓴다. 번지가
//     없으므로 어떤 실제 사업장도 가리키지 않는다.
//
// ⚠️ 사업자 인증 원문(businessVerifications / businessOwnership)은 이 사전이
//    다루지 않는다. 그건 국세청 실제 판정이라 위조하지 않는다
//    (scripts/seedReviewAccount.js 상단 주석과 같은 원칙).

'use strict';

/// 상세 설명 하단에 항상 붙는 한 줄. 실제 제휴업체로 오인되는 것을 막는
/// 유일한 장치이므로 **문구를 바꾸더라도 지우지는 말 것**.
const DEMO_NOTICE = '파티츄 서비스 안내를 위한 예시 콘텐츠입니다.';

/// 서울 주요 상권. 배정은 이 배열 순서대로 순환한다.
///
/// lat/lng는 각 상권의 **지하철역 좌표**다 — 공개된 교통 시설이라 특정
/// 사업장을 가리키지 않는다. address/road/dong도 동·도로명까지만 적는다
/// (번지·층·호수 없음).
const REGIONS = [
  {
    key: 'hongdae',
    label: '홍대',
    region: '서울',
    district: '마포구',
    dong: '서교동',
    road: '양화로',
    landmark: '홍대입구역 인근',
    lat: 37.5570,
    lng: 126.9240,
  },
  {
    key: 'gangnam',
    label: '강남',
    region: '서울',
    district: '강남구',
    dong: '역삼동',
    road: '테헤란로',
    landmark: '강남역 인근',
    lat: 37.4979,
    lng: 127.0276,
  },
  {
    key: 'seongsu',
    label: '성수',
    region: '서울',
    district: '성동구',
    dong: '성수동2가',
    road: '아차산로',
    landmark: '성수역 인근',
    lat: 37.5446,
    lng: 127.0559,
  },
  {
    key: 'itaewon',
    label: '이태원',
    region: '서울',
    district: '용산구',
    dong: '이태원동',
    road: '이태원로',
    landmark: '이태원역 인근',
    lat: 37.5345,
    lng: 126.9946,
  },
  {
    key: 'euljiro',
    label: '을지로',
    region: '서울',
    district: '중구',
    dong: '을지로3가',
    road: '을지로',
    landmark: '을지로3가역 인근',
    lat: 37.5662,
    lng: 126.9917,
  },
  {
    key: 'yeonnam',
    label: '연남',
    region: '서울',
    district: '마포구',
    dong: '연남동',
    road: '동교로',
    landmark: '홍대입구역 인근',
    lat: 37.5620,
    lng: 126.9250,
  },
  {
    key: 'sinnonhyeon',
    label: '신논현',
    region: '서울',
    district: '강남구',
    dong: '논현동',
    road: '봉은사로',
    landmark: '신논현역 인근',
    lat: 37.5045,
    lng: 127.0250,
  },
  {
    key: 'jamsil',
    label: '잠실',
    region: '서울',
    district: '송파구',
    dong: '잠실동',
    road: '올림픽로',
    landmark: '잠실역 인근',
    lat: 37.5133,
    lng: 127.1000,
  },
];

/// 도메인별 이름 꼬리. `파티츄 {지역} {꼬리}` 로 조합된다.
///
/// ⚠️ `place`는 **플레이스(events 컬렉션)**, `rental`은 **장소대여(places
///    컬렉션)**다. 이 프로젝트는 UI 이름과 컬렉션 이름이 뒤집혀 있다.
const NAME_SUFFIXES = {
  party: [
    '소셜 나이트',
    '라이브',
    '미트업',
    '루프탑 파티',
    '와인 나이트',
    '보드게임 나이트',
    '살롱 파티',
    '네트워킹 나이트',
  ],
  place: ['플레이스', '라운지', '바', '카페', '다이닝', '비스트로'],
  rental: ['파티룸', '루프탑', '스튜디오', '하우스', '로프트', '라운지룸'],
  event: [
    '웰컴 드링크',
    '해피아워',
    '단체 이용 혜택',
    '시그니처 코스',
    '평일 타임 혜택',
  ],
};

/// 슬러그별 이름 강제 지정 — 순환 규칙(buildName)으로는 나올 수 없는 이름을
/// 박아 넣는다. 지금은 플레이스 하나뿐이다.
///
/// place-01은 문서의 `themeTags`가 `["혼술바","이벤트"]`라 앱이 혼술바로
/// 분류한다. 이름이 "플레이스"면 카드 분류와 이름이 어긋나므로 맞춘다.
const NAME_OVERRIDES = {
  'place-01': '파티츄 홍대 혼술바',
};

/// 파티 유형·분위기 — 슬러그별로 새 제목·콘텐츠에 맞춰 다시 정한다.
///
/// ⚠️ 값은 **앱의 허용 목록에 있는 문자열 그대로**여야 한다
///    (party_app/lib/models/party_constants.dart의 partyTypes / vibes).
///    저장값이 곧 검색 키라, 한 글자라도 다르면 그 파티가 필터에서 사라진다.
///
/// ⚠️ `🎉 대규모` · `🏠 소규모` · `🔥 신나는` 은 **은퇴한 분위기**다
///    (PartyConstants.retiredVibes). 기존 문서가 들고 있었지만 새로 고를 수
///    없는 값이라, 여기서는 현행 값으로만 채운다.
///
/// 유형+분위기 합계는 8개를 넘지 않는다(PartyConstants.maxTypeVibes).
const PARTY_TYPE_VIBES = {
  // 홍대 지하 라운지 바, 40명 규모 소셜 파티
  'party-01': { types: ['라운지 파티', '칵테일 파티', '펍 파티'], vibes: ['🍺 술 중심', '🏡 실내'] },
  // 강남 소규모 라이브하우스, 밴드 공연
  'party-02': { types: ['라이브 파티', '공연 파티'], vibes: ['🎵 음악 중심', '🏡 실내'] },
  // 성수 카페바에서의 소규모 미트업
  'party-03': { types: ['라운지 파티', '와인 파티'], vibes: ['🍺 술 중심', '🏡 실내'] },
  // 이태원 옥상, 야경 루프탑 파티
  'party-04': { types: ['루프탑 파티', '칵테일 파티'], vibes: ['🌅 야외', '🍺 술 중심'] },
  // 을지로 개조 와인바
  'party-05': { types: ['와인 파티', '라운지 파티'], vibes: ['🍺 술 중심', '🏡 실내'] },
  // 연남 보드게임 카페 — '보드게임' 유형 자체가 앱 목록에 없어 가장 가까운 둘을 쓴다
  'party-06': { types: ['펍 파티', '맥주 파티'], vibes: ['🏡 실내', '🍺 술 중심'] },
  // 신논현 살롱형 라운지 바, 60명 규모
  'party-07': { types: ['라운지 파티', '칵테일 파티', '프라이빗 파티'], vibes: ['✨ 프리미엄', '🏡 실내'] },
  // 잠실 고층 실내 라운지, 스탠딩 네트워킹
  'party-08': { types: ['라운지 파티', '프라이빗 파티'], vibes: ['🏡 실내', '✨ 프리미엄'] },
};

/// 룸(placeRooms) 이름 — 부모 장소대여 이름 뒤에 붙는 것이 아니라 독립적으로
/// 쓰인다(앱이 룸 이름만 단독으로 보여주는 화면이 있다).
const ROOM_NAMES = [
  '메인 홀',
  '루프탑 룸',
  '프라이빗 룸',
  '라운지 룸',
  '스튜디오 룸',
  '테라스 룸',
];

/// 파티 태그 — 전부 일반 명사다(상호·브랜드가 섞이지 않는다).
const PARTY_TAGS = ['소셜', '네트워킹', '와인', '보드게임', '루프탑', '음악'];

/// 이벤트(placePromotions) 태그 — 앱의 프리셋(kPromotionTagPresets)에서만 고른다.
const PROMOTION_TAGS = ['오늘 혼술 환영', '직장인 할인', '단체 환영', '커플 할인'];

// ── 본문 생성기 ────────────────────────────────────────────────────────────
//
// 전부 [DEMO_NOTICE]로 끝난다. 호출측이 따로 붙이지 않는다.

function withNotice(body) {
  return `${body.trim()}\n\n${DEMO_NOTICE}`;
}

/// 파티 소개글.
function partyDescription({ name, region }) {
  return withNotice(
    `${region.landmark}에서 열리는 ${name}입니다.\n` +
      '처음 오시는 분도 편하게 어울릴 수 있도록 호스트가 자리를 안내하고, ' +
      '가벼운 아이스브레이킹으로 시작합니다.\n' +
      '음료 한 잔과 간단한 안주가 준비되어 있고, 중간중간 자유롭게 자리를 ' +
      '옮기며 이야기 나눌 수 있어요.\n' +
      '혼자 오셔도 괜찮습니다 — 파티츄가 처음 오신 분들을 먼저 챙깁니다.',
  );
}

/// 플레이스(events) 소개글.
function placeDescription({ name, region }) {
  return withNotice(
    `${region.landmark}에 있는 ${name}입니다.\n` +
      '편안한 조명과 좌석 배치로 소규모 모임부터 단체 모임까지 두루 어울리는 ' +
      '공간을 보여드리기 위해 만든 예시입니다.\n' +
      '시그니처 음료와 안주, 좌석별 이용 안내를 앱에서 미리 확인하고 방문할 수 ' +
      '있습니다.',
  );
}

/// 장소대여(places) 소개글.
function rentalDescription({ name, region }) {
  return withNotice(
    `${region.landmark}의 ${name}입니다.\n` +
      '생일 파티, 모임, 워크숍처럼 시간 단위로 공간을 빌려 쓰는 흐름을 ' +
      '보여드리기 위한 예시 공간입니다.\n' +
      '음향·빔프로젝터·냉난방 등 기본 시설이 준비되어 있고, 예약 시간과 ' +
      '인원에 맞춰 좌석을 배치할 수 있습니다.',
  );
}

/// 이벤트(placePromotions) 소개글.
function promotionDescription({ title, region }) {
  return withNotice(
    `${region.landmark} 파티츄 예시 공간에서 진행하는 ${title} 안내입니다.\n` +
      '앱에서 이벤트를 확인하고 방문하면 안내된 혜택을 받는 흐름을 그대로 ' +
      '보여드립니다.',
  );
}

/// 룸(placeRooms) 소개글 — 짧게 유지한다(룸 카드가 2~3줄만 보여준다).
function roomDescription({ roomName, region }) {
  return withNotice(
    `${region.landmark} 파티츄 예시 공간의 ${roomName}입니다. ` +
      '기본 음향과 조명이 준비되어 있고 좌석은 인원에 맞춰 조정할 수 있습니다.',
  );
}

/// 메뉴(placeMenus) 설명 — 한 줄.
function menuDescription() {
  return `파티츄 예시 메뉴입니다. ${DEMO_NOTICE}`;
}

/// 상품·이용권(placeProducts) 설명.
function productDescription({ name }) {
  return withNotice(
    `${name} 구매·사용 흐름을 보여드리기 위한 예시 상품입니다.\n` +
      '앱에서 결제하고 현장에서 QR로 사용하는 과정을 그대로 확인할 수 있습니다.',
  );
}

/// 파티츄 전용 혜택(partychuPerk) 문구.
const PARTYCHU_PERK = '파티츄에서 예약하면 웰컴 드링크 1잔을 드립니다. (예시 혜택)';

/// 메뉴 이름 풀.
const MENU_NAMES = [
  '파티츄 시그니처 하이볼',
  '파티츄 하우스 와인',
  '파티츄 치즈 플래터',
  '파티츄 감자튀김',
  '파티츄 수제 맥주',
  '파티츄 안주 모둠',
];

/// 상품·이용권 이름 풀.
const PRODUCT_NAMES = [
  '파티츄 웰컴 세트',
  '파티츄 단체 이용권',
  '파티츄 2인 코스',
  '파티츄 프리미엄 패키지',
];

/// 룸 옵션 이름 풀 — 실제 옵션명이 상호를 담고 있을 때만 이 값으로 바꾼다.
const ROOM_OPTION_NAMES = ['추가 인원', '음향 장비', '빔프로젝터', '케이터링'];

// ── 상세페이지 블록(detailBlocks) 데모 문구 ────────────────────────────────
//
// 블록의 **구조(id·type·순서·크롭값)는 그대로 두고 글자만** 바꾼다. 원문에
// 실제 상호가 섞여 있을 수 있어 "일부만 치환"이 아니라 통째로 다시 쓴다.

const BLOCK_TEXT = {
  heading: ['오늘의 파티츄', '이렇게 진행돼요', '함께 즐겨요'],
  subheading: ['처음 오셔도 괜찮아요', '준비된 것들', '이용 안내'],
  paragraph: [
    '파티츄가 서비스 흐름을 보여드리기 위해 만든 예시 콘텐츠입니다. 실제 ' +
      '상세페이지에서는 호스트가 직접 작성한 소개가 이 자리에 들어갑니다.',
    '호스트가 자리를 안내하고 가벼운 인사로 시작합니다. 중간중간 자유롭게 ' +
      '이동하며 이야기 나눌 수 있어요.',
  ],
  notice: [
    '이 페이지는 파티츄 서비스 안내를 위한 예시 콘텐츠입니다.',
    '예시 콘텐츠이므로 실제 예약·방문이 이뤄지지 않습니다.',
  ],
};

const BLOCK_CHECKLIST = {
  title: '준비물',
  items: ['신분증', '편한 복장', '가벼운 마음'],
};

const BLOCK_FAQ = {
  title: '자주 묻는 질문',
  items: [
    { question: '혼자 가도 괜찮나요?', answer: '네, 대부분 혼자 오십니다. 호스트가 먼저 안내해 드려요.' },
    { question: '늦게 도착해도 되나요?', answer: '가능합니다. 도착 전에 채팅으로 알려주시면 자리를 안내해 드려요.' },
  ],
};

const BLOCK_TIMELINE = {
  title: '진행 순서',
  items: [
    { time: '19:00', title: '입장 및 인사', description: '자리를 안내받고 가볍게 인사합니다.' },
    { time: '19:30', title: '아이스브레이킹', description: '짧은 소개로 어색함을 풉니다.' },
    { time: '20:30', title: '자유 시간', description: '자유롭게 이동하며 이야기 나눕니다.' },
  ],
};

const BLOCK_INFO_CARD = {
  title: '이용 안내',
  text: `파티츄 예시 콘텐츠입니다. 실제 이용 안내가 이 자리에 들어갑니다. ${DEMO_NOTICE}`,
};

const BLOCK_IMAGE_CAPTION = '파티츄 예시 이미지';

// ── 조합 헬퍼 ──────────────────────────────────────────────────────────────

/// `파티츄 {지역} {꼬리}` — index로 지역과 꼬리를 함께 순환시킨다. 같은 지역에
/// 같은 꼬리가 두 번 나오지 않도록 꼬리 회전을 지역 한 바퀴마다 한 칸 민다.
function buildName(domain, index, slug) {
  const region = REGIONS[index % REGIONS.length];
  return buildNameAt(domain, index, region, slug);
}

/// 지역을 **바깥에서 정해 주는** 조합. 이벤트(placePromotions)처럼 지역이
/// 순번이 아니라 **부모 장소**를 따라가야 하는 경우에 쓴다 — 이벤트 사진은
/// 곧 부모 매장 사진이라, 제목의 지역이 부모와 다르면 어느 쪽으로 만들어도
/// 틀린 사진이 된다.
function buildNameAt(domain, index, region, slug) {
  const suffixes = NAME_SUFFIXES[domain];
  if (!suffixes) throw new Error(`알 수 없는 도메인: ${domain}`);
  const lap = Math.floor(index / REGIONS.length);
  const suffix = suffixes[(index + lap) % suffixes.length];
  const name = (slug && NAME_OVERRIDES[slug]) || `파티츄 ${region.label} ${suffix}`;
  return { name, region };
}

/// 위치 관련 필드를 **한 덩어리로** 만든다. 개별 필드를 따로 계산하면
/// address와 lat/lng가 어긋난다.
///
/// 컬렉션마다 키 이름이 다르므로(장소대여는 lat/lng, 나머지는 latitude/
/// longitude) 원자재만 돌려주고 조립은 호출측이 한다.
function locationParts(region) {
  const address = `${region.region} ${region.district} ${region.dong}`;
  const roadAddress = `${region.region} ${region.district} ${region.road}`;
  return {
    address,
    roadAddress,
    jibunAddress: address,
    detailAddress: region.landmark,
    location: `${address} ${region.landmark}`,
    latitude: region.lat,
    longitude: region.lng,
    region: region.region,
    district: region.district,
  };
}

module.exports = {
  DEMO_NOTICE,
  REGIONS,
  NAME_SUFFIXES,
  NAME_OVERRIDES,
  PARTY_TYPE_VIBES,
  ROOM_NAMES,
  PARTY_TAGS,
  PROMOTION_TAGS,
  PARTYCHU_PERK,
  MENU_NAMES,
  PRODUCT_NAMES,
  ROOM_OPTION_NAMES,
  BLOCK_TEXT,
  BLOCK_CHECKLIST,
  BLOCK_FAQ,
  BLOCK_TIMELINE,
  BLOCK_INFO_CARD,
  BLOCK_IMAGE_CAPTION,
  withNotice,
  partyDescription,
  placeDescription,
  rentalDescription,
  promotionDescription,
  roomDescription,
  menuDescription,
  productDescription,
  buildName,
  buildNameAt,
  locationParts,
};
