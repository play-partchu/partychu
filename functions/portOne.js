// PortOne V2 결제 조회 — raw https 모듈로 새 npm 의존성 없이 호출한다
// (geocodeSingle과 동일한 방식). placeReservations.js와 packageBookings.js가
// 공유한다.

const https = require('https');

function portOneGetPayment(paymentId, apiSecret) {
  const path = `/payments/${encodeURIComponent(paymentId)}`;
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: 'api.portone.io',
        path,
        method: 'GET',
        headers: { Authorization: `PortOne ${apiSecret}` },
      },
      (res) => {
        let body = '';
        res.on('data', (c) => { body += c; });
        res.on('end', () => {
          try {
            resolve({ statusCode: res.statusCode, body: JSON.parse(body) });
          } catch (_) {
            resolve({ statusCode: res.statusCode, body: { _raw: body } });
          }
        });
      },
    );
    req.on('error', reject);
    req.end();
  });
}

// PG사 계약/심사가 끝나기 전에는 PORTONE_API_SECRET 시크릿에 실제 값이
// 들어있지 않다 — 그 상태(비어있거나 아래 플레이스홀더 값 중 하나)일 때만
// 테스트 모드로 판단해 실제 PortOne 조회를 건너뛴다. 계약 완료 후 진짜
// 시크릿 값을 등록하는 순간 이 분기는 더 이상 타지 않고 항상 실검증
// 경로로 강제 전환된다 — 사람이 테스트 분기를 끄는 걸 깜빡해서 실사용자
// 결제를 검증 없이 통과시키는 사고를 코드 레벨에서 막기 위함이다.
const TEST_MODE_SECRET_SENTINELS = new Set(['', 'TEST_MODE', 'REPLACE_WITH_PORTONE_API_SECRET']);

function resolveApiSecret(apiSecretParam) {
  let value = '';
  try {
    value = (apiSecretParam.value() || '').trim();
  } catch (e) {
    value = '';
  }
  return TEST_MODE_SECRET_SENTINELS.has(value) ? null : value;
}

// paymentId(= placeReservations의 groupId, packageBookings의
// bundleBookingId)의 결제를 검증한다. expectedAmount는 pending 문서 생성
// 시 서버가 계산해 저장해둔 금액이어야 한다(클라이언트 값을 그대로 믿지
// 않기 위함). 반환값의 testMode는 로그/모니터링용 — 호출부의 확정 로직은
// 테스트 모드든 아니든 동일하게 ok만 보고 진행한다.
async function verifyPortOnePayment(paymentId, expectedAmount, apiSecretParam) {
  const apiSecret = resolveApiSecret(apiSecretParam);
  if (!apiSecret) {
    console.warn(
      `[portOne] PORTONE_API_SECRET 미설정 — 테스트 모드로 ${paymentId} 결제를 실제 검증 없이 통과시킵니다. ` +
      'PG 계약 후 시크릿을 등록하면 이 분기는 자동으로 비활성화됩니다.',
    );
    return { ok: true, testMode: true };
  }

  const { statusCode, body } = await portOneGetPayment(paymentId, apiSecret);
  if (statusCode !== 200) {
    return { ok: false, testMode: false, reason: `PortOne 조회 실패 (${statusCode})` };
  }
  const paidAmount = body && body.amount && body.amount.total;
  const status = body && body.status;
  if (status !== 'PAID' || paidAmount !== expectedAmount) {
    return { ok: false, testMode: false, reason: '결제 금액/상태 불일치', status, paidAmount };
  }
  return { ok: true, testMode: false };
}

module.exports = { portOneGetPayment, verifyPortOnePayment };
