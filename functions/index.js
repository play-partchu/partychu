const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule }         = require('firebase-functions/v2/scheduler');
const { onDocumentWritten, onDocumentCreated } = require('firebase-functions/v2/firestore');
const { defineSecret }       = require('firebase-functions/params');
const functionsV1 = require('firebase-functions/v1');
const admin  = require('firebase-admin');
const https  = require('https');
const crypto = require('crypto');
const {
  computeAppliedFee,
  computeAppliedFeeForRounds,
  computeRefund,
  reserveApplicantSlot,
  releaseApplicantSlot,
} = require('./partyCapacity');

admin.initializeApp();

// ── KST(Asia/Seoul, UTC+9, DST 없음) 날짜/시간 헬퍼 ──────────────────────────
// 통계 집계는 전부 한국 기준 날짜/요일/시간대를 써야 "오늘"/"저녁 시간대" 같은
// 지표가 실제 사용자 체감과 맞는다. Cloud Functions 런타임은 UTC로 동작하므로
// 매번 이 헬퍼로 변환한다.
const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

function kstDateKey(date) {
  const kst = new Date(date.getTime() + KST_OFFSET_MS);
  const y = kst.getUTCFullYear();
  const m = String(kst.getUTCMonth() + 1).padStart(2, '0');
  const d = String(kst.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function kstParts(date) {
  const kst = new Date(date.getTime() + KST_OFFSET_MS);
  const utcDay = kst.getUTCDay(); // 0=일 ~ 6=토
  return {
    dateKey: kstDateKey(date),
    hour: kst.getUTCHours(),
    dayOfWeek: utcDay === 0 ? 7 : utcDay, // 1=월 ~ 7=일로 변환
  };
}

// NICE 통합인증 — 공식 REST API 가이드 기준 재구현 (기존 niceIntc* 로직과 분리)
Object.assign(exports, require('./niceAuth'));

// 공유 링크(partychu.co.kr/party/{id}) 서버 렌더 랜딩 페이지 — OG 태그 등
// 자세한 설계 이유는 partyLandingPage.js 상단 주석 참고.
Object.assign(exports, require('./partyLandingPage'));

// 장소대여 예약(시간제/패키지) 생성·결제검증·취소·자동만료 — 자세한 설계
// 이유는 placeReservations.js 상단 주석 참고.
Object.assign(exports, require('./placeReservations'));

// 숙박+파티 패키지 통합 예약/결제 — packageBookingEnabled인 콤보에서만
// 쓰인다. 자세한 설계 이유는 packageBookings.js 상단 주석 참고.
Object.assign(exports, require('./packageBookings'));

// 통합 회원 관리(활동 배지·userStats 확장·통합 활동 타임라인) — 자세한 설계
// 이유는 memberManagement.js 상단 주석 참고. 공용 헬퍼는 memberActivityHelpers.js
// 에서 직접 가져온다(partyCapacity.js와 동일하게 순수 헬퍼 모듈은 항상
// 구조분해로만 참조 — Object.assign(exports,...) 대상은 Cloud Functions만).
Object.assign(exports, require('./memberManagement'));
Object.assign(exports, require('./crmExportFunction'));
const {
  logUserActivity,
  addActivityRole,
  bumpUserStats,
  bumpFavoriteReceivedCount,
  logScheduledFunctionError,
  isTestAccountUid,
} = require('./memberActivityHelpers');

// ── Cloudflare 미디어 삭제 헬퍼 ──────────────────────────────────────────────

function httpsDelete(hostname, path, token) {
  return new Promise((resolve, reject) => {
    const req = https.request(
      { hostname, path, method: 'DELETE',
        headers: { Authorization: `Bearer ${token}` } },
      (res) => {
        let body = '';
        res.on('data', (c) => { body += c; });
        res.on('end', () => {
          if (res.statusCode === 200 || res.statusCode === 204) resolve();
          else reject(new Error(`HTTP ${res.statusCode}: ${body.slice(0, 200)}`));
        });
      },
    );
    req.on('error', reject);
    req.end();
  });
}

async function deleteStreamVideo(accountId, token, uid) {
  await httpsDelete(
    'api.cloudflare.com',
    `/client/v4/accounts/${accountId}/stream/${uid}`,
    token,
  );
}

async function deleteR2Object(accountId, token, bucket, key) {
  await httpsDelete(
    'api.cloudflare.com',
    `/client/v4/accounts/${accountId}/r2/buckets/${bucket}/objects/${encodeURIComponent(key)}`,
    token,
  );
}

// ── Cloudflare Secrets ────────────────────────────────────────────────────────

const cfAccountId = defineSecret('CLOUDFLARE_ACCOUNT_ID');
const cfApiToken  = defineSecret('CLOUDFLARE_API_TOKEN');
const cfR2Bucket  = defineSecret('CLOUDFLARE_R2_BUCKET');

// ── 만료 파티 자동 삭제 (매일 03:00 KST) ─────────────────────────────────────
//
// 기준: partyDateTime + 30일 경과 & status != 'active'
// 처리: Cloudflare Stream 동영상 삭제 → R2 이미지 삭제 → Firestore 문서 삭제

exports.deleteExpiredParties = onSchedule(
  {
    schedule:  '0 3 * * *',
    timeZone:  'Asia/Seoul',
    region:    'asia-northeast3',
    secrets:   [cfAccountId, cfApiToken, cfR2Bucket],
  },
  async () => {
    const db = admin.firestore();
    try {
      const cutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
      const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);

      const snapshot = await db.collection('parties')
        .where('partyDateTime', '<', cutoffTs)
        .get();

      let accountId, apiToken, r2Bucket;
      try {
        accountId = cfAccountId.value().trim();
        apiToken  = cfApiToken.value().trim();
        r2Bucket  = cfR2Bucket.value().trim();
      } catch (_) {
        console.warn('[cleanup] Cloudflare 시크릿 미설정 — Firestore만 삭제합니다.');
      }

      const toDelete = snapshot.docs.filter((doc) => {
        const d = doc.data();
        // 재등록(status='active')이거나 이미 삭제된 문서는 건너뜀
        return d.status !== 'active' && d.isDeleted !== true && d.status !== 'deleted';
      });

      console.log(`[cleanup] 만료 후보 ${toDelete.length}개 / 전체 쿼리 ${snapshot.size}개`);

      for (const doc of toDelete) {
        const d = doc.data();

        // ① Cloudflare Stream 동영상 삭제
        if (accountId && apiToken && d.videoUid) {
          try { await deleteStreamVideo(accountId, apiToken, d.videoUid); }
          catch (e) { console.error(`[cleanup] Stream 삭제 실패 (${d.videoUid}):`, e.message); }
        }

        // ② Cloudflare R2 이미지 삭제
        if (accountId && apiToken && r2Bucket) {
          const images = [...(d.images || []), ...(d.imageUrls || [])];
          for (const url of images) {
            try {
              const key = new URL(url).pathname.replace(/^\//, '');
              if (key) await deleteR2Object(accountId, apiToken, r2Bucket, key);
            } catch (e) { console.error(`[cleanup] R2 삭제 실패 (${url}):`, e.message); }
          }
        }

        // ③ Firestore 문서 삭제 (400건씩 batch)
      }

      // Batch delete (Firestore 최대 500건/batch)
      const CHUNK = 400;
      for (let i = 0; i < toDelete.length; i += CHUNK) {
        const batch = db.batch();
        toDelete.slice(i, i + CHUNK).forEach((doc) => batch.delete(doc.reference));
        await batch.commit();
      }

      console.log(`[cleanup] 완료 — ${toDelete.length}개 삭제됨`);
    } catch (e) {
      await logScheduledFunctionError(db, 'deleteExpiredParties', e);
      throw e; // Cloud Scheduler 재시도/실패 기록은 기존과 동일하게 유지
    }
  },
);

// ── 만료 장소 자동 삭제 (매일 03:00 KST) ─────────────────────────────────────
//
// 기준: isActive == false(숨김) & hiddenAt + 30일 경과
// 처리: 장소 Stream 동영상 삭제 → 장소 R2 이미지 삭제 → 하위 placeRooms
//       문서마다 룸 R2 이미지 삭제 → placeRooms 문서 삭제 → 장소 문서 삭제
// 주의: isActive==false + hiddenAt 범위 비교 조합이라 Firestore 복합 인덱스가
// 필요할 수 있다 — 처음 실행 시 오류 로그에 인덱스 생성 링크가 뜨면 그 링크로
// 인덱스를 만들어야 한다.

exports.deleteExpiredPlaces = onSchedule(
  {
    schedule:  '0 3 * * *',
    timeZone:  'Asia/Seoul',
    region:    'asia-northeast3',
    secrets:   [cfAccountId, cfApiToken, cfR2Bucket],
  },
  async () => {
    const db = admin.firestore();
    try {
      const cutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
      const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);

      const snapshot = await db.collection('places')
        .where('isActive', '==', false)
        .where('hiddenAt', '<', cutoffTs)
        .get();

      let accountId, apiToken, r2Bucket;
      try {
        accountId = cfAccountId.value().trim();
        apiToken  = cfApiToken.value().trim();
        r2Bucket  = cfR2Bucket.value().trim();
      } catch (_) {
        console.warn('[cleanup-place] Cloudflare 시크릿 미설정 — Firestore만 삭제합니다.');
      }

      console.log(`[cleanup-place] 만료 후보 ${snapshot.size}개`);

      // 삭제할 Firestore 문서 레퍼런스를 모아뒀다가 마지막에 한 번에 batch 삭제
      const refsToDelete = [];

      for (const doc of snapshot.docs) {
        const d = doc.data();

        // ① 장소 대표 동영상(Cloudflare Stream) 삭제
        if (accountId && apiToken && d.videoUid) {
          try { await deleteStreamVideo(accountId, apiToken, d.videoUid); }
          catch (e) { console.error(`[cleanup-place] Stream 삭제 실패 (${d.videoUid}):`, e.message); }
        }

        // ② 장소 사진(R2) 삭제
        if (accountId && apiToken && r2Bucket) {
          const images = [...(d.imageUrls || [])];
          for (const url of images) {
            try {
              const key = new URL(url).pathname.replace(/^\//, '');
              if (key) await deleteR2Object(accountId, apiToken, r2Bucket, key);
            } catch (e) { console.error(`[cleanup-place] R2 삭제 실패 (${url}):`, e.message); }
          }
        }

        // ③ 하위 룸(placeRooms) — 룸 사진 삭제 + 룸 문서도 함께 삭제 목록에 추가
        const roomsSnap = await db.collection('placeRooms')
          .where('placeId', '==', doc.id)
          .get();
        for (const roomDoc of roomsSnap.docs) {
          const roomData = roomDoc.data();
          if (accountId && apiToken && r2Bucket) {
            const roomImages = roomData.roomImages || [];
            for (const url of roomImages) {
              try {
                const key = new URL(url).pathname.replace(/^\//, '');
                if (key) await deleteR2Object(accountId, apiToken, r2Bucket, key);
              } catch (e) { console.error(`[cleanup-place] 룸 R2 삭제 실패 (${url}):`, e.message); }
            }
          }
          refsToDelete.push(roomDoc.ref);
        }

        refsToDelete.push(doc.ref);
      }

      // Batch delete (Firestore 최대 500건/batch)
      const CHUNK = 400;
      for (let i = 0; i < refsToDelete.length; i += CHUNK) {
        const batch = db.batch();
        refsToDelete.slice(i, i + CHUNK).forEach((ref) => batch.delete(ref));
        await batch.commit();
      }

      console.log(`[cleanup-place] 완료 — 장소 ${snapshot.size}개(+하위 룸 포함 문서 ${refsToDelete.length}개) 삭제됨`);
    } catch (e) {
      await logScheduledFunctionError(db, 'deleteExpiredPlaces', e);
      throw e; // Cloud Scheduler 재시도/실패 기록은 기존과 동일하게 유지
    }
  },
);

// ── Naver Geocoding ───────────────────────────────────────────────────────────

const NAVER_CLIENT_ID = 'tdehle93zg';
const naverClientSecret = defineSecret('NAVER_MAP_CLIENT_SECRET');

// 한글 행정구역 접미사 뒤에 숫자가 바로 붙으면 공백 삽입
// 예: 송정동406-22 → 송정동 406-22
//
// "로"/"길"은 뒤에 오는 숫자가 또 다른 "로/길"로 이어지는 복합 도로명일
// 때만(예: "강남대로65길", "테헤란로14길") 공백을 넣지 않는다 — 이걸 넣으면
// "강남대로 65길"처럼 존재하지 않는 주소로 잘못 쪼개진다. 반대로 "경포로463"
// 처럼 숫자 뒤에 더 이상 로/길이 붙지 않는(= 건물번호로 끝나는) 흔한 경우는
// 공백이 없으면 지오코딩 API가 주소를 찾지 못하므로 공백을 넣어야 한다.
// (?!\d*(로|길))로 "숫자 뒤에 또 로/길이 오는" 케이스만 제외한다.
function normalizeAddress(q) {
  let out = q.replace(/(동|읍|면|리|구|시|도)(\d)/g, '$1 $2');
  out = out.replace(/(로|길)(\d+)(?!\d*(로|길))/g, '$1 $2');
  return out;
}

// 공백+숫자 패턴 이전 부분만 추출 (지역명 간소화)
// 예: 송정동 406-22 → 송정동
function simplifyAddress(q) {
  const m = q.match(/^(.+?)\s+\d/);
  return m ? m[1].trim() : q;
}

// NCP Geocoding API 단일 요청
function geocodeSingle(query, clientId, clientSecret) {
  const path = `/map-geocode/v2/geocode?query=${encodeURIComponent(query)}&count=10`;
  const url  = `https://maps.apigw.ntruss.com${path}`;

  const maskedSecret = clientSecret
    ? clientSecret.slice(0, 4) + '***' + clientSecret.slice(-2)
    : '(empty)';

  console.log('[geocodeAddress] ── 요청 진단 ──────────────────────────');
  console.log('  URL   :', url);
  console.log('  query :', query);
  console.log('  clientId :', clientId);
  console.log('  hasSecret:', !!clientSecret);
  console.log('  secretLen:', clientSecret ? clientSecret.length : 0);
  console.log('  secret(masked):', maskedSecret);
  console.log('  headers: X-NCP-APIGW-API-KEY-ID =', clientId);
  console.log('  headers: X-NCP-APIGW-API-KEY    =', maskedSecret);
  console.log('─────────────────────────────────────────────────────');

  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'maps.apigw.ntruss.com',
      path,
      method: 'GET',
      headers: {
        'X-NCP-APIGW-API-KEY-ID': clientId,
        'X-NCP-APIGW-API-KEY':    clientSecret,
      },
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        // 401/403은 전체 body 출력 (오류 메시지 확인)
        const isError = res.statusCode === 401 || res.statusCode === 403;
        const bodyLog = isError ? data : data.slice(0, 300);
        console.log(`[geocodeAddress] query="${query}" statusCode=${res.statusCode}`);
        console.log('[geocodeAddress] response body:', bodyLog);
        try {
          resolve({ statusCode: res.statusCode, body: JSON.parse(data) });
        } catch (_) {
          resolve({ statusCode: res.statusCode, body: { _raw: data } });
        }
      });
    });
    req.on('error', (error) => {
      console.error('[geocodeAddress] 네트워크 오류:', error.message);
      reject(error);
    });
    req.end();
  });
}

exports.geocodeAddress = onCall(
  { secrets: [naverClientSecret], region: 'asia-northeast3' },
  async (request) => {
    const query = request.data?.query;
    if (!query || typeof query !== 'string' || query.trim().length === 0) {
      throw new HttpsError('invalid-argument', '주소 검색어가 필요합니다.');
    }

    const rawQuery      = query.trim();
    const normalizedQuery = normalizeAddress(rawQuery);
    const simplifiedQuery = simplifyAddress(normalizedQuery);

    // 중복 제거 후 fallback 순서대로 시도
    const candidates = [...new Set([rawQuery, normalizedQuery, simplifiedQuery])];

    let clientSecret;
    try {
      clientSecret = naverClientSecret.value().trim(); // 공백·개행 제거
      console.log('[geocodeAddress] Secret 로드 성공, length =', clientSecret.length);
    } catch (e) {
      console.error('[geocodeAddress] Secret 로딩 실패:', e.message);
      throw new HttpsError('internal', `API 키 로딩 실패: ${e.message}`);
    }

    const attempts = [];
    let lastStatusCode = 0;
    let lastBody = null;

    for (const q of candidates) {
      let statusCode, body;
      try {
        ({ statusCode, body } = await geocodeSingle(q, NAVER_CLIENT_ID, clientSecret));
      } catch (err) {
        attempts.push({ query: q, statusCode: 0, count: 0, error: err.message });
        continue;
      }

      lastStatusCode = statusCode;
      lastBody = body;

      const count = body?.addresses?.length ?? 0;
      console.log(`[geocodeAddress] query="${q}" count=${count}`);
      attempts.push({ query: q, statusCode, count });

      // 인증 오류 → 더 시도해도 의미 없음
      if (statusCode === 401 || statusCode === 403) {
        return {
          status: 'AUTH_ERROR',
          statusCode,
          addresses: [],
          debug: { rawQuery, normalizedQuery, simplifiedQuery, attempts },
        };
      }

      if (statusCode === 200 && count > 0) {
        return {
          status: 'OK',
          statusCode,
          addresses: body.addresses,
          meta: body.meta,
          debug: { rawQuery, normalizedQuery, simplifiedQuery, attempts, successQuery: q },
        };
      }
    }

    // 모든 시도 결과 없음
    return {
      status: lastBody?.status ?? 'ZERO_RESULTS',
      statusCode: lastStatusCode,
      addresses: [],
      debug: { rawQuery, normalizedQuery, simplifiedQuery, attempts },
    };
  }
);

// ── 신청자 목록 조회 (파티장 전용) ───────────────────────────────────────────

exports.getApplicants = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');

    const { partyId } = request.data;
    if (!partyId || typeof partyId !== 'string') {
      throw new HttpsError('invalid-argument', 'partyId가 필요합니다.');
    }

    const db = admin.firestore();
    const partyDoc = await db.collection('parties').doc(partyId).get();
    if (!partyDoc.exists) throw new HttpsError('not-found', '파티를 찾을 수 없습니다.');
    if (partyDoc.data().hostId !== request.auth.uid) {
      throw new HttpsError('permission-denied', '파티장만 신청자 목록을 조회할 수 있습니다.');
    }

    // applications 서브컬렉션을 단일 출처로 삼는다 — 취소된 신청은 applicants
    // 배열에서는 제거되지만(정원 계산용) applications 문서는 상태와 함께
    // 그대로 남아있으므로, 취소 내역까지 포함한 전체 신청 이력은 이쪽에서만
    // 확인할 수 있다.
    const appsSnap = await db
      .collection('parties')
      .doc(partyId)
      .collection('applications')
      .orderBy('appliedAt', 'asc')
      .get();

    const applicants = await Promise.all(
      appsSnap.docs.map(async (doc) => {
        const a = doc.data();
        const uid = doc.id;
        const userDoc = await db.collection('users').doc(uid).get();
        const name = userDoc.exists ? (userDoc.data().name || '(이름 없음)') : '(알 수 없음)';
        const gender = a.gender || (userDoc.exists ? userDoc.data().gender : '') || '';
        return {
          uid,
          name,
          gender,
          status: a.status || 'applied',
          cancelledBy: a.cancelledBy || null,
          refundAmount: a.refundAmount ?? null,
          refundStatus: a.refundStatus ?? null,
          selectedRounds: a.selectedRounds ?? null,
        };
      })
    );

    return { applicants };
  }
);

// ── 파티 신청 (서버사이드 적격성 검증) ──────────────────────────────────────
//
// 보안 설계:
//   클라이언트 Firestore Transaction에서 서버로 이전.
//   gender·birthYear는 Admin SDK로 읽으므로 클라이언트가 위조 불가.
//   Firestore Security Rules의 신청자 경로(isApplicantUpdateOnly)는
//   이 함수 배포 후 제거 가능하나, 현재는 심층 방어(defense-in-depth)로 유지.
//
// 검증 순서:
//   1. 이미신청 → 2. 모집상태/마감일 → 3. 연령제한 → 4. 성별/정원 → 5. Firestore 업데이트
//
// 얼리버드 할인: 클라이언트가 보낸 금액은 절대 신뢰하지 않고, 서버에서
// earlyBirdEnabled/earlyBirdEndAt/earlyBirdDiscountPercent를 직접 읽어
// 신청 확정 시점의 실제 적용 금액(appliedFee)을 계산해 응답으로 돌려준다.
// (lib/utils/early_bird.dart의 계산 로직과 동일하게 유지해야 함)

// computeAppliedFee/computeAppliedFeeForRounds는 partyCapacity.js로 이동됨
// (packageBookings.js와 공유하기 위해) — 위 require 참고.

exports.applyToParty = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');

    const { partyId, selectedRounds } = request.data;
    if (!partyId || typeof partyId !== 'string') {
      throw new HttpsError('invalid-argument', 'partyId가 필요합니다.');
    }
    if (selectedRounds !== undefined) {
      const valid =
        Array.isArray(selectedRounds) &&
        selectedRounds.length > 0 &&
        selectedRounds.every((n) => Number.isInteger(n) && n > 0);
      if (!valid) {
        throw new HttpsError('invalid-argument', 'selectedRounds가 올바르지 않습니다.');
      }
    }

    const uid = request.auth.uid;
    const db = admin.firestore();

    // 사용자 인증 데이터: Admin SDK 읽기 → 클라이언트 위조 불가
    const userDoc = await db.collection('users').doc(uid).get();
    const userData = userDoc.exists ? userDoc.data() : {};
    const gender = userData.gender || null;
    const birthYear = userData.birthYear != null ? Number(userData.birthYear) : null;

    let appliedFee = 0;

    await db.runTransaction(async (transaction) => {
      const partyRef = db.collection('parties').doc(partyId);
      const applicationRef = partyRef.collection('applications').doc(uid);
      const partySnapshot = await transaction.get(partyRef);
      if (!partySnapshot.exists) throw new HttpsError('not-found', '파티를 찾을 수 없어요');

      const data = partySnapshot.data();

      // 자격 검증(이미신청/모집상태/마감일/연령제한/성별) + 정원 확인 +
      // 카운터 증가분 계산은 partyCapacity.js의 reserveApplicantSlot으로
      // 추출돼 있다 — createPendingPackageBooking(숙박+파티 패키지 예약의
      // pending 단계)과 동일한 로직을 공유한다.
      const { updateData, appliedFee: fee, effectiveSelectedRounds } =
        reserveApplicantSlot(data, { uid, gender, birthYear, selectedRounds });
      appliedFee = fee;
      transaction.update(partyRef, updateData);

      // 관리자 웹/향후 통계용 신청 상태 추적 — 기존 applicants 배열은 그대로 두고
      // 신청 1건당 문서 1개를 추가로 남긴다 (배열만으로는 승인/참석/취소/노쇼
      // 같은 개별 상태를 표현할 수 없어서 별도 서브컬렉션으로 분리).
      //
      // 지역·시간·카테고리는 파티 문서가 나중에 수정/삭제돼도 통계가 그대로
      // 유지되도록 신청 시점 스냅샷으로 함께 저장한다(파티 원본을 다시 조인해서
      // 읽지 않아도 통계 집계가 가능해야 하기 때문).
      const partyDateTime = data.partyDateTime && typeof data.partyDateTime.toDate === 'function'
        ? data.partyDateTime.toDate()
        : null;
      const kst = partyDateTime ? kstParts(partyDateTime) : null;

      transaction.set(applicationRef, {
        uid,
        partyId,
        hostId: data.hostId || null,
        status: 'applied',
        gender,
        appliedFee,
        region: data.region || null,
        district: data.district || null,
        partyDateTime: data.partyDateTime || null,
        partyDate: kst?.dateKey || null,
        partyStartHour: kst?.hour ?? null,
        dayOfWeek: kst?.dayOfWeek ?? null,
        partyCategory: data.category || null,
        appliedAt: admin.firestore.FieldValue.serverTimestamp(),
        statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        confirmedAt: null,
        attendedAt: null,
        cancelledAt: null,
        ...(effectiveSelectedRounds ? { selectedRounds: effectiveSelectedRounds } : {}),
      });
    });

    return { success: true, appliedFee };
  }
);

// ── 참가자 자체 취소 (호스트가 설정한 파티별 환불 규정에 따라 자동 환불 계산) ──
//
// PartyChu는 환불률을 정하거나 권장하지 않는다 — 환불 규정은 전적으로 파티
// 등록/수정 시 호스트가 직접 입력한 refundPolicy 배열([{daysBefore, refundPercent}])을
// 그대로 따른다. 규정이 없거나(호스트 미설정) 해당 시점을 커버하는 구간이 없으면
// 환불 0%로 처리한다(임의로 유리하게/불리하게 추정하지 않음).
//
// 무료 파티(appliedFee<=0)는 환불 계산 없이 참가 취소만 처리한다.
//
// 아직 실제 PG 환불 API가 연결되어 있지 않으므로, 여기서는 refundStatus를
// 'pending'으로 저장만 해두고 실제 환불 실행은 이후 PG 연동 시 이 필드를
// 구독/폴링하는 별도 처리로 연결하기 쉬운 구조로 남겨둔다.

// computeRefund는 partyCapacity.js로 이동됨(packageBookings.js와 공유하기
// 위해) — 위 require 참고.

exports.cancelApplication = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');

    const { partyId } = request.data;
    if (!partyId || typeof partyId !== 'string') {
      throw new HttpsError('invalid-argument', 'partyId가 필요합니다.');
    }

    const uid = request.auth.uid;
    const db = admin.firestore();
    const partyRef = db.collection('parties').doc(partyId);
    const applicationRef = partyRef.collection('applications').doc(uid);

    let result;

    await db.runTransaction(async (transaction) => {
      const [partySnap, appSnap] = await Promise.all([
        transaction.get(partyRef),
        transaction.get(applicationRef),
      ]);
      if (!partySnap.exists) throw new HttpsError('not-found', '파티를 찾을 수 없어요');
      if (!appSnap.exists) throw new HttpsError('not-found', '신청 내역을 찾을 수 없어요');

      const partyData = partySnap.data();
      const appData = appSnap.data();

      if (appData.status === 'cancelled') {
        throw new HttpsError('failed-precondition', '이미취소');
      }
      if (appData.status === 'attended') {
        throw new HttpsError('failed-precondition', '이미참석');
      }

      const partyDateTime = partyData.partyDateTime;
      if (
        partyDateTime &&
        typeof partyDateTime.toDate === 'function' &&
        partyDateTime.toDate().getTime() <= Date.now()
      ) {
        throw new HttpsError('failed-precondition', '종료된파티');
      }

      const appliedFee = Number(appData.appliedFee || 0);
      const refund = computeRefund(partyData.refundPolicy, appliedFee, partyDateTime);

      // 정원/카운트 되돌리기 — reserveApplicantSlot의 증가 로직을 그대로
      // 역산하는 releaseApplicantSlot(partyCapacity.js)으로 추출돼 있다 —
      // 패키지 예약의 pending 취소/만료(cancelPackageBooking,
      // expireStalePackageBookings)와 동일한 로직을 공유한다.
      const gender = appData.gender;
      const updateData = releaseApplicantSlot(partyData, {
        uid,
        gender,
        selectedRounds: appData.selectedRounds,
      });

      transaction.update(partyRef, updateData);
      transaction.update(applicationRef, {
        status: 'cancelled',
        cancelledBy: 'user',
        refundPercent: refund.refundPercent,
        refundAmount: refund.refundAmount,
        refundStatus: refund.refundStatus,
        appliedRefundTier: refund.matchedTier,
        statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      result = { appliedFee, ...refund };
    });

    return { success: true, ...result };
  }
);

// ── 호스트가 파티 전체를 취소하면 모든 신청자에게 전액 환불 처리 ────────────
// (환불 규정과 무관하게 100% 환불 — 참가자 귀책이 아니라 호스트 귀책이므로
// 참가자가 불이익을 받지 않아야 한다는 원칙에 따른 예외 처리)
exports.onPartyCancelledByHost = onDocumentWritten(
  { document: 'parties/{partyId}', region: 'asia-northeast3' },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    if (!after) return;
    if (before?.recruitStatus === '취소' || after.recruitStatus !== '취소') return;

    const partyId = event.params.partyId;
    const db = admin.firestore();
    const applicationsSnap = await db
      .collection('parties')
      .doc(partyId)
      .collection('applications')
      .where('status', 'in', ['applied', 'approved'])
      .get();

    if (applicationsSnap.empty) return;

    const batch = db.batch();
    applicationsSnap.docs.forEach((doc) => {
      const appData = doc.data();
      const appliedFee = Number(appData.appliedFee || 0);
      batch.update(doc.ref, {
        status: 'cancelled',
        cancelledBy: 'host',
        refundPercent: appliedFee > 0 ? 100 : 0,
        refundAmount: appliedFee,
        refundStatus: appliedFee > 0 ? 'pending' : 'not_applicable',
        appliedRefundTier: null,
        statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
    batch.update(db.collection('parties').doc(partyId), { applicants: [] });
    await batch.commit();
  }
);

// ── 신청 상태 변경 → 사용자 요약 통계 + 전역 집계 반영 ───────────────────────
//
// parties/{partyId}/applications/{uid} 문서의 status가 바뀔 때마다:
//   1. userStats/{uid} 카운터 증감(신청/승인/참여/취소/노쇼/거절 구분,
//      users/{uid}.stats.*는 이 기능 도입 전 임시로 썼던 것 — 이제부터는
//      userStats가 유일한 요약 통계 출처다. 원본 기록은 이 서브컬렉션,
//      요약은 userStats로 분리)
//   2. 지역·시간대 집계(regionCounts/hourCounts)는 신청 시점(최초 생성)에만
//      1회 반영 — 같은 건이 승인→참석으로 바뀔 때마다 중복 집계하지 않는다.
//   3. dailyStats(오늘)/regionStats/hourlyStats 전역 집계도 함께 증감한다.
// 신청서 생성(added)은 신청 카운터만 +1, 이후 상태 전환(modified)은 이전
// 상태 카운터를 -1, 새 상태 카운터를 +1 한다. 문서 삭제는 현재 없음.

const STATUS_COUNTER_FIELD = {
  applied: 'totalApplications',
  approved: 'totalConfirmed',
  attended: 'totalAttended',
  cancelled: 'totalCancelled',
  rejected: 'totalRejected',
  no_show: 'totalNoShows',
};

const STATUS_TIMESTAMP_FIELD = {
  approved: 'confirmedAt',
  attended: 'attendedAt',
  cancelled: 'cancelledAt',
};

const DAILY_STATUS_FIELD = {
  applied: 'applications',
  approved: 'confirmed',
  attended: 'attended',
  cancelled: 'cancelled',
};

function argMaxKey(map) {
  if (!map) return null;
  let best = null;
  let bestVal = -Infinity;
  for (const [key, value] of Object.entries(map)) {
    if (typeof value === 'number' && value > bestVal) {
      best = key;
      bestVal = value;
    }
  }
  return best;
}

exports.onApplicationStatusWrite = onDocumentWritten(
  { document: 'parties/{partyId}/applications/{uid}', region: 'asia-northeast3' },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    if (!after) return; // 삭제는 다루지 않음

    const uid = event.params.uid;
    const prevStatus = before?.status;
    const newStatus = after.status;
    if (prevStatus === newStatus) return;

    const db = admin.firestore();
    const isTest = await isTestAccountUid(db, uid);
    const { dateKey } = kstParts(new Date());
    const regionKey = `${after.region || '기타'}_${after.district || '기타'}`;
    const hourKey = after.partyStartHour != null ? String(after.partyStartHour) : null;

    // 1) userStats 카운터 증감
    const userStatsPatch = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastParticipationAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (!before) {
      userStatsPatch[STATUS_COUNTER_FIELD.applied] = admin.firestore.FieldValue.increment(1);
    }
    if (before && prevStatus && prevStatus !== 'applied' && STATUS_COUNTER_FIELD[prevStatus]) {
      userStatsPatch[STATUS_COUNTER_FIELD[prevStatus]] = admin.firestore.FieldValue.increment(-1);
    }
    if (newStatus !== 'applied' && STATUS_COUNTER_FIELD[newStatus]) {
      userStatsPatch[STATUS_COUNTER_FIELD[newStatus]] = admin.firestore.FieldValue.increment(1);
    }
    // 2) 지역·시간대는 최초 신청 시점에만 집계
    if (!before) {
      userStatsPatch[`regionCounts.${regionKey}`] = admin.firestore.FieldValue.increment(1);
      if (hourKey != null) {
        userStatsPatch[`hourCounts.${hourKey}`] = admin.firestore.FieldValue.increment(1);
      }
    }

    const userStatsRef = db.collection('userStats').doc(uid);
    await userStatsRef.set(userStatsPatch, { merge: true });

    // 통합 회원 관리 — 최초 신청 시 게스트 활동 배지, 상태 전이마다 타임라인 로그.
    // 게스트 본인이 신청을 취소한 경우는 호스트가 파티 전체를 취소하는
    // party_cancelled(onPartyActivityLog)와 구분하기 위해 별도 이름을 쓴다.
    if (!before) {
      await addActivityRole(db, uid, 'guest_activity');
      // 관리자 웹 "승인/실제참여/취소/노쇼 수"(adminGetApplicationStatusCount)가
      // 테스트 계정 신청을 뺄 수 있도록 신청 문서 자체에도 표시해둔다.
      await event.data.after.ref.set({ isTestAccount: isTest }, { merge: true });
    }
    const APPLICATION_ACTIVITY_TYPE = {
      applied: 'party_applied',
      approved: 'party_approved',
      attended: 'party_attended',
      cancelled: 'party_application_cancelled',
      rejected: 'party_rejected',
      no_show: 'party_no_show',
    };
    const applicationActivityType = APPLICATION_ACTIVITY_TYPE[newStatus];
    if (applicationActivityType) {
      await logUserActivity(db, {
        uid,
        activityType: applicationActivityType,
        refCollection: 'applications',
        refId: event.params.partyId,
      });
    }

    // 상태별 전이 시각(승인/참석/취소) 기록 — 기존 statusUpdatedAt(마지막 변경
    // 시각)과 별도로 각 단계가 "언제" 일어났는지 구분해서 볼 수 있게 한다.
    const timestampField = STATUS_TIMESTAMP_FIELD[newStatus];
    if (timestampField) {
      await event.data.after.ref.set(
        { [timestampField]: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true }
      );
    }

    // 최초 신청 시점에만 favoriteRegion/mostUsedHour 재계산 — 방금 늘린
    // regionCounts/hourCounts를 다시 읽어 최댓값을 뽑는다.
    if (!before) {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(userStatsRef);
        const data = snap.data() || {};
        const topRegion = argMaxKey(data.regionCounts);
        const topHour = argMaxKey(data.hourCounts);
        tx.set(
          userStatsRef,
          {
            favoriteRegion: topRegion,
            mostUsedHour: topHour != null ? Number(topHour) : null,
          },
          { merge: true }
        );
      });
    }

    // 3) 전역 집계 — dailyStats(오늘, 액션이 실제로 일어난 날짜 기준). 실제
    // 서비스 KPI에 테스트 계정 활동이 섞이지 않도록 여기서부터는 전부
    // isTestAccount인 회원의 액션은 건너뛴다(userStats 등 위쪽 "본인 기록"은
    // 관리자 웹에서 이미 테스트 계정으로 구분되므로 그대로 둔다).
    const dailyField = DAILY_STATUS_FIELD[newStatus];
    if (dailyField && !isTest) {
      await db
        .collection('dailyStats')
        .doc(dateKey)
        .set({ [dailyField]: admin.firestore.FieldValue.increment(1) }, { merge: true });
    }

    // regionStats/hourlyStats는 전 기간 누적 — "신청" 시점과 "참석" 시점에만 집계
    if (!isTest && (newStatus === 'applied' || newStatus === 'attended')) {
      const regionField = newStatus === 'applied' ? 'totalApplications' : 'totalAttended';
      await db
        .collection('regionStats')
        .doc(regionKey)
        .set(
          {
            region1: after.region || null,
            region2: after.district || null,
            [regionField]: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

      if (hourKey != null) {
        const hourField = newStatus === 'applied' ? 'applications' : 'attended';
        await db
          .collection('hourlyStats')
          .doc(hourKey)
          .set(
            { hour: after.partyStartHour, [hourField]: admin.firestore.FieldValue.increment(1) },
            { merge: true }
          );
      }
    }
  }
);

// ── 신규 가입 → users 문서에 가입일/이메일/검색·정렬용 기본값 채우기 ─────────
//
// users/{uid} 문서는 지금까지 NICE 본인확인을 완료해야만(또는 다른 화면에서
// 처음 write할 때) 생성됐고 createdAt/email 필드는 어디서도 기록되지 않았다.
// Firebase Auth 계정 생성 즉시 이 트리거가 실행되어 관리자 웹의 가입일·이메일
// 표시가 항상 가능하도록 최소 필드만 merge로 남긴다.
//
// nicknameLower/nameLower/emailLower/stats.*를 빈 문자열/0으로라도 항상
// 채워두는 이유 — Firestore는 정렬 대상 필드가 아예 없는 문서를 orderBy
// 결과에서 제외한다. 이 필드들을 아예 안 채우면 "이름순"/"실제 이용 횟수순"
// 정렬 시 아직 값이 없는 회원이 통째로 목록에서 빠져버린다.
exports.onUserCreated = functionsV1
  .region('asia-northeast3')
  .auth.user()
  .onCreate(async (user) => {
    const email = user.email || '';
    const db = admin.firestore();
    await db.collection('users').doc(user.uid).set(
      {
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        email: email || null,
        emailLower: email.toLowerCase(),
        nicknameLower: '',
        nameLower: '',
        accountStatus: 'active',
        // 통계 집계 시 isTestAccount == false 필터로 실사용자만 걸러낼 수
        // 있으려면(관리자 웹 대시보드) 이 필드가 모든 회원에게 항상 존재해야
        // 한다 — Firestore는 필드가 아예 없는 문서를 등호/부등호 필터에서
        // 제외하므로, 기존 회원은 별도 백필 스크립트로 false를 채웠다.
        isTestAccount: false,
      },
      { merge: true }
    );

    const { dateKey } = kstParts(new Date());
    await db
      .collection('dailyStats')
      .doc(dateKey)
      .set({ newUsers: admin.firestore.FieldValue.increment(1) }, { merge: true });

    await logUserActivity(db, { uid: user.uid, activityType: 'signup' });
  });

// ── nickname/name/email 변경 → 검색용 소문자 필드 자동 반영 ─────────────────
//
// 관리자 웹 회원 검색(닉네임/이름/이메일 prefix 검색)은 원본 필드가 아니라
// nicknameLower/nameLower/emailLower를 조회한다 — Firestore는 대소문자
// 구분 없는 검색을 지원하지 않으므로 소문자 사본을 별도로 유지해야 한다.
// 클라이언트가 이 파생 필드를 직접 쓰지 못하도록 firestore.rules에서 막아
// 두었고(Functions만 기록), 이 트리거가 유일한 반영 경로다.
//
// 무한 루프 방지: 계산한 소문자 값이 이미 저장된 값과 같으면 아무것도 쓰지
// 않는다 — 이 트리거 자신의 쓰기가 다시 이 트리거를 건드려도 두 번째
// 실행에서는 변경 사항이 없어 멈춘다.
exports.onUserFieldsWrite = onDocumentWritten(
  { document: 'users/{uid}', region: 'asia-northeast3' },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    if (!after) return; // 삭제는 다루지 않음

    // 본인인증 최초 완료 시점 — 통합 활동 타임라인용. patch가 없어도(닉네임/
    // 이름/이메일이 이번 쓰기에서 안 바뀌었어도) 항상 검사해야 한다.
    const wasVerified = (before?.identityVerified ?? before?.isVerified) === true;
    const isVerified = (after.identityVerified ?? after.isVerified) === true;
    if (!wasVerified && isVerified) {
      await logUserActivity(admin.firestore(), {
        uid: event.params.uid,
        activityType: 'identity_verified',
      });
    }

    const wantNicknameLower = String(after.nickname || '').toLowerCase();
    const wantNameLower = String(after.name || '').toLowerCase();
    const wantEmailLower = String(after.email || '').toLowerCase();

    const patch = {};
    if ((after.nicknameLower || '') !== wantNicknameLower) patch.nicknameLower = wantNicknameLower;
    if ((after.nameLower || '') !== wantNameLower) patch.nameLower = wantNameLower;
    if ((after.emailLower || '') !== wantEmailLower) patch.emailLower = wantEmailLower;
    if (Object.keys(patch).length === 0) return;

    await event.data.after.ref.set(patch, { merge: true });

    // 닉네임/이름이 실제로 바뀐 경우에만 userStats에도 스냅샷을 반영한다(관리자
    // 웹 "이용 통계" 사용자 목록이 매번 users 컬렉션과 조인하지 않아도 되도록).
    // userStats 문서가 아직 없는 사용자(신청/찜/조회 등 활동이 전혀 없는 상태)는
    // merge:true라 이 시점에 처음 만들어진다 — 닉네임을 설정했다는 건 최소한
    // 온보딩은 마쳤다는 뜻이라 사용자 목록에 나타나도 자연스럽다.
    if (patch.nicknameLower !== undefined || patch.nameLower !== undefined) {
      await admin.firestore().collection('userStats').doc(event.params.uid).set(
        {
          nickname: after.nickname || '',
          name: after.name || '',
        },
        { merge: true }
      );
    }
  }
);

// ── 찜 추가/삭제 → 회원 통계 반영 ────────────────────────────────────────────
//
// favorites 컬렉션은 문서 생성/삭제 자체가 곧 "찜 추가"/"찜 해제" 이벤트라
// 클라이언트에 별도 analyticsEvents 로깅을 추가하지 않고 이 트리거로 감지한다.
// totalFavorites는 해제해도 줄이지 않는다 — "찜 횟수"를 현재 찜한 개수가 아니라
// 누적 참여 행동(engagement) 지표로 다루기 위함.
exports.onFavoriteWrite = onDocumentWritten(
  { document: 'favorites/{favoriteId}', region: 'asia-northeast3' },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    const db = admin.firestore();
    const { dateKey } = kstParts(new Date());

    if (!before && after) {
      // 찜 추가
      await db
        .collection('userStats')
        .doc(after.userId)
        .set(
          {
            totalFavorites: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      await db
        .collection('dailyStats')
        .doc(dateKey)
        .set({ favorites: admin.firestore.FieldValue.increment(1) }, { merge: true });

      // 찜을 받은 대상(파티/플레이스/샵/크루)의 등록자에게도 "받은 찜 수"를
      // 반영한다 — 통합 회원 관리 회원 상세의 "받은 찜 수" 통계용.
      await bumpFavoriteReceivedCount(db, after.type, after.itemId);

      await logUserActivity(db, {
        uid: after.userId,
        activityType: 'favorite_added',
        refCollection: 'favorites',
        refId: after.itemId,
        extra: { type: after.type },
      });
    } else if (before && !after) {
      // 찜 해제
      await logUserActivity(db, {
        uid: before.userId,
        activityType: 'favorite_removed',
        refCollection: 'favorites',
        refId: before.itemId,
        extra: { type: before.type },
      });
    }
    // totalFavorites/dailyStats.favorites는 해제 시 건드리지 않는다(위 설명 참고)
    // — 향후 "해제율" 같은 지표가 필요해지면 별도 카운터를 추가한다.
  }
);

// ── 파티/플레이스 등록 → 최초 등록 호스트 표시 ───────────────────────────────
// 관리자 웹 통합 회원 관리 목록의 "호스트만 보기" 필터가
// users.where('isHost','==',true)로 바로 조회할 수 있도록, 파티 또는
// 플레이스를 처음 만든 시점에 한 번만 users/{hostId}.isHost를 true로
// 세팅한다. firestore.rules가 이 필드를 클라이언트 쓰기로부터 막아두므로
// 반드시 이 트리거(Admin SDK)에서만 써야 한다.
async function markHostIfNeeded(hostId) {
  if (!hostId || typeof hostId !== 'string') return;
  const userRef = admin.firestore().collection('users').doc(hostId);
  const snap = await userRef.get();
  if (snap.exists && snap.data().isHost === true) return;
  await userRef.set(
    { isHost: true, hostSince: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true }
  );
}

// ── 파티 등록 → 일별 등록 수 집계 + 호스트 표시 + 활동 배지/통계/로그 ────────
exports.onPartyCreated = onDocumentCreated(
  { document: 'parties/{partyId}', region: 'asia-northeast3' },
  async (event) => {
    const db = admin.firestore();
    const hostId = event.data?.data()?.hostId;
    const isTest = await isTestAccountUid(db, hostId);
    // 관리자 웹 대시보드가 '등록된 파티 수' 등을 컬렉션 카운트로 직접 세므로,
    // 문서 자체에 표시해둬야 테스트 계정이 만든 파티를 그 카운트에서 뺄 수 있다.
    await event.data.ref.set({ isTestAccount: isTest }, { merge: true });

    if (!isTest) {
      const { dateKey } = kstParts(new Date());
      await db
        .collection('dailyStats')
        .doc(dateKey)
        .set({ createdParties: admin.firestore.FieldValue.increment(1) }, { merge: true });
    }

    await markHostIfNeeded(hostId);
    if (hostId) {
      if (!isTest) {
        await bumpUserStats(db, hostId, {
          totalPartiesCreated: admin.firestore.FieldValue.increment(1),
        });
      }
      await addActivityRole(db, hostId, 'host_activity');
      await logUserActivity(db, {
        uid: hostId,
        activityType: 'party_created',
        refCollection: 'parties',
        refId: event.params.partyId,
      });
    }
  }
);

// ── 플레이스 등록 → 호스트 표시 + 활동 배지/통계/로그 ────────────────────────
// places/{placeId}에는 지금까지 생성 시점 트리거가 없었다 — 이 트리거가 처음.
exports.onPlaceCreated = onDocumentCreated(
  { document: 'places/{placeId}', region: 'asia-northeast3' },
  async (event) => {
    const db = admin.firestore();
    const hostId = event.data?.data()?.hostId;
    const isTest = await isTestAccountUid(db, hostId);
    // '장소 수' 대시보드 카드도 컬렉션 카운트라 문서 자체에 표시해둬야 한다.
    await event.data.ref.set({ isTestAccount: isTest }, { merge: true });

    await markHostIfNeeded(hostId);
    if (hostId) {
      if (!isTest) {
        await bumpUserStats(db, hostId, {
          totalPlacesCreated: admin.firestore.FieldValue.increment(1),
        });
      }
      await addActivityRole(db, hostId, 'place_operator');
      await logUserActivity(db, {
        uid: hostId,
        activityType: 'place_registered',
        refCollection: 'places',
        refId: event.params.placeId,
      });
    }
  }
);

// ── 행동 로그(analyticsEvents) → 사용자/전역 통계 반영 ───────────────────────
//
// Firestore 쓰기로 자연히 파생되지 않는 "화면을 봤다" 류의 순수 조회 이벤트만
// 클라이언트가 직접 남긴다(app_open/party_view/place_view — party_apply 등은
// applications/favorites 트리거가 이미 처리하므로 여기서 다루지 않음).
// hourBucket/dayOfWeek는 클라이언트 기기 시간을 신뢰하지 않고, 이 트리거가
// occurredAt(서버 타임스탬프)을 기준으로 한국 시간으로 다시 계산해 채운다.
const ANALYTICS_USER_STATS_FIELD = {
  app_open: 'totalAppOpens',
  party_view: 'totalPartyViews',
};

exports.onAnalyticsEventCreated = onDocumentCreated(
  { document: 'analyticsEvents/{eventId}', region: 'asia-northeast3' },
  async (event) => {
    const data = event.data.data();
    if (!data) return;

    const occurredAt = data.occurredAt && typeof data.occurredAt.toDate === 'function'
      ? data.occurredAt.toDate()
      : new Date();
    const { dateKey, hour, dayOfWeek } = kstParts(occurredAt);

    const db = admin.firestore();
    const isTest = await isTestAccountUid(db, data.userId);
    const patch = { hourBucket: hour, dayOfWeek };
    await event.data.ref.set(patch, { merge: true });

    const userStatsField = ANALYTICS_USER_STATS_FIELD[data.eventType];
    if (data.userId) {
      // lastActiveAt은 관리자 웹 "이용 통계 > 사용자별 목록"이 users 컬렉션과
      // 조인하지 않고도 최근 활동일을 바로 보여주도록 모든 이벤트에 반영한다.
      const userStatsPatch = { updatedAt: admin.firestore.FieldValue.serverTimestamp() };
      userStatsPatch.lastActiveAt = admin.firestore.FieldValue.serverTimestamp();
      if (userStatsField) {
        userStatsPatch[userStatsField] = admin.firestore.FieldValue.increment(1);
      }
      await db.collection('userStats').doc(data.userId).set(userStatsPatch, { merge: true });
    }

    // dailyStats/regionStats/hourlyStats는 실제 서비스 조회수 KPI라 테스트
    // 계정의 조회는 여기서부터 제외한다(위 userStats는 본인 기록이라 그대로 둠).
    if (data.eventType === 'party_view' && !isTest) {
      await db
        .collection('dailyStats')
        .doc(dateKey)
        .set({ partyViews: admin.firestore.FieldValue.increment(1) }, { merge: true });
      await db
        .collection('hourlyStats')
        .doc(String(hour))
        .set({ hour, partyViews: admin.firestore.FieldValue.increment(1) }, { merge: true });
    }

    if (!isTest && (data.eventType === 'party_view' || data.eventType === 'place_view') && (data.region1 || data.region2)) {
      const regionKey = `${data.region1 || '기타'}_${data.region2 || '기타'}`;
      await db
        .collection('regionStats')
        .doc(regionKey)
        .set(
          {
            region1: data.region1 || null,
            region2: data.region2 || null,
            totalViews: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
    }

    // party_share는 지금까지 analyticsEvents에 기록만 되고 서버에서 아무
    // 처리도 안 하고 있었다 — 통합 활동 타임라인용 로그만 추가한다.
    if (data.eventType === 'party_share' && data.userId) {
      await logUserActivity(db, {
        uid: data.userId,
        activityType: 'party_shared',
        refCollection: 'parties',
        refId: data.partyId || null,
      });
    }
  }
);

// ── NICE 통합인증(ido/intc) 표준창 연동 ───────────────────────────────────────
//
// 보안 설계:
//   Client ID / Client Secret 은 Firebase Secret Manager에만 저장.
//   앱 코드·.env·Firestore·로그에 절대 노출되지 않음.
//   PBKDF2 유도 키(ticket 등)는 verificationSessions/{uid} 에만 보관 — 클라이언트 읽기 차단.
//   이름·생년월일·성별은 NICE 서버 검증값만 신뢰(클라이언트 입력 불수용).
//   KDF/무결성/복호화 로직은 NICE 공식 Node.js 샘플(NiceIntc_implmentation.js)과 동일하게 구현.
//
// 흐름:
//   1. niceIntcRequestUrl : access token 발급(24h 캐시) → 인증 URL 요청 → transaction_id 등 세션 저장
//   2. Flutter WebView    : auth_url 을 그대로 GET 로드 → 사용자가 표준창에서 본인확인
//   3. niceIntcResult     : return_url 로 전달된 web_transaction_id 수신 → 인증결과 조회
//                           → PBKDF2 키 유도 → 무결성 검증 → AES-256-GCM 복호화 → Firestore 저장

const NICE_RETURN_URL = 'https://partychu-30c24.web.app/nice/callback';
const NICE_CLOSE_URL  = 'https://partychu-30c24.web.app/nice/callback?closed=1';
const NICE_HOST       = 'auth.niceid.co.kr';

const niceClientId     = defineSecret('NICE_CLIENT_ID');
const niceClientSecret = defineSecret('NICE_CLIENT_SECRET');

// NICE 통합인증 API POST 요청 (HTTPS 443)
function httpsPostNiceIntc(path, bodyObj, extraHeaders) {
  const body = JSON.stringify(bodyObj);
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: NICE_HOST,
        path,
        method:   'POST',
        headers: {
          'Content-Type':   'application/json',
          'Content-Length': Buffer.byteLength(body, 'utf8'),
          ...extraHeaders,
        },
      },
      (res) => {
        let data = '';
        res.on('data', (c) => { data += c; });
        res.on('end', () => {
          try   { resolve({ status: res.statusCode, body: JSON.parse(data) }); }
          catch { reject(new Error(`NICE 응답 파싱 오류: ${data.slice(0, 200)}`)); }
        });
      },
    );
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

// 요청고유번호 (20~50byte)
function niceReqNo() {
  const ts = new Date().toISOString().replace(/[-T:.Z]/g, '').slice(0, 14);
  return 'REQ' + ts + '/' + crypto.randomBytes(14).toString('hex').slice(0, 27);
}

// 접근 토큰 발급 (24시간 유효 — Firestore(niceIntcConfig/accessToken)에 캐시하여 재사용)
async function getNiceAccessToken(clientId, clientSecret) {
  const db       = admin.firestore();
  const tokenRef = db.collection('niceIntcConfig').doc('accessToken');
  const cached   = await tokenRef.get();

  if (cached.exists) {
    const d = cached.data();
    // 만료 10분 전까지는 재사용 (신규 요청마다 토큰을 새로 발급하지 않도록)
    if (d.expiresAt && d.expiresAt.toDate().getTime() - Date.now() > 10 * 60 * 1000) {
      console.log(`[NICE] 캐시된 토큰 재사용. expiresAt=${d.expiresAt.toDate().toISOString()}`);
      return { accessToken: d.accessToken, iterators: d.iterators, ticket: d.ticket };
    }
  }

  const authHeader = 'Basic ' +
    Buffer.from(`${clientId}:${clientSecret}`).toString('base64').replace(/=+$/, '');

  const { status, body } = await httpsPostNiceIntc(
    '/ido/intc/v1.0/auth/token',
    { grant_type: 'client_credentials', request_no: niceReqNo() },
    { Authorization: authHeader, 'X-Intc-DevLang': 'Linux/Node.js' },
  );

  console.log(`[NICE] auth/token 응답. httpStatus=${status}`
    + ` result_code=${body.result_code} result_message=${body.result_message}`);

  if (status !== 200 || body.result_code !== '0000') {
    console.error('[NICE] 토큰 발급 실패:', {
      httpStatus: status, result_code: body.result_code, result_message: body.result_message,
    });
    throw new HttpsError('internal', `NICE 토큰 발급 실패 (${body.result_code || status}) ${body.result_message || ''}`.trim());
  }

  await tokenRef.set({
    accessToken: body.access_token,
    iterators:   body.iterators,
    ticket:      body.ticket,
    expiresAt:   admin.firestore.Timestamp.fromMillis(body.expires_in),
    updatedAt:   admin.firestore.FieldValue.serverTimestamp(),
  });

  return { accessToken: body.access_token, iterators: body.iterators, ticket: body.ticket };
}

// PBKDF2 키 유도 (NICE 공식 Node.js 샘플과 동일)
// key = PBKDF2(password=ticket, salt=transactionId, iterations=iterators, keylen=64, sha256) → base64url
// 대칭키    = 그 base64url 문자열의 앞 32자
// 무결성 키 = 그 base64url 문자열의 48번째 문자부터 32자
function niceDeriveKeys(ticket, transactionId, iterators) {
  const raw = crypto.pbkdf2Sync(ticket, transactionId, iterators, 64, 'sha256');
  const b64 = raw.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return { key: b64.substring(0, 32), hmacKey: b64.substring(48, 48 + 32) };
}

// HMAC-SHA256 무결성 값 (base64url) — enc_data 원문 문자열 기준
function niceIntegrityValue(encData, hmacKey) {
  const mac = crypto.createHmac('sha256', hmacKey).update(encData).digest('base64');
  return mac.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// AES-256-GCM 복호화
// enc_data(base64url) = iv(16byte) + cipherText + authTag(16byte)
function niceDecrypt(encData, key) {
  const buf          = Buffer.from(encData.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
  const iv           = buf.subarray(0, 16);
  const cipherAndTag = buf.subarray(16);
  const tag          = cipherAndTag.subarray(cipherAndTag.length - 16);
  const cipherText   = cipherAndTag.subarray(0, cipherAndTag.length - 16);

  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  const plain = Buffer.concat([decipher.update(cipherText), decipher.final()]);
  return JSON.parse(plain.toString('utf8'));
}

// ── niceIntcRequestUrl : 접근 토큰 발급/재사용 → 인증 URL 요청 ────────────────

exports.niceIntcRequestUrl = onCall(
  {
    secrets: [niceClientId, niceClientSecret],
    region: 'asia-northeast3',
    // NICE IP 화이트리스트 통과용 — Cloud NAT 고정 IP를 거치도록 VPC 커넥터 경유
    vpcConnector: 'projects/partychu-30c24/locations/asia-northeast3/connectors/nice-connector',
    vpcConnectorEgressSettings: 'ALL_TRAFFIC',
  },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');

    const uid = request.auth.uid;
    const db  = admin.firestore();

    // 이미 본인확인 완료 여부 체크
    const userSnap = await db.collection('users').doc(uid).get();
    if (userSnap.exists && userSnap.data().identityVerified === true) {
      throw new HttpsError('already-exists', '이미 본인확인이 완료된 계정입니다.');
    }

    const clientId     = niceClientId.value().trim();
    const clientSecret = niceClientSecret.value().trim();

    const { accessToken, iterators, ticket } = await getNiceAccessToken(clientId, clientSecret);

    const reqNo = niceReqNo();
    console.log(`[NICE] auth/url 요청. uid=${uid} return_url=${NICE_RETURN_URL}`
      + ` close_url=${NICE_CLOSE_URL} method_type=GET reqNo=${reqNo}`);

    const { status, body } = await httpsPostNiceIntc(
      '/ido/intc/v1.0/auth/url',
      {
        return_url:  NICE_RETURN_URL,
        close_url:   NICE_CLOSE_URL,
        svc_types:   ['M'],               // 휴대폰 본인확인만 노출
        method_type: 'GET',
        exp_mods:    ['closeButtonOn'],
        request_no:  reqNo,
      },
      { Authorization: `Bearer ${accessToken}`, 'X-Intc-DevLang': 'Linux/Node.js' },
    );

    console.log(`[NICE] auth/url 응답. uid=${uid} httpStatus=${status}`
      + ` result_code=${body.result_code} result_message=${body.result_message}`);

    if (status !== 200 || body.result_code !== '0000') {
      console.error('[NICE] 인증URL 요청 실패:', {
        uid, httpStatus: status,
        result_code: body.result_code, result_message: body.result_message,
      });
      throw new HttpsError('internal', `NICE 인증URL 요청 실패 (${body.result_code || status}) ${body.result_message || ''}`.trim());
    }

    // NICE 응답의 request_no를 우선 사용 — 공식 샘플(NiceIntc_implmentation.js)도
    // auth/url 응답의 request_no로 재할당 후 auth/result에 사용함.
    // (NICE가 요청값을 그대로 에코하지 않고 변형/재발급할 수 있어, 요청 시 보낸
    //  reqNo를 그대로 재사용하면 auth/result 단계에서 request_no 불일치로
    //  "잘못된 정보 또는 처리중 오류" 실패가 발생할 수 있음)
    const effectiveReqNo = body.request_no || reqNo;
    if (body.request_no && body.request_no !== reqNo) {
      console.warn(`[NICE] auth/url 응답 request_no가 요청값과 다름. sent=${reqNo} received=${body.request_no}`);
    }

    // 복호화에 필요한 값(ticket/iterators/transactionId) 포함 세션 저장
    // — 클라이언트 읽기 차단 (Firestore Rules 참조)
    await db.collection('verificationSessions').doc(uid).set({
      provider:      'nice_intc',
      requestNo:     effectiveReqNo,
      transactionId: body.transaction_id,
      ticket,
      iterators,
      used:          false,
      createdAt:     admin.firestore.FieldValue.serverTimestamp(),
      expiresAt:     admin.firestore.Timestamp.fromDate(new Date(Date.now() + 10 * 60 * 1000)),
    });

    console.log(`[NICE] niceIntcRequestUrl 완료. uid=${uid} reqNo=${effectiveReqNo} transactionId=${body.transaction_id}`);
    return { authUrl: body.auth_url };
  },
);

// ── niceIntcResult : 인증결과 조회 → 무결성 검증·복호화·저장 ──────────────────

exports.niceIntcResult = onCall(
  {
    secrets: [niceClientId, niceClientSecret],
    region: 'asia-northeast3',
    // NICE IP 화이트리스트 통과용 — Cloud NAT 고정 IP를 거치도록 VPC 커넥터 경유
    vpcConnector: 'projects/partychu-30c24/locations/asia-northeast3/connectors/nice-connector',
    vpcConnectorEgressSettings: 'ALL_TRAFFIC',
  },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');

    const { webTransactionId } = request.data;
    if (!webTransactionId || typeof webTransactionId !== 'string') {
      throw new HttpsError('invalid-argument', 'webTransactionId가 필요합니다.');
    }

    const uid        = request.auth.uid;
    const db         = admin.firestore();
    const sessionRef = db.collection('verificationSessions').doc(uid);
    const userRef    = db.collection('users').doc(uid);

    const sessionDoc = await sessionRef.get();
    if (!sessionDoc.exists) {
      throw new HttpsError('not-found', '인증 세션이 없습니다. 처음부터 다시 시도해주세요.');
    }
    const session = sessionDoc.data();

    if (session.provider !== 'nice_intc') {
      throw new HttpsError('failed-precondition', 'NICE 세션이 아닙니다.');
    }
    if (session.used) {
      throw new HttpsError('already-exists', '이미 사용된 인증 세션입니다. 다시 시도해주세요.');
    }
    if (session.expiresAt.toDate() < new Date()) {
      throw new HttpsError('deadline-exceeded', '인증 세션이 만료되었습니다. 다시 시도해주세요.');
    }

    // 재사용/경쟁 조건 방지 — 즉시 소비 처리
    await sessionRef.update({ used: true });

    const clientId     = niceClientId.value().trim();
    const clientSecret = niceClientSecret.value().trim();
    const { accessToken } = await getNiceAccessToken(clientId, clientSecret);

    console.log(`[NICE] auth/result 요청. uid=${uid} webTransactionId=${webTransactionId}`
      + ` transactionId=${session.transactionId} requestNo=${session.requestNo}`);

    const { status, body } = await httpsPostNiceIntc(
      '/ido/intc/v1.0/auth/result',
      {
        web_transaction_id: webTransactionId,
        transaction_id:     session.transactionId,
        request_no:         session.requestNo,
      },
      { Authorization: `Bearer ${accessToken}`, 'X-Intc-DevLang': 'Linux/Node.js' },
    );

    // NICE 응답의 result_code/result_message는 성공/실패 여부와 관계없이 항상 로그로 남김
    console.log(`[NICE] auth/result 응답. uid=${uid} httpStatus=${status}`
      + ` result_code=${body.result_code} result_message=${body.result_message}`);

    if (status !== 200 || body.result_code !== '0000') {
      console.error('[NICE] 인증결과 요청 실패:', {
        uid, httpStatus: status,
        result_code: body.result_code, result_message: body.result_message,
      });
      throw new HttpsError(
        'cancelled',
        `NICE 인증 실패 또는 취소 (${body.result_code || status}) ${body.result_message || ''}`.trim(),
      );
    }

    const { key, hmacKey } = niceDeriveKeys(session.ticket, session.transactionId, session.iterators);

    // 무결성 검증 — enc_data 위변조 여부 확인
    const expectedIntegrity = niceIntegrityValue(body.enc_data, hmacKey);
    if (expectedIntegrity !== body.integrity_value) {
      console.error('[NICE] 무결성 검증 실패:', {
        uid,
        transactionId: session.transactionId,
        expected: expectedIntegrity,
        received: body.integrity_value,
      });
      throw new HttpsError('invalid-argument', 'NICE 인증 결과 무결성 검증에 실패했습니다.');
    }

    let result;
    try {
      result = niceDecrypt(body.enc_data, key);
    } catch (e) {
      console.error('[NICE] 복호화 실패:', {
        uid,
        transactionId: session.transactionId,
        errorName: e.name,
        errorMessage: e.message,
        stack: e.stack,
      });
      throw new HttpsError('invalid-argument', 'NICE 인증 결과 복호화에 실패했습니다.');
    }

    // 인증 결과 파싱 (NICE 검증값만 신뢰, 클라이언트 입력 불수용)
    const name       = (result.name || '').trim();
    const birthdate  = result.birthdate || '';       // YYYYMMDD
    const birthYear  = birthdate.length >= 4 ? parseInt(birthdate.slice(0, 4), 10) : null;
    const birthMonth = birthdate.length >= 6 ? parseInt(birthdate.slice(4, 6), 10) : null;
    const birthDay   = birthdate.length >= 8 ? parseInt(birthdate.slice(6, 8), 10) : null;
    const gender     = result.gender === '1' ? 'male' : 'female'; // 1=남, 0=여
    const di         = result.di || '';   // 중복가입방지 정보
    const ci         = result.ci || '';   // 연계정보

    await userRef.set({
      // NICE 인증 잠금 필드 — Admin SDK만 쓸 수 있음 (Firestore Rules 참조)
      name,
      gender,
      birthYear,
      birthMonth,
      birthDay,
      di,
      ci,
      identityVerified:     true,
      identityVerifiedAt:   admin.firestore.FieldValue.serverTimestamp(),
      isVerified:           true,     // Firestore Rules 하위 호환
      verifiedAt:           admin.firestore.FieldValue.serverTimestamp(),
      profileCompleted:     true,
      verificationProvider: 'nice_intc',
    }, { merge: true });

    console.log(`[NICE] niceIntcResult 완료. uid=${uid}`);
    return { success: true };
  },
);
