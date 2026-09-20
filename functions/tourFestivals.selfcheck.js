// TourAPI 축제 수집 규칙 자체 검증 — `npm run check:tourfestivals`.
//
// 실제 TourAPI도, Firestore도 부르지 않는다. HTTP와 저장소를 가짜로 바꿔
// 끼우고 다음을 못 박는다.
//   1. 날짜·좌표·빈 값 방어(달력에 없는 날짜, 0 좌표, 범위 밖, 빈 제목)
//   2. 응답 파싱(빈 결과 '', 단건 객체, 결과코드 오류, XML 게이트웨이 오류)
//   3. 재시도는 5xx·네트워크만, 4xx·결과코드 오류는 바로 실패
//   4. 페이지네이션과 contentid 중복 제거, 끝까지 못 받으면 complete=false
//   5. API가 실패하면 쓰기 0건, 빈 결과 이상 응답도 쓰기 0건
//   6. 같은 데이터로 두 번 돌리면 두 번째는 쓰기 0건(중복·불필요 쓰기 없음)
//   7. modifiedtime만 바뀌면 메타만, 본문이 바뀌면 본문까지
//   8. 종료 → ended, 연속 누락 → removed, 불완전 회차는 누락을 세지 않음
//   9. 관리자 숨김(adminHidden)은 쓰지 않고, 다시 보여도 숨김 유지
//  10. 배치는 400개 이하로 잘린다
//  11. 서비스키는 로그용 쿼리·오류 메시지에 실리지 않는다
//  12. 2026-09-19 실제 응답 특성: 진행 중 행사 포함(조회 기준일 = 당일),
//      areacode·sigungucode는 빈 값이고 지역은 법정동 코드가 정본,
//      cat1~3·progresstype·festivaltype·mlevel은 저장하지 않는다
//  14. 상세 보강: 3종(Common·Intro·Image)만, 새 문서·modifiedtime 변경 시에만,
//      한 축제라도 실패하면 그 축제만 건너뛰고 기존 보강 보존·다음 회차 재시도,
//      호출량 초과·연속 실패·시간 상한에서 멈춤, 회차당 상한, 목록 본문·해시 불변
//  15. 보강 구성 2: detailIntro2 축제 필드 전부(예매는 원문 + 안전한 링크만 분리),
//      첫 배포분(버전 없음)은 한 번 다시 받되 안 받은 문서 다음, 실패 시 보존
//  16. 보강 구성 3: detailInfo2 — 중복 버림, 빈 program·overview 대체, 출연,
//      그 밖의 줄 extraInfo, 의미 없는 값 버림
//  17. 호출 예산: 한도 − 예비 − 오늘 쓴 것 − 목록 안에서 최대한, 최악의 재시도도
//      넘지 않음, 실제 요청 수를 일일 기록(tourApiUsage)에 더함

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'selfcheck';

const assert = require('assert');
const t = require('./tourFestivals');

const results = [];
async function check(name, fn) {
  try {
    await fn();
    results.push(['ok', name]);
  } catch (e) {
    results.push(['FAIL', name, e]);
  }
}

// ── 가짜들 ─────────────────────────────────────────────────────────────

function item(overrides = {}) {
  return {
    contentid: '1000001',
    contenttypeid: '15',
    title: '  서울 빛 축제  ',
    addr1: '서울특별시 중구 세종대로 110',
    addr2: '',
    zipcode: '04524',
    tel: '02-000-0000',
    // v2 실제 응답처럼 areacode·sigungucode는 비어 오고 법정동 코드만 온다.
    areacode: '',
    sigungucode: '',
    lDongRegnCd: '11',
    lDongSignguCd: '140',
    lclsSystm1: 'EV',
    lclsSystm2: 'EV01',
    lclsSystm3: 'EV010100',
    cat1: '',
    cat2: '',
    cat3: '',
    mlevel: '',
    progresstype: '선택안함',
    festivaltype: '',
    mapx: '126.9779692',
    mapy: '37.566535',
    eventstartdate: '20260910',
    eventenddate: '20261010',
    firstimage: 'http://tong.visitkorea.or.kr/cms/resource/1.jpg',
    firstimage2: 'http://tong.visitkorea.or.kr/cms/resource/1_s.jpg',
    cpyrhtDivCd: 'Type3',
    createdtime: '20260801090000',
    modifiedtime: '20260901090000',
    ...overrides,
  };
}

function okBody(items, { totalCount = items.length, pageNo = 1 } = {}) {
  return JSON.stringify({
    response: {
      header: { resultCode: '0000', resultMsg: 'OK' },
      body: {
        items: items.length ? { item: items } : '',
        numOfRows: t.PAGE_SIZE,
        pageNo,
        totalCount,
      },
    },
  });
}

/** 항목 목록을 PAGE_SIZE로 잘라 페이지를 돌려주는 가짜 fetchPage. */
function pagedFetcher(allItems, { failOnPage = null, totalCount = allItems.length } = {}) {
  const calls = [];
  const fn = async ({ pageNo, eventStartDate }) => {
    calls.push({ pageNo, eventStartDate });
    if (pageNo === failOnPage) throw new Error('boom');
    const start = (pageNo - 1) * t.PAGE_SIZE;
    return {
      ok: true,
      items: allItems.slice(start, start + t.PAGE_SIZE),
      totalCount,
      pageNo,
      numOfRows: t.PAGE_SIZE,
    };
  };
  fn.calls = calls;
  return fn;
}

/** 메모리 저장소. commit은 Firestore set/merge를 흉내 낸다. usage는 일일 호출 기록. */
function memoryStore(initial = {}, usageInit = {}) {
  const docs = new Map(Object.entries(initial).map(([k, v]) => [k, { ...v }]));
  const commits = [];
  const usage = new Map(Object.entries(usageInit));
  const usageWrites = [];
  return {
    docs,
    commits,
    usage,
    usageWrites,
    async loadUsage(day) {
      return usage.get(day) || 0;
    },
    async addUsage(day, calls) {
      usageWrites.push({ day, calls });
      usage.set(day, (usage.get(day) || 0) + calls);
    },
    async loadActive() {
      const out = new Map();
      for (const [id, d] of docs) {
        if (d.source === t.SOURCE && d.status === 'active') out.set(id, { ...d });
      }
      return out;
    },
    async loadByIds(ids) {
      const out = new Map();
      for (const id of ids) if (docs.has(id)) out.set(id, { ...docs.get(id) });
      return out;
    },
    async commit(plans) {
      commits.push(plans.map((p) => ({ id: p.id, kind: p.kind, keys: Object.keys(p.data) })));
      for (const p of plans) {
        if (p.kind === 'create') docs.set(p.id, { ...p.data });
        else docs.set(p.id, { ...(docs.get(p.id) || {}), ...p.data });
      }
      return plans.length;
    },
  };
}

const NOW = new Date('2026-09-19T01:00:00Z'); // 한국 시각 2026-09-19 10:00

(async () => {
  // ── 1. 값 방어 ───────────────────────────────────────────────────────
  await check('날짜: 정상·달력에 없는 날짜·형식 오류', () => {
    assert.deepStrictEqual(t.parseTourDate('20260919'), { y: 2026, m: 9, d: 19, key: '20260919' });
    assert.strictEqual(t.parseTourDate('20260231'), null);
    assert.strictEqual(t.parseTourDate('2026-09-19'), null);
    assert.strictEqual(t.parseTourDate(''), null);
    assert.strictEqual(t.parseTourDate(null), null);
    assert.strictEqual(t.parseTourDate('20261301'), null);
    assert.ok(t.parseTourDate(20260919)); // 숫자로 와도 받는다
  });

  await check('날짜: KST 하루 경계로 저장된다', () => {
    const d = t.parseTourDate('20260919');
    assert.strictEqual(t.kstDayStart(d).toISOString(), '2026-09-18T15:00:00.000Z');
    assert.strictEqual(t.kstDayEnd(d).toISOString(), '2026-09-19T14:59:59.999Z');
    assert.strictEqual(t.kstDateKey(new Date('2026-09-18T15:00:00Z')), '20260919');
    assert.strictEqual(t.kstDateKey(new Date('2026-09-18T14:59:59Z')), '20260918');
    assert.strictEqual(
      t.parseTourDateTime('20260901090000').toISOString(),
      '2026-09-01T00:00:00.000Z',
    );
    assert.strictEqual(t.parseTourDateTime('20260901250000'), null);
  });

  await check('좌표: 0·빈 값·범위 밖·숫자 아님은 null', () => {
    assert.deepStrictEqual(t.parseCoordinates('126.9779692', '37.566535'), { lat: 37.566535, lng: 126.9779692 });
    assert.strictEqual(t.parseCoordinates('0', '0'), null);
    assert.strictEqual(t.parseCoordinates('', '37.5'), null);
    assert.strictEqual(t.parseCoordinates('abc', '37.5'), null);
    assert.strictEqual(t.parseCoordinates('139.69', '35.68'), null); // 도쿄
    // 위경도를 뒤바꿔 넣은 값도 범위 밖이라 걸러진다.
    assert.strictEqual(t.parseCoordinates('37.566535', '126.9779692'), null);
  });

  await check('이미지: http(s)만, 관광공사 http는 https로', () => {
    assert.strictEqual(
      t.cleanImageUrl('http://tong.visitkorea.or.kr/a.jpg'),
      'https://tong.visitkorea.or.kr/a.jpg',
    );
    assert.strictEqual(t.cleanImageUrl('https://example.com/a.jpg'), 'https://example.com/a.jpg');
    assert.strictEqual(t.cleanImageUrl('javascript:alert(1)'), null);
    assert.strictEqual(t.cleanImageUrl('not a url'), null);
    assert.strictEqual(t.cleanImageUrl(''), null);
  });

  await check('normalize: 정상 항목의 본문', () => {
    const n = t.normalizeFestival(item());
    assert.strictEqual(n.id, 'tour_1000001');
    assert.strictEqual(n.body.source, 'tourapi');
    assert.strictEqual(n.body.sourceId, '1000001');
    assert.strictEqual(n.body.title, '서울 빛 축제');
    assert.strictEqual(n.body.addressDetail, null); // 빈 문자열 → null
    assert.strictEqual(n.body.startDate, '20260910');
    assert.strictEqual(n.body.endDate, '20261010');
    assert.ok(n.body.startAt instanceof Date && n.body.endAt instanceof Date);
    assert.deepStrictEqual(n.body.location, { lat: 37.566535, lng: 126.9779692 });
    assert.strictEqual(n.body.attribution, '한국관광공사');
    assert.strictEqual(n.sourceModifiedTime, '20260901090000');
    assert.ok(!('status' in n.body), '상태는 본문(해시 대상)에 넣지 않는다');
  });

  await check('normalize: 건너뛸 항목과 이유', () => {
    assert.strictEqual(t.normalizeFestival(null).skip, 'not-object');
    assert.strictEqual(t.normalizeFestival(item({ contentid: '' })).skip, 'bad-contentid');
    assert.strictEqual(t.normalizeFestival(item({ contentid: '12a' })).skip, 'bad-contentid');
    assert.strictEqual(t.normalizeFestival(item({ title: '   ' })).skip, 'no-title');
    assert.strictEqual(
      t.normalizeFestival(item({ eventstartdate: '', eventenddate: 'x' })).skip,
      'no-dates',
    );
    assert.strictEqual(
      t.normalizeFestival(item({ eventstartdate: '20261010', eventenddate: '20261001' })).skip,
      'end-before-start',
    );
  });

  await check('normalize: 날짜 한쪽만 있으면 하루짜리, 좌표 없으면 location null', () => {
    const a = t.normalizeFestival(item({ eventenddate: '' }));
    assert.strictEqual(a.body.endDate, '20260910');
    const b = t.normalizeFestival(item({ eventstartdate: '', eventenddate: '20260915' }));
    assert.strictEqual(b.body.startDate, '20260915');
    const c = t.normalizeFestival(item({ mapx: '0', mapy: '0' }));
    assert.strictEqual(c.body.location, null);
    assert.ok(!c.skip, '좌표가 없어도 항목은 저장한다');
  });

  // ── 2. 응답 파싱 ─────────────────────────────────────────────────────
  await check('파싱: 배열·단건 객체·빈 결과', () => {
    const many = t.parseFestivalResponse(okBody([item(), item({ contentid: '2' })], { totalCount: 2 }));
    assert.strictEqual(many.ok, true);
    assert.strictEqual(many.items.length, 2);
    assert.strictEqual(many.totalCount, 2);

    const single = t.parseFestivalResponse(JSON.stringify({
      response: {
        header: { resultCode: '0000' },
        body: { items: { item: item() }, totalCount: 1, pageNo: 1, numOfRows: 100 },
      },
    }));
    assert.strictEqual(single.items.length, 1);

    const empty = t.parseFestivalResponse(okBody([], { totalCount: 0 }));
    assert.strictEqual(empty.ok, true);
    assert.deepStrictEqual(empty.items, []);
    assert.strictEqual(empty.totalCount, 0);
  });

  await check('파싱: 결과코드 오류·XML 게이트웨이 오류·헤더 없음', () => {
    const bad = t.parseFestivalResponse(JSON.stringify({
      response: { header: { resultCode: '10', resultMsg: 'INVALID_REQUEST_PARAMETER_ERROR' } },
    }));
    assert.deepStrictEqual([bad.ok, bad.code], [false, '10']);

    const xml = t.parseFestivalResponse(
      '<OpenAPI_ServiceResponse><cmmMsgHeader><errMsg>SERVICE ERROR</errMsg>'
      + '<returnAuthMsg>SERVICE_KEY_IS_NOT_REGISTERED_ERROR</returnAuthMsg>'
      + '<returnReasonCode>30</returnReasonCode></cmmMsgHeader></OpenAPI_ServiceResponse>',
    );
    assert.deepStrictEqual(
      [xml.ok, xml.code, xml.message],
      [false, '30', 'SERVICE_KEY_IS_NOT_REGISTERED_ERROR'],
    );

    const noHeader = t.parseFestivalResponse('{"foo":1}');
    assert.strictEqual(noHeader.ok, false);
    assert.strictEqual(t.parseFestivalResponse('<html>502</html>').ok, false);
  });

  // ── 3. 키 인코딩·재시도 ──────────────────────────────────────────────
  await check('서비스키: 디코딩 키는 인코딩, 인코딩 키는 그대로', () => {
    assert.strictEqual(t.encodeServiceKey('ab+c/d=='), 'ab%2Bc%2Fd%3D%3D');
    assert.strictEqual(t.encodeServiceKey('ab%2Bc%2Fd%3D%3D'), 'ab%2Bc%2Fd%3D%3D');
    const q = t.buildFestivalQuery({ pageNo: 3, eventStartDate: '20260721' });
    assert.ok(!q.includes('serviceKey'), '로그용 쿼리에는 키가 없다');
    assert.ok(q.includes('pageNo=3') && q.includes('eventStartDate=20260721') && q.includes('_type=json'));
    assert.ok(q.includes('MobileOS=ETC') && q.includes('MobileApp=Partychu'));
    const path = t.buildFestivalPath('SECRET+KEY', q);
    assert.ok(path.startsWith('/B551011/KorService2/searchFestival2?serviceKey=SECRET%2BKEY&'));
  });

  const noSleep = async () => {};

  await check('재시도: 5xx 두 번 뒤 성공', async () => {
    let n = 0;
    const res = await t.fetchFestivalPage(
      { serviceKey: 'K', pageNo: 1, eventStartDate: '20260721' },
      {
        sleep: noSleep,
        httpGet: async () => {
          n += 1;
          return n < 3 ? { statusCode: 503, raw: '', elapsedMs: 1 } : { statusCode: 200, raw: okBody([item()]), elapsedMs: 1 };
        },
      },
    );
    assert.strictEqual(n, 3);
    assert.strictEqual(res.items.length, 1);
  });

  await check('재시도: 네트워크 예외도 재시도, 끝내 실패하면 예외', async () => {
    let n = 0;
    await assert.rejects(
      t.fetchFestivalPage(
        { serviceKey: 'SECRETKEY', pageNo: 2, eventStartDate: '20260721' },
        { sleep: noSleep, httpGet: async () => { n += 1; throw new Error('ECONNRESET'); } },
      ),
      (err) => !String(err.message).includes('SECRETKEY'),
    );
    assert.strictEqual(n, 3);
  });

  await check('재시도: 4xx·결과코드 오류는 한 번만 부르고 실패, 키는 메시지에 없다', async () => {
    let n = 0;
    await assert.rejects(
      t.fetchFestivalPage(
        { serviceKey: 'SECRETKEY', pageNo: 1, eventStartDate: '20260721' },
        { sleep: noSleep, httpGet: async () => { n += 1; return { statusCode: 401, raw: '', elapsedMs: 1 }; } },
      ),
      (err) => !String(err.message).includes('SECRETKEY'),
    );
    assert.strictEqual(n, 1);

    n = 0;
    await assert.rejects(
      t.fetchFestivalPage(
        { serviceKey: 'SECRETKEY', pageNo: 1, eventStartDate: '20260721' },
        {
          sleep: noSleep,
          httpGet: async () => {
            n += 1;
            return { statusCode: 200, raw: '<returnReasonCode>22</returnReasonCode>', elapsedMs: 1 };
          },
        },
      ),
      (err) => /code=22/.test(err.message) && !err.message.includes('SECRETKEY'),
    );
    assert.strictEqual(n, 1, '호출량 초과(22)는 재시도하지 않는다');
  });

  // ── 4. 페이지네이션 ──────────────────────────────────────────────────
  const many = (count, from = 1) =>
    Array.from({ length: count }, (_, i) => item({ contentid: String(from + i), title: `축제 ${from + i}` }));

  await check('페이지: 250건을 3페이지로 모두 받는다', async () => {
    const f = pagedFetcher(many(250));
    const r = await t.fetchAllFestivals({ eventStartDate: '20260721', fetchPage: f });
    assert.strictEqual(f.calls.length, 3);
    assert.strictEqual(r.items.length, 250);
    assert.strictEqual(r.complete, true);
  });

  await check('페이지: 딱 100건이면 빈 페이지를 더 부르지 않는다', async () => {
    const f = pagedFetcher(many(100));
    const r = await t.fetchAllFestivals({ eventStartDate: '20260721', fetchPage: f });
    assert.strictEqual(f.calls.length, 1);
    assert.strictEqual(r.complete, true);
  });

  await check('페이지: 같은 contentid가 두 페이지에 걸쳐 오면 하나로', async () => {
    const list = many(150);
    list[120] = item({ contentid: '5', title: '중복' });
    const f = pagedFetcher(list);
    const r = await t.fetchAllFestivals({ eventStartDate: '20260721', fetchPage: f });
    assert.strictEqual(r.rawCount, 150);
    assert.strictEqual(r.items.length, 149);
  });

  await check('페이지: 한도에 걸리면 complete=false, 한 페이지 실패는 예외', async () => {
    const r = await t.fetchAllFestivals({
      eventStartDate: '20260721',
      fetchPage: pagedFetcher(many(350)),
      maxPages: 2,
    });
    assert.strictEqual(r.complete, false);
    await assert.rejects(t.fetchAllFestivals({
      eventStartDate: '20260721',
      fetchPage: pagedFetcher(many(250), { failOnPage: 2 }),
    }));
  });

  await check('페이지: totalCount보다 적게 오면 complete=false', async () => {
    const r = await t.fetchAllFestivals({
      eventStartDate: '20260721',
      fetchPage: pagedFetcher(many(50), { totalCount: 80 }),
    });
    assert.strictEqual(r.complete, false);
  });

  await check('조회 기준일은 실행 당일 한국 날짜', async () => {
    const f = pagedFetcher([]);
    await t.syncTourFestivalsOnce({ store: memoryStore(), fetchPage: f, now: NOW });
    assert.strictEqual(f.calls[0].eventStartDate, '20260919');
    // UTC로는 전날이지만 한국은 이미 다음 날인 시각(KST 00:30).
    const g = pagedFetcher([]);
    await t.syncTourFestivalsOnce({
      store: memoryStore(),
      fetchPage: g,
      now: new Date('2026-09-19T15:30:00Z'),
    });
    assert.strictEqual(g.calls[0].eventStartDate, '20260920');
    assert.ok(!('LOOKBACK_DAYS' in t), '앞당겨 조회하는 설정은 없어졌다');
  });

  // ── 5·6. 실패 시 무변경, 중복·불필요 쓰기 없음 ──────────────────────
  await check('API 실패: 기존 문서가 있어도 쓰기 0건', async () => {
    const store = memoryStore();
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(10)), now: NOW });
    const before = JSON.stringify([...store.docs]);
    const commitsBefore = store.commits.length;
    await assert.rejects(t.syncTourFestivalsOnce({
      store,
      fetchPage: pagedFetcher(many(250), { failOnPage: 3 }),
      now: NOW,
    }));
    assert.strictEqual(store.commits.length, commitsBefore);
    assert.strictEqual(JSON.stringify([...store.docs]), before);
  });

  await check('빈 결과 이상 응답: active가 많으면 멈추고 쓰기 0건', async () => {
    const store = memoryStore();
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(t.EMPTY_RESULT_GUARD)), now: NOW });
    const commitsBefore = store.commits.length;
    await assert.rejects(
      t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher([]), now: NOW }),
      /0건/,
    );
    assert.strictEqual(store.commits.length, commitsBefore);
  });

  await check('첫 회차 생성, 같은 데이터 두 번째 회차는 쓰기 0건', async () => {
    const store = memoryStore();
    const list = [...many(3), item({ contentid: 'x' }), item({ contentid: '9', title: '' })];
    const first = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(list), now: NOW });
    assert.strictEqual(first.created, 3);
    assert.deepStrictEqual(first.skipped, { 'bad-contentid': 1, 'no-title': 1 });
    assert.deepStrictEqual([...store.docs.keys()].sort(), ['tour_1', 'tour_2', 'tour_3']);
    const doc = store.docs.get('tour_1');
    assert.strictEqual(doc.status, 'active');
    assert.strictEqual(doc.isVisible, true);
    assert.strictEqual(doc.missingCount, 0);
    assert.ok(doc.contentHash && doc.schemaVersion === 1);

    const second = await t.syncTourFestivalsOnce({
      store,
      fetchPage: pagedFetcher(list),
      now: new Date(NOW.getTime() + 3600e3),
    });
    assert.strictEqual(second.written, 0);
    assert.strictEqual(store.docs.size, 3);
  });

  // ── 7. 수정 추적 ─────────────────────────────────────────────────────
  await check('modifiedtime만 바뀌면 메타만, 본문이 바뀌면 본문까지', async () => {
    const store = memoryStore();
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher([item()]), now: NOW });
    const createdAt = store.docs.get('tour_1000001').createdAt;

    const metaRun = await t.syncTourFestivalsOnce({
      store,
      fetchPage: pagedFetcher([item({ modifiedtime: '20260915090000' })]),
      now: NOW,
    });
    assert.strictEqual(metaRun.meta, 1);
    assert.strictEqual(metaRun.updated, 0);
    const metaKeys = store.commits[store.commits.length - 1][0].keys;
    assert.ok(!metaKeys.includes('title'), '메타 갱신은 본문을 다시 쓰지 않는다');
    assert.strictEqual(store.docs.get('tour_1000001').sourceModifiedTime, '20260915090000');

    const bodyRun = await t.syncTourFestivalsOnce({
      store,
      fetchPage: pagedFetcher([item({ title: '서울 빛 축제 2026', modifiedtime: '20260916090000' })]),
      now: NOW,
    });
    assert.strictEqual(bodyRun.updated, 1);
    const doc = store.docs.get('tour_1000001');
    assert.strictEqual(doc.title, '서울 빛 축제 2026');
    assert.strictEqual(doc.createdAt, createdAt, 'createdAt은 유지된다');
  });

  await check('SCHEMA_VERSION이 해시에 들어간다(매핑 변경 시 재작성)', () => {
    const n = t.normalizeFestival(item());
    assert.strictEqual(t.contentHash(n.body), t.contentHash(t.normalizeFestival(item()).body));
    assert.notStrictEqual(
      t.contentHash(n.body),
      t.contentHash({ ...n.body, title: 'x' }),
    );
  });

  // ── 8. 종료·누락·삭제 ────────────────────────────────────────────────
  await check('종료일이 지나면 ended, 응답에 있든 없든', async () => {
    const store = memoryStore();
    const ending = item({ contentid: '7', eventstartdate: '20260801', eventenddate: '20260920' });
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher([ending, item({ contentid: '8' })]), now: NOW });
    assert.strictEqual(store.docs.get('tour_7').status, 'active');

    const later = new Date('2026-09-21T01:00:00Z');
    // 7은 응답에서 빠졌다.
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher([item({ contentid: '8' })]), now: later });
    assert.strictEqual(store.docs.get('tour_7').status, 'ended');
    assert.strictEqual(store.docs.get('tour_7').isVisible, false);

    // 응답에 계속 오는 항목도 기간이 지나면 ended.
    const s2 = memoryStore();
    await t.syncTourFestivalsOnce({ store: s2, fetchPage: pagedFetcher([ending]), now: NOW });
    await t.syncTourFestivalsOnce({ store: s2, fetchPage: pagedFetcher([ending]), now: later });
    assert.strictEqual(s2.docs.get('tour_7').status, 'ended');
  });

  await check('연속 누락 3회에 removed, 중간에 다시 오면 카운트 초기화', async () => {
    const store = memoryStore();
    const base = many(10);
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(base), now: NOW });
    const without1 = base.slice(1);

    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(without1), now: NOW });
    assert.strictEqual(store.docs.get('tour_1').missingCount, 1);
    assert.strictEqual(store.docs.get('tour_1').status, 'active');

    // 다시 나타남 → 초기화
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(base), now: NOW });
    assert.strictEqual(store.docs.get('tour_1').missingCount, 0);

    for (let i = 0; i < t.MISSING_RUNS_TO_REMOVE; i += 1) {
      await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(without1), now: NOW });
    }
    const d = store.docs.get('tour_1');
    assert.strictEqual(d.status, 'removed');
    assert.strictEqual(d.isVisible, false);
    assert.ok(store.docs.has('tour_1'), '문서를 지우지는 않는다');

    // removed 뒤 원본에 다시 나타나면 active로 돌아온다(새 문서가 생기지 않는다).
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(base), now: NOW });
    assert.strictEqual(store.docs.get('tour_1').status, 'active');
    assert.strictEqual(store.docs.get('tour_1').isVisible, true);
    assert.strictEqual(store.docs.size, 10);
  });

  await check('불완전 회차·대량 누락 회차는 누락을 세지 않는다', async () => {
    const store = memoryStore();
    const base = many(10);
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(base), now: NOW });

    // totalCount가 더 크다 = 끝까지 못 받았다.
    const partial = await t.syncTourFestivalsOnce({
      store,
      fetchPage: pagedFetcher(base.slice(1), { totalCount: 50 }),
      now: NOW,
    });
    assert.strictEqual(partial.countMissing, false);
    assert.strictEqual(store.docs.get('tour_1').missingCount, 0);

    // 절반이 한꺼번에 빠졌다 = 원본 이상으로 본다.
    const bulk = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(base.slice(5)), now: NOW });
    assert.strictEqual(bulk.countMissing, false);
    assert.strictEqual(store.docs.get('tour_1').missingCount, 0);

  });

  await check('누락 판정: 종료일 ≥ 기준일인 active만 센다(시작일은 보지 않는다)', () => {
    const opts = { now: NOW, runId: 'r', queryStartDate: '20260919', countMissing: true };
    // 오래전에 시작한 장기 축제 — API가 진행 중인 행사도 주므로 빠지면 누락이다.
    const longRunning = t.planUnseen(
      { startDate: '20260101', endDate: '20261231', endAt: new Date('2026-12-31T14:59:59.999Z'), status: 'active', missingCount: 0 },
      'tour_long',
      opts,
    );
    assert.deepStrictEqual([longRunning.kind, longRunning.data.missingCount], ['meta', 1]);

    // 기준일 당일에 끝나는 행사도 응답에 와야 한다(종료일 = 기준일).
    const endsToday = t.planUnseen(
      { startDate: '20260915', endDate: '20260919', endAt: new Date('2026-09-19T14:59:59.999Z'), status: 'active', missingCount: 2 },
      'tour_today',
      opts,
    );
    assert.strictEqual(endsToday.data.status, 'removed');

    // 종료일 정보가 없는(형식이 깨진) 문서는 근거가 없어 세지 않는다.
    const noEnd = t.planUnseen(
      { startDate: '20260915', endDate: '', endAt: null, status: 'active', missingCount: 0 },
      'tour_noend',
      opts,
    );
    assert.strictEqual(noEnd.kind, 'none');

    // 종료일이 기준일보다 앞서면(= 이미 끝남) 누락이 아니라 ended다.
    const past = t.planUnseen(
      { startDate: '20260901', endDate: '20260918', endAt: new Date('2026-09-18T14:59:59.999Z'), status: 'active', missingCount: 0 },
      'tour_past',
      opts,
    );
    assert.strictEqual(past.data.status, 'ended');
    assert.ok(!('missingCount' in past.data));

    // 불완전 회차면 장기 축제도 세지 않는다.
    const incomplete = t.planUnseen(
      { startDate: '20260101', endDate: '20261231', endAt: new Date('2026-12-31T14:59:59.999Z'), status: 'active', missingCount: 0 },
      'tour_long',
      { ...opts, countMissing: false },
    );
    assert.strictEqual(incomplete.kind, 'none');
  });

  await check('동기화: 진행 중 장기 축제가 응답에서 빠지면 3회차에 removed', async () => {
    const store = memoryStore();
    const long = item({ contentid: '77', eventstartdate: '20260101', eventenddate: '20261231' });
    const others = many(9, 100);
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher([long, ...others]), now: NOW });
    assert.strictEqual(store.docs.get('tour_77').status, 'active', '기준일보다 먼저 시작해도 저장된다');
    for (let i = 0; i < t.MISSING_RUNS_TO_REMOVE; i += 1) {
      await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(others), now: NOW });
    }
    assert.strictEqual(store.docs.get('tour_77').status, 'removed');
  });

  // ── 12. 실제 응답 특성(2026-09-19 실측) ─────────────────────────────
  // 실측 1페이지의 한 건을 그대로 옮겼다(모든 값이 문자열, 빈 값은 '').
  const realSample = {
    addr1: '울산광역시 남구 대공원로 94 (옥동)',
    addr2: '',
    zipcode: '44660',
    cat1: '',
    cat2: '',
    cat3: '',
    contentid: '4090201',
    contenttypeid: '15',
    createdtime: '20260721133956',
    eventstartdate: '20260729',
    eventenddate: '20260829',
    firstimage: 'https://tong.visitkorea.or.kr/cms/resource/02/4090202_image2_1.jpg',
    firstimage2: 'https://tong.visitkorea.or.kr/cms/resource/02/4090202_image3_1.jpg',
    cpyrhtDivCd: 'Type3',
    mapx: '129.2938457635',
    mapy: '35.5310582726',
    mlevel: '',
    modifiedtime: '20260722161226',
    areacode: '',
    sigungucode: '',
    tel: '052-255-1823',
    title: '가든 나이트 마켓',
    lDongRegnCd: '31',
    lDongSignguCd: '140',
    lclsSystm1: 'EV',
    lclsSystm2: 'EV03',
    lclsSystm3: 'EV030400',
    progresstype: '선택안함',
    festivaltype: '',
  };

  await check('실측 항목: 매핑 결과', () => {
    const n = t.normalizeFestival(realSample);
    assert.strictEqual(n.id, 'tour_4090201');
    assert.strictEqual(n.body.regionCode, '31');
    assert.strictEqual(n.body.sigunguCode, '31140');
    assert.deepStrictEqual(n.body.location, { lat: 35.5310583, lng: 129.2938458 });
    assert.strictEqual(n.body.startAt.toISOString(), '2026-07-28T15:00:00.000Z');
    assert.strictEqual(n.body.endAt.toISOString(), '2026-08-29T14:59:59.999Z');
    assert.strictEqual(n.body.imageUrl, realSample.firstimage);
    assert.strictEqual(n.body.thumbnailUrl, realSample.firstimage2);
    assert.strictEqual(n.body.addressDetail, null);
    assert.deepStrictEqual(n.body.categoryCodes, ['EV', 'EV03', 'EV030400']);
    assert.strictEqual(n.body.copyrightType, 'Type3');
    assert.strictEqual(n.sourceModifiedTime, '20260722161226');
  });

  await check('실측 항목: 저장 필드 목록이 정확히 이것뿐이다', () => {
    const n = t.normalizeFestival(realSample);
    assert.deepStrictEqual(Object.keys(n.body).sort(), [
      'address', 'addressDetail', 'attribution', 'categoryCodes', 'contentTypeId',
      'copyrightType', 'endAt', 'endDate', 'imageUrl', 'location', 'regionCode',
      'sigunguCode', 'source', 'sourceCreatedTime', 'sourceId', 'sourceType',
      'startAt', 'startDate', 'tel', 'thumbnailUrl', 'title', 'zipcode',
    ]);
    for (const dropped of [
      'areaCode', 'legalDongRegionCode', 'legalDongSigunguCode',
      'cat1', 'cat2', 'cat3', 'progresstype', 'progressType',
      'festivaltype', 'festivalType', 'mlevel',
    ]) {
      assert.ok(!(dropped in n.body), dropped + '는 저장하지 않는다');
    }
  });

  await check('지역 코드: 법정동 코드가 정본, 형식 방어', () => {
    assert.deepStrictEqual(t.regionCodes('11', '200'), { regionCode: '11', sigunguCode: '11200' });
    assert.deepStrictEqual(t.regionCodes('48', '250'), { regionCode: '48', sigunguCode: '48250' });
    // 시군구 3자리는 시도마다 겹친다 — 5자리 조합으로만 구분된다.
    assert.notStrictEqual(t.regionCodes('31', '140').sigunguCode, t.regionCodes('11', '140').sigunguCode);
    assert.deepStrictEqual(t.regionCodes('', ''), { regionCode: null, sigunguCode: null });
    assert.deepStrictEqual(t.regionCodes('11', ''), { regionCode: '11', sigunguCode: null });
    assert.deepStrictEqual(t.regionCodes('', '200'), { regionCode: null, sigunguCode: null });
    assert.deepStrictEqual(t.regionCodes('1', '20'), { regionCode: '01', sigunguCode: '01020' });
    assert.deepStrictEqual(t.regionCodes('111', '2000'), { regionCode: null, sigunguCode: null });
    assert.deepStrictEqual(t.regionCodes('서울', 'x'), { regionCode: null, sigunguCode: null });
    assert.deepStrictEqual(t.regionCodes(11, 200), { regionCode: '11', sigunguCode: '11200' });
    // areacode·sigungucode에 값이 와도 쓰지 않는다.
    const n = t.normalizeFestival(item({ areacode: '1', sigungucode: '24', lDongRegnCd: '', lDongSignguCd: '' }));
    assert.deepStrictEqual([n.body.regionCode, n.body.sigunguCode], [null, null]);
  });

  await check('실측 응답 모양: 429건을 5페이지로 받고 파싱', async () => {
    const all = Array.from({ length: 429 }, (_, i) => ({ ...realSample, contentid: String(4000000 + i) }));
    let calls = 0;
    const fetchPage = async ({ pageNo }) => {
      calls += 1;
      const start = (pageNo - 1) * t.PAGE_SIZE;
      const raw = JSON.stringify({
        response: {
          header: { resultCode: '0000', resultMsg: 'OK' },
          body: {
            items: { item: all.slice(start, start + t.PAGE_SIZE) },
            numOfRows: t.PAGE_SIZE,
            pageNo,
            totalCount: 429,
          },
        },
      });
      return t.parseFestivalResponse(raw);
    };
    const r = await t.fetchAllFestivals({ eventStartDate: '20260919', fetchPage });
    assert.strictEqual(calls, 5);
    assert.strictEqual(r.items.length, 429);
    assert.strictEqual(r.complete, true);
  });

  await check('이미 끝난 행사가 응답에 섞여 와도 ended로만 저장된다', async () => {
    // 기준일을 당일로 하면 오지 않아야 하지만, 오더라도 노출되지 않아야 한다.
    const store = memoryStore();
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher([realSample]), now: NOW });
    const d = store.docs.get('tour_4090201');
    assert.strictEqual(d.status, 'ended');
    assert.strictEqual(d.isVisible, false);
  });

  // ── 13. dry-run ──────────────────────────────────────────────────────
  await check('dry-run: commit을 부르지 않고 예상 건수만 돌려준다', async () => {
    const store = memoryStore();
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(5)), now: NOW });
    let commitCalls = 0;
    const guarded = { ...store, commit: async () => { commitCalls += 1; throw new Error('write'); } };
    const list = [
      ...many(5),
      ...many(3, 50),
      item({ contentid: '1', title: '중복' }),
      item({ contentid: '60', mapx: '0', mapy: '0', firstimage: '' }),
      item({ contentid: '61', eventstartdate: '20260901', eventenddate: '20260910' }),
      item({ contentid: '', title: '잘못된 id' }),
    ];
    list[0] = item({ contentid: '1', title: '제목 바뀜', modifiedtime: '20260918000000' });
    const r = await t.syncTourFestivalsOnce({ store: guarded, fetchPage: pagedFetcher(list), now: NOW, dryRun: true });
    assert.strictEqual(commitCalls, 0);
    assert.strictEqual(r.dryRun, true);
    assert.strictEqual(r.written, 0);
    assert.strictEqual(r.stats.duplicateContentIds, 1);
    assert.strictEqual(r.stats.invalid, 1);
    assert.strictEqual(r.stats.valid, 10);
    assert.strictEqual(r.stats.expectedEnded, 1);
    assert.strictEqual(r.stats.expectedActive, 9);
    assert.strictEqual(r.stats.noLocation, 1);
    assert.strictEqual(r.stats.noImage, 1);
    assert.strictEqual(r.stats.existingActiveDocs, 5);
    assert.strictEqual(r.stats.existingMatched, 5);
    assert.strictEqual(r.stats.plannedCreate, 5);
    assert.strictEqual(r.stats.plannedUpdate, 1);
    assert.strictEqual(r.wouldWrite, 6);
    assert.strictEqual(store.docs.size, 5, '저장소는 그대로다');
  });

  // ── 9. 관리자 숨김 ───────────────────────────────────────────────────
  await check('adminHidden은 쓰지 않고 다시 보여도 숨김 유지', async () => {
    const store = memoryStore();
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher([item()]), now: NOW });
    const d = store.docs.get('tour_1000001');
    d.adminHidden = true;
    d.isVisible = false;

    await t.syncTourFestivalsOnce({
      store,
      fetchPage: pagedFetcher([item({ title: '제목 변경', modifiedtime: '20260917000000' })]),
      now: NOW,
    });
    const after = store.docs.get('tour_1000001');
    assert.strictEqual(after.adminHidden, true);
    assert.strictEqual(after.isVisible, false);
    assert.strictEqual(after.title, '제목 변경');
    for (const c of store.commits) {
      for (const p of c) assert.ok(!p.keys.includes('adminHidden'));
    }
  });

  // ── 10. 배치 한도 ────────────────────────────────────────────────────
  await check('배치는 400개 이하, 한 회차 쓰기 상한', async () => {
    assert.ok(t.BATCH_SIZE <= 500);
    const parts = t.chunk(Array.from({ length: 1001 }, (_, i) => i), t.BATCH_SIZE);
    assert.deepStrictEqual(parts.map((p) => p.length), [400, 400, 201]);

    // firestoreStore.commit이 배치를 BATCH_SIZE로 자르는지 가짜 db로 확인.
    const batches = [];
    const fakeDb = {
      collection: () => ({ doc: (id) => ({ id }) }),
      batch: () => {
        const ops = [];
        batches.push(ops);
        return {
          set: (ref, data, opts) => ops.push({ ref, merge: !!(opts && opts.merge) }),
          commit: async () => {},
        };
      },
    };
    const plans = Array.from({ length: 850 }, (_, i) => ({
      id: `tour_${i}`,
      kind: i % 2 ? 'create' : 'meta',
      data: {},
    }));
    const written = await t.firestoreStore(fakeDb).commit(plans);
    assert.strictEqual(written, 850);
    assert.deepStrictEqual(batches.map((b) => b.length), [400, 400, 50]);
    assert.strictEqual(batches[0][0].merge, true); // meta → merge
    assert.strictEqual(batches[0][1].merge, false); // create → set

    // 한 회차 상한: 상한보다 많은 새 항목이면 나머지는 deferred.
    const big = many(t.MAX_WRITES_PER_RUN + 5);
    const store = memoryStore();
    const r = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(big), now: NOW });
    assert.strictEqual(r.written, t.MAX_WRITES_PER_RUN);
    assert.strictEqual(r.deferred, 5);
    const r2 = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(big), now: NOW });
    assert.strictEqual(r2.created, 5, '다음 회차가 남은 것을 이어서 쓴다');
  });

  // ── 14. 상세 보강(detailCommon2·detailIntro2·detailImage2) ──────────
  // 가짜 응답은 2026-09-19 실제 응답(강동선사문화축제 등 5건)의 모양을 따른다.
  const IMG = (n) => `https://tong.visitkorea.or.kr/cms/resource/${n}/${n}_image2_1.jpg`;
  const detailSet = (contentid, overrides = {}) => ({
    common: [{
      contentid,
      contenttypeid: '15',
      title: '축제',
      tel: '02-3425-5240',
      telname: '강동구',
      homepage: 'http://www.gdsunsa.com',
      firstimage: IMG(1),
      firstimage2: IMG(1).replace('image2', 'image3'),
      overview: '올해로 제30회를 맞이한<br>강동선사문화축제는 &amp; 선사시대 테마',
      modifiedtime: '20260901090000',
      ...(overrides.common || {}),
    }],
    intro: [{
      contentid,
      contenttypeid: '15',
      sponsor1: '강동구',
      sponsor1tel: '02-3425-5240',
      sponsor2: '(재)강동문화재단',
      sponsor2tel: '',
      eventhomepage: '',
      playtime: '10:00~22:00',
      eventplace: '서울 암사동 유적',
      program: '1. 메인프로그램\n- 개막식\n\n\n\n2. 부대프로그램\n- 먹거리장터',
      usetimefestival: '무료(먹거리장터의 경우 개별 음식구매는 유료)',
      bookingplace: '',
      progresstype: '선택안함',
      ...(overrides.intro || {}),
    }],
    info: overrides.info || [
      { contentid, contenttypeid: '15', serialnum: '1', infoname: '행사소개', fldgubun: '1',
        infotext: '올해로 제30회를 맞이한 강동선사문화축제는 & 선사시대 테마' },
      { contentid, contenttypeid: '15', serialnum: '6', infoname: '행사내용', fldgubun: '2',
        infotext: '1. 메인프로그램\n- 개막식\n\n2. 부대프로그램\n- 먹거리장터' },
    ],
    image: overrides.image || [
      { contentid, originimgurl: IMG(11), smallimageurl: IMG(11), imgname: '사진 1', cpyrhtDivCd: 'Type3', serialnum: '11_1' },
      { contentid, originimgurl: IMG(12), smallimageurl: IMG(12), imgname: '사진 2', cpyrhtDivCd: 'Type3', serialnum: '12_2' },
    ],
  });

  /**
   * 가짜 상세 API. [fail]은 (op, contentId) → Error | undefined.
   * 부른 순서를 calls에 남긴다.
   */
  function detailFetcher({ fail = () => undefined, sets = {} } = {}) {
    const calls = [];
    const fn = async ({ operation, contentId, contentTypeId }) => {
      calls.push({ operation, contentId, contentTypeId });
      const err = fail(operation, contentId);
      if (err) throw err;
      const set = sets[contentId] || detailSet(String(contentId));
      const key = { detailCommon2: 'common', detailIntro2: 'intro', detailImage2: 'image', detailInfo2: 'info' }[operation];
      assert.ok(key, `허용되지 않은 상세 API: ${operation}`);
      return { ok: true, items: set[key], totalCount: set[key].length };
    };
    fn.calls = calls;
    return fn;
  }
  const quotaError = () => {
    const e = new Error('TourAPI 결과 오류 code=22');
    e.code = '22';
    e.fatal = true;
    return e;
  };
  const DETAIL_KEYS = ['overview', 'program', 'homepageUrl', 'organizer', 'host', 'contactName',
    'feeText', 'playTime', 'eventPlace', 'images',
    'ageLimit', 'spendTime', 'bookingInfo', 'bookingUrl', 'discountInfo', 'subEvent',
    'placeInfo', 'hostTel', 'festivalGrade', 'performers', 'extraInfo',
    'detailFetchedModifiedTime', 'detailSchemaVersion'];
  const META_KEYS = ['detailFetchedModifiedTime', 'detailSchemaVersion'];

  await check('상세: 실제 응답 모양 → 보강 필드(줄바꿈·엔티티·태그 정리)', () => {
    const s = detailSet('1307813');
    const d = t.normalizeDetail(
      { common: s.common[0], intro: s.intro[0], images: s.image },
      { firstImageUrl: IMG(1) },
    );
    assert.strictEqual(d.overview, '올해로 제30회를 맞이한\n강동선사문화축제는 & 선사시대 테마');
    assert.strictEqual(d.program, '1. 메인프로그램\n- 개막식\n\n2. 부대프로그램\n- 먹거리장터');
    assert.strictEqual(d.homepageUrl, 'http://www.gdsunsa.com/');
    assert.strictEqual(d.organizer, '강동구');
    assert.strictEqual(d.host, '(재)강동문화재단');
    assert.strictEqual(d.contactName, '강동구');
    assert.strictEqual(d.feeText, '무료(먹거리장터의 경우 개별 음식구매는 유료)');
    assert.strictEqual(d.playTime, '10:00~22:00');
    assert.strictEqual(d.eventPlace, '서울 암사동 유적');
    assert.deepStrictEqual(d.images, [IMG(1), IMG(11), IMG(12)]);
    assert.deepStrictEqual(Object.keys(d).sort(), DETAIL_KEYS.filter((k) => !META_KEYS.includes(k)).sort());
    // 예매·연령·소요시간·진행상태는 저장하지 않는다.
    for (const k of ['bookingplace', 'progresstype', 'agelimit', 'sponsor1tel', 'tel']) assert.ok(!(k in d), k);
  });

  await check('상세: 빈 값은 null, 홈페이지가 없으면 eventhomepage, 둘 다 없으면 null', () => {
    const s = detailSet('1', {
      common: { homepage: '', overview: '  ', telname: '' },
      intro: { sponsor2: '', eventhomepage: '<a href="https://fest.example.kr/2026" target="_blank">https://fest.example.kr/2026</a>', usetimefestival: '' },
    });
    const d = t.normalizeDetail({ common: s.common[0], intro: s.intro[0], images: [] }, { firstImageUrl: null });
    assert.strictEqual(d.overview, null);
    assert.strictEqual(d.homepageUrl, 'https://fest.example.kr/2026');
    assert.strictEqual(d.host, null);
    assert.strictEqual(d.contactName, null);
    assert.strictEqual(d.feeText, null);
    assert.deepStrictEqual(d.images, []);
    const none = t.normalizeDetail({ common: { homepage: 'javascript:alert(1)' }, intro: {} }, { firstImageUrl: null });
    assert.strictEqual(none.homepageUrl, null);
    assert.strictEqual(none.program, null);
    assert.strictEqual(t.cleanWebUrl('홈페이지 없음'), null);
    assert.strictEqual(t.cleanWebUrl('<a href="http://a.kr/?x=1&amp;y=2">a</a>'), 'http://a.kr/?x=1&y=2');
  });

  await check('상세 이미지: 대표 + originimgurl, 중복 제거, 최대 10장, 공식 URL 그대로', () => {
    const detail = Array.from({ length: 14 }, (_, i) => ({ originimgurl: IMG(100 + i), smallimageurl: IMG(100 + i) }));
    detail.splice(2, 0, { originimgurl: IMG(1) }); // 대표와 같은 사진
    detail.splice(4, 0, { originimgurl: IMG(101) }); // 목록 안 중복
    detail.push({ originimgurl: 'ftp://x/y.jpg' }, { originimgurl: '' }, null);
    const images = t.mergeImages(IMG(1).replace('https:', 'http:'), detail);
    assert.strictEqual(images.length, t.MAX_IMAGES);
    assert.strictEqual(new Set(images).size, images.length);
    assert.strictEqual(images[0], IMG(1), '대표가 첫 장, http는 https로');
    assert.ok(images.every((u) => u.includes('_image2_1')), '비공식 _image1_1 치환을 하지 않는다');
    assert.ok(!images.some((u) => u.includes('_image1_1')));
  });

  await check('상세: 새 축제는 4종(Common·Intro·Image·Info)을 부르고 create에 함께 쓴다', async () => {
    const store = memoryStore();
    const fd = detailFetcher();
    const r = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(3)), fetchDetail: fd, now: NOW });
    assert.deepStrictEqual(
      [...new Set(fd.calls.map((c) => c.operation))].sort(),
      ['detailCommon2', 'detailImage2', 'detailInfo2', 'detailIntro2'],
    );
    assert.strictEqual(fd.calls.length, 12);
    assert.ok(fd.calls.filter((c) => c.operation === 'detailIntro2').every((c) => c.contentTypeId === '15'));
    assert.strictEqual(r.created, 3);
    assert.strictEqual(r.written, 3, '보강은 create 안에 들어가 문서당 한 번만 쓴다');
    assert.strictEqual(r.detail.succeeded, 3);
    assert.strictEqual(r.detail.detailOnlyWrites, 0);
    const d = store.docs.get('tour_1');
    for (const k of DETAIL_KEYS) assert.ok(k in d, k);
    assert.strictEqual(d.detailFetchedModifiedTime, '20260901090000');
    assert.strictEqual(d.images[0], d.imageUrl);
  });

  await check('상세: 같은 데이터로 다시 돌리면 상세 호출 0회·쓰기 0건', async () => {
    const store = memoryStore();
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(3)), fetchDetail: detailFetcher(), now: NOW });
    const fd = detailFetcher();
    const r = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(3)), fetchDetail: fd, now: NOW });
    assert.strictEqual(fd.calls.length, 0);
    assert.strictEqual(r.written, 0);
    assert.strictEqual(r.detail.targets, 0);
  });

  await check('상세: 기존 문서(보강 전 295건 상황) → 보강 필드만 merge, 목록 본문·해시 그대로', async () => {
    const store = memoryStore();
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(4)), now: NOW }); // 보강 없는 예전 회차
    const before = new Map([...store.docs].map(([k, v]) => [k, { ...v }]));
    const r = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(4)), fetchDetail: detailFetcher(), now: NOW });
    assert.strictEqual(r.detail.listPlans, 0, '목록 계획은 예전과 같이 0건');
    assert.strictEqual(r.detail.detailOnlyWrites, 4);
    assert.strictEqual(r.written, 4);
    const commit = store.commits[store.commits.length - 1];
    for (const c of commit) {
      assert.strictEqual(c.kind, 'detail');
      assert.deepStrictEqual(c.keys.sort(), [...DETAIL_KEYS].sort(), '보강 필드 말고는 쓰지 않는다');
    }
    for (const [id, old] of before) {
      const now = store.docs.get(id);
      for (const k of ['contentHash', 'schemaVersion', 'updatedAt', 'title', 'status', 'isVisible', 'lastSyncedAt']) {
        assert.deepStrictEqual(now[k], old[k], `${id}.${k}`);
      }
    }
    assert.strictEqual(t.SCHEMA_VERSION, 1, '보강 때문에 SCHEMA_VERSION을 올리지 않는다');
  });

  await check('상세: modifiedtime이 바뀐 축제만 다시 받는다', async () => {
    const store = memoryStore();
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(3)), fetchDetail: detailFetcher(), now: NOW });
    const list = many(3);
    list[1] = item({ contentid: '2', title: '축제 2', modifiedtime: '20260918120000' });
    const fd = detailFetcher({ sets: { 2: detailSet('2', { common: { overview: '새 소개' } }) } });
    const r = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(list), fetchDetail: fd, now: NOW });
    assert.deepStrictEqual([...new Set(fd.calls.map((c) => c.contentId))], ['2']);
    assert.strictEqual(fd.calls.length, 4);
    assert.strictEqual(r.meta, 1, '목록은 메타만(본문 같음)');
    assert.strictEqual(r.written, 1, '메타와 보강이 한 문서 쓰기로 합쳐진다');
    const d = store.docs.get('tour_2');
    assert.strictEqual(d.overview, '새 소개');
    assert.strictEqual(d.detailFetchedModifiedTime, '20260918120000');
    assert.strictEqual(d.sourceModifiedTime, '20260918120000');
  });

  await check('상세 일부 실패: 그 축제만 건너뛰고 기존 보강 보존, 목록 동기화는 계속, 다음 회차 재시도', async () => {
    const store = memoryStore();
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(3)), fetchDetail: detailFetcher(), now: NOW });
    const oldOverview = store.docs.get('tour_2').overview;
    const list = many(4).map((it) => ({ ...it, modifiedtime: '20260918120000' }));
    list[1] = { ...list[1], title: '축제 2 바뀜' };
    const fd = detailFetcher({
      sets: { 1: detailSet('1', { common: { overview: '1 새 소개' } }) },
      fail: (op, id) => (op === 'detailIntro2' && id === '2' ? new Error('TourAPI http=503 detailIntro2') : undefined),
    });
    const r = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(list), fetchDetail: fd, now: NOW });
    assert.strictEqual(r.detail.succeeded, 3);
    assert.strictEqual(r.detail.failed, 1);
    assert.deepStrictEqual(r.detail.failures, { 'request-failed': 1 });
    assert.strictEqual(r.created, 1, '새 축제 4는 생성');
    assert.strictEqual(r.updated, 1, '축제 2의 목록 본문 변경은 그대로 반영');
    const d2 = store.docs.get('tour_2');
    assert.strictEqual(d2.title, '축제 2 바뀜');
    assert.strictEqual(d2.overview, oldOverview, '실패한 축제의 기존 보강 값 보존');
    assert.strictEqual(d2.detailFetchedModifiedTime, '20260901090000', '받은 시점 표시도 그대로 → 다음 회차 재시도');
    assert.strictEqual(store.docs.get('tour_1').overview, '1 새 소개');

    const retry = detailFetcher();
    const r2 = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(list), fetchDetail: retry, now: NOW });
    assert.deepStrictEqual([...new Set(retry.calls.map((c) => c.contentId))], ['2']);
    assert.strictEqual(r2.detail.succeeded, 1);
    assert.strictEqual(store.docs.get('tour_2').detailFetchedModifiedTime, '20260918120000');
  });

  await check('상세: 공통정보가 비거나 contentid가 다르면 실패로 보고 쓰지 않는다', async () => {
    const store = memoryStore();
    const fd = detailFetcher({
      sets: {
        1: { ...detailSet('1'), common: [] },
        2: detailSet('999'),
      },
    });
    const r = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(3)), fetchDetail: fd, now: NOW });
    assert.deepStrictEqual(r.detail.failures, { 'common-empty': 1, 'common-mismatch': 1 });
    assert.ok(!('overview' in store.docs.get('tour_1')));
    assert.ok(!('detailFetchedModifiedTime' in store.docs.get('tour_2')));
    assert.ok('overview' in store.docs.get('tour_3'));
    assert.strictEqual(r.created, 3, '목록 생성은 그대로');
  });

  await check('상세: 사진이 없어도 성공(대표 사진만)', async () => {
    const store = memoryStore();
    const fd = detailFetcher({ sets: { 1: detailSet('1', { image: [] }) } });
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(1)), fetchDetail: fd, now: NOW });
    const d = store.docs.get('tour_1');
    assert.deepStrictEqual(d.images, [d.imageUrl]);
  });

  await check('상세: 호출량 초과(22)면 즉시 보강을 멈추고 목록은 그대로 쓴다', async () => {
    const store = memoryStore();
    const fd = detailFetcher({ fail: (op, id) => (id === '2' ? quotaError() : undefined) });
    const r = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(5)), fetchDetail: fd, now: NOW });
    assert.strictEqual(r.detail.stoppedBy, 'fatal:code-22');
    assert.strictEqual(r.detail.attempted, 2);
    assert.strictEqual(r.detail.succeeded, 1);
    assert.strictEqual(fd.calls.length, 5, '축제1 4회 + 축제2 첫 호출 1회에서 멈춤');
    assert.strictEqual(r.created, 5);
    assert.strictEqual(store.docs.size, 5);
  });

  await check('상세: 연속 3건 실패면 멈춘다(치명 코드가 아니어도)', async () => {
    const store = memoryStore();
    const fd = detailFetcher({ fail: (op) => (op === 'detailCommon2' ? new Error('timeout') : undefined) });
    const r = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(8)), fetchDetail: fd, now: NOW });
    assert.strictEqual(r.detail.stoppedBy, 'consecutive-failures');
    assert.strictEqual(r.detail.attempted, t.DETAIL_MAX_CONSECUTIVE_FAILURES);
    assert.strictEqual(fd.calls.length, t.DETAIL_MAX_CONSECUTIVE_FAILURES);
    assert.strictEqual(r.created, 8);
  });

  await check('호출 예산: 여유가 있으면 대상 전부를 한 회차에(건수 상한 없음)', async () => {
    const store = memoryStore();
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(150)), now: NOW });
    const fd = detailFetcher();
    const r = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(150)), fetchDetail: fd, now: NOW });
    assert.strictEqual(r.detail.targets, 150);
    assert.strictEqual(r.detail.attempted, 150);
    assert.strictEqual(fd.calls.length, 600);
    assert.strictEqual(r.detail.stoppedBy, null);
    assert.strictEqual(r.detail.remaining, 0);
    const r2 = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(150)), fetchDetail: detailFetcher(), now: NOW });
    assert.strictEqual(r2.detail.targets, 0);
    assert.strictEqual(r2.written, 0);
  });

  await check('호출 예산: 한도 1,000(합산 가정) − 예비 150 − 오늘 쓴 것 − 목록 조회 안에서만', async () => {
    assert.strictEqual(t.TOUR_DAILY_CALL_LIMIT, 1000);
    assert.strictEqual(t.TOUR_DAILY_RESERVE, 150);
    assert.strictEqual(t.DETAIL_WORST_CASE_CALLS, 12, '4종 × 재시도 3회');
    const day = t.kstDateKey(NOW);
    const store = memoryStore({}, { [day]: 700 });
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(150)), now: NOW });
    store.usage.set(day, 700); // 위 목록 회차의 기록은 되돌려 조건을 고정한다
    const fd = detailFetcher();
    const r = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(150)), fetchDetail: fd, now: NOW });
    const b = r.detail.budget;
    assert.strictEqual(b.usedBefore, 700);
    assert.strictEqual(b.listCalls, 2);
    assert.strictEqual(b.detailBudget, 1000 - 150 - 700 - 2);
    // 첫 축제는 최악의 12회가 들어가야 시작, 이후 실제로 쓴 4회씩 준다.
    assert.strictEqual(b.fundableFestivals, Math.floor((148 - 12) / 4) + 1);
    assert.strictEqual(r.detail.attempted, 35);
    assert.strictEqual(r.detail.stoppedBy, 'call-budget');
    assert.ok(fd.calls.length <= b.detailBudget);
    assert.strictEqual(store.usage.get(day), 700 + 2 + 140, '이번 회차 호출 수를 오늘 기록에 더한다');

    // 같은 날 또 돌면 남은 예산이 최악의 경우에 못 미쳐 상세는 0건, 목록은 정상.
    const fd2 = detailFetcher();
    const r2 = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(150)), fetchDetail: fd2, now: NOW });
    assert.strictEqual(fd2.calls.length, 0);
    assert.strictEqual(r2.detail.stoppedBy, 'call-budget');
    assert.strictEqual(r2.complete, true);

    // 다음 날은 새 예산 — 남은 115건을 이어서 받는다.
    const tomorrow = new Date(NOW.getTime() + 24 * 3600 * 1000);
    const r3 = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(150)), fetchDetail: detailFetcher(), now: tomorrow });
    assert.strictEqual(r3.detail.budget.usedBefore, 0);
    assert.strictEqual(r3.detail.attempted, 115);
    assert.strictEqual(r3.detail.remaining, 0);
  });

  await check('호출 예산: 재시도로 실제 요청이 늘어도 예산을 넘지 않는다(attemptCounter)', async () => {
    const day = t.kstDateKey(NOW);
    const store = memoryStore({}, { [day]: 500 });
    const counter = { n: 0 };
    const pages = pagedFetcher(many(200));
    const fd = detailFetcher();
    const r = await t.syncTourFestivalsOnce({
      store,
      // 목록 1회 = 요청 1회, 상세 1회 = 최악의 재시도 3회.
      fetchPage: async (a) => { counter.n += 1; return pages(a); },
      fetchDetail: async (a) => { counter.n += t.TOUR_RETRY_ATTEMPTS; return fd(a); },
      attemptCounter: counter,
      now: NOW,
    });
    const b = r.detail.budget;
    assert.strictEqual(b.detailBudget, 1000 - 150 - 500 - 2);
    assert.ok(counter.n - b.listCalls <= b.detailBudget, `${counter.n - b.listCalls} <= ${b.detailBudget}`);
    assert.strictEqual(r.detail.attempted, Math.floor(b.detailBudget / t.DETAIL_WORST_CASE_CALLS));
    assert.strictEqual(store.usage.get(day), 500 + counter.n, '기록은 실제 요청 수');
    assert.ok(500 + counter.n <= t.TOUR_DAILY_CALL_LIMIT - t.TOUR_DAILY_RESERVE);
  });

  await check('호출 기록: 목록이 실패해도 쓴 만큼 기록, dry-run은 기록하지 않음', async () => {
    const day = t.kstDateKey(NOW);
    const store = memoryStore();
    await assert.rejects(t.syncTourFestivalsOnce({
      store, fetchPage: pagedFetcher(many(150), { failOnPage: 2 }), now: NOW,
    }));
    assert.strictEqual(store.usage.get(day), 2);
    const dry = memoryStore();
    await t.syncTourFestivalsOnce({ store: dry, fetchPage: pagedFetcher(many(3)), fetchDetail: detailFetcher(), now: NOW, dryRun: true });
    assert.strictEqual(dry.usageWrites.length, 0);
    // 기록 쓰기가 실패해도 회차 결과는 그대로.
    const flaky = memoryStore();
    flaky.addUsage = async () => { throw new Error('usage write'); };
    const r = await t.syncTourFestivalsOnce({ store: flaky, fetchPage: pagedFetcher(many(3)), now: NOW });
    assert.strictEqual(r.created, 3);
  });

  await check('상세 대상: 새 문서 먼저, 종료된 축제는 부르지 않는다', async () => {
    const store = memoryStore();
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(2)), now: NOW });
    const list = [
      ...many(2),
      item({ contentid: '30', eventstartdate: '20260901', eventenddate: '20260910' }), // 종료
      item({ contentid: '31', eventstartdate: '20261001', eventenddate: '20261003' }),
    ];
    const fd = detailFetcher();
    const r = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(list), fetchDetail: fd, now: NOW });
    assert.strictEqual(r.detail.targets, 3);
    assert.deepStrictEqual([...new Set(fd.calls.map((c) => c.contentId))], ['31', '1', '2']);
    assert.ok(!('overview' in store.docs.get('tour_30')));
  });

  await check('상세: 시간 상한에 닿으면 멈춘다', async () => {
    const store = memoryStore();
    let ms = 0;
    const clock = () => ms;
    const fd = detailFetcher();
    const slow = async (args) => { ms += t.DETAIL_TIME_BUDGET_MS / 4; return fd(args); };
    const r = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(5)), fetchDetail: slow, clock, now: NOW });
    assert.strictEqual(r.detail.stoppedBy, 'time-budget');
    assert.ok(r.detail.succeeded >= 1 && r.detail.succeeded < 5);
    assert.strictEqual(r.created, 5);
  });

  await check('상세 dry-run: detailLimit 0이면 상세를 안 부르고 대상·예상 호출만 센다', async () => {
    const store = memoryStore();
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(3)), now: NOW });
    const guarded = { ...store, commit: async () => { throw new Error('write'); } };
    const fd = detailFetcher();
    const r = await t.syncTourFestivalsOnce({
      store: guarded, fetchPage: pagedFetcher(many(3)), fetchDetail: fd, detailLimit: 0, now: NOW, dryRun: true,
    });
    assert.strictEqual(fd.calls.length, 0);
    assert.strictEqual(r.written, 0);
    assert.strictEqual(r.detail.targets, 3);
    assert.strictEqual(r.detail.plannedThisRun, 3);
    assert.strictEqual(r.detail.plannedCallsThisRun.total, 12);
    const sample = await t.syncTourFestivalsOnce({
      store: guarded, fetchPage: pagedFetcher(many(3)), fetchDetail: detailFetcher(), detailLimit: 1, now: NOW, dryRun: true,
    });
    assert.strictEqual(sample.detail.attempted, 1);
    assert.strictEqual(sample.detail.detailOnlyWrites, 1);
    assert.strictEqual(sample.written, 0);
  });

  await check('fetchDetail 없이 돌리면 예전과 똑같다(보강 꺼짐)', async () => {
    const store = memoryStore();
    const r = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(2)), now: NOW });
    assert.strictEqual(r.detail.stoppedBy, 'disabled');
    assert.strictEqual(r.detail.totalCalls, 0);
    assert.ok(!('overview' in store.docs.get('tour_1')));
  });

  await check('상세 API 요청: 쿼리·경로·재시도·키 비노출', async () => {
    const qc = t.buildDetailQuery('detailCommon2', { contentId: '1307813' });
    const qi = t.buildDetailQuery('detailIntro2', { contentId: '1307813', contentTypeId: '15' });
    const qm = t.buildDetailQuery('detailImage2', { contentId: '1307813' });
    for (const q of [qc, qi, qm]) {
      assert.ok(!q.includes('serviceKey'));
      assert.ok(q.includes('_type=json') && q.includes('contentId=1307813'));
    }
    assert.ok(qi.includes('contentTypeId=15'));
    // detailInfo2도 contentTypeId 필수(2026-09-20 dry-run에서 빠뜨려 결과코드 11).
    const qf = t.buildDetailQuery('detailInfo2', { contentId: '1307813', contentTypeId: '15' });
    assert.ok(qf.includes('contentTypeId=15') && qf.includes('contentId=1307813'));
    assert.ok(t.buildDetailQuery('detailInfo2', { contentId: '1' }).includes('contentTypeId=15'));
    assert.ok(!qc.includes('contentTypeId'), 'Common에는 붙이지 않는다');
    assert.ok(qm.includes('imageYN=Y'));
    assert.ok(t.buildDetailPath('SECRET+KEY', 'detailImage2', qm)
      .startsWith('/B551011/KorService2/detailImage2?serviceKey=SECRET%2BKEY&'));

    const quiet = async () => {};
    let n = 0;
    const ok = await t.fetchDetail(
      { serviceKey: 'K', operation: 'detailCommon2', contentId: '1' },
      {
        sleep: quiet,
        httpGet: async () => {
          n += 1;
          if (n === 1) return { statusCode: 502, raw: '', elapsedMs: 1 };
          return { statusCode: 200, raw: okBody([{ contentid: '1', overview: 'x' }]), elapsedMs: 1 };
        },
      },
    );
    assert.strictEqual(n, 2, '5xx는 재시도');
    assert.strictEqual(ok.items[0].overview, 'x');

    n = 0;
    await assert.rejects(
      t.fetchDetail(
        { serviceKey: 'SECRETKEY', operation: 'detailIntro2', contentId: '1', contentTypeId: '15' },
        {
          sleep: quiet,
          httpGet: async () => {
            n += 1;
            return { statusCode: 200, raw: '<returnReasonCode>22</returnReasonCode>', elapsedMs: 1 };
          },
        },
      ),
      (err) => err.fatal === true && err.code === '22' && !err.message.includes('SECRETKEY'),
    );
    assert.strictEqual(n, 1, '호출량 초과는 재시도하지 않는다');
  });

  // ── 15. 보강 구성 2 — detailIntro2 축제 필드 전부(2026-09-20 표본 80건) ──
  await check('상세 v2: 실측 값(관람연령·소요시간·주관 전화) 저장, 0건 필드도 null로', () => {
    const s = detailSet('1', {
      intro: {
        agelimit: '전 연령',
        spendtimefestival: '약 90분',
        sponsor2tel: '032-743-0468',
        bookingplace: '',
        discountinfofestival: '',
        subevent: '',
        placeinfo: '',
        festivalgrade: '',
        progresstype: '선택안함',
        festivaltype: '선택안함',
      },
    });
    const d = t.normalizeDetail({ common: s.common[0], intro: s.intro[0], images: [] }, { firstImageUrl: null });
    assert.strictEqual(d.ageLimit, '전 연령');
    assert.strictEqual(d.spendTime, '약 90분');
    assert.strictEqual(d.hostTel, '032-743-0468');
    for (const k of ['bookingInfo', 'bookingUrl', 'discountInfo', 'subEvent', 'placeInfo', 'festivalGrade']) {
      assert.strictEqual(d[k], null, k);
    }
    for (const k of ['progresstype', 'festivaltype', 'progressType', 'festivalType', 'sponsor1tel']) assert.ok(!(k in d), k);
  });

  await check('상세 v2: 예매 정보 — 원문은 늘 보존, 안전한 http(s) 주소가 있을 때만 링크', () => {
    assert.deepStrictEqual(t.bookingFields('인터파크 티켓, 현장 판매'), { text: '인터파크 티켓, 현장 판매', url: null });
    assert.deepStrictEqual(
      t.bookingFields('<a href="https://tickets.interpark.com/goods/26001234" target="_blank">인터파크 티켓</a>'),
      { text: '인터파크 티켓', url: 'https://tickets.interpark.com/goods/26001234' },
    );
    assert.deepStrictEqual(
      t.bookingFields('온라인 예매: https://booking.naver.com/x?a=1&amp;b=2<br>현장 예매 가능'),
      { text: '온라인 예매: https://booking.naver.com/x?a=1&b=2\n현장 예매 가능', url: 'https://booking.naver.com/x?a=1&b=2' },
    );
    assert.deepStrictEqual(t.bookingFields('javascript:alert(1)'), { text: 'javascript:alert(1)', url: null });
    assert.deepStrictEqual(t.bookingFields(''), { text: null, url: null });
    assert.deepStrictEqual(t.bookingFields(undefined), { text: null, url: null });
    const s = detailSet('1', { intro: { bookingplace: 'YES24 티켓 http://ticket.yes24.com/Perf/55555' } });
    const d = t.normalizeDetail({ common: s.common[0], intro: s.intro[0], images: [] }, { firstImageUrl: null });
    assert.strictEqual(d.bookingInfo, 'YES24 티켓 http://ticket.yes24.com/Perf/55555');
    assert.strictEqual(d.bookingUrl, 'http://ticket.yes24.com/Perf/55555');
  });

  await check('상세 v2: 새로 받은 문서에 detailSchemaVersion이 붙는다', async () => {
    const store = memoryStore();
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(1)), fetchDetail: detailFetcher(), now: NOW });
    const d = store.docs.get('tour_1');
    assert.strictEqual(d.detailSchemaVersion, t.DETAIL_SCHEMA_VERSION);
    assert.strictEqual(t.DETAIL_SCHEMA_VERSION, 3);
    for (const k of DETAIL_KEYS) assert.ok(k in d, k);
  });

  // 운영의 첫 보강 100건 모양: 보강 필드 11개는 있고 detailSchemaVersion은 없다.
  async function v1Store(count, enrichedIds) {
    const store = memoryStore();
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(count)), now: NOW });
    for (const id of enrichedIds) {
      const d = store.docs.get(`tour_${id}`);
      Object.assign(d, {
        overview: `예전 소개 ${id}`, program: null, homepageUrl: null, organizer: '예전 주최', host: null,
        contactName: null, feeText: '무료', playTime: null, eventPlace: null, images: [d.imageUrl],
        detailFetchedModifiedTime: d.sourceModifiedTime,
      });
    }
    return store;
  }

  await check('상세 v2: 첫 배포분(버전 없음)은 한 번 다시 받는다 — 안 받은 문서 다음 순서, 목록 본문·해시 그대로', async () => {
    const store = await v1Store(5, ['1', '2', '3']);
    const before = new Map([...store.docs].map(([k, v]) => [k, { ...v }]));
    const fd = detailFetcher();
    const r = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(5)), fetchDetail: fd, now: NOW });
    assert.deepStrictEqual(r.detail.targetsByReason, { newDoc: 0, neverFetched: 2, sourceChanged: 0, schemaOutdated: 3 });
    // 안 받은 4·5 먼저, 그다음 1·2·3.
    assert.deepStrictEqual([...new Set(fd.calls.map((c) => c.contentId))], ['4', '5', '1', '2', '3']);
    assert.strictEqual(r.detail.listPlans, 0);
    assert.strictEqual(r.written, 5);
    for (const [id, old] of before) {
      const now = store.docs.get(id);
      for (const k of ['contentHash', 'schemaVersion', 'updatedAt', 'title', 'status', 'isVisible', 'startAt', 'endAt', 'location', 'lastSyncRunId']) {
        assert.deepStrictEqual(now[k], old[k], `${id}.${k}`);
      }
      assert.strictEqual(now.detailSchemaVersion, t.DETAIL_SCHEMA_VERSION);
    }
    assert.strictEqual(store.docs.get('tour_1').overview, '올해로 제30회를 맞이한\n강동선사문화축제는 & 선사시대 테마');
    const again = detailFetcher();
    const r2 = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(5)), fetchDetail: again, now: NOW });
    assert.strictEqual(again.calls.length, 0, '한 번 받으면 끝');
    assert.strictEqual(r2.written, 0);
  });

  await check('상세 v2: 다시 받기가 실패하면 예전 보강 그대로 두고 다음 회차에 다시', async () => {
    const store = await v1Store(2, ['1', '2']);
    const fd = detailFetcher({ fail: (op, id) => (id === '1' && op === 'detailIntro2' ? new Error('timeout') : undefined) });
    const r = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(2)), fetchDetail: fd, now: NOW });
    assert.strictEqual(r.detail.failed, 1);
    const d1 = store.docs.get('tour_1');
    assert.strictEqual(d1.overview, '예전 소개 1');
    assert.strictEqual(d1.organizer, '예전 주최');
    assert.ok(!('detailSchemaVersion' in d1));
    assert.ok(!('ageLimit' in d1));
    assert.strictEqual(store.docs.get('tour_2').detailSchemaVersion, t.DETAIL_SCHEMA_VERSION);
    const retry = detailFetcher();
    await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(2)), fetchDetail: retry, now: NOW });
    assert.deepStrictEqual([...new Set(retry.calls.map((c) => c.contentId))], ['1']);
  });

  await check('상세 v2: 예산이 모자라면 안 받은 문서가 먼저 자리를 차지한다', async () => {
    const day = t.kstDateKey(NOW);
    const store = await v1Store(150, Array.from({ length: 100 }, (_, i) => String(i + 1)));
    store.usage.set(day, 700);
    const fd = detailFetcher();
    const r = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(150)), fetchDetail: fd, now: NOW });
    assert.deepStrictEqual(r.detail.targetsByReason, { newDoc: 0, neverFetched: 50, sourceChanged: 0, schemaOutdated: 100 });
    assert.strictEqual(r.detail.attempted, 35);
    const ids = [...new Set(fd.calls.map((c) => c.contentId))];
    assert.ok(ids.every((id) => Number(id) > 100), '안 받은 101~150이 먼저');
  });

  await check('storedDetailVersion — 안 받음 0, 첫 배포분 1, v2 문서도 v3로 한 번 다시', () => {
    assert.strictEqual(t.storedDetailVersion(null), 0);
    assert.strictEqual(t.storedDetailVersion({ title: 'x' }), 0);
    assert.strictEqual(t.storedDetailVersion({ detailFetchedModifiedTime: '1' }), 1);
    assert.strictEqual(t.storedDetailVersion({ detailFetchedModifiedTime: '1', detailSchemaVersion: 2 }), 2);
    assert.strictEqual(t.needsDetail({ detailFetchedModifiedTime: '1' }, '1'), true);
    assert.strictEqual(t.needsDetail({ detailFetchedModifiedTime: '1', detailSchemaVersion: 2 }, '1'), true);
    assert.strictEqual(t.needsDetail({ detailFetchedModifiedTime: '1', detailSchemaVersion: 3 }, '1'), false);
    assert.strictEqual(t.needsDetail({ detailFetchedModifiedTime: '1', detailSchemaVersion: 3 }, '2'), true);
  });

  // ── 16. detailInfo2 · 의미 없는 값 ────────────────────────────────────
  const infoRow = (serialnum, infoname, infotext) => ({ contentid: '1', contenttypeid: '15', serialnum, infoname, infotext, fldgubun: '2' });

  await check('Info: 소개·내용이 Common·Intro와 같으면 버린다(이중 저장 없음)', () => {
    const r = t.normalizeInfo([
      infoRow('1', '행사소개', '가을 축제<br>소개'),
      infoRow('6', '행사내용', '1. 개막식\n2. 공연'),
    ], { overview: '가을 축제\n소개', program: '1. 개막식\n2. 공연' });
    assert.deepStrictEqual(r, { overviewFallback: null, programFallback: null, performers: null, extraInfo: [] });
  });

  await check('Info: Intro program이 비면 행사내용을 program으로(사천에어쇼 실측)', () => {
    const s1 = detailSet('1', {
      intro: { program: '' },
      info: [
        infoRow('1', '행사소개', '올해로 제30회를 맞이한 강동선사문화축제는 & 선사시대 테마'),
        infoRow('6', '행사내용', '1. 에어쇼<br>2. 블랙이글스 비행'),
      ],
    });
    const d = t.normalizeDetail({ common: s1.common[0], intro: s1.intro[0], images: [], info: s1.info }, { firstImageUrl: null });
    assert.strictEqual(d.program, '1. 에어쇼\n2. 블랙이글스 비행');
    assert.deepStrictEqual(d.extraInfo, []);
  });

  await check('Info: Common overview가 비면 행사소개를 overview로', () => {
    const r = t.normalizeInfo([infoRow('1', '행사소개', '대체 소개')], { overview: null, program: 'x' });
    assert.strictEqual(r.overviewFallback, '대체 소개');
  });

  await check('Info: 출연은 performers(서울뮤직페스티벌 실측), 여러 줄이면 이어 붙인다', () => {
    const r = t.normalizeInfo([
      infoRow('1', '행사소개', '소개'),
      infoRow('6', '행사내용', '내용'),
      infoRow('7', '출연', '폴킴, 권진아, 옥상달빛, 너드커넥션, 추다혜차지스, 김창완밴드, 글(GLL)'),
      infoRow('8', '출연진', '2일차: 옥상달빛'),
    ], { overview: '소개', program: '내용' });
    assert.strictEqual(r.performers, '폴킴, 권진아, 옥상달빛, 너드커넥션, 추다혜차지스, 김창완밴드, 글(GLL)\n2일차: 옥상달빛');
    assert.deepStrictEqual(r.extraInfo, []);
  });

  await check('Info: 처음 보는 줄은 제목 그대로 extraInfo — 중복·빈 값·선택안함은 뺀다, 최대 10개', () => {
    const rows = [
      infoRow('9', '관람 안내', '우천 시 실내로 옮깁니다'),
      infoRow('10', '주차 안내', '임시 주차장 운영'),
      infoRow('11', '안내', '우천 시 실내로 옮깁니다'), // 앞 줄과 같은 글
      infoRow('12', '비고', '선택안함'),
      infoRow('13', '빈 줄', '   '),
      infoRow('14', '요약', '소개'), // overview와 같은 글
      infoRow('6', '행사내용', '프로그램과 다른 추가 내용'), // program과 다르면 살린다
    ];
    for (let i = 0; i < 12; i++) rows.push(infoRow(String(20 + i), `기타${i}`, `내용${i}번`));
    const r = t.normalizeInfo(rows, { overview: '소개', program: '1. 개막식' });
    assert.deepStrictEqual(r.extraInfo.slice(0, 3), [
      { title: '행사내용', text: '프로그램과 다른 추가 내용' },
      { title: '관람 안내', text: '우천 시 실내로 옮깁니다' },
      { title: '주차 안내', text: '임시 주차장 운영' },
    ]);
    assert.strictEqual(r.extraInfo.length, t.MAX_EXTRA_INFO);
    assert.ok(!r.extraInfo.some((e) => e.title === '비고' || e.title === '빈 줄' || e.title === '요약' || e.title === '안내'));
  });

  await check('Info가 비어 있어도 성공 — 대체·출연·추가 정보만 빈다', async () => {
    const store = memoryStore();
    const fd = detailFetcher({ sets: { 1: detailSet('1', { info: [] }) } });
    const r = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(1)), fetchDetail: fd, now: NOW });
    assert.strictEqual(r.detail.succeeded, 1);
    const d = store.docs.get('tour_1');
    assert.strictEqual(d.performers, null);
    assert.deepStrictEqual(d.extraInfo, []);
    assert.ok(d.overview && d.program);
  });

  await check('Info 호출이 실패하면 그 축제 전체를 다음 회차로(기존 보강 보존)', async () => {
    const store = memoryStore();
    const fd = detailFetcher({ fail: (op, id) => (op === 'detailInfo2' && id === '1' ? new Error('timeout') : undefined) });
    const r = await t.syncTourFestivalsOnce({ store, fetchPage: pagedFetcher(many(2)), fetchDetail: fd, now: NOW });
    assert.strictEqual(r.detail.failed, 1);
    assert.ok(!('overview' in store.docs.get('tour_1')));
    assert.ok('overview' in store.docs.get('tour_2'));
  });

  await check('의미 없는 값(선택안함·없음·-)은 저장하지 않는다', () => {
    const s1 = detailSet('1', {
      intro: {
        agelimit: '선택안함', spendtimefestival: '-', festivalgrade: '선택안함', bookingplace: '없음',
        discountinfofestival: '해당없음', subevent: ' ', placeinfo: '선택 안함', sponsor2tel: '-',
      },
    });
    const d = t.normalizeDetail({ common: s1.common[0], intro: s1.intro[0], images: [], info: [] }, { firstImageUrl: null });
    for (const k of ['ageLimit', 'spendTime', 'festivalGrade', 'bookingInfo', 'bookingUrl', 'discountInfo', 'subEvent', 'placeInfo', 'hostTel']) {
      assert.strictEqual(d[k], null, k);
    }
    assert.strictEqual(t.meaningful('문화관광축제'), '문화관광축제');
  });

  await check('Cloud Function은 syncTourFestivals 하나(나머지는 헬퍼)', () => {
    assert.strictEqual(typeof t.syncTourFestivals, 'function');
  });

  // ── 결과 ─────────────────────────────────────────────────────────────
  let failed = 0;
  for (const [status, name, err] of results) {
    console.log(`${status === 'ok' ? '✓' : '✗'} ${name}`);
    if (err) {
      failed += 1;
      console.log(`    ${err && err.stack ? err.stack.split('\n').slice(0, 4).join('\n    ') : err}`);
    }
  }
  console.log(`\n${results.length - failed}/${results.length} 통과`);
  if (failed) process.exit(1);
})();
