// 관리자 판매 통계 원자료 콜러블 자체 검증 — `node adminSalesStats.selfcheck.js`.
//
// 이 콜러블은 계산을 하지 않는다(파일 상단 주석 참고). 그래서 여기서 볼 것은
// **Dart 매퍼와 짝이 맞는가** 하나다. 짝이 어긋나면 계산은 멀쩡한데 입력이
// 비어서, 관리자 화면에만 매출이 0원으로 뜬다 — 에러 없이 조용히 틀린다.
//
// 못 박는 것 셋:
//   ① 읽는 컬렉션 목록이 Dart의 SalesSource와 1:1이다
//   ② **판매자 필드가 소스별로 같다** — 파티샵만 sellerId다
//   ③ 매퍼가 읽는 필드가 FIELDS 화이트리스트에 다 들어 있다
//      (빠지면 그 필드만 undefined로 내려가 금액이 0원이 된다)
//
// Dart를 실행할 수는 없으므로 소스 텍스트에서 읽는다 — accountWithdrawal의
// contentCleanup 대조와 같은 방식이다.

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const { __test } = require('./adminSalesStats');
const { SOURCES, FIELDS } = __test;

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

const MAPPER = path.join(
  __dirname,
  '..',
  'packages',
  'partychu_sales',
  'lib',
  'src',
  'sales_entry_mapper.dart',
);

/**
 * Dart enum에서 `이름('컬렉션', SalesKind.x[, sellerField: 'y'])`를 뽑는다.
 * sellerField를 적지 않은 항목은 Dart 기본값 'hostId'다.
 */
function dartSources() {
  const src = fs.readFileSync(MAPPER, 'utf8');
  const re =
    /^\s{2}(\w+)\('([^']+)',\s*SalesKind\.(\w+)(?:,\s*sellerField:\s*'([^']+)')?\)/gm;
  const out = [];
  for (const m of src.matchAll(re)) {
    out.push({ name: m[1], key: m[2], kind: m[3], sellerField: m[4] || 'hostId' });
  }
  return out;
}

// ── ① 컬렉션 목록 ────────────────────────────────────────────────────────

test('읽는 컬렉션이 Dart SalesSource와 1:1이다', () => {
  const dart = dartSources();
  assert.ok(dart.length >= 6, `Dart 소스를 못 읽었다(${dart.length}개)`);
  assert.deepStrictEqual(
    SOURCES.map((s) => s.key).sort(),
    dart.map((s) => s.key).sort(),
  );
});

test('파티샵 주문(orders)이 목록에 있다', () => {
  const shop = SOURCES.find((s) => s.key === 'orders');
  assert.ok(shop, 'orders가 SOURCES에 없다 — 관리자 파티샵 매출이 0원이 된다');
  assert.strictEqual(shop.dateField, 'createdAt');
  assert.strictEqual(shop.group, false);
});

test('파티샵과 플레이스 상품은 다른 컬렉션이다', () => {
  // 헷갈려 같은 값을 넣으면 한쪽 매출이 통째로 사라지거나 두 배가 된다.
  assert.notStrictEqual('orders', 'placeProductOrders');
  assert.ok(SOURCES.some((s) => s.key === 'orders'));
  assert.ok(SOURCES.some((s) => s.key === 'placeProductOrders'));
});

// ── ② 판매자 필드 ────────────────────────────────────────────────────────

test('판매자 필드가 소스별로 Dart와 같다', () => {
  const dart = new Map(dartSources().map((s) => [s.key, s.sellerField]));
  for (const s of SOURCES) {
    assert.strictEqual(
      s.sellerField,
      dart.get(s.key),
      `${s.key}의 판매자 필드가 Dart와 다르다`,
    );
  }
});

test('파티샵만 sellerId이고 나머지는 hostId다', () => {
  for (const s of SOURCES) {
    const expected = s.key === 'orders' ? 'sellerId' : 'hostId';
    assert.strictEqual(s.sellerField, expected, s.key);
  }
});

test('모든 소스에 판매자 필드가 있다 — 빠지면 필터가 전부 통과시킨다', () => {
  for (const s of SOURCES) {
    assert.ok(s.sellerField, `${s.key}에 sellerField가 없다`);
  }
});

// ── ③ 필드 화이트리스트 ──────────────────────────────────────────────────

test('매퍼가 읽는 금액·수량 정본이 전부 화이트리스트에 있다', () => {
  // 매퍼의 _amountOf / _headcountOf / _titleOf / _subtitleOf가 읽는 이름들.
  const needed = [
    'appliedFee', 'depositAmount', 'totalPrice', 'amount', // 금액 정본
    'quantity', 'peopleCount', // 인원·수량 축
    'placeName', 'partyTitle', 'shopName', // 제목
    'productName', 'selectedOptionName', 'packageName', 'roomName', // 부가 줄
    'status', 'payment', 'amounts', 'refundStatus', 'refundAmount', // 판정
    'appliedAt', 'createdAt', // 날짜 축
    'hostId', 'sellerId', // 판매자
  ];
  for (const f of needed) {
    assert.ok(FIELDS.includes(f), `${f}가 FIELDS에 없다 — 그 값만 비어서 내려간다`);
  }
});

test('구매자 개인정보는 내려보내지 않는다', () => {
  // 통계에 필요 없는 값은 관리자에게도 주지 않는다(파일 상단 원칙).
  for (const f of [
    'buyerId', 'buyerName', 'sellerName',
    'requesterName', 'requesterPhone', 'uid',
  ]) {
    assert.ok(!FIELDS.includes(f), `${f}는 통계에 필요 없다`);
  }
});

test('화이트리스트에 중복이 없다', () => {
  assert.strictEqual(new Set(FIELDS).size, FIELDS.length);
});

// ── 실행 ─────────────────────────────────────────────────────────────────

let failed = 0;
for (const [name, fn] of cases) {
  try {
    fn();
    console.log(`  ✓ ${name}`);
  } catch (e) {
    failed++;
    console.error(`  ✗ ${name}\n    ${e.message}`);
  }
}
console.log(`\n관리자 판매 통계 원자료 검증 ${cases.length - failed}/${cases.length} 통과`);
process.exit(failed === 0 ? 0 : 1);
