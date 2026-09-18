(function () {
  // 스크롤 등장 효과 — IntersectionObserver가 없으면 전부 바로 보인다.
  var items = [].slice.call(document.querySelectorAll('.reveal'));
  if (!('IntersectionObserver' in window)) {
    items.forEach(function (el) { el.classList.add('in'); });
  } else {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('in');
          io.unobserve(entry.target);
        }
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    items.forEach(function (el) { io.observe(el); });
  }

  // 하단 고정 신청 버튼 — 첫 화면 버튼이 지나간 뒤부터, 마지막 신청 섹션 전까지만.
  var sticky = document.getElementById('sticky');
  var heroCta = document.querySelector('.hero-cta');
  var apply = document.getElementById('apply');
  if (!sticky || !heroCta || !apply) return;
  var ticking = false;
  function update() {
    ticking = false;
    var passedHero = heroCta.getBoundingClientRect().bottom < 0;
    var beforeFinal = apply.getBoundingClientRect().top > window.innerHeight * 0.7;
    sticky.classList.toggle('show', passedHero && beforeFinal);
  }
  window.addEventListener('scroll', function () {
    if (!ticking) { ticking = true; window.requestAnimationFrame(update); }
  }, { passive: true });
  update();
})();
