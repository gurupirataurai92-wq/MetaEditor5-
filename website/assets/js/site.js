/* ==========================================================================
   Lymond Services — public site behaviour
   Filtering, sorting and paging are done by the server now, so this file only
   handles the things that genuinely belong in the browser.
   ========================================================================== */
(function () {
  'use strict';

  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };

  /* ------------------------------------------------------- mobile menu -- */
  var toggle = $('.nav-toggle');
  var menu = $('.nav-menu');
  if (toggle && menu) {
    toggle.addEventListener('click', function () {
      var open = menu.classList.toggle('open');
      toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
    $$('a', menu).forEach(function (a) {
      a.addEventListener('click', function () {
        menu.classList.remove('open');
        toggle.setAttribute('aria-expanded', 'false');
      });
    });
  }

  /* ----------------------------------------------------- photo gallery -- */
  var mainImg = $('#gallery-main-img');
  if (mainImg) {
    $$('.gallery-thumb').forEach(function (thumb) {
      thumb.addEventListener('click', function () {
        mainImg.src = thumb.getAttribute('data-full');
        $$('.gallery-thumb').forEach(function (t) { t.classList.remove('is-active'); });
        thumb.classList.add('is-active');
      });
    });
  }

  /* --------------------------------------------------- reveal on scroll -- */
  var revealables = $$('.reveal');
  if (revealables.length) {
    if ('IntersectionObserver' in window) {
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) { entry.target.classList.add('in'); io.unobserve(entry.target); }
        });
      }, { rootMargin: '0px 0px -60px 0px', threshold: 0.08 });
      revealables.forEach(function (el) { io.observe(el); });
    } else {
      revealables.forEach(function (el) { el.classList.add('in'); });
    }
  }

  /* Submitting a filter form should always start at the first page. */
  $$('form.toolbar').forEach(function (form) {
    form.addEventListener('submit', function () {
      var page = form.querySelector('[name="page"]');
      if (page) { page.remove(); }
    });
  });
}());
