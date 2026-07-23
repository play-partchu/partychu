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

module.exports = { portOneGetPayment };
