// 파티 등록 공용 조립(partyRegistration.js) 셀프체크.
//
//   node partyRegistration.selfcheck.js            — 검증
//   node partyRegistration.selfcheck.js --write    — 픽스처 다시 만들기
//
// ── 이 파일이 지키는 것 ────────────────────────────────────────────────────
//
// 1. **회귀 잠금** — fixtures/party_registration_cases.json에 적힌 기대값과
//    지금 모듈의 출력이 같은지 본다. 조립 규칙을 건드리면 여기가 먼저 깨진다.
//
// 2. **앱과의 파리티** — 같은 픽스처 파일을
//    party_app/test/party_registration_parity_test.dart가 읽어서, Dart 모델
//    (PartyRegistrationData / PartyPricing / PartyEarlyBird / PartySchedule /
//    PartyRound / PartyRoundPackage)이 **같은 값**을 내는지 확인한다.
//    한쪽만 고치면 반대쪽 검증이 깨지므로 드리프트가 조용히 지나가지 않는다.
//
// 픽스처의 기대값은 이 모듈이 만들어 넣지만, 그게 옳은지 판정하는 것은
// Dart 테스트다. 두 검증이 모두 초록일 때만 "앱과 같다"고 말할 수 있다.
//
// ⚠️ --write로 픽스처를 다시 만들었으면 **반드시 Dart 테스트도 돌려서**
//    앱이 같은 값을 내는지 확인해야 한다. 안 그러면 이 파일은 자기 자신을
//    증명하는 셈이 된다.
//
// ── 픽스처가 다루지 않는 것 ────────────────────────────────────────────────
//
// 문서 전체 조립(buildPartyDocuments — 슬롯 팬아웃, 공유 필드, 차수 합계)은
// 앱 쪽 대응 코드가 party_register_screen.dart의 로컬 클로저라 테스트에서
// 부를 수 없다. 그래서 이 층은 JS 셀프체크만 덮는다. 앱 등록 화면이
// createParty로 옮겨오면 그 간극이 사라진다
// (docs/party-registration-parity.md 참고).

const fs = require('fs');
const path = require('path');
const assert = require('assert');

const R = require('./partyRegistration');

const FIXTURE_PATH = path.join(__dirname, 'fixtures', 'party_registration_cases.json');
const WRITE = process.argv.includes('--write');

// 모든 케이스가 공유하는 "지금" — 픽스처가 시간에 흔들리지 않도록 고정한다.
// 2026-08-22 12:00 KST.
const NOW = new Date('2026-08-22T03:00:00.000Z');

let passed = 0;
const failures = [];

function check(name, fn) {
  try {
    fn();
    passed += 1;
  } catch (e) {
    failures.push(`${name}\n    ${e.message.split('\n').join('\n    ')}`);
  }
}

// ── 직렬화 ────────────────────────────────────────────────────────────────
// Date는 ISO 문자열로 바꿔 JSON에 담는다. undefined는 아예 키를 지우고,
// null은 **그대로 남긴다** — "반대쪽 방식은 명시적으로 null"이라는 규칙이
// 문서 모양의 일부이기 때문이다.
function encode(value) {
  if (value === null) return null;
  if (value instanceof Date) return { __date: value.toISOString() };
  if (Array.isArray(value)) return value.map(encode);
  if (value && typeof value === 'object') {
    const out = {};
    for (const key of Object.keys(value)) {
      if (value[key] === undefined) continue;
      out[key] = encode(value[key]);
    }
    return out;
  }
  return value;
}

// ═══════════════════════════════════════════════════════════════════════════
// 케이스 입력 — 여기에 적힌 입력만 픽스처가 된다.
// ═══════════════════════════════════════════════════════════════════════════

const PRICING_CASES = [
  { name: '무료', input: { male: 0, female: 0 } },
  { name: '음수는 0으로 자른다', input: { male: -5000, female: 0 } },
  { name: '남녀 같은 금액 → same', input: { male: 30000, female: 30000 } },
  { name: 'type:same 직접 지정', input: { type: 'same', price: 25000 } },
  { name: '남녀 다른 금액 → gendered', input: { male: 35000, female: 25000 } },
  { name: '한쪽만 유료 — 대표가는 0보다 큰 쪽', input: { male: 35000, female: 0 } },
  { name: 'type:free는 금액을 무시한다', input: { type: 'free', male: 30000 } },
];

const RECRUIT_RULE_CASES = [
  { name: '기본(시작 60분 전)', input: {} },
  { name: '시작 90분 전 — hours는 내림', input: { mode: 'beforeStart', minutes: 90 } },
  { name: '옛 문서: hours만 있음', input: { mode: 'beforeStart', hours: 2 } },
  { name: '시작일 지정 시각', input: { mode: 'startDayTime', time: '18:00' } },
  { name: '전날 지정 시각', input: { mode: 'prevDayTime', time: '21:30' } },
  {
    name: '직접 지정',
    input: { mode: 'customDateTime', atMs: Date.UTC(2026, 8, 4, 9, 0) },
  },
  { name: '제한 없음', input: { mode: 'none' } },
  { name: '옛 키 hoursBefore → beforeStart', input: { mode: 'hoursBefore', hours: 3 } },
  { name: '옛 키 sameDayTime → startDayTime', input: { mode: 'sameDayTime', time: '20:00' } },
];

const EARLY_BIRD_CASES = [
  { name: '꺼짐', input: { enabled: false }, isRecurring: false },
  {
    name: '고정 종료 시각',
    input: {
      enabled: true,
      percent: 10,
      endType: 'fixedDate',
      endAt: { date: '2026-09-01', time: '23:59' },
    },
    isRecurring: false,
  },
  {
    name: '고정 종료 시각인데 시각이 없으면 꺼진 것으로 저장된다',
    input: { enabled: true, percent: 10, endType: 'fixedDate' },
    isRecurring: false,
  },
  {
    name: '시작 N일 전',
    input: {
      enabled: true,
      percent: 15,
      endType: 'beforeStart',
      beforeStartRule: { mode: 'daysBefore', days: 3, time: '23:59' },
    },
    isRecurring: false,
  },
  {
    name: '시작 N시간 전 — time은 저장하지 않는다',
    input: {
      enabled: true,
      percent: 20,
      endType: 'beforeStart',
      beforeStartRule: { mode: 'hoursBefore', hours: 24 },
    },
    isRecurring: false,
  },
  {
    name: '정기 파티는 고정 시각을 골라도 규칙으로 저장된다',
    input: {
      enabled: true,
      percent: 10,
      endType: 'fixedDate',
      endAt: { date: '2026-09-01', time: '23:59' },
      beforeStartRule: { mode: 'sameDayTime', time: '18:00' },
    },
    isRecurring: true,
  },
];

const SINGLE_SCHEDULE_CASES = [
  {
    name: '일회성 — 시작일 18:00 마감',
    slot: { date: '2026-09-05', startTime: '20:00', endTime: '23:00' },
    deadlineRule: { mode: 'startDayTime', time: '18:00' },
    openRule: { mode: 'none' },
  },
  {
    name: '자정을 넘기는 파티 — 종료가 다음 날',
    slot: { date: '2026-09-05', startTime: '21:00', endTime: '02:00' },
    deadlineRule: { mode: 'beforeStart', minutes: 60 },
    openRule: { mode: 'prevDayTime', time: '10:00' },
  },
  {
    name: '마감 제한 없음',
    slot: { date: '2026-09-05', startTime: '19:00', endTime: null },
    deadlineRule: { mode: 'none' },
    openRule: { mode: 'none' },
  },
];

const RECURRING_CASES = [
  {
    name: '매주 금·토 20:00~23:00',
    input: {
      startDate: '2026-09-01',
      endDate: '2026-12-31',
      weekly: {
        friday: { enabled: true, startTime: '20:00', endTime: '23:00' },
        saturday: { enabled: true, startTime: '20:00', endTime: '23:00' },
      },
      deadlineRule: { mode: 'startDayTime', time: '18:00' },
      openRule: { mode: 'none' },
    },
  },
  {
    name: '종료일 없음 + 자정 넘김',
    input: {
      startDate: '2026-09-01',
      endDate: null,
      weekly: {
        wednesday: { enabled: true, startTime: '21:00', endTime: '01:00' },
      },
      deadlineRule: { mode: 'beforeStart', minutes: 120 },
      openRule: { mode: 'prevDayTime', time: '09:00' },
    },
  },
];

const ROUND_CASES = [
  {
    name: '통합 정원 — 정원·참가비를 저장하지 않는다',
    isoDate: '2026-09-05',
    roundNumber: 2,
    perRound: false,
    input: {
      id: 'round_x',
      label: '',
      startTime: '22:00',
      endTime: '23:30',
      openRule: { mode: 'none' },
      closeRule: { mode: 'beforeStart', minutes: 30 },
    },
  },
  {
    name: '차수별 정원 — 남녀 분리 합계가 최대',
    isoDate: '2026-09-05',
    roundNumber: 2,
    perRound: true,
    input: {
      id: 'round_y',
      label: '2부',
      startTime: '22:00',
      endTime: '01:00',
      openRule: { mode: 'prevDayTime', time: '12:00' },
      closeRule: { mode: 'startDayTime', time: '21:00' },
      minCapacity: 4,
      maxCapacity: 0,
      maleCapacity: 6,
      femaleCapacity: 6,
      maleFee: 20000,
      femaleFee: 15000,
      earlyBird: {
        enabled: true,
        percent: 10,
        endType: 'beforeStart',
        beforeStartRule: { mode: 'hoursBefore', hours: 6 },
      },
    },
  },
];

const ROUND_PACKAGE_CASES = [
  {
    name: '이름 없이 — 1+2차 패키지',
    firstRoundStart: '2026-09-05T11:00:00.000Z', // 20:00 KST
    input: {
      id: 'pkg_a',
      // 중복 없는 입력만 둔다 — 중복이 섞이면 앱과 값이 갈린다(패키지 기본
      // 이름이 원본 목록을 쓰기 때문). docs/party-registration-parity.md 참고.
      roundNumbers: [2, 1],
      roundIds: ['round_1', 'round_y'],
      maleFee: 35000,
      femaleFee: 28000,
      earlyBirdEnabled: true,
      earlyBirdMaleFee: 30000,
      earlyBirdFemaleFee: 24000,
      earlyBirdDeadlineRule: { mode: 'daysBefore', days: 3, time: '23:59' },
    },
  },
  {
    name: '얼리버드 꺼짐 — 금액과 규칙이 비워진다',
    firstRoundStart: '2026-09-05T11:00:00.000Z',
    input: {
      id: 'pkg_b',
      name: '풀패키지',
      roundNumbers: [1, 2],
      maleFee: 40000,
      femaleFee: 32000,
      earlyBirdEnabled: false,
      earlyBirdMaleFee: 30000,
      earlyBirdFemaleFee: 24000,
    },
  },
];

/// PartyRegistrationData.toFirestore()에 대응하는 케이스 — 앱과 맞대볼 수 있는
/// 가장 넓은 면이다.
const REGISTRATION_DATA_CASES = [
  {
    name: '일회성 · 통합 정원 · 남녀 다른 참가비 · 고정 얼리버드',
    input: {
      title: '금요일 루프탑 파티',
      description: '한강뷰 루프탑에서 여는 파티예요.',
      capacity: {
        genderLimit: 'all',
        genderCapacityMode: 'unlimited',
        maxCapacity: 30,
        minCapacity: 10,
        minCapacityPolicy: 'autoCancel',
      },
      pricing: { male: 35000, female: 25000 },
      earlyBird: {
        enabled: true,
        percent: 10,
        endType: 'fixedDate',
        endAt: { date: '2026-09-01', time: '23:59' },
      },
      refundTiers: [
        { daysBefore: 7, refundPercent: 100 },
        { daysBefore: 3, refundPercent: 50 },
      ],
      paymentPolicy: { paymentMode: 'partial', upfrontType: 'percentage', upfrontPercent: 30 },
      age: {
        enabled: true,
        male: { enabled: true, minBirthYear: 1995, maxBirthYear: 2003 },
        female: { enabled: true, minBirthYear: 1995, maxBirthYear: 2003 },
      },
      taxonomy: {
        partyTypes: ['루프탑 파티', '와인 파티'],
        vibes: ['🔥 신나는'],
        tags: ['한강뷰', '루프탑'],
      },
      schedule: {
        type: 'single',
        slots: [{ date: '2026-09-05', startTime: '20:00', endTime: '23:00' }],
        deadlineRule: { mode: 'startDayTime', time: '18:00' },
        // 모집 **시작** 규칙도 실제 값으로 둔다 — 'none'만 쓰면
        // recruitOpenRule/recruitOpenAt이 늘 비어 있어, 그 두 필드가 저장되는지
        // 이 케이스가 확인하지 못한다(예전에 콤보 등록이 조용히 규칙을 잃던
        // 자리다 — docs/party-registration-parity.md).
        openRule: { mode: 'prevDayTime', time: '10:00' },
      },
    },
  },
  {
    name: '무료 파티 — 결제 방식과 얼리버드가 저장되지 않는다',
    input: {
      title: '무료 보드게임 모임',
      description: '',
      capacity: {
        genderLimit: 'all',
        genderCapacityMode: 'separate',
        maleCapacity: 8,
        femaleCapacity: 8,
        minCapacity: 0,
        minCapacityPolicy: 'autoCancel',
      },
      pricing: { male: 0, female: 0 },
      earlyBird: { enabled: true, percent: 10, endType: 'beforeStart' },
      refundTiers: [{ daysBefore: 1, refundPercent: 100 }],
      paymentPolicy: { paymentMode: 'prepaid' },
      age: { enabled: false },
      taxonomy: { partyTypes: [], vibes: [], tags: [] },
      schedule: {
        type: 'single',
        slots: [{ date: '2026-09-12', startTime: '14:00', endTime: '18:00' }],
        deadlineRule: { mode: 'none' },
        openRule: { mode: 'none' },
      },
    },
  },
  {
    name: '정기 파티 — 얼리버드가 규칙으로, 마감은 null로 저장된다',
    input: {
      title: '매주 수요일 와인 클래스',
      description: '소믈리에와 함께하는 와인 모임.',
      capacity: {
        genderLimit: 'all',
        genderCapacityMode: 'unlimited',
        maxCapacity: 16,
        minCapacity: 6,
        minCapacityPolicy: 'autoCancel',
      },
      pricing: { male: 40000, female: 40000 },
      earlyBird: {
        enabled: true,
        percent: 15,
        endType: 'beforeStart',
        beforeStartRule: { mode: 'daysBefore', days: 2, time: '23:59' },
      },
      refundTiers: [{ daysBefore: 3, refundPercent: 100 }],
      paymentPolicy: null,
      age: { enabled: false },
      taxonomy: { partyTypes: ['와인 파티'], vibes: ['✨ 프리미엄'], tags: [] },
      schedule: {
        type: 'recurring',
        // ⚠️ 운영 기간을 **아주 먼 미래**로 둔다.
        //
        // PartyRegistrationData.toFirestore()는 now를 받지 않아 정기 파티의
        // buildRecurringFields를 DateTime.now()로 부른다. 그래서 이 케이스만은
        // 기대값이 "테스트를 돌리는 날"에 흔들린다 — 운영 기간이 지나면 다음
        // 회차가 달라지거나 아예 없어져 어느 날 갑자기 빨개진다.
        //
        // 시작일이 지금보다 한참 뒤면 nextOccurrence가 "지금"이 아니라
        // 운영 시작일부터 훑으므로 결과가 항상 같은 첫 회차(2099-01-07 수)가
        // 된다. 앱·서버 모두 같은 규칙이라 양쪽에서 똑같이 고정된다.
        recurring: {
          startDate: '2099-01-01',
          endDate: '2099-12-31',
          weekly: {
            wednesday: { enabled: true, startTime: '19:30', endTime: '22:00' },
          },
          deadlineRule: { mode: 'startDayTime', time: '18:00' },
          openRule: { mode: 'prevDayTime', time: '09:00' },
        },
      },
    },
  },
  // ── 성별별 연령 제한 ───────────────────────────────────────────────────
  //
  // 아래 네 케이스가 이 기능의 저장 규칙 전부다. 출생연도는 "지금 몇 년인지"에
  // 흔들리지 않도록 **절대값**으로 둔다(2026년 기준 남 25~35 / 여 23~32).
  {
    name: '연령 제한 · 남녀 서로 다른 범위',
    input: {
      title: '남녀 연령 다른 파티',
      description: '',
      capacity: {
        genderLimit: 'all',
        genderCapacityMode: 'unlimited',
        maxCapacity: 20,
        minCapacity: 0,
        minCapacityPolicy: 'proceed',
      },
      pricing: { male: 30000, female: 20000 },
      earlyBird: { enabled: false },
      refundTiers: [{ daysBefore: 1, refundPercent: 100 }],
      paymentPolicy: null,
      age: {
        enabled: true,
        male: { enabled: true, minBirthYear: 1991, maxBirthYear: 2001 },
        female: { enabled: true, minBirthYear: 1994, maxBirthYear: 2003 },
      },
      taxonomy: { partyTypes: [], vibes: [], tags: [] },
      schedule: {
        type: 'single',
        slots: [{ date: '2026-10-02', startTime: '19:00', endTime: '23:00' }],
        deadlineRule: { mode: 'none' },
        openRule: { mode: 'none' },
      },
    },
  },
  {
    name: '연령 제한 · 남성만 제한(여성 제한 없음) — 공통 필드는 만들지 않는다',
    input: {
      title: '남성만 연령 제한',
      description: '',
      capacity: {
        genderLimit: 'all',
        genderCapacityMode: 'unlimited',
        maxCapacity: 20,
        minCapacity: 0,
        minCapacityPolicy: 'proceed',
      },
      pricing: { male: 0, female: 0 },
      earlyBird: { enabled: false },
      refundTiers: [{ daysBefore: 1, refundPercent: 100 }],
      paymentPolicy: null,
      age: {
        enabled: true,
        male: { enabled: true, minBirthYear: 1991, maxBirthYear: 2001 },
        // 껐지만 값은 남아 있다 — 저장되면 안 된다.
        female: { enabled: false, minBirthYear: 1994, maxBirthYear: 2003 },
      },
      taxonomy: { partyTypes: [], vibes: [], tags: [] },
      schedule: {
        type: 'single',
        slots: [{ date: '2026-10-03', startTime: '19:00', endTime: '23:00' }],
        deadlineRule: { mode: 'none' },
        openRule: { mode: 'none' },
      },
    },
  },
  {
    name: '연령 제한 · 여성만 모집 — 모집하지 않는 성별(남성)의 제한은 지워진다',
    input: {
      title: '여성만 모집 파티',
      description: '',
      capacity: {
        genderLimit: 'female',
        genderCapacityMode: 'separate',
        maleCapacity: 10,
        femaleCapacity: 12,
        minCapacity: 0,
        minCapacityPolicy: 'proceed',
      },
      pricing: { male: 0, female: 20000 },
      earlyBird: { enabled: false },
      refundTiers: [{ daysBefore: 1, refundPercent: 100 }],
      paymentPolicy: null,
      age: {
        enabled: true,
        // 남성 값은 예전에 골라 둔 유령 값 — 저장되면 안 된다.
        male: { enabled: true, minBirthYear: 1991, maxBirthYear: 2001 },
        female: { enabled: true, minBirthYear: 1994, maxBirthYear: 2003 },
      },
      taxonomy: { partyTypes: [], vibes: [], tags: [] },
      schedule: {
        type: 'single',
        slots: [{ date: '2026-10-04', startTime: '19:00', endTime: '23:00' }],
        deadlineRule: { mode: 'none' },
        openRule: { mode: 'none' },
      },
    },
  },
  {
    name: '연령 제한 · 옛 공통 스키마 입력 — 남녀 모두에게 같은 값으로 저장된다',
    input: {
      title: '옛 스키마로 들어온 파티',
      description: '',
      capacity: {
        genderLimit: 'all',
        genderCapacityMode: 'unlimited',
        maxCapacity: 20,
        minCapacity: 0,
        minCapacityPolicy: 'proceed',
      },
      pricing: { male: 0, female: 0 },
      earlyBird: { enabled: false },
      refundTiers: [{ daysBefore: 1, refundPercent: 100 }],
      paymentPolicy: null,
      // 성별 블록이 없다 = 갱신되지 않은 호출자(옛 웹 폼 등).
      age: { enabled: true, minBirthYear: 1990, maxBirthYear: 2000 },
      taxonomy: { partyTypes: [], vibes: [], tags: [] },
      schedule: {
        type: 'single',
        slots: [{ date: '2026-10-05', startTime: '19:00', endTime: '23:00' }],
        deadlineRule: { mode: 'none' },
        openRule: { mode: 'none' },
      },
    },
  },
  // ── 참가자 성비 공개 ───────────────────────────────────────────────────
  //
  // 위 케이스들은 이 값을 보내지 않아 **기본값(공개)** 경로를 덮는다.
  // 여기 하나가 명시적으로 끈 경로를 덮는다 — 둘이 함께 있어야 "안 보내면
  // 공개 / false면 비공개"라는 계약 전체가 잠긴다.
  {
    name: '참가자 성비 비공개 — 호스트가 끈 값이 그대로 저장된다',
    input: {
      title: '성비 비공개 파티',
      description: '',
      capacity: {
        genderLimit: 'all',
        genderCapacityMode: 'separate',
        maleCapacity: 10,
        femaleCapacity: 10,
        minCapacity: 0,
        minCapacityPolicy: 'proceed',
        // 감추는 것은 "지금 참가한 사람들의 남/여 인원"뿐이다 — 위 모집
        // 정원(남 10 / 여 10)은 그대로 저장되고 그대로 보인다.
        revealParticipantGenderRatio: false,
      },
      pricing: { male: 30000, female: 30000 },
      earlyBird: { enabled: false },
      refundTiers: [{ daysBefore: 1, refundPercent: 100 }],
      paymentPolicy: null,
      age: { enabled: false },
      taxonomy: { partyTypes: [], vibes: [], tags: [] },
      schedule: {
        type: 'single',
        slots: [{ date: '2026-10-12', startTime: '19:00', endTime: '23:00' }],
        deadlineRule: { mode: 'none' },
        openRule: { mode: 'none' },
      },
    },
  },
];

// ═══════════════════════════════════════════════════════════════════════════
// 픽스처 생성
// ═══════════════════════════════════════════════════════════════════════════

/// PartyRegistrationData.toFirestore()에 해당하는 부분만 뽑는다 — 앱의
/// 그 메서드가 만드는 필드와 정확히 같은 집합이어야 비교가 성립한다.
const REGISTRATION_DATA_KEYS = [
  // 일정 유형
  'scheduleType', 'singleSchedule', 'recurringSchedule',
  'recruitDeadlineRule', 'recruitOpenRule',
  'partyDateTime', 'recruitDeadlineAt', 'recruitOpenAt',
  // 성별 / 정원
  'people', 'genderLimit', 'genderCapacityMode', 'genderMode',
  'maleCapacity', 'femaleCapacity', 'currentMaleCount', 'currentFemaleCount',
  'revealParticipantGenderRatio',
  'partyMinCapacity', 'minCapacity', 'maxCapacity', 'minCapacityPolicy',
  'maxParticipants', 'currentParticipants',
  // 금액
  'pricingType', 'price', 'malePrice', 'femalePrice', 'maleFee', 'femaleFee',
  'earlyBirdEnabled', 'earlyBirdDiscountPercent', 'earlyBirdEndType',
  'earlyBirdEndAt', 'earlyBirdDeadlineRule', 'refundPolicy',
  'paymentMode', 'upfrontType', 'upfrontPercent', 'upfrontFixedAmount',
  // 조건 / 분류
  // 연령 제한 — 성별별 필드가 정본이고, 옛 공통 필드는 구버전 앱용이다.
  'ageRestrictionEnabled',
  'maleAgeRestrictionEnabled', 'maleMinBirthYear', 'maleMaxBirthYear',
  'femaleAgeRestrictionEnabled', 'femaleMinBirthYear', 'femaleMaxBirthYear',
  'minBirthYear', 'maxBirthYear',
  'category', 'partyTypes', 'vibes', 'tags',
  // 내용
  'description',
];

function pickRegistrationDataFields(fields) {
  const out = {};
  for (const key of REGISTRATION_DATA_KEYS) {
    if (Object.prototype.hasOwnProperty.call(fields, key)) out[key] = fields[key];
  }
  return out;
}

/// 케이스 하나 → PartyRegistrationData.toFirestore()에 대응하는 필드.
///
/// **일정 필드는 그 메서드가 만드는 것만 담는다.** 앱의 toFirestore()는
///   · 정기 → buildRecurringFields(partyDateTime·recruitDeadlineAt 포함)
///   · 일회성 → buildSingleFields(그 둘을 만들지 않는다 — 등록 화면이 슬롯마다
///     따로 계산한다)
/// 를 부르므로, 여기서 buildSlotFields(등록 화면 몫)를 합쳐 버리면 일회성
/// 케이스에서 앱에 없는 키가 생겨 비교가 성립하지 않는다.
function registrationDataFieldsOf(rawInput) {
  const input = R.normalizeInput(rawInput);

  let scheduleFields = {};
  let primarySlot = null;

  if (input.schedule.isRecurring) {
    const rec = input.schedule.recurring;
    const first = R.firstOccurrenceOf(rec, NOW);
    scheduleFields = R.buildRecurringFields(rec, { firstOccurrence: first });
    if (first) {
      primarySlot = {
        date: R.isoDateOf(first.start),
        startTime: hmOfDate(first.start),
        endTime: hmOfDate(first.end),
      };
    }
  } else if (input.schedule.slots.length > 0) {
    primarySlot = input.schedule.slots[0];
    const w = endWindowOf(primarySlot);
    scheduleFields = R.buildSingleFields(primarySlot, {
      deadlineRule: input.schedule.deadlineRule,
      openRule: input.schedule.openRule,
      deadlineAt: R.resolveRuleAt(input.schedule.deadlineRule, w.start, w.end),
      openAt: R.resolveRuleAt(input.schedule.openRule, w.start, w.end),
    });
  }

  const shared = R.buildSharedFields(input, {
    primarySlot,
    businessVerified: true,
    now: NOW,
  });
  return pickRegistrationDataFields({ ...scheduleFields, ...shared });
}

/// 절대 시각 → KST 벽시계 {h, m}.
function hmOfDate(date) {
  const shifted = new Date(date.getTime() + 9 * 3600000);
  return { h: shifted.getUTCHours(), m: shifted.getUTCMinutes() };
}

/// 슬롯의 시작/종료 절대 시각(종료가 시작보다 이르면 다음 날).
function endWindowOf(slot) {
  const p = R.parseIsoDate(slot.date);
  const start = R.kstAt(p.y, p.m, p.d, slot.startTime.h, slot.startTime.m);
  let end = null;
  if (slot.endTime) {
    end = R.kstAt(p.y, p.m, p.d, slot.endTime.h, slot.endTime.m);
    if (end.getTime() <= start.getTime()) end = new Date(end.getTime() + 24 * 3600000);
  }
  return { start, end };
}

function buildFixture() {
  return {
    // 픽스처를 읽는 쪽이 시간 기준을 맞출 수 있도록 함께 적는다.
    now: NOW.toISOString(),
    note:
      '이 파일은 functions/partyRegistration.selfcheck.js --write 로 만들어지고, ' +
      'party_app/test/party_registration_parity_test.dart 가 같은 파일을 읽어 ' +
      '앱 모델이 같은 값을 내는지 확인한다. 손으로 고치지 말 것.',
    pricing: PRICING_CASES.map((c) => ({
      name: c.name,
      input: c.input,
      expected: encode(R.pricingFields(R.normalizePricing(c.input))),
    })),
    recruitRule: RECRUIT_RULE_CASES.map((c) => ({
      name: c.name,
      input: c.input,
      expected: encode(R.recruitRuleFields(R.normalizeRecruitRule(c.input))),
    })),
    earlyBird: EARLY_BIRD_CASES.map((c) => ({
      name: c.name,
      input: c.input,
      isRecurring: c.isRecurring,
      expected: encode(
        R.earlyBirdFields(R.normalizeEarlyBird(c.input), { isRecurring: c.isRecurring })
      ),
    })),
    singleSchedule: SINGLE_SCHEDULE_CASES.map((c) => {
      const slot = {
        date: c.slot.date,
        startTime: R.parseHm(c.slot.startTime),
        endTime: c.slot.endTime ? R.parseHm(c.slot.endTime) : null,
      };
      const deadlineRule = R.normalizeRecruitRule(c.deadlineRule, { defaultMode: 'none' });
      const openRule = R.normalizeRecruitRule(c.openRule, { defaultMode: 'none' });
      const w = { start: R.kstAt(...isoParts(c.slot.date), R.parseHm(c.slot.startTime).h, R.parseHm(c.slot.startTime).m) };
      const end = c.slot.endTime ? endOf(c.slot.date, c.slot.startTime, c.slot.endTime) : null;
      const deadlineAt = R.resolveRuleAt(deadlineRule, w.start, end);
      const openAt = R.resolveRuleAt(openRule, w.start, end);
      return {
        name: c.name,
        slot: c.slot,
        deadlineRule: c.deadlineRule,
        openRule: c.openRule,
        expected: encode(
          R.buildSingleFields(slot, { deadlineRule, openRule, deadlineAt, openAt })
        ),
      };
    }),
    recurringSchedule: RECURRING_CASES.map((c) => {
      const rec = R.normalizeRecurring(c.input);
      return {
        name: c.name,
        input: c.input,
        expected: encode(
          R.buildRecurringFields(rec, { firstOccurrence: R.firstOccurrenceOf(rec, NOW) })
        ),
      };
    }),
    round: ROUND_CASES.map((c) => ({
      name: c.name,
      input: c.input,
      isoDate: c.isoDate,
      roundNumber: c.roundNumber,
      perRound: c.perRound,
      expected: encode(
        R.roundFields(R.normalizeRound(c.input, c.roundNumber - 2), {
          roundNumber: c.roundNumber,
          isoDate: c.isoDate,
          perRound: c.perRound,
        })
      ),
    })),
    roundPackage: ROUND_PACKAGE_CASES.map((c) => ({
      name: c.name,
      input: c.input,
      firstRoundStart: c.firstRoundStart,
      expected: encode(
        R.roundPackageFields(R.normalizeRoundPackage(c.input, 0), {
          firstRoundStart: new Date(c.firstRoundStart),
        })
      ),
    })),
    registrationData: REGISTRATION_DATA_CASES.map((c) => ({
      name: c.name,
      input: c.input,
      expected: encode(registrationDataFieldsOf(c.input)),
    })),
  };
}

function isoParts(iso) {
  const p = R.parseIsoDate(iso);
  return [p.y, p.m, p.d];
}

function endOf(isoDate, startHm, endHm) {
  const p = R.parseIsoDate(isoDate);
  const s = R.parseHm(startHm);
  const e = R.parseHm(endHm);
  const start = R.kstAt(p.y, p.m, p.d, s.h, s.m);
  let end = R.kstAt(p.y, p.m, p.d, e.h, e.m);
  if (end.getTime() <= start.getTime()) end = new Date(end.getTime() + 24 * 3600000);
  return end;
}

// ═══════════════════════════════════════════════════════════════════════════
// 실행
// ═══════════════════════════════════════════════════════════════════════════

const fixture = buildFixture();

if (WRITE) {
  fs.mkdirSync(path.dirname(FIXTURE_PATH), { recursive: true });
  fs.writeFileSync(FIXTURE_PATH, `${JSON.stringify(fixture, null, 2)}\n`, 'utf8');
  console.log(`픽스처를 새로 썼습니다: ${path.relative(process.cwd(), FIXTURE_PATH)}`);
  console.log('⚠️ 이제 party_app 쪽 party_registration_parity_test.dart도 돌려서');
  console.log('   앱이 같은 값을 내는지 반드시 확인하세요.');
  process.exit(0);
}

// ── 1. 회귀 잠금 — 픽스처와 지금 출력이 같은가 ─────────────────────────────
check('픽스처 파일이 있다', () => {
  assert.ok(fs.existsSync(FIXTURE_PATH), `${FIXTURE_PATH} 가 없습니다. --write로 만드세요.`);
});

if (fs.existsSync(FIXTURE_PATH)) {
  const saved = JSON.parse(fs.readFileSync(FIXTURE_PATH, 'utf8'));
  for (const section of Object.keys(fixture)) {
    if (section === 'now' || section === 'note') continue;
    check(`[회귀] ${section} 케이스 수`, () => {
      assert.strictEqual(
        (saved[section] || []).length,
        fixture[section].length,
        '케이스를 더하거나 뺐으면 --write로 픽스처를 다시 만드세요.'
      );
    });
    fixture[section].forEach((c, i) => {
      check(`[회귀] ${section}: ${c.name}`, () => {
        assert.deepStrictEqual(c.expected, (saved[section] || [])[i]?.expected);
      });
    });
  }
}

// ── 2. 규칙 자체의 불변식 ──────────────────────────────────────────────────

check('무료 파티는 malePrice/femalePrice가 0이고 pricingType이 free', () => {
  const f = R.pricingFields(R.normalizePricing({ male: 0, female: 0 }));
  assert.strictEqual(f.pricingType, 'free');
  assert.strictEqual(f.malePrice, 0);
  assert.strictEqual(f.femalePrice, 0);
  assert.strictEqual(f.maleFee, 0);
  assert.strictEqual(f.femaleFee, 0);
});

check('gendered는 price를 null로 남긴다 — 대표가를 두 곳에 적지 않는다', () => {
  const f = R.pricingFields(R.normalizePricing({ male: 35000, female: 25000 }));
  assert.strictEqual(f.pricingType, 'gendered');
  assert.strictEqual(f.price, null);
  assert.strictEqual(f.maleFee, 35000);
  assert.strictEqual(f.femaleFee, 25000);
});

check('same은 malePrice/femalePrice를 null로 남긴다', () => {
  const f = R.pricingFields(R.normalizePricing({ male: 30000, female: 30000 }));
  assert.strictEqual(f.pricingType, 'same');
  assert.strictEqual(f.price, 30000);
  assert.strictEqual(f.malePrice, null);
  assert.strictEqual(f.femalePrice, null);
});

check('얼리버드는 두 방식이 한 문서에 섞이지 않는다', () => {
  const fixed = R.earlyBirdFields(
    R.normalizeEarlyBird({
      enabled: true,
      percent: 10,
      endType: 'fixedDate',
      endAt: { date: '2026-09-01', time: '23:59' },
    }),
    { isRecurring: false }
  );
  assert.ok(fixed.earlyBirdEndAt instanceof Date);
  assert.strictEqual(fixed.earlyBirdDeadlineRule, null);

  const rule = R.earlyBirdFields(
    R.normalizeEarlyBird({
      enabled: true,
      percent: 10,
      endType: 'beforeStart',
      beforeStartRule: { mode: 'daysBefore', days: 3, time: '23:59' },
    }),
    { isRecurring: false }
  );
  assert.strictEqual(rule.earlyBirdEndAt, null);
  assert.deepStrictEqual(rule.earlyBirdDeadlineRule, {
    mode: 'daysBefore',
    days: 3,
    time: '23:59',
  });
});

check('정기 파티는 고정 종료 시각을 저장할 수 없다', () => {
  const f = R.earlyBirdFields(
    R.normalizeEarlyBird({
      enabled: true,
      percent: 10,
      endType: 'fixedDate',
      endAt: { date: '2026-09-01', time: '23:59' },
    }),
    { isRecurring: true }
  );
  assert.strictEqual(f.earlyBirdEndType, 'beforeStart');
  assert.strictEqual(f.earlyBirdEndAt, null);
  assert.ok(f.earlyBirdDeadlineRule);
});

check('정기 파티는 recruitDeadlineAt을 null로 남긴다 — 고정 마감이 남으면 신청이 영구히 막힌다', () => {
  const rec = R.normalizeRecurring(RECURRING_CASES[0].input);
  const f = R.buildRecurringFields(rec, { firstOccurrence: R.firstOccurrenceOf(rec, NOW) });
  assert.strictEqual(f.recruitDeadlineAt, null);
  assert.strictEqual(f.recruitDeadlineRule, null);
  assert.strictEqual(f.singleSchedule, null);
});

check('정기 일정은 켜진 요일만 weeklySchedule에 담는다', () => {
  const rec = R.normalizeRecurring(RECURRING_CASES[0].input);
  const f = R.buildRecurringFields(rec, { firstOccurrence: null });
  assert.deepStrictEqual(
    Object.keys(f.recurringSchedule.weeklySchedule),
    ['friday', 'saturday']
  );
});

check('자정을 넘기는 차수는 종료가 다음 날로 넘어간다', () => {
  const w = R.resolveRoundOn(
    R.normalizeRound({ startTime: '22:00', endTime: '01:00' }, 0),
    '2026-09-05'
  );
  assert.ok(w.end.getTime() > w.start.getTime());
  assert.strictEqual(R.isoDateOf(w.end), '2026-09-06');
});

check('통합 정원 차수는 정원·참가비를 저장하지 않는다', () => {
  const f = R.roundFields(R.normalizeRound({ startTime: '22:00', endTime: '23:30' }, 0), {
    roundNumber: 2,
    isoDate: '2026-09-05',
    perRound: false,
  });
  assert.ok(!('maxCapacity' in f));
  assert.ok(!('maleFee' in f));
  assert.ok(!('earlyBirdEnabled' in f));
});

check('차수별 정원 모드에서 남녀 분리 정원의 합계가 maxCapacity가 된다', () => {
  const f = R.roundFields(
    R.normalizeRound(
      { startTime: '22:00', endTime: '23:30', maleCapacity: 6, femaleCapacity: 4, maxCapacity: 0 },
      0
    ),
    { roundNumber: 2, isoDate: '2026-09-05', perRound: true }
  );
  assert.strictEqual(f.maxCapacity, 10);
});

check('최소 모집 인원은 차수 합계로 오염되지 않는다', () => {
  const input = {
    title: '차수 파티',
    capacity: { genderCapacityMode: 'unlimited', maxCapacity: 10, minCapacity: 5 },
    pricing: { male: 20000, female: 20000 },
    refundTiers: [{ daysBefore: 1, refundPercent: 100 }],
    schedule: {
      type: 'single',
      slots: [{ date: '2026-09-05', startTime: '20:00', endTime: '23:00' }],
    },
    rounds: {
      enabled: true,
      capacityMode: 'perRound',
      round1MinCapacity: 3,
      extra: [
        {
          startTime: '22:00',
          endTime: '23:59',
          minCapacity: 4,
          maxCapacity: 8,
        },
      ],
    },
  };
  const normalized = R.normalizeInput(input);
  const slot = normalized.schedule.slots[0];
  const shared = R.buildSharedFields(normalized, {
    primarySlot: slot,
    businessVerified: true,
    now: NOW,
  });
  // 파티 전체 최소 인원은 호스트가 정한 값 하나(5)여야 한다 — 3 + 4 = 7이 아니다.
  assert.strictEqual(shared.partyMinCapacity, 5);
  assert.strictEqual(shared.minCapacity, 5);
  // 정원은 자리 수라 합산한다(10 + 8).
  assert.strictEqual(shared.maxCapacity, 18);
});

check('최소 인원을 0으로 두면 자동 취소 정책이 저장되지 않는다', () => {
  const normalized = R.normalizeInput({
    capacity: { maxCapacity: 10, minCapacity: 0, minCapacityPolicy: 'autoCancel' },
    pricing: { male: 0, female: 0 },
  });
  const shared = R.buildSharedFields(normalized, {
    primarySlot: null,
    businessVerified: true,
    now: NOW,
  });
  assert.strictEqual(shared.minCapacityPolicy, 'proceed');
});

check('무료 파티는 결제 방식 필드를 만들지 않는다', () => {
  const normalized = R.normalizeInput({
    capacity: { maxCapacity: 10 },
    pricing: { male: 0, female: 0 },
    paymentPolicy: { paymentMode: 'partial', upfrontType: 'percentage', upfrontPercent: 30 },
  });
  const shared = R.buildSharedFields(normalized, {
    primarySlot: null,
    businessVerified: true,
    now: NOW,
  });
  assert.ok(!('paymentMode' in shared));
});

check('미인증 호스트는 preopen으로만 저장된다', () => {
  const normalized = R.normalizeInput({
    capacity: { maxCapacity: 10 },
    pricing: { male: 0, female: 0 },
    schedule: { type: 'single', slots: [{ date: '2026-09-05', startTime: '20:00' }] },
  });
  const shared = R.buildSharedFields(normalized, {
    primarySlot: normalized.schedule.slots[0],
    businessVerified: false,
    now: NOW,
  });
  assert.strictEqual(shared.openState, 'preopen');
  assert.strictEqual(shared.hostBusinessVerified, false);
});

check('날짜가 없으면 인증 호스트라도 preopen이고 dateTbd가 켜진다', () => {
  const normalized = R.normalizeInput({
    capacity: { maxCapacity: 10 },
    pricing: { male: 0, female: 0 },
    dateTbd: true,
    schedule: { type: 'single', slots: [] },
  });
  const shared = R.buildSharedFields(normalized, {
    primarySlot: null,
    businessVerified: true,
    now: NOW,
  });
  assert.strictEqual(shared.openState, 'preopen');
  assert.strictEqual(shared.dateTbd, true);
});

check('날짜를 여러 개 고르면 날짜마다 문서가 하나씩 만들어진다', () => {
  const out = R.buildPartyDocuments(
    {
      title: '3주 연속 파티',
      capacity: { maxCapacity: 20 },
      pricing: { male: 20000, female: 20000 },
      refundTiers: [{ daysBefore: 1, refundPercent: 100 }],
      schedule: {
        type: 'single',
        slots: [
          { date: '2026-09-05', startTime: '20:00', endTime: '23:00' },
          { date: '2026-09-12', startTime: '20:00', endTime: '23:00' },
          { date: '2026-09-19', startTime: '20:00', endTime: '23:00' },
        ],
        deadlineRule: { mode: 'startDayTime', time: '18:00' },
      },
    },
    { now: NOW, hostId: 'h1', hostUid: 'u1', seriesId: 's1', businessVerified: true }
  );
  assert.strictEqual(out.docs.length, 3);
  // 같은 게시글의 날짜 문서는 모두 같은 seriesId로 묶인다.
  assert.ok(out.docs.every((d) => d.fields.seriesId === 's1'));
  // 날짜 문서마다 dateSlotId가 다르다 — 다음 수정 저장이 문서를 되찾는 열쇠.
  assert.strictEqual(new Set(out.docs.map((d) => d.dateSlotId)).size, 3);
  assert.strictEqual(out.docs[0].fields.date, '2026.09.05 오후 08:00');
  assert.strictEqual(R.isoDateOf(out.docs[1].fields.partyDateTime), '2026-09-12');
});

check('정기 파티는 문서가 하나만 만들어진다', () => {
  const out = R.buildPartyDocuments(
    {
      title: '매주 수요일',
      capacity: { maxCapacity: 16 },
      pricing: { male: 40000, female: 40000 },
      refundTiers: [{ daysBefore: 1, refundPercent: 100 }],
      schedule: {
        type: 'recurring',
        recurring: {
          startDate: '2026-09-01',
          weekly: { wednesday: { enabled: true, startTime: '19:30', endTime: '22:00' } },
          deadlineRule: { mode: 'startDayTime', time: '18:00' },
        },
      },
    },
    { now: NOW, hostId: 'h1', hostUid: 'u1', seriesId: 's2', businessVerified: true }
  );
  assert.strictEqual(out.docs.length, 1);
  assert.strictEqual(out.docs[0].fields.scheduleType, 'recurring');
  assert.strictEqual(out.docs[0].fields.recruitDeadlineAt, null);
  // 첫 회차는 2026-09-02(수).
  assert.strictEqual(R.isoDateOf(out.docs[0].fields.partyDateTime), '2026-09-02');
});

// ── 3. 검증 규칙 ──────────────────────────────────────────────────────────

function errorsOf(raw) {
  return R.validateRegistration(R.normalizeInput(raw), { now: NOW }).map((e) => e.field);
}

check('제목·정원·환불정책이 없으면 각각 걸린다', () => {
  const fields = errorsOf({ pricing: { male: 0, female: 0 }, schedule: { type: 'single', slots: [] }, dateTbd: true });
  assert.ok(fields.includes('title'));
  assert.ok(fields.includes('capacity'));
  assert.ok(fields.includes('refundTiers'));
});

check('최소 인원이 최대보다 크면 걸린다', () => {
  const fields = errorsOf({
    title: 'x',
    capacity: { maxCapacity: 10, minCapacity: 20 },
    pricing: { male: 0, female: 0 },
    refundTiers: [{ daysBefore: 1, refundPercent: 100 }],
    schedule: { type: 'single', slots: [{ date: '2026-09-05', startTime: '20:00' }] },
  });
  assert.ok(fields.includes('capacity'));
});

check('참가비는 1,000원 단위여야 한다', () => {
  const fields = errorsOf({
    title: 'x',
    capacity: { maxCapacity: 10 },
    pricing: { male: 30500, female: 20000 },
    refundTiers: [{ daysBefore: 1, refundPercent: 100 }],
    schedule: { type: 'single', slots: [{ date: '2026-09-05', startTime: '20:00' }] },
  });
  assert.ok(fields.includes('pricing'));
});

check('무료 파티에는 얼리버드를 켤 수 없다', () => {
  const fields = errorsOf({
    title: 'x',
    capacity: { maxCapacity: 10 },
    pricing: { male: 0, female: 0 },
    earlyBird: { enabled: true, percent: 10, endType: 'beforeStart' },
    refundTiers: [{ daysBefore: 1, refundPercent: 100 }],
    schedule: { type: 'single', slots: [{ date: '2026-09-05', startTime: '20:00' }] },
  });
  assert.ok(fields.includes('earlyBird'));
});

check('이미 지난 얼리버드 종료 시각은 걸린다', () => {
  const fields = errorsOf({
    title: 'x',
    capacity: { maxCapacity: 10 },
    pricing: { male: 20000, female: 20000 },
    earlyBird: {
      enabled: true,
      percent: 10,
      endType: 'fixedDate',
      endAt: { date: '2026-08-01', time: '23:59' },
    },
    refundTiers: [{ daysBefore: 1, refundPercent: 100 }],
    schedule: { type: 'single', slots: [{ date: '2026-09-05', startTime: '20:00' }] },
  });
  assert.ok(fields.includes('earlyBird'));
});

check('얼리버드는 모집 마감보다 늦게 끝날 수 없다', () => {
  const fields = errorsOf({
    title: 'x',
    capacity: { maxCapacity: 10 },
    pricing: { male: 20000, female: 20000 },
    earlyBird: {
      enabled: true,
      percent: 10,
      endType: 'fixedDate',
      // 마감(9/5 18:00)보다 늦다.
      endAt: { date: '2026-09-05', time: '19:00' },
    },
    refundTiers: [{ daysBefore: 1, refundPercent: 100 }],
    schedule: {
      type: 'single',
      slots: [{ date: '2026-09-05', startTime: '20:00' }],
      deadlineRule: { mode: 'startDayTime', time: '18:00' },
    },
  });
  assert.ok(fields.includes('earlyBird'));
});

check('열릴 회차가 없는 정기 일정은 걸린다', () => {
  const fields = errorsOf({
    title: 'x',
    capacity: { maxCapacity: 10 },
    pricing: { male: 0, female: 0 },
    refundTiers: [{ daysBefore: 1, refundPercent: 100 }],
    schedule: {
      type: 'recurring',
      recurring: {
        startDate: '2026-01-01',
        endDate: '2026-02-01', // 이미 지났다
        weekly: { friday: { enabled: true, startTime: '20:00', endTime: '23:00' } },
      },
    },
  });
  assert.ok(fields.includes('schedule'));
});

check('날짜 미정 사전등록은 일정 없이도 통과한다', () => {
  const fields = errorsOf({
    title: 'x',
    capacity: { maxCapacity: 10 },
    pricing: { male: 0, female: 0 },
    refundTiers: [{ daysBefore: 1, refundPercent: 100 }],
    dateTbd: true,
    schedule: { type: 'single', slots: [] },
  });
  assert.ok(!fields.includes('schedule'));
});

check('차수 종료 시간이 없으면 걸린다', () => {
  const fields = errorsOf({
    title: 'x',
    capacity: { maxCapacity: 10 },
    pricing: { male: 20000, female: 20000 },
    refundTiers: [{ daysBefore: 1, refundPercent: 100 }],
    schedule: { type: 'single', slots: [{ date: '2026-09-05', startTime: '20:00', endTime: '23:00' }] },
    rounds: { enabled: true, extra: [{ startTime: '23:00' }] },
  });
  assert.ok(fields.includes('rounds'));
});

// ── 4. 웹 폼이 앱과 같은 선택지를 쓰는가 ───────────────────────────────────
//
// website/는 빌드 스텝이 없는 정적 사이트라 이 모듈을 import할 수 없어서
// 유형·분위기 목록의 사본을 들고 있다. 사본이 갈리면 웹에서 등록한 파티만
// 필터에 안 걸리는 상태가 되므로(원문 문자열이 그대로 매칭에 쓰인다) 여기서
// 파일을 읽어 대조한다.

const WEB_FORM_PATH = path.join(__dirname, '..', 'website', 'js', 'party-register.js');

/// 웹 폼 파일에서 `const NAME = [ '...', ... ];` 배열의 문자열만 뽑는다.
function webArray(source, name) {
  const m = new RegExp('const ' + name + ' = \\[([\\s\\S]*?)\\];').exec(source);
  if (!m) return null;
  return [...m[1].matchAll(/'([^']+)'/g)].map((x) => x[1]);
}

/// 웹 폼 파일에서 `const NAME = 5;` 숫자 상수를 뽑는다.
function webInt(source, name) {
  const m = new RegExp('const ' + name + ' = (\\d+);').exec(source);
  return m ? Number(m[1]) : null;
}

check('웹 폼 파일이 있다', () => {
  assert.ok(fs.existsSync(WEB_FORM_PATH), WEB_FORM_PATH + ' 가 없습니다.');
});

if (fs.existsSync(WEB_FORM_PATH)) {
  const web = fs.readFileSync(WEB_FORM_PATH, 'utf8');
  check('웹 폼의 파티 유형 목록이 앱과 같다', () => {
    assert.deepStrictEqual(webArray(web, 'PARTY_TYPES'), R.PARTY_TYPES);
  });
  check('웹 폼의 분위기 목록이 앱과 같다', () => {
    assert.deepStrictEqual(webArray(web, 'PARTY_VIBES'), R.PARTY_VIBES);
  });
  check('웹 폼의 선택 개수 상한이 앱과 같다', () => {
    assert.strictEqual(webInt(web, 'MAX_PARTY_TYPES'), R.MAX_PARTY_TYPES);
    assert.strictEqual(webInt(web, 'MAX_VIBES'), R.MAX_VIBES);
    assert.strictEqual(webInt(web, 'MAX_TAGS'), R.MAX_TAGS);
  });
}

// ── 결과 ──────────────────────────────────────────────────────────────────

if (failures.length > 0) {
  console.error(`\n❌ ${failures.length}건 실패 (통과 ${passed}건)\n`);
  for (const f of failures) console.error(`  · ${f}\n`);
  process.exit(1);
}
console.log(`✅ partyRegistration 셀프체크 ${passed}건 통과`);
