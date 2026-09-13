/**
 * KST(한국 표준시) 날짜 계산 — **하루 단위 판정의 정본.**
 *
 * 원래 placeProductOrders.js 안에만 있던 함수를 그대로 꺼낸 것이다. 통합 QR
 * 체크인이 "예약 날짜가 오늘인가"를 같은 규칙으로 물어야 하는데, 판정이 두 벌이
 * 되면 자정 무렵에 상품 이용권과 예약이 서로 다른 날로 갈린다.
 *
 * 서버는 UTC로 돈다. 9시간을 더한 뒤 **UTC 게터로** 읽는 이유가 이것이다 —
 * 로컬 타임존에 의존하면 배포 지역이 바뀌는 순간 하루가 어긋난다.
 */

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

/** `2026-08-05` 꼴의 KST 날짜 문자열. */
function kstDateStr(ms) {
  const kst = new Date(ms + KST_OFFSET_MS);
  const y = kst.getUTCFullYear();
  const m = String(kst.getUTCMonth() + 1).padStart(2, '0');
  const d = String(kst.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

/** 두 시각이 KST 기준 같은 날인가. */
function isSameKstDay(aMs, bMs) {
  return kstDateStr(aMs) === kstDateStr(bMs);
}

module.exports = { KST_OFFSET_MS, kstDateStr, isSameKstDay };
