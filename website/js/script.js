// PartyChu 공식 소개 홈페이지 — 공통 스크립트 (외부 라이브러리 의존 없음)

document.addEventListener('DOMContentLoaded', function () {
  // 모바일 메뉴 토글
  var navToggle = document.getElementById('navToggle');
  var mainNav = document.getElementById('mainNav');

  if (navToggle && mainNav) {
    navToggle.addEventListener('click', function () {
      var isOpen = mainNav.classList.toggle('open');
      navToggle.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
    });

    // 메뉴 항목 클릭 시 모바일 메뉴 자동 닫기
    mainNav.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () {
        mainNav.classList.remove('open');
      });
    });
  }

  // 현재 연도 자동 표시 (푸터 copyright)
  var yearEl = document.getElementById('currentYear');
  if (yearEl) {
    yearEl.textContent = new Date().getFullYear();
  }
});
