// 홈페이지 내 로그인 — 비로그인 상태에서도 파티 목록/상세는 그대로 보여주고,
// 찜·참가신청처럼 로그인이 필요한 동작을 누를 때만 로그인 모달을 띄운다.
// 카카오 로그인은 서버 쪽 kakaoCustomToken Cloud Function이 아직 구현되어
// 있지 않아(functions/ 전체에 카카오 관련 코드 없음) 이번 단계에서는 제외하고,
// 확실히 동작하는 Google 로그인만 제공한다.
import { auth } from './firebase-init.js';
import {
  GoogleAuthProvider,
  onAuthStateChanged,
  signInWithPopup,
  signOut,
} from 'https://www.gstatic.com/firebasejs/10.7.1/firebase-auth.js';

const loginOverlay = document.getElementById('loginOverlay');
const loginClose = document.getElementById('loginClose');
const googleLoginBtn = document.getElementById('googleLoginBtn');
const loginPromptMessage = document.getElementById('loginPromptMessage');
const loginError = document.getElementById('loginError');
const headerLoginBtn = document.getElementById('headerLoginBtn');

let currentUser = null;
let pendingResolve = null;

function openLoginModal(message) {
  if (loginPromptMessage) {
    loginPromptMessage.textContent = message || '로그인이 필요한 기능이에요.';
  }
  if (loginError) loginError.hidden = true;
  if (loginOverlay) loginOverlay.hidden = false;
}

function closeLoginModal(success) {
  if (loginOverlay) loginOverlay.hidden = true;
  if (pendingResolve) {
    pendingResolve(!!success);
    pendingResolve = null;
  }
}

loginClose?.addEventListener('click', () => closeLoginModal(false));
loginOverlay?.addEventListener('click', (e) => {
  if (e.target === loginOverlay) closeLoginModal(false);
});

googleLoginBtn?.addEventListener('click', async () => {
  try {
    await signInWithPopup(auth, new GoogleAuthProvider());
    closeLoginModal(true);
  } catch (e) {
    console.error('[auth] Google 로그인 실패', e);
    if (loginError) {
      loginError.textContent = '로그인에 실패했어요. 다시 시도해주세요.';
      loginError.hidden = false;
    }
  }
});

headerLoginBtn?.addEventListener('click', () => {
  if (currentUser) {
    signOut(auth);
  } else {
    openLoginModal('로그인하고 파티츄의 모든 기능을 이용해보세요.');
  }
});

onAuthStateChanged(auth, (user) => {
  currentUser = user;
  if (headerLoginBtn) {
    headerLoginBtn.textContent = user ? `${user.displayName || '회원'}님 · 로그아웃` : '로그인';
  }
  document.dispatchEvent(new CustomEvent('partychu:authchange', { detail: { user } }));
});

// 로그인이 필요한 동작(찜, 참가신청 등) 앞에서 호출한다 — 이미 로그인
// 상태면 바로 true로 resolve, 아니면 로그인 모달을 띄우고 로그인 성공
// 여부에 따라 true/false로 resolve한다.
export function requireLogin(message) {
  if (currentUser) return Promise.resolve(true);
  return new Promise((resolve) => {
    pendingResolve = resolve;
    openLoginModal(message);
  });
}

export function getCurrentUser() {
  return currentUser;
}
