// TourAPI 축제 수집 dry-run — 배포되는 Cloud Function이 아니라 로컬에서 직접 실행한다.
//
// syncTourFestivals와 **같은 코드 경로**(syncTourFestivalsOnce)를 dryRun으로
// 돌린다. 실제 TourAPI는 전 페이지를 읽고, 운영 publicEvents는 **읽기만** 해서
// 신규·변경·종료 예상 건수를 계산한다. Firestore에는 절대 쓰지 않는다.
//
//   · 쓰기 차단은 두 겹이다. syncTourFestivalsOnce가 dryRun이면 commit을
//     부르지 않고, 이 스크립트의 저장소 어댑터는 commit이 불리면 예외를 던진다.
//     REST 호출도 GET·runQuery·runAggregationQuery·batchGet만 쓴다.
//   · 서비스키와 액세스 토큰은 메모리에서만 쓰고 출력하지 않는다.
//   · 개인정보는 다루지 않는다(공공 축제 데이터뿐). 출력은 건수 위주다.
//
// 인증: 다른 스크립트와 같이 로컬 gcloud 사용자 자격 증명을 쓴다
//   (`gcloud auth print-access-token`, `gcloud secrets versions access`).
//   Git Bash에서는 gcloud가 죽을 수 있으니 PowerShell에서 실행한다.
//
// 실행:
//   cd functions
//   node scripts/tourFestivalsDryRun.js
//   (선택) --samples=3  : 신규 예정 항목의 id·제목·기간만 몇 건 보여준다
//   (선택) --detail-sample=5 : 상세 보강을 실제 회차 순서대로 앞의 N건만 불러
//          본다(N × 4회 호출, 기본 5, 최대 10, 0이면 상세를 부르지 않는다).
//          나머지 대상은 호출 없이 건수·예상 호출 수만 센다. 결과는 쓰지 않는다.
//
// 호출량: 목록 페이지 수 + 상세 N × 4회. 오늘 호출 기록(tourApiUsage)은 읽기만
// 하고 더하지 않는다 — 이 호출은 예비분(TOUR_DAILY_RESERVE) 몫이다. 개발계정 일일 트래픽(1,000)을 같이
// 쓰므로 하루에 여러 번 돌리지 않는다.

const { execSync } = require('child_process');
const path = require('path');

const tour = require(path.join(__dirname, '..', 'tourFestivals'));

const PROJECT_ID = 'partychu-30c24';
const DOCS = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const GCLOUD_ENV = { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' };

function gcloud(cmd) {
  // stdio: 표준출력은 값으로만 받고 화면에 흘리지 않는다.
  return execSync(`gcloud ${cmd}`, { encoding: 'utf8', env: GCLOUD_ENV, stdio: ['ignore', 'pipe', 'pipe'] })
    .replace(/^﻿/, '')
    .trim();
}

function readServiceKey() {
  let key = '';
  try {
    key = gcloud(`secrets versions access latest --secret=TOUR_API_SERVICE_KEY --project=${PROJECT_ID}`);
  } catch (e) {
    // 오류 메시지에도 키는 실리지 않는다(명령이 실패한 경우라 값이 없다).
    throw new Error(`TOUR_API_SERVICE_KEY를 읽지 못했다 (exit=${e.status})`);
  }
  if (!key) throw new Error('TOUR_API_SERVICE_KEY가 비어 있다');
  return key;
}

// ── Firestore REST (읽기 전용) ──────────────────────────────────────────

async function firestorePost(url, token, body) {
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'x-goog-user-project': PROJECT_ID,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const json = await res.json().catch(() => null);
  if (!res.ok) throw new Error(`Firestore ${url.split('/documents')[1]} -> ${res.status}: ${JSON.stringify(json).slice(0, 300)}`);
  return json;
}

/** REST Value → JS 값. 판정에 필요한 타입만 푼다. */
function decodeValue(v) {
  if (!v || typeof v !== 'object') return null;
  if ('nullValue' in v) return null;
  if ('stringValue' in v) return v.stringValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('timestampValue' in v) return new Date(v.timestampValue);
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(decodeValue);
  if ('mapValue' in v) return decodeFields(v.mapValue.fields || {});
  return null;
}

function decodeFields(fields) {
  const out = {};
  for (const [k, v] of Object.entries(fields || {})) out[k] = decodeValue(v);
  return out;
}

const docIdOf = (name) => name.slice(name.lastIndexOf('/') + 1);

function readOnlyStore(token) {
  return {
    async loadActive() {
      const out = new Map();
      const rows = await firestorePost(`${DOCS}:runQuery`, token, {
        structuredQuery: {
          from: [{ collectionId: tour.COLLECTION }],
          where: {
            compositeFilter: {
              op: 'AND',
              filters: [
                { fieldFilter: { field: { fieldPath: 'source' }, op: 'EQUAL', value: { stringValue: tour.SOURCE } } },
                { fieldFilter: { field: { fieldPath: 'status' }, op: 'EQUAL', value: { stringValue: 'active' } } },
              ],
            },
          },
        },
      });
      for (const r of rows) if (r.document) out.set(docIdOf(r.document.name), decodeFields(r.document.fields));
      return out;
    },
    async loadByIds(ids) {
      const out = new Map();
      for (const part of tour.chunk(ids, 100)) {
        const res = await firestorePost(`${DOCS}:batchGet`, token, {
          documents: part.map((id) => `projects/${PROJECT_ID}/databases/(default)/documents/${tour.COLLECTION}/${id}`),
        });
        for (const r of res) if (r.found) out.set(docIdOf(r.found.name), decodeFields(r.found.fields));
      }
      return out;
    },
    /** 오늘 호출 기록(tourApiUsage/{YYYYMMDD}) — 읽기만. 없으면 0. */
    async loadUsage(day) {
      const res = await fetch(`${DOCS}/${tour.USAGE_COLLECTION}/${day}`, {
        headers: { Authorization: `Bearer ${token}`, 'x-goog-user-project': PROJECT_ID },
      });
      if (res.status === 404) return 0;
      const json = await res.json().catch(() => null);
      if (!res.ok) throw new Error(`Firestore usage -> ${res.status}`);
      const n = Number(decodeValue(json.fields && json.fields.calls));
      return Number.isFinite(n) && n > 0 ? n : 0;
    },
    async commit() {
      throw new Error('dry-run: Firestore 쓰기는 금지돼 있다');
    },
  };
}

async function countByStatus(token) {
  const counts = {};
  const run = async (label, where) => {
    const res = await firestorePost(`${DOCS}:runAggregationQuery`, token, {
      structuredAggregationQuery: {
        structuredQuery: { from: [{ collectionId: tour.COLLECTION }], ...(where ? { where } : {}) },
        aggregations: [{ alias: 'n', count: {} }],
      },
    });
    counts[label] = Number(res[0].result.aggregateFields.n.integerValue);
  };
  await run('total', null);
  for (const status of ['active', 'ended', 'removed']) {
    await run(status, { fieldFilter: { field: { fieldPath: 'status' }, op: 'EQUAL', value: { stringValue: status } } });
  }
  return counts;
}

// ── 실행 ────────────────────────────────────────────────────────────────

async function main() {
  const samplesArg = process.argv.find((a) => a.startsWith('--samples='));
  const samples = samplesArg ? Math.max(0, Math.min(10, Number(samplesArg.split('=')[1]) || 0)) : 0;
  const detailArg = process.argv.find((a) => a.startsWith('--detail-sample='));
  const detailSample = detailArg ? Math.max(0, Math.min(10, Number(detailArg.split('=')[1]) || 0)) : 5;

  const token = gcloud('auth print-access-token');
  let serviceKey = readServiceKey();

  const existing = await countByStatus(token);
  console.log(`[Firestore 읽기] ${tour.COLLECTION} 기존 문서: ${JSON.stringify(existing)}`);

  let pageCalls = 0;
  const detailCalls = {};
  // 실제 HTTP 요청 수(재시도 포함) — 운영 회차와 같은 방식으로 센다.
  const attemptCounter = { n: 0 };
  const deps = { httpGet: (p) => { attemptCounter.n += 1; return tour.httpsGet(p); } };
  const startedAt = Date.now();
  const now = new Date();
  // 신규 예정 샘플을 뽑으려고 원본 항목을 한 번 더 들고 있는다(출력은 건수·제목만).
  const sampleItems = [];
  const summary = await tour.syncTourFestivalsOnce({
    store: readOnlyStore(token),
    fetchPage: async (args) => {
      pageCalls += 1;
      const page = await tour.fetchFestivalPage({ serviceKey, ...args }, deps);
      if (sampleItems.length < 200) sampleItems.push(...page.items.slice(0, 200 - sampleItems.length));
      return page;
    },
    fetchDetail: async (args) => {
      detailCalls[args.operation] = (detailCalls[args.operation] || 0) + 1;
      return tour.fetchDetail({ serviceKey, ...args }, deps);
    },
    detailLimit: detailSample,
    attemptCounter,
    now,
    runId: `dryrun-${now.toISOString()}`,
    dryRun: true,
  });
  serviceKey = null;

  const s = summary.stats;
  console.log(`\n[TourAPI] 조회 기준일 ${summary.queryStartDate} · 페이지 ${summary.pages}회 호출(${pageCalls}) · ${Date.now() - startedAt}ms`);
  console.log(`  totalCount(API)        ${summary.totalCount}`);
  console.log(`  수집 원본 건수          ${summary.fetched}`);
  console.log(`  중복 contentid          ${s.duplicateContentIds}`);
  console.log(`  고유 건수               ${summary.unique}`);
  console.log(`  유효 / skipped·invalid  ${s.valid} / ${s.invalid} ${JSON.stringify(summary.skipped)}`);
  console.log(`  예상 active / ended     ${s.expectedActive} / ${s.expectedEnded}`);
  console.log(`  좌표 없음 / 이미지 없음 ${s.noLocation} / ${s.noImage}`);
  console.log(`  전 페이지 수집 완료     ${summary.complete} (누락 판정 ${summary.countMissing ? '함' : '안 함'})`);
  console.log(`\n[예상 쓰기 — 실제로 쓰지 않음]`);
  console.log(`  기존 active 문서        ${s.existingActiveDocs} (이번 응답과 일치 ${s.existingMatched}, 응답에 없음 ${s.unseenActiveDocs})`);
  console.log(`  신규 생성               ${s.plannedCreate}`);
  console.log(`  본문 변경               ${s.plannedUpdate}`);
  console.log(`  메타만 변경             ${s.plannedMeta} (ended 전환 ${s.plannedEnded}, removed 전환 ${s.plannedRemoved})`);
  console.log(`  이번 회차 쓰기 예정     ${summary.wouldWrite} (한도 초과로 다음 회차 ${summary.deferred}) · 실제 쓰기 ${summary.written}`);

  const d = summary.detail;
  console.log(`
[상세 보강 — 실제로 쓰지 않음]`);
  console.log(`  보강 대상 축제           ${d.targets} (새 문서·보강 없음·modifiedtime 변경, active만)`);
  console.log(`  대상 까닭               ${JSON.stringify(d.targetsByReason)} (보강 구성 v${tour.DETAIL_SCHEMA_VERSION})`);
  const b = d.budget;
  console.log(`  오늘(${b.day}) 호출 예산    한도 ${b.dailyLimit} − 예비 ${b.reserve} − 오늘 기록 ${b.usedBefore} − 목록 ${b.listCalls} = 상세 ${b.detailBudget}회`);
  console.log(`  실제 회차에서 받을 축제    ${d.plannedThisRun}건 (예산으로 가능 ${b.fundableFestivals}건, 최악의 경우 축제당 ${b.worstCasePerFestival}회로 멈춤) · 대상 소진까지 ${d.runsToClearBacklog}회차`);
  console.log(`  실제 회차 예상 호출       ${JSON.stringify(d.plannedCallsThisRun)}`);
  console.log(`  이번 dry-run 표본 호출    ${d.attempted}건 · ${JSON.stringify(detailCalls)} (합계 ${d.totalCalls}) · 실제 HTTP 요청 ${attemptCounter.n}회(목록 포함)`);
  console.log(`  표본 성공 / 실패          ${d.succeeded} / ${d.failed} ${JSON.stringify(d.failures)} 중단: ${d.stoppedBy || '없음'}`);
  for (const p of summary.detailPreview || []) {
    console.log(`    · ${p.id} ${p.title} — 소개 ${p.overviewChars}자 · 프로그램 ${p.programChars}자 · 사진 ${p.images}장 · 홈페이지 ${p.homepageUrl ? 'O' : 'X'} · 주최 ${p.organizer ? 'O' : 'X'} · 주관 ${p.host ? 'O' : 'X'} · 문의처 ${p.contactName ? 'O' : 'X'} · 요금 ${p.feeText ? 'O' : 'X'} · 시간 ${p.playTime ? 'O' : 'X'} · 장소 ${p.eventPlace ? 'O' : 'X'}`);
    console.log(`        v2: 관람연령 ${JSON.stringify(p.ageLimit)} · 소요시간 ${JSON.stringify(p.spendTime)} · 예매 ${JSON.stringify(p.bookingInfo)} / 링크 ${JSON.stringify(p.bookingUrl)} · 할인 ${JSON.stringify(p.discountInfo)} · 부대행사 ${p.subEvent}자 · 위치안내 ${p.placeInfo}자 · 주관전화 ${p.hostTel ? 'O' : 'X'} · 등급 ${JSON.stringify(p.festivalGrade)}`);
    console.log(`        v3: 출연 ${JSON.stringify(p.performers)} · 추가 정보 ${JSON.stringify(p.extraInfo)}`);
  }
  console.log(`
[목록 동기화 영향]`);
  console.log(`  목록 계획(보강과 무관)    ${d.listPlans}건 = 신규 ${s.plannedCreate} + 본문 ${s.plannedUpdate} + 메타 ${s.plannedMeta}`);
  console.log(`  보강이 얹힌 목록 계획     ${d.mergedIntoListPlans}건 · 보강만 쓰는 문서 ${d.detailOnlyWrites}건`);
  console.log(`  계획 종류별 쓰는 필드      ${JSON.stringify(summary.writeKeysByKind || {})}`);
  console.log(`  실제 회차 예상 쓰기 문서   목록 ${d.listPlans} + 보강 최대 ${d.plannedThisRun} (같은 문서면 한 번으로 합쳐짐)`);

  if (samples) {
    console.log(`\n[신규 예정 샘플 ${samples}건]`);
    let shown = 0;
    for (const it of sampleItems) {
      if (shown >= samples) break;
      const n = tour.normalizeFestival(it);
      if (n.skip) continue;
      console.log(`  ${n.id} · ${n.body.title} · ${n.body.startDate}~${n.body.endDate} · 지역 ${n.body.sigunguCode}`);
      shown += 1;
    }
  }
}

main().catch((e) => {
  console.error(`dry-run 실패: ${e.message}`);
  process.exit(1);
});
