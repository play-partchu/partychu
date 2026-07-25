// 공유 링크(https://partychu.co.kr/party/{partyId}) 전용 서버 렌더 랜딩 페이지.
//
// 왜 정적 파일이 아니라 Cloud Function인가:
// 카카오톡/페이스북/트위터 같은 공유 미리보기 크롤러는 JS를 실행하지 않고
// 최초 HTML 응답의 <meta> 태그만 읽는다. website/는 순수 정적 사이트라
// 파티마다 다른 og:title/og:image를 넣을 방법이 없다 — 그래서 이 경로만
// Cloud Function으로 라우팅해(firebase.json rewrite) 요청 시점에 Firestore
// 파티 데이터를 읽어 그 파티에 맞는 HTML을 직접 만들어 응답한다.
//
// 인증 없이 공개 접근되는 엔드포인트이므로 사용자 입력(파티 제목 등)은
// escapeHtml()로 반드시 이스케이프한 뒤 HTML에 삽입한다(XSS 방지).

const { onRequest } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const SITE_ORIGIN = 'https://partychu.co.kr';
const DEFAULT_OG_IMAGE = `${SITE_ORIGIN}/images/partychu-og-default.png`;
const ACCENT = '#FF6FA0';

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function extractPartyId(req) {
  // Hosting rewrite는 원래 경로(/party/{id})를 그대로 함수에 전달한다.
  // 혹시 다른 방식으로 붙는 경우까지 대비해 쿼리스트링도 함께 확인한다.
  const parts = (req.path || '').split('/').filter(Boolean);
  const fromPath = parts[parts.length - 1];
  return fromPath && fromPath !== 'party' ? fromPath : req.query.partyId || null;
}

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
const WEEKDAY_KO = ['일', '월', '화', '수', '목', '금', '토'];

function formatKstDateTime(timestamp) {
  if (!timestamp || typeof timestamp.toDate !== 'function') return null;
  const date = timestamp.toDate();
  const kst = new Date(date.getTime() + KST_OFFSET_MS);
  const y = kst.getUTCFullYear();
  const m = kst.getUTCMonth() + 1;
  const d = kst.getUTCDate();
  const weekday = WEEKDAY_KO[kst.getUTCDay()];
  const hour24 = kst.getUTCHours();
  const period = hour24 < 12 ? '오전' : '오후';
  const hour12 = hour24 % 12 === 0 ? 12 : hour24 % 12;
  const minute = String(kst.getUTCMinutes()).padStart(2, '0');
  return `${y}.${String(m).padStart(2, '0')}.${String(d).padStart(2, '0')} (${weekday}) ${period} ${hour12}:${minute}`;
}

function formatFee(data) {
  const maleFee = Number(data.maleFee ?? NaN);
  const femaleFee = Number(data.femaleFee ?? NaN);
  const fee = Number(data.fee ?? NaN);
  const fmt = (n) => (n <= 0 ? '무료' : `${n.toLocaleString('ko-KR')}원`);
  if (!Number.isNaN(maleFee) && !Number.isNaN(femaleFee) && maleFee !== femaleFee) {
    return `여성 ${fmt(femaleFee)} · 남성 ${fmt(maleFee)}`;
  }
  const base = !Number.isNaN(maleFee) ? maleFee : !Number.isNaN(femaleFee) ? femaleFee : (Number.isNaN(fee) ? 0 : fee);
  return fmt(base);
}

function addressLabel(data) {
  if (data.roadAddress) return data.roadAddress;
  if (data.address) return data.address;
  return data.location || '';
}

// 카카오톡/페이스북 등 공유 크롤러는 같은 URL의 OG 데이터를 자체적으로
// 오래 캐시해두고, 우리 쪽 Cache-Control(max-age=60)과 무관하게 그 캐시를
// 그대로 재사용한다 — 그래서 호스트가 대표 이미지를 바꿔도 예전에 공유된
// 미리보기가 계속 옛 이미지로 보이는 문제가 생긴다. 파티 문서가 마지막으로
// 수정된 시각(updatedAt)을 쿼리스트링 버전으로 이미지 URL에 붙여서, 대표
// 이미지가 바뀔 때마다 og:image 자체가 "새 URL"이 되어 크롤러가 다시
// 가져가도록 만든다.
function withCacheBust(url, version) {
  if (!url || !version) return url;
  const separator = url.includes('?') ? '&' : '?';
  return `${url}${separator}v=${version}`;
}

function resolveVersion(data) {
  const ts = data.updatedAt || data.createdAt;
  return ts && typeof ts.toMillis === 'function' ? ts.toMillis() : null;
}

// 대표 미디어가 동영상이면 재생 주소를 돌려준다(아니면 null).
// party_app/lib/utils/party_utils.dart의 getPartyCoverMedia와 같은 규칙 —
// coverMediaType이 'video'면 그대로 신뢰하고, 없는 옛 데이터는 "사진이
// 하나도 없고 동영상만 있을 때"만 동영상을 대표로 본다.
function resolveCoverVideo(data) {
  const nonEmpty = (v) => typeof v === 'string' && v.trim() !== '';
  if (data.coverMediaType === 'video' && nonEmpty(data.coverVideoUrl)) {
    return { url: data.coverVideoUrl, poster: data.coverThumbnailUrl || data.videoThumbnailUrl || null };
  }
  if (data.coverMediaType === 'image') return null;
  const hasPhoto =
    nonEmpty(data.mainImageUrl) ||
    (Array.isArray(data.images) && data.images.length > 0) ||
    (Array.isArray(data.imageUrls) && data.imageUrls.length > 0);
  if (nonEmpty(data.videoUrl) && !hasPhoto) {
    return { url: data.videoUrl, poster: data.videoThumbnailUrl || null };
  }
  return null;
}

// Cloudflare Stream이 주는 건 HLS(.m3u8)라 Safari 외 브라우저는 <video src>
// 로 재생하지 못한다 — Safari는 네이티브, 나머지는 hls.js로 분기한다.
// 실패하면 <video>를 감추고 아래 깔린 썸네일이 그대로 보인다.
function videoHtml({ url, poster }, title) {
  return `
    <div class="hero-media">
      ${poster ? `<img class="hero-poster" src="${escapeHtml(poster)}" alt="${escapeHtml(title)}" onerror="this.style.display='none'">` : ''}
      <video id="heroVideo" class="hero-video" muted autoplay loop playsinline webkit-playsinline preload="metadata"${poster ? ` poster="${escapeHtml(poster)}"` : ''}></video>
      <button id="heroSound" class="hero-btn hero-sound" type="button" aria-label="소리 켜기">&#128263;</button>
      <button id="heroPlay" class="hero-btn hero-play" type="button" aria-label="재생" hidden>&#9654;</button>
    </div>
    <script>
    (function () {
      var src = ${JSON.stringify(url)};
      var video = document.getElementById('heroVideo');
      var soundBtn = document.getElementById('heroSound');
      var playBtn = document.getElementById('heroPlay');
      function fail(reason, detail) {
        console.error('[party-landing] 동영상 재생 실패', {
          '영상 URL': src,
          'URL 형식': /\\.m3u8($|\\?)/i.test(src) ? 'hls' : 'progressive/unknown',
          '실패 지점': reason,
          'video.error': video.error ? { code: video.error.code, message: video.error.message } : null,
          '상세': detail || null
        });
        video.style.display = 'none';
        soundBtn.hidden = true;
        playBtn.hidden = true;
      }
      function start() {
        var p = video.play();
        if (p && p.catch) {
          p.catch(function (err) {
            // 자동재생 차단 — 영상이 깨진 게 아니므로 재생 버튼만 띄운다.
            console.warn('[party-landing] 자동재생 거부됨:', err && err.name, err && err.message);
            playBtn.hidden = false;
          });
        }
      }
      video.addEventListener('playing', function () { video.classList.add('is-playing'); playBtn.hidden = true; });
      video.addEventListener('error', function () { fail('video-error'); });
      playBtn.addEventListener('click', function () { playBtn.hidden = true; start(); });
      soundBtn.addEventListener('click', function () {
        video.muted = !video.muted;
        soundBtn.innerHTML = video.muted ? '&#128263;' : '&#128266;';
        soundBtn.setAttribute('aria-label', video.muted ? '소리 켜기' : '소리 끄기');
        if (!video.muted) video.play().catch(function () { video.muted = true; soundBtn.innerHTML = '&#128263;'; });
      });

      var isHls = /\\.m3u8($|\\?)/i.test(src) || /\\/manifest\\//.test(src);
      if (!isHls || video.canPlayType('application/vnd.apple.mpegurl')) {
        video.src = src;
        start();
        return;
      }
      var s = document.createElement('script');
      s.src = 'https://cdn.jsdelivr.net/npm/hls.js@1.5.20/dist/hls.min.js';
      s.onload = function () {
        if (!window.Hls || !window.Hls.isSupported()) { fail('hls-unsupported'); return; }
        var hls = new window.Hls({ maxBufferLength: 10, capLevelToPlayerSize: true });
        hls.on(window.Hls.Events.ERROR, function (_e, d) {
          if (!d || !d.fatal) return;
          if (d.type === window.Hls.ErrorTypes.NETWORK_ERROR) { hls.startLoad(); return; }
          if (d.type === window.Hls.ErrorTypes.MEDIA_ERROR) { hls.recoverMediaError(); return; }
          fail('hls-fatal', { type: d.type, details: d.details, reason: d.reason });
          hls.destroy();
        });
        hls.loadSource(src);
        hls.attachMedia(video);
        start();
        window.addEventListener('pagehide', function () { hls.destroy(); });
      };
      s.onerror = function () { fail('hls-js-load-failed'); };
      document.head.appendChild(s);
    })();
    <\/script>`;
}

function pageShell({ title, description, image, url, bodyHtml, refresh }) {
  return `<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
${refresh ? `<meta http-equiv="refresh" content="${refresh}">` : ''}
<title>${escapeHtml(title)}</title>
<meta name="description" content="${escapeHtml(description)}">
<meta property="og:type" content="website">
<meta property="og:title" content="${escapeHtml(title)}">
<meta property="og:description" content="${escapeHtml(description)}">
<meta property="og:image" content="${escapeHtml(image)}">
<meta property="og:url" content="${escapeHtml(url)}">
<meta property="og:site_name" content="PartyChu">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${escapeHtml(title)}">
<meta name="twitter:description" content="${escapeHtml(description)}">
<meta name="twitter:image" content="${escapeHtml(image)}">
<style>
  * { box-sizing: border-box; }
  body {
    margin: 0; font-family: -apple-system, BlinkMacSystemFont, 'Apple SD Gothic Neo', 'Malgun Gothic', sans-serif;
    background: #FFF4F8; color: #1F2430; display: flex; justify-content: center; padding: 32px 16px;
  }
  .card {
    width: 100%; max-width: 420px; background: #fff; border-radius: 20px; overflow: hidden;
    box-shadow: 0 8px 24px rgba(0,0,0,0.06);
  }
  .card > img { width: 100%; height: 240px; object-fit: cover; display: block; background: #E9ECF5; }
  .hero-media { position: relative; width: 100%; height: 240px; background: #E9ECF5; overflow: hidden; }
  .hero-poster, .hero-video { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; display: block; }
  .hero-video { opacity: 0; transition: opacity .25s ease; }
  .hero-video.is-playing { opacity: 1; }
  .hero-btn {
    position: absolute; border: 0; border-radius: 999px; background: rgba(0,0,0,.45); color: #fff;
    cursor: pointer; line-height: 1; display: flex; align-items: center; justify-content: center;
  }
  .hero-sound { right: 12px; bottom: 12px; width: 34px; height: 34px; font-size: 15px; }
  .hero-play { left: 50%; top: 50%; transform: translate(-50%,-50%); width: 54px; height: 54px; font-size: 20px; }
  .card-body { padding: 24px; }
  .eyebrow { color: ${ACCENT}; font-weight: 700; font-size: 13px; }
  h1 { font-size: 21px; margin: 8px 0 16px; line-height: 1.35; }
  .meta-row { display: flex; gap: 8px; font-size: 14.5px; color: #444; margin-bottom: 8px; }
  .meta-row .label { color: #999; min-width: 44px; }
  .actions { margin-top: 24px; display: flex; flex-direction: column; gap: 10px; }
  .btn {
    display: block; text-align: center; padding: 14px; border-radius: 12px; font-weight: 700;
    text-decoration: none; font-size: 15px;
  }
  .btn-primary { background: ${ACCENT}; color: #fff; }
  .btn-secondary { background: #F5F6FA; color: #333; }
  .logo { text-align: center; margin-bottom: 18px; font-weight: 800; font-size: 18px; color: ${ACCENT}; }
</style>
</head>
<body>
  <div class="card">
    <div style="padding-top:20px"><div class="logo">Party<span style="color:#1F2430">Chu</span></div></div>
    ${bodyHtml}
  </div>
</body>
</html>`;
}

function notFoundHtml(url) {
  return pageShell({
    title: '존재하지 않는 파티 · PartyChu',
    description: '존재하지 않거나 종료된 파티입니다.',
    image: DEFAULT_OG_IMAGE,
    url,
    refresh: `3;url=${SITE_ORIGIN}/`,
    bodyHtml: `
      <div class="card-body" style="text-align:center;">
        <p style="font-size:16px;font-weight:700;margin:24px 0 8px;">존재하지 않거나 종료된 파티입니다.</p>
        <p style="color:#888;font-size:13.5px;margin-bottom:24px;">3초 후 PartyChu 홈으로 이동합니다.</p>
        <a class="btn btn-primary" href="${SITE_ORIGIN}/">지금 홈으로 이동</a>
      </div>`,
  });
}

exports.partyLandingPage = onRequest({ region: 'asia-northeast3', cors: true }, async (req, res) => {
  const partyId = extractPartyId(req);
  const url = `${SITE_ORIGIN}/party/${partyId || ''}`;

  if (!partyId) {
    res.status(404).set('Content-Type', 'text/html; charset=utf-8').send(notFoundHtml(url));
    return;
  }

  let data = null;
  try {
    const doc = await admin.firestore().collection('parties').doc(partyId).get();
    if (doc.exists) data = doc.data();
  } catch (e) {
    console.error('[partyLandingPage] Firestore read failed:', e);
  }

  const isGone = !data || data.isDeleted === true || data.status === 'deleted';
  if (isGone) {
    res.status(404).set('Content-Type', 'text/html; charset=utf-8').send(notFoundHtml(url));
    return;
  }

  const title = data.title || '파티';
  const address = addressLabel(data);
  const dateLabel = formatKstDateTime(data.partyDateTime);
  const feeLabel = formatFee(data);
  // 호스트가 고른 "대표 미디어"(사진이든 동영상이든)를 최우선으로 쓴다 —
  // coverThumbnailUrl은 등록 화면에서 대표가 동영상이든 사진이든 항상
  // 채워지는 정지 이미지라(party_register_screen.dart), 앱이 실제로
  // 보여주는 대표 화면과 공유 미리보기가 일치하려면 이걸 먼저 봐야 한다.
  // 예전엔 mainImageUrl/images[0]/imageUrls[0]만 봐서, 대표를 동영상으로
  // 고른 파티는 엉뚱한(또는 아예 없는) 사진이 공유 미리보기에 떴다.
  // 아래 필드는 전부 이 요청에서 읽은 이 파티(data) 문서 안의 값만
  // 참조하므로 다른 파티의 이미지가 섞일 수 없다 — 이 파티에 값이 하나도
  // 없을 때만 정적 기본 이미지(DEFAULT_OG_IMAGE)로 떨어진다.
  const rawImage = data.coverThumbnailUrl
    || data.coverImageUrl
    || data.mainImageUrl
    || (Array.isArray(data.images) && data.images[0])
    || (Array.isArray(data.imageUrls) && data.imageUrls[0])
    || data.videoThumbnailUrl
    || null;
  const image = rawImage ? withCacheBust(rawImage, resolveVersion(data)) : DEFAULT_OG_IMAGE;

  const descriptionParts = [dateLabel, address, feeLabel].filter(Boolean);
  const description = descriptionParts.length ? descriptionParts.join(' · ') : 'PartyChu에서 파티 상세정보를 확인해보세요.';

  // 앱이 partychu:// 스킴을 처리하도록 등록되어 있으면(추후 릴리스) 앱에서
  // 바로 열리고, 아직 처리하지 못하는 기기(대부분의 현재 사용자)에서는
  // 아무 반응 없이 이 웹페이지가 그대로 보인다 — 안전한 점진적 개선.
  const appScheme = `partychu://party/${escapeHtml(partyId)}`;

  // 대표가 동영상인 파티는 정지 이미지 대신 실제로 재생되는 플레이어를
  // 보여준다(og:image는 크롤러용이라 그대로 썸네일을 쓴다).
  const coverVideo = resolveCoverVideo(data);
  const heroHtml = coverVideo
    ? videoHtml({ url: coverVideo.url, poster: coverVideo.poster || (rawImage ? image : null) }, title)
    : `<img src="${escapeHtml(image)}" alt="${escapeHtml(title)}" onerror="this.style.display='none'">`;

  const bodyHtml = `
    ${heroHtml}
    <div class="card-body">
      <div class="eyebrow">PartyChu</div>
      <h1>${escapeHtml(title)}</h1>
      ${dateLabel ? `<div class="meta-row"><span class="label">일시</span><span>${escapeHtml(dateLabel)}</span></div>` : ''}
      ${address ? `<div class="meta-row"><span class="label">장소</span><span>${escapeHtml(address)}</span></div>` : ''}
      <div class="meta-row"><span class="label">참가비</span><span>${escapeHtml(feeLabel)}</span></div>
      <div class="actions">
        <a class="btn btn-primary" href="${appScheme}">PartyChu 앱에서 보기</a>
        <a class="btn btn-secondary" href="${SITE_ORIGIN}/">PartyChu 홈으로</a>
      </div>
    </div>`;

  const html = pageShell({ title: `${title} · PartyChu`, description, image, url, bodyHtml });
  res.status(200).set('Content-Type', 'text/html; charset=utf-8').set('Cache-Control', 'public, max-age=60').send(html);
});
