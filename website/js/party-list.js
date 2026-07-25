// 홈페이지 "파티 찾기" 섹션 — party_app이 쓰는 것과 같은 Firestore
// 'parties' 컬렉션을 실시간 구독(onSnapshot)해 카드 그리드로 보여준다.
// 비로그인 상태에서도 전부 조회 가능(firestore.rules: parties는 공개 읽기),
// 찜/참가신청처럼 로그인이 필요한 동작만 requireLogin()으로 게이트한다.
import { db } from './firebase-init.js';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  onSnapshot,
  setDoc,
} from 'https://www.gstatic.com/firebasejs/10.7.1/firebase-firestore.js';
import { getCurrentUser, requireLogin } from './auth.js';
import {
  addressLabel,
  capacityLabel,
  coverImage,
  coverMedia,
  formatFee,
  formatKstDateTime,
  genderLabel,
  isRecruitClosed,
  isUpcoming,
  matchesCategory,
  mediaItems,
  partyDateTime,
} from './party-format.js';
import { destroyPlayersIn, mountVideo, videoUrlKind } from './video-player.js';

const grid = document.getElementById('partyGrid');
const statusEl = document.getElementById('partyListStatus');
const searchInput = document.getElementById('partySearchInput');
const filterChips = Array.from(document.querySelectorAll('#partyFilterChips .chip'));
const detailOverlay = document.getElementById('partyDetailOverlay');
const detailContent = document.getElementById('partyDetailContent');
const detailClose = document.getElementById('partyDetailClose');

let allParties = [];
let favoriteIds = new Set();
// 날짜 카테고리는 이제 복수 선택(OR 조건)이다 — 비어 있으면 "전체"(모든 날짜).
// main_screen.dart의 _selectedCategories와 동일한 개념(빈 Set = 전체).
let selectedFilters = new Set();
let searchQuery = '';

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function matchesSearch(data, query) {
  if (!query) return true;
  const haystack = `${data.title || ''} ${addressLabel(data)}`.toLowerCase();
  return haystack.includes(query.toLowerCase());
}

// 선택된 날짜 카테고리 중 하나라도 맞으면 통과(OR). 아무것도 선택 안 하면 전체.
function matchesSelectedFilters(data) {
  if (selectedFilters.size === 0) return true;
  for (const cat of selectedFilters) {
    if (matchesCategory(data, cat)) return true;
  }
  return false;
}

function visibleParties() {
  return allParties.filter(
    (p) => isUpcoming(p.data) && matchesSelectedFilters(p.data) && matchesSearch(p.data, searchQuery),
  );
}

// 대표 미디어가 동영상인 카드는 썸네일만 깔고 <video>는 render() 뒤에
// mountPlayers()가 붙인다 — 카드마다 hls.js 인스턴스를 만들어야 해서
// innerHTML 문자열로는 만들 수 없다.
function mediaHtml(id, data) {
  const media = coverMedia(data);
  if (media?.kind === 'video') {
    const poster = media.posterUrl ? ` style="background-image:url('${encodeURI(media.posterUrl)}')"` : '';
    return `<div class="party-card-media" data-video-for="${id}"${poster}></div>`;
  }
  const img = media?.imageUrl || coverImage(data);
  return img
    ? `<div class="party-card-photo" style="background-image:url('${encodeURI(img)}')"></div>`
    : '<span class="party-card-noimg">🎉</span>';
}

function cardHtml(p) {
  const { id, data } = p;
  const dateLabel = formatKstDateTime(partyDateTime(data));
  const address = addressLabel(data);
  const fee = formatFee(data);
  const cap = capacityLabel(data);
  const closed = isRecruitClosed(data);
  const favored = favoriteIds.has(id);
  return `
    <div class="party-card${closed ? ' party-card-closed' : ''}" data-party-id="${id}" tabindex="0" role="button" aria-label="${escapeHtml(data.title || '파티')} 상세보기">
      <div class="party-card-img">
        ${mediaHtml(id, data)}
        ${closed ? '<span class="party-card-badge">모집마감</span>' : ''}
        <button class="party-favorite${favored ? ' active' : ''}" data-party-id="${id}" aria-label="찜하기">${favored ? '❤️' : '🤍'}</button>
      </div>
      <div class="party-card-body">
        <h3>${escapeHtml(data.title || '제목 없는 파티')}</h3>
        ${dateLabel ? `<p class="party-card-meta">🗓️ ${escapeHtml(dateLabel)}</p>` : ''}
        ${address ? `<p class="party-card-meta">📍 ${escapeHtml(address)}</p>` : ''}
        <div class="party-card-foot">
          <span class="party-card-fee">${escapeHtml(fee)}</span>
          ${cap ? `<span class="party-card-cap">${escapeHtml(cap)}</span>` : ''}
        </div>
      </div>
    </div>`;
}

// 카드가 다시 그려질 때마다 이전 플레이어를 정리하고 새로 붙인다.
// (정리하지 않으면 떨어져 나간 <video>와 hls.js가 계속 세그먼트를 받는다)
function mountPlayers() {
  grid.querySelectorAll('[data-video-for]').forEach((box) => {
    const id = box.getAttribute('data-video-for');
    const party = allParties.find((x) => x.id === id);
    if (!party) return;
    const media = coverMedia(party.data);
    if (media?.kind !== 'video') return;
    media.urlKind = videoUrlKind(media.videoUrl);
    mountVideo(box, media, {
      scope: 'party-card',
      docId: id,
      autoplay: true,
      loop: true,
      controls: false,
    });
  });
}

function render() {
  if (!grid || !statusEl) return;
  const filtered = visibleParties();
  destroyPlayersIn(grid);

  if (!filtered.length) {
    grid.hidden = true;
    statusEl.hidden = false;
    statusEl.textContent = allParties.length
      ? '조건에 맞는 파티가 없어요. 다른 필터를 선택해보세요.'
      : '아직 등록된 파티가 없어요.';
    return;
  }

  statusEl.hidden = true;
  grid.hidden = false;
  grid.innerHTML = filtered.map(cardHtml).join('');

  grid.querySelectorAll('[data-party-id]').forEach((card) => {
    card.addEventListener('click', (e) => {
      if (e.target.closest('.party-favorite')) return;
      openDetail(card.getAttribute('data-party-id'));
    });
    card.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') openDetail(card.getAttribute('data-party-id'));
    });
  });
  grid.querySelectorAll('.party-favorite').forEach((btn) => {
    btn.addEventListener('click', async (e) => {
      e.stopPropagation();
      const id = btn.getAttribute('data-party-id');
      const ok = await requireLogin('파티를 찜하려면 로그인이 필요해요.');
      if (ok) await toggleFavorite(id, btn);
    });
  });
  mountPlayers();
}

function detailHtml(p) {
  const { data } = p;
  const dateLabel = formatKstDateTime(partyDateTime(data));
  const address = addressLabel(data);
  const fee = formatFee(data);
  const cap = capacityLabel(data);
  const gender = genderLabel(data);
  const closed = isRecruitClosed(data);
  return `
    <div class="party-detail-media" id="partyDetailMedia"></div>
    <div class="party-detail-body">
      ${closed ? '<span class="party-card-badge party-detail-badge">모집마감</span>' : ''}
      <h2>${escapeHtml(data.title || '제목 없는 파티')}</h2>
      ${dateLabel ? `<div class="party-detail-row"><span class="label">일시</span><span>${escapeHtml(dateLabel)}</span></div>` : ''}
      ${address ? `<div class="party-detail-row"><span class="label">장소</span><span>${escapeHtml(address)}</span></div>` : ''}
      <div class="party-detail-row"><span class="label">참가비</span><span>${escapeHtml(fee)}</span></div>
      ${cap ? `<div class="party-detail-row"><span class="label">인원</span><span>${escapeHtml(cap)}</span></div>` : ''}
      <div class="party-detail-row"><span class="label">참가조건</span><span>${escapeHtml(gender)}</span></div>
      ${data.description ? `<p class="party-detail-desc">${escapeHtml(data.description)}</p>` : ''}
      <div class="party-detail-actions">
        <button class="btn btn-primary" id="partyApplyBtn" ${closed ? 'disabled' : ''}>${closed ? '모집이 마감됐어요' : '참가 신청하기'}</button>
      </div>
    </div>`;
}

// 상세 모달의 미디어 슬라이드 — 사진과 동영상이 섞여 있어도 각 항목의
// kind로 판별해서, 동영상 슬라이드에서는 플레이어를 새로 붙이고 슬라이드를
// 벗어나면 즉시 정리한다(다른 슬라이드에서 소리가 계속 나는 일이 없다).
function mountDetailMedia(container, items, docId) {
  if (!container) return;
  if (!items.length) {
    container.remove();
    return;
  }
  let index = 0;

  const stage = document.createElement('div');
  stage.className = 'party-detail-stage';
  container.appendChild(stage);

  const showItem = () => {
    destroyPlayersIn(stage);
    stage.innerHTML = '';
    const item = items[index];
    if (item.kind === 'video') {
      const box = document.createElement('div');
      box.className = 'party-detail-video';
      stage.appendChild(box);
      item.urlKind = videoUrlKind(item.videoUrl);
      mountVideo(box, item, {
        scope: 'party-detail',
        docId,
        autoplay: true,
        loop: true,
        // 상세에서는 사용자가 직접 조작할 수 있어야 한다.
        controls: true,
        exclusive: true,
      });
    } else {
      const img = document.createElement('img');
      img.className = 'party-detail-img';
      img.src = item.imageUrl;
      img.alt = '';
      stage.appendChild(img);
    }
    container.querySelectorAll('.party-detail-dot').forEach((dot, i) => {
      dot.classList.toggle('active', i === index);
    });
  };

  if (items.length > 1) {
    const nav = document.createElement('div');
    nav.className = 'party-detail-dots';
    items.forEach((item, i) => {
      const dot = document.createElement('button');
      dot.type = 'button';
      dot.className = 'party-detail-dot';
      dot.setAttribute('aria-label', `${i + 1}번째 ${item.kind === 'video' ? '동영상' : '사진'}`);
      dot.addEventListener('click', () => {
        index = i;
        showItem();
      });
      nav.appendChild(dot);
    });
    container.appendChild(nav);

    const arrow = (dir, label) => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = `party-detail-arrow ${dir < 0 ? 'prev' : 'next'}`;
      btn.setAttribute('aria-label', label);
      btn.textContent = dir < 0 ? '‹' : '›';
      btn.addEventListener('click', () => {
        index = (index + dir + items.length) % items.length;
        showItem();
      });
      container.appendChild(btn);
    };
    arrow(-1, '이전 미디어');
    arrow(1, '다음 미디어');
  }

  showItem();
}

function closeDetail() {
  if (!detailOverlay) return;
  // 모달을 닫을 때 반드시 hls.destroy()까지 도달해야 소리가 남지 않는다.
  destroyPlayersIn(detailContent);
  if (detailContent) detailContent.innerHTML = '';
  detailOverlay.hidden = true;
  render();
}

function openDetail(id) {
  const p = allParties.find((x) => x.id === id);
  if (!p || !detailContent || !detailOverlay) return;
  destroyPlayersIn(detailContent);
  detailContent.innerHTML = detailHtml(p);
  mountDetailMedia(document.getElementById('partyDetailMedia'), mediaItems(p.data), id);
  document.getElementById('partyApplyBtn')?.addEventListener('click', async () => {
    const ok = await requireLogin('파티 참가 신청은 로그인 후 이용할 수 있어요.');
    if (ok) {
      alert('참가 신청 기능은 곧 웹에서도 제공될 예정이에요. 지금은 파티츄 앱에서 신청해주세요!');
    }
  });
  detailOverlay.hidden = false;
}

detailClose?.addEventListener('click', closeDetail);
detailOverlay?.addEventListener('click', (e) => {
  if (e.target === detailOverlay) closeDetail();
});
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && detailOverlay && !detailOverlay.hidden) closeDetail();
});

async function toggleFavorite(partyId, btn) {
  const user = getCurrentUser();
  if (!user) return;
  const favId = `${user.uid}_party_${partyId}`;
  const ref = doc(db, 'favorites', favId);
  try {
    if (favoriteIds.has(partyId)) {
      await deleteDoc(ref);
      favoriteIds.delete(partyId);
      btn.textContent = '🤍';
      btn.classList.remove('active');
    } else {
      await setDoc(ref, {
        userId: user.uid,
        type: 'party',
        itemId: partyId,
        createdAt: new Date().toISOString(),
      });
      favoriteIds.add(partyId);
      btn.textContent = '❤️';
      btn.classList.add('active');
    }
  } catch (e) {
    console.error('[party-list] 찜 처리 실패', e);
  }
}

async function loadFavoriteIds(user) {
  favoriteIds = new Set();
  if (!user) {
    render();
    return;
  }
  // 문서 id 자체가 "{uid}_party_{partyId}" 형식이라(favorites_service.dart와
  // 동일 규칙) 목록 화면에서 매번 컬렉션 전체를 훑는 대신, 현재 그리드에
  // 보이는 파티들만 존재 여부를 확인한다.
  await Promise.all(
    allParties.map(async (p) => {
      try {
        const snap = await getDoc(doc(db, 'favorites', `${user.uid}_party_${p.id}`));
        if (snap.exists()) favoriteIds.add(p.id);
      } catch (e) {
        // 권한/네트워크 오류는 조용히 무시 — 찜 표시만 비어 보일 뿐 목록 자체는 정상 동작.
      }
    }),
  );
  render();
}

searchInput?.addEventListener('input', (e) => {
  searchQuery = e.target.value.trim();
  render();
});

// "전체"는 배타 선택(누르면 모든 날짜 선택 해제), 나머지 넷은 복수 토글이다.
// 하나라도 날짜가 선택되면 "전체"는 자동으로 비활성, 모두 해제되면 "전체"가
// 다시 켜진다 — main_screen.dart의 날짜 카테고리 탭과 동일한 규칙.
function syncFilterChipStyles() {
  filterChips.forEach((chip) => {
    const f = chip.getAttribute('data-filter');
    const active = f === 'all' ? selectedFilters.size === 0 : selectedFilters.has(f);
    chip.classList.toggle('active', active);
    chip.setAttribute('aria-pressed', active ? 'true' : 'false');
  });
}

filterChips.forEach((chip) => {
  chip.setAttribute('role', 'button');
  chip.setAttribute('aria-pressed', 'false');
  chip.addEventListener('click', () => {
    const f = chip.getAttribute('data-filter');
    if (f === 'all') {
      selectedFilters.clear();
    } else if (selectedFilters.has(f)) {
      selectedFilters.delete(f);
    } else {
      selectedFilters.add(f);
    }
    syncFilterChipStyles();
    render();
  });
});
syncFilterChipStyles();

document.addEventListener('partychu:authchange', (e) => {
  loadFavoriteIds(e.detail.user);
});

onSnapshot(
  collection(db, 'parties'),
  (snap) => {
    allParties = snap.docs
      .map((d) => ({ id: d.id, data: d.data() }))
      .filter((p) => p.data.isDeleted !== true && p.data.status !== 'deleted');
    render();
    loadFavoriteIds(getCurrentUser());
  },
  (err) => {
    console.error('[party-list] Firestore 구독 실패', err);
    if (statusEl) {
      statusEl.hidden = false;
      statusEl.textContent = '파티 목록을 불러오지 못했어요. 잠시 후 다시 시도해주세요.';
    }
    if (grid) grid.hidden = true;
  },
);
