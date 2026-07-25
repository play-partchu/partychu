// 홈페이지 공용 동영상 플레이어 — 파티/플레이스 목록 카드와 상세 모달이
// 모두 이 모듈 하나를 쓴다.
//
// 배경: 앱(party_app)이 올리는 영상은 Cloudflare Stream이고, Firestore에는
// HLS 매니페스트 주소(.m3u8)가 저장된다.
//   videoUrl / coverVideoUrl =
//     https://customer-<code>.cloudflarestream.com/<uid>/manifest/video.m3u8
// HLS를 네이티브로 재생할 수 있는 브라우저는 Safari(iOS/macOS)뿐이라,
// Chrome/Edge/Firefox에서 <video src="...m3u8">는 그냥 아무것도 재생되지
// 않는다(에러조차 조용히 나는 경우가 많다). 그래서 여기서 브라우저를
// 분기한다 — Safari는 네이티브, 나머지는 hls.js.
//
// 이 파일은 웹 전용이며 앱(Dart) 재생 코드와는 아무 관련이 없다.

// ─────────────────────────────────────────────────────────────────────────────
// hls.js 지연 로드
// ─────────────────────────────────────────────────────────────────────────────

const HLS_JS_URL = 'https://cdn.jsdelivr.net/npm/hls.js@1.5.20/dist/hls.min.js';

let hlsJsPromise = null;

/// hls.js를 실제로 필요한 순간에만 불러온다(Safari/iOS는 끝까지 안 받는다).
function loadHlsJs() {
  if (window.Hls) return Promise.resolve(window.Hls);
  if (hlsJsPromise) return hlsJsPromise;
  hlsJsPromise = new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = HLS_JS_URL;
    script.async = true;
    script.onload = () => resolve(window.Hls);
    script.onerror = () => reject(new Error(`hls.js 로드 실패 (${HLS_JS_URL})`));
    document.head.appendChild(script);
  });
  return hlsJsPromise;
}

// ─────────────────────────────────────────────────────────────────────────────
// URL 판별
// ─────────────────────────────────────────────────────────────────────────────

const CF_STREAM_HOST = /(?:cloudflarestream\.com|videodelivery\.net)/;

/// 'hls' | 'progressive' | 'iframe' — 재생 방식을 결정하는 형식 판별.
export function videoUrlKind(url) {
  if (!url) return 'none';
  const clean = String(url).split('?')[0];
  if (/\.m3u8$/i.test(clean)) return 'hls';
  if (/\.(mp4|webm|mov|m4v)$/i.test(clean)) return 'progressive';
  // Cloudflare Stream의 /iframe(=플레이어 페이지) 주소는 <video>에 넣을 수
  // 없다. HLS 매니페스트 주소와 절대 섞이면 안 되는 부분이라 따로 구분한다.
  if (CF_STREAM_HOST.test(clean) && /\/iframe\/?$/.test(clean)) return 'iframe';
  if (CF_STREAM_HOST.test(clean) && /\/manifest\//.test(clean)) return 'hls';
  return 'unknown';
}

/// Cloudflare Stream UID만 있고 재생 주소가 없을 때 쓰는 공용 HLS 주소.
/// (videodelivery.net은 어떤 계정의 uid든 그대로 열리는 공식 도메인)
export function hlsUrlFromUid(uid) {
  return uid ? `https://videodelivery.net/${uid}/manifest/video.m3u8` : null;
}

/// Cloudflare Stream 공식 iframe embed 주소 — HLS로도 못 트는 예외 상황의
/// 최종 폴백이다. 매니페스트 주소를 그대로 iframe에 넣는 실수를 막기 위해
/// 반드시 uid에서 새로 만든다.
export function iframeUrlFromUid(uid, { muted = true, autoplay = true, loop = true } = {}) {
  if (!uid) return null;
  const q = new URLSearchParams();
  if (muted) q.set('muted', 'true');
  if (autoplay) q.set('autoplay', 'true');
  if (loop) q.set('loop', 'true');
  q.set('controls', 'false');
  return `https://iframe.videodelivery.net/${uid}?${q.toString()}`;
}

// ─────────────────────────────────────────────────────────────────────────────
// 진단 로그 — "조용히 빈 화면"을 만들지 않기 위해 실패 원인을 전부 남긴다.
// ─────────────────────────────────────────────────────────────────────────────

const MEDIA_ERR_MEANING = {
  1: 'MEDIA_ERR_ABORTED — 사용자가 재생을 중단',
  2: 'MEDIA_ERR_NETWORK — 네트워크 오류로 다운로드 실패',
  3: 'MEDIA_ERR_DECODE — 코덱/디코딩 실패',
  4: 'MEDIA_ERR_SRC_NOT_SUPPORTED — 이 브라우저가 재생할 수 없는 형식(HLS를 그대로 넣었을 때 대부분 여기)',
};

export async function reportVideoFailure({
  scope,
  docId,
  media,
  video,
  hlsError,
  autoplayRejected,
  extra,
}) {
  const url = media?.videoUrl ?? null;
  const err = video?.error ?? null;
  /* eslint-disable no-console */
  console.group(`%c[video] 재생 실패 · ${scope}${docId ? ` · ${docId}` : ''}`, 'color:#ff4d8d');
  console.error('영상 URL           :', url);
  console.error('URL 형식           :', media?.urlKind ?? videoUrlKind(url));
  console.error('재생 방식          :', media?.playbackMode ?? '(미정)');
  console.error('video.error        :', err ? `${err.code} · ${MEDIA_ERR_MEANING[err.code] ?? '알 수 없음'} · ${err.message || ''}` : null);
  console.error('HLS 오류           :', hlsError ?? null);
  console.error('자동재생 거부 여부 :', !!autoplayRejected);
  console.error('Firestore 원본 필드:', media?.rawFields ?? null);
  if (extra) console.error('추가 정보          :', extra);
  if (url) {
    try {
      const res = await fetch(url, { method: 'GET', headers: { Range: 'bytes=0-1' } });
      console.error(
        '네트워크 응답      :',
        `${res.status} ${res.statusText} · content-type=${res.headers.get('content-type')} · CORS=${res.headers.get('access-control-allow-origin')}`,
      );
    } catch (e) {
      console.error('네트워크 응답      : 요청 자체 실패 —', e?.message || e);
    }
  }
  console.groupEnd();
  /* eslint-enable no-console */
}

// ─────────────────────────────────────────────────────────────────────────────
// 재생 조율 — 화면에 보이는 카드 하나만 재생한다.
// ─────────────────────────────────────────────────────────────────────────────

/// 소리 켜짐 여부는 페이지 전체가 공유한다(앱의 전역 음소거 버튼과 동일한
/// 개념). 브라우저 정책상 최초 재생은 반드시 muted여야 하므로 기본은 꺼짐.
let soundOn = false;

const players = new Set();
let activePlayer = null;

const visibilityObserver =
  typeof IntersectionObserver === 'undefined'
    ? null
    : new IntersectionObserver(
        (entries) => {
          for (const entry of entries) {
            const player = entry.target.__pcPlayer;
            if (player) player.visibleRatio = entry.isIntersecting ? entry.intersectionRatio : 0;
          }
          syncPlayback();
        },
        { threshold: [0, 0.25, 0.5, 0.75, 1] },
      );

/// 가장 많이 보이는 카드 하나만 재생하고 나머지는 일시정지한다.
/// (여러 영상이 동시에 재생되지 않도록 하는 지점이 여기 한 곳뿐이다)
function syncPlayback() {
  let best = null;
  for (const p of players) {
    if (!p.autoplay || p.failed) continue;
    if (p.visibleRatio >= 0.5 && (!best || p.visibleRatio > best.visibleRatio)) best = p;
  }
  for (const p of players) {
    if (p !== best && p.autoplay) p.pause();
  }
  activePlayer = best;
  if (best) best.play();
}

/// 상세 모달처럼 "무조건 이게 주인공"인 영상은 목록 재생을 멈추고 독점한다.
function pauseAllExcept(player) {
  for (const p of players) {
    if (p !== player) p.pause();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 플레이어 본체
// ─────────────────────────────────────────────────────────────────────────────

class VideoPlayer {
  /**
   * @param {HTMLElement} container 영상이 들어갈 박스(position:relative 필요)
   * @param {object} media resolveCoverMedia()가 만든 미디어 객체
   * @param {object} opts { autoplay, loop, controls, scope, docId, exclusive }
   */
  constructor(container, media, opts = {}) {
    this.container = container;
    this.media = media;
    this.opts = { autoplay: true, loop: true, controls: false, exclusive: false, ...opts };
    this.autoplay = this.opts.autoplay;
    this.visibleRatio = 0;
    this.failed = false;
    this.destroyed = false;
    this.hls = null;
    this.playRequest = null;

    this.container.classList.add('pc-video');
    this.container.innerHTML = '';
    this.container.__pcPlayer = this;

    // 1) 정지 썸네일 — 재생 전/실패 시 항상 이게 보인다. 영상이 안 나올 때
    //    빈 화면 대신 대표 이미지로 자동 대체되는 지점.
    this.poster = document.createElement('img');
    this.poster.className = 'pc-video-poster';
    this.poster.alt = '';
    this.poster.loading = 'lazy';
    if (media.posterUrl) this.poster.src = media.posterUrl;
    else this.poster.style.display = 'none';
    this.poster.addEventListener('error', () => {
      this.poster.style.display = 'none';
    });
    this.container.appendChild(this.poster);

    // 2) <video> — 웹 자동재생 정책상 muted + playsinline이 필수다.
    const video = document.createElement('video');
    this.video = video;
    video.className = 'pc-video-el';
    video.muted = true;
    video.defaultMuted = true;
    video.playsInline = true;
    video.setAttribute('playsinline', '');
    video.setAttribute('webkit-playsinline', '');
    video.loop = !!this.opts.loop;
    video.preload = 'metadata';
    video.controls = !!this.opts.controls;
    video.disableRemotePlayback = true;
    if (media.posterUrl) video.poster = media.posterUrl;
    // autoplay 속성은 일부러 걸지 않는다 — 속성이 있으면 소스가 준비되는
    // 순간 브라우저가 제멋대로 재생을 시작해, "화면에 보이는 카드 하나만
    // 재생" 규칙(syncPlayback)을 무시하고 여러 영상이 동시에 재생된다.
    // 자동재생은 아래 play()로 우리가 직접 건다(항상 muted라 정책상 허용).
    this.container.appendChild(video);

    // 3) 소리 / 수동 재생 버튼
    this.soundBtn = document.createElement('button');
    this.soundBtn.type = 'button';
    this.soundBtn.className = 'pc-video-btn pc-video-sound';
    this.soundBtn.setAttribute('aria-label', '소리 켜기');
    this.soundBtn.textContent = '🔇';
    this.soundBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      this.toggleSound();
    });
    this.container.appendChild(this.soundBtn);

    // 자동재생이 브라우저 정책으로 막히면 이 버튼이 나타난다.
    this.playBtn = document.createElement('button');
    this.playBtn.type = 'button';
    this.playBtn.className = 'pc-video-btn pc-video-play';
    this.playBtn.setAttribute('aria-label', '재생');
    this.playBtn.textContent = '▶';
    this.playBtn.hidden = true;
    this.playBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      // 사용자 제스처 안에서의 play()는 정책상 항상 허용된다.
      this.play({ userGesture: true });
    });
    this.container.appendChild(this.playBtn);

    this.onPlaying = () => {
      this.container.classList.add('is-playing');
      this.playBtn.hidden = true;
    };
    this.onWaiting = () => this.container.classList.remove('is-playing');
    this.onVideoError = () => this.handleFailure({ reason: 'video-error' });
    video.addEventListener('playing', this.onPlaying);
    video.addEventListener('waiting', this.onWaiting);
    video.addEventListener('error', this.onVideoError);

    players.add(this);
    this.attachSource();

    if (this.opts.exclusive) {
      // 상세 모달 등: 화면 안/밖 판단 없이 곧바로 독점 재생.
      pauseAllExcept(this);
      this.visibleRatio = 1;
      if (this.autoplay) this.play();
    } else if (visibilityObserver) {
      visibilityObserver.observe(this.container);
    } else {
      // IntersectionObserver가 없는 아주 오래된 브라우저 — 그냥 재생 시도.
      this.visibleRatio = 1;
      if (this.autoplay) this.play();
    }
  }

  /// 브라우저별 재생 방식 분기 — 여기가 이 모듈의 핵심.
  async attachSource() {
    const { video, media } = this;
    const url = media.videoUrl;
    if (!url) {
      this.handleFailure({ reason: 'no-url' });
      return;
    }

    if (media.urlKind === 'progressive') {
      media.playbackMode = 'native-progressive';
      video.src = url;
      this.sourceReady();
      return;
    }

    if (media.urlKind === 'iframe') {
      // <video>로는 못 트는 주소 — 공식 iframe embed로 대체한다.
      this.mountIframe(url);
      return;
    }

    // 여기부터 HLS.
    // Safari(iOS/macOS)는 HLS를 네이티브로 재생한다 — hls.js를 쓰면 오히려
    // iOS에서 MSE 미지원으로 실패하므로 반드시 네이티브를 먼저 본다.
    if (video.canPlayType('application/vnd.apple.mpegurl')) {
      media.playbackMode = 'native-hls';
      video.src = url;
      this.sourceReady();
      return;
    }

    // Chrome/Edge/Firefox — hls.js(MSE).
    try {
      const Hls = await loadHlsJs();
      if (this.destroyed) return;
      if (Hls && Hls.isSupported()) {
        media.playbackMode = 'hls.js (MSE)';
        const hls = new Hls({
          // 목록 카드에서 여러 개가 동시에 붙어도 트래픽이 튀지 않게
          // 시작은 가볍게, 자동 화질 선택.
          maxBufferLength: 10,
          maxMaxBufferLength: 30,
          capLevelToPlayerSize: true,
          startLevel: -1,
        });
        this.hls = hls;
        hls.on(Hls.Events.ERROR, (_evt, data) => {
          if (!data) return;
          if (data.fatal) {
            // 복구 가능한 종류는 hls.js 권장 절차대로 한 번 되살려 본다.
            if (data.type === Hls.ErrorTypes.NETWORK_ERROR) {
              hls.startLoad();
              return;
            }
            if (data.type === Hls.ErrorTypes.MEDIA_ERROR) {
              hls.recoverMediaError();
              return;
            }
            this.handleFailure({ reason: 'hls-fatal', hlsError: data });
          } else {
            // eslint-disable-next-line no-console
            console.warn('[video] hls.js 경고', {
              url,
              type: data.type,
              details: data.details,
            });
          }
        });
        hls.loadSource(url);
        hls.attachMedia(video);
        this.sourceReady();
        return;
      }
      // MSE도 없고 네이티브 HLS도 없는 환경(구형 안드로이드 웹뷰 등):
      // Cloudflare 공식 iframe으로 마지막 시도.
      const iframeUrl = iframeUrlFromUid(media.videoUid, { loop: this.opts.loop });
      if (iframeUrl) {
        this.mountIframe(iframeUrl);
        return;
      }
      this.handleFailure({ reason: 'hls-unsupported' });
    } catch (e) {
      this.handleFailure({ reason: 'hls-load-failed', extra: e?.message || e });
    }
  }

  /// 소스가 붙은 뒤 — 지금 재생해야 할 카드인지 다시 판단한다.
  /// (소스 연결은 비동기라 처음 화면 판정 때는 아직 준비 전일 수 있다)
  sourceReady() {
    if (this.destroyed || !this.autoplay) return;
    if (this.opts.exclusive) this.play();
    else syncPlayback();
  }

  mountIframe(src) {
    this.media.playbackMode = 'cloudflare-iframe';
    const frame = document.createElement('iframe');
    frame.className = 'pc-video-el';
    frame.src = src;
    frame.loading = 'lazy';
    frame.allow = 'accelerometer; gyroscope; autoplay; encrypted-media; picture-in-picture;';
    frame.allowFullscreen = true;
    frame.setAttribute('frameborder', '0');
    this.iframe = frame;
    this.video.remove();
    this.soundBtn.hidden = true;
    this.playBtn.hidden = true;
    this.container.appendChild(frame);
    this.container.classList.add('is-playing');
  }

  play({ userGesture = false } = {}) {
    if (this.destroyed || this.failed || this.iframe) return;
    const { video } = this;
    if (!video.paused && !video.ended) return;
    // 정책상 소리 있는 자동재생은 차단된다 — 사용자가 소리를 켠 뒤에만,
    // 그것도 실패하면 조용히 음소거로 되돌린다.
    video.muted = !(soundOn && (userGesture || activePlayer === this));
    this.syncSoundButton();
    const p = video.play();
    if (p && typeof p.catch === 'function') {
      p.catch((err) => {
        if (this.destroyed) return;
        if (!video.muted) {
          // 소리 때문에 막힌 것 — 음소거로 한 번 더.
          video.muted = true;
          this.syncSoundButton();
          video.play().catch((err2) => this.handlePlayRejection(err2));
          return;
        }
        this.handlePlayRejection(err);
      });
    }
  }

  handlePlayRejection(err) {
    if (this.destroyed) return;
    // hls.js가 소스를 새로 붙이거나 곧바로 pause()가 걸리면 진행 중이던
    // play() 프로미스가 AbortError로 끝난다 — 재생 자체는 정상이므로
    // 자동재생 차단으로 오해해서 재생 버튼을 띄우면 안 된다.
    if (err?.name === 'AbortError') return;
    if (err?.name && err.name !== 'NotAllowedError') {
      // eslint-disable-next-line no-console
      console.warn('[video] play() 거부', err.name, err.message, this.media?.videoUrl);
      return;
    }
    this.handleAutoplayBlocked(err);
  }

  handleAutoplayBlocked(err) {
    // 자동재생이 막혔다고 영상이 깨진 건 아니다 — 재생 버튼만 띄우고
    // 썸네일은 그대로 두면 사용자가 눌러서 볼 수 있다.
    this.playBtn.hidden = false;
    this.container.classList.remove('is-playing');
    // 스크롤할 때마다 재생을 다시 시도하므로, 진단 로그는 카드당 한 번만
    // 남긴다(콘솔이 같은 메시지로 도배되지 않게).
    if (this.autoplayReported) return;
    this.autoplayReported = true;
    reportVideoFailure({
      scope: this.opts.scope || 'video',
      docId: this.opts.docId,
      media: this.media,
      video: this.video,
      autoplayRejected: true,
      extra: err?.name ? `${err.name}: ${err.message}` : err,
    });
  }

  pause() {
    if (this.destroyed || this.iframe) return;
    if (!this.video.paused) this.video.pause();
    this.container.classList.remove('is-playing');
  }

  toggleSound() {
    soundOn = !soundOn;
    if (soundOn) {
      pauseAllExcept(this);
      this.video.muted = false;
      // 사용자 제스처 안이라 여기서의 play()는 소리와 함께 허용된다.
      this.video.play().catch(() => {
        this.video.muted = true;
        this.syncSoundButton();
      });
    } else {
      this.video.muted = true;
    }
    for (const p of players) p.syncSoundButton();
  }

  syncSoundButton() {
    if (!this.soundBtn) return;
    const on = !this.video.muted;
    this.soundBtn.textContent = on ? '🔊' : '🔇';
    this.soundBtn.setAttribute('aria-label', on ? '소리 끄기' : '소리 켜기');
  }

  handleFailure({ reason, hlsError, extra }) {
    if (this.failed || this.destroyed) return;
    this.failed = true;
    this.container.classList.add('has-error');
    this.container.classList.remove('is-playing');
    // 썸네일/대표 이미지로 자동 대체 — 빈 화면을 남기지 않는다.
    if (this.video) this.video.style.display = 'none';
    this.soundBtn.hidden = true;
    this.playBtn.hidden = true;
    reportVideoFailure({
      scope: this.opts.scope || 'video',
      docId: this.opts.docId,
      media: this.media,
      video: this.video,
      hlsError,
      extra: extra ?? reason,
    });
  }

  destroy() {
    if (this.destroyed) return;
    this.destroyed = true;
    players.delete(this);
    if (activePlayer === this) activePlayer = null;
    if (visibilityObserver) visibilityObserver.unobserve(this.container);
    const { video } = this;
    if (video) {
      video.removeEventListener('playing', this.onPlaying);
      video.removeEventListener('waiting', this.onWaiting);
      video.removeEventListener('error', this.onVideoError);
      try {
        video.pause();
      } catch (_) {
        /* 이미 정리된 엘리먼트 */
      }
      video.removeAttribute('src');
      try {
        video.load();
      } catch (_) {
        /* noop */
      }
    }
    // hls.js 인스턴스는 반드시 destroy() — 안 하면 세그먼트를 계속 받는다.
    if (this.hls) {
      this.hls.destroy();
      this.hls = null;
    }
    if (this.container) delete this.container.__pcPlayer;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 공개 API
// ─────────────────────────────────────────────────────────────────────────────

/// 컨테이너에 동영상을 붙인다. 반환값의 destroy()를 반드시 불러 정리한다.
export function mountVideo(container, media, opts) {
  return new VideoPlayer(container, media, opts);
}

/// [root] 안에 붙어 있는 모든 플레이어를 정리한다.
/// 목록을 다시 그리기 전(innerHTML 교체 전)에 호출해야 hls.js가 남아
/// 백그라운드로 세그먼트를 계속 받는 일이 없다.
export function destroyPlayersIn(root) {
  if (!root) return;
  const nodes = root.querySelectorAll?.('.pc-video') ?? [];
  for (const node of nodes) node.__pcPlayer?.destroy();
  if (root.classList?.contains('pc-video')) root.__pcPlayer?.destroy();
}

/// 페이지가 숨겨지면(탭 전환/뒤로가기) 전부 멈춘다.
document.addEventListener('visibilitychange', () => {
  if (document.hidden) {
    for (const p of players) p.pause();
  } else {
    syncPlayback();
  }
});
