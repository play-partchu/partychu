// 참가비(pricingType) 해석 자체 검증 — `npm run check:pricing`.
//
// 클라이언트 lib/models/party_pricing.dart 및 test/party_pricing_test.dart와
// 같은 결과를 내야 한다. 돈이 걸린 계산이라 기존 문서(pricingType 없음)에서
// 값이 달라지지 않는지도 함께 고정한다.

const assert = require('assert');
const { resolveBaseFee, computeAppliedFee } = require('./partyCapacity');

const cases = [];
function test(name, fn) {
  cases.push([name, fn]);
}

// ── 새 구조 ────────────────────────────────────────────────────────────
test('same — 성별과 무관하게 같은 금액', () => {
  const d = { pricingType: 'same', price: 30000, maleFee: 30000, femaleFee: 30000 };
  assert.strictEqual(resolveBaseFee(d, 'male'), 30000);
  assert.strictEqual(resolveBaseFee(d, 'female'), 30000);
  assert.strictEqual(resolveBaseFee(d, null), 30000);
});

test('gendered — 성별에 맞는 금액', () => {
  const d = {
    pricingType: 'gendered',
    price: null,
    malePrice: 35000,
    femalePrice: 25000,
    maleFee: 35000,
    femaleFee: 25000,
  };
  assert.strictEqual(resolveBaseFee(d, 'male'), 35000);
  assert.strictEqual(resolveBaseFee(d, 'female'), 25000);
  // 성별 미확인이면 낮은 쪽으로 방어
  assert.strictEqual(resolveBaseFee(d, null), 25000);
});

test('free — 항상 0원', () => {
  const d = { pricingType: 'free', price: 0, malePrice: 0, femalePrice: 0 };
  assert.strictEqual(resolveBaseFee(d, 'male'), 0);
  assert.strictEqual(resolveBaseFee(d, null), 0);
});

test('pricingType만 있고 값은 레거시 필드에 있어도 읽는다', () => {
  assert.strictEqual(
    resolveBaseFee({ pricingType: 'same', maleFee: 18000 }, 'female'),
    18000,
  );
  assert.strictEqual(
    resolveBaseFee({ pricingType: 'gendered', maleFee: 30000, femaleFee: 20000 }, 'female'),
    20000,
  );
});

// ── 기존 데이터 회귀 방지 ──────────────────────────────────────────────
test('기존 maleFee/femaleFee 문서는 예전과 동일하게 계산된다', () => {
  const d = { maleFee: 30000, femaleFee: 20000 };
  assert.strictEqual(resolveBaseFee(d, 'male'), 30000);
  assert.strictEqual(resolveBaseFee(d, 'female'), 20000);
  assert.strictEqual(resolveBaseFee(d, null), 30000); // 예전 폴백 순서 유지
});

test('아주 오래된 단일 fee 필드', () => {
  assert.strictEqual(resolveBaseFee({ fee: 12000 }, 'male'), 12000);
});

test('플레이스+파티가 쓰던 단일 price만 있어도 읽는다', () => {
  assert.strictEqual(resolveBaseFee({ price: 30000 }, 'male'), 30000);
});

test('참가비 정보가 없으면 0원', () => {
  assert.strictEqual(resolveBaseFee({}, 'male'), 0);
});

// ── 얼리버드와의 조합 ──────────────────────────────────────────────────
test('얼리버드 할인은 새 구조에도 그대로 적용된다', () => {
  const endAt = { toDate: () => new Date(Date.now() + 60 * 60 * 1000) };
  const d = {
    pricingType: 'gendered',
    malePrice: 40000,
    femalePrice: 20000,
    earlyBirdEnabled: true,
    earlyBirdDiscountPercent: 10,
    earlyBirdEndAt: endAt,
  };
  assert.strictEqual(computeAppliedFee(d, 'male'), 36000);
  assert.strictEqual(computeAppliedFee(d, 'female'), 18000);
});

test('무료 파티에는 얼리버드가 영향을 주지 않는다', () => {
  const endAt = { toDate: () => new Date(Date.now() + 60 * 60 * 1000) };
  assert.strictEqual(
    computeAppliedFee(
      {
        pricingType: 'free',
        earlyBirdEnabled: true,
        earlyBirdDiscountPercent: 50,
        earlyBirdEndAt: endAt,
      },
      'male',
    ),
    0,
  );
});

let failed = 0;
for (const [name, fn] of cases) {
  try {
    fn();
    console.log(`  ok  ${name}`);
  } catch (e) {
    failed++;
    console.error(`FAIL  ${name}\n      ${e.message}`);
  }
}
console.log(`\n${cases.length - failed}/${cases.length} passed`);
process.exit(failed === 0 ? 0 : 1);
