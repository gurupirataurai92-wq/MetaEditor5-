/* ==========================================================================
   Lymond Services — site behaviour
   Vanilla JS, no dependencies. Every block guards on the elements it needs,
   so this one file can be loaded by every page.
   ========================================================================== */
(function () {
  'use strict';

  var SITE = window.SITE || {};
  var CO = SITE.company || {};
  var $ = function (sel, root) { return (root || document).querySelector(sel); };
  var $$ = function (sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); };

  /* ------------------------------------------------------------ helpers -- */

  function money(n) {
    return '$' + Number(n).toLocaleString('en-US');
  }

  function esc(str) {
    return String(str == null ? '' : str)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function waLink(message) {
    var num = (CO.whatsapp || '').replace(/[^0-9]/g, '');
    return 'https://wa.me/' + num + '?text=' + encodeURIComponent(message);
  }

  function param(name) {
    return new URLSearchParams(window.location.search).get(name);
  }

  var STATUS_LABEL = {
    'in-stock':   { text: 'In stock',   cls: 'card-flag--stock' },
    'in-transit': { text: 'In transit', cls: 'card-flag--order' },
    'to-order':   { text: 'To order',   cls: '' }
  };

  var STOCK_LABEL = {
    'in-stock': { text: 'In stock', cls: 'card-flag--stock' },
    'order':    { text: 'On order', cls: 'card-flag--order' }
  };

  var SIZE_LABEL = { small: 'Small part', medium: 'Medium part', large: 'Large part' };

  var TYPE_LABEL = {
    genuine: { text: 'Genuine', cls: 'tag--genuine' },
    oem: { text: 'OEM', cls: 'tag--oem' },
    aftermarket: { text: 'Aftermarket', cls: '' },
    used: { text: 'Japan used', cls: '' }
  };

  /* -------------------------------------------------------- header/nav -- */

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

  /* Mark the current page in the nav. */
  var here = location.pathname.split('/').pop() || 'index.html';
  $$('.nav-links a').forEach(function (a) {
    var target = a.getAttribute('href');
    if (target === here) { a.setAttribute('aria-current', 'page'); }
  });

  /* --------------------------------------------------- company details -- */

  $$('[data-co]').forEach(function (el) {
    var key = el.getAttribute('data-co');
    if (!CO[key]) { return; }
    if (el.tagName === 'A') {
      var href = el.getAttribute('href');
      if (!href || href === '#') {
        if (key === 'phone' || key === 'whatsapp') {
          el.href = 'tel:' + CO[key].replace(/\s/g, '');
        } else if (key.indexOf('email') > -1) {
          el.href = 'mailto:' + CO[key];
        }
      }
    }
    el.textContent = CO[key];
  });

  $$('[data-wa]').forEach(function (el) {
    el.href = waLink(el.getAttribute('data-wa') || ('Hello ' + CO.name + ', I would like more information.'));
    el.target = '_blank';
    el.rel = 'noopener';
  });

  var yearEl = $('[data-year]');
  if (yearEl) { yearEl.textContent = new Date().getFullYear(); }

  /* ------------------------------------------------------ reveal on scroll */

  var revealables = $$('.reveal');
  if (revealables.length) {
    if ('IntersectionObserver' in window) {
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
        });
      }, { rootMargin: '0px 0px -60px 0px', threshold: 0.08 });
      revealables.forEach(function (el) { io.observe(el); });
    } else {
      revealables.forEach(function (el) { el.classList.add('in'); });
    }
  }

  /* ------------------------------------------------------ card markup -- */

  function vehicleCard(v) {
    var s = STATUS_LABEL[v.status] || STATUS_LABEL['to-order'];
    var title = v.year + ' ' + v.make + ' ' + v.model;
    var msg = 'Hello ' + CO.name + ', I am interested in the ' + title + ' (ref ' + v.id.toUpperCase() + '). Is it still available?';
    return '' +
      '<article class="card">' +
        '<div class="card-media">' +
          '<img src="assets/img/' + esc(v.body) + '.svg" alt="' + esc(title) + ' — ' + esc(v.body) + '" loading="lazy" width="800" height="500">' +
          '<span class="card-flag ' + s.cls + '">' + s.text + '</span>' +
        '</div>' +
        '<div class="card-body">' +
          '<h3 class="card-title">' + esc(title) + '</h3>' +
          '<p class="card-sub">Ref ' + esc(v.id.toUpperCase()) + ' · Auction grade ' + esc(v.grade) + ' · ' + esc(v.steering) + '</p>' +
          '<ul class="spec-list">' +
            '<li><span class="k">Engine</span><span class="v">' + esc(v.engine) + '</span></li>' +
            '<li><span class="k">Fuel</span><span class="v">' + esc(v.fuel) + '</span></li>' +
            '<li><span class="k">Gearbox</span><span class="v">' + esc(v.transmission) + '</span></li>' +
            '<li><span class="k">Drive</span><span class="v">' + esc(v.drive) + '</span></li>' +
            '<li><span class="k">Mileage</span><span class="v">' + Number(v.mileage).toLocaleString('en-US') + ' km</span></li>' +
            '<li><span class="k">Colour</span><span class="v">' + esc(v.colour) + '</span></li>' +
          '</ul>' +
          (v.note ? '<p class="card-sub">' + esc(v.note) + '</p>' : '') +
          '<div class="card-foot">' +
            '<span class="price">' + money(v.price) + '<small>CIF, duty not included</small></span>' +
            '<a class="btn btn--primary btn--sm" href="' + waLink(msg) + '" target="_blank" rel="noopener">Enquire</a>' +
          '</div>' +
        '</div>' +
      '</article>';
  }

  function partCard(p) {
    var s = STOCK_LABEL[p.stock] || STOCK_LABEL.order;
    var t = TYPE_LABEL[p.type] || { text: p.type, cls: '' };
    var msg = 'Hello ' + CO.name + ', I need a quote for ' + p.name + ' (SKU ' + p.sku + ').';
    return '' +
      '<article class="card part-card">' +
        '<div class="card-media">' +
          '<img src="assets/img/parts/' + esc(p.category) + '.svg" alt="' + esc(p.name) + '" loading="lazy" width="800" height="500">' +
          '<span class="card-flag ' + s.cls + '">' + s.text + '</span>' +
        '</div>' +
        '<div class="card-body">' +
          '<h3 class="card-title">' + esc(p.name) + '</h3>' +
          '<p class="card-sub">SKU ' + esc(p.sku) + ' · ' + esc(p.brand) + '</p>' +
          '<div class="part-meta">' +
            '<span class="tag ' + t.cls + '">' + esc(t.text) + '</span>' +
            '<span class="tag">' + esc(SIZE_LABEL[p.size] || p.size) + '</span>' +
          '</div>' +
          '<p class="fit-list"><b>Fits:</b> ' + esc(p.fits.join(', ')) + '</p>' +
          (p.note ? '<p class="card-sub">' + esc(p.note) + '</p>' : '') +
          '<div class="card-foot">' +
            '<span class="price">' + money(p.price) + '<small>ex-works, per unit</small></span>' +
            '<a class="btn btn--primary btn--sm" href="' + waLink(msg) + '" target="_blank" rel="noopener">Order</a>' +
          '</div>' +
        '</div>' +
      '</article>';
  }

  function emptyState(what) {
    return '<div class="empty"><h3>Nothing matches those filters</h3>' +
      '<p>Try widening your search — or ask us to source the ' + what + ' for you.</p>' +
      '<a class="btn btn--ghost btn--sm" href="contact.html">Request a sourcing quote</a></div>';
  }

  /* ------------------------------------------------------ home page -- */

  var featured = $('#featured-vehicles');
  if (featured) {
    var picks = SITE.vehicles.filter(function (v) { return v.status === 'in-stock'; }).slice(0, 6);
    featured.innerHTML = picks.map(vehicleCard).join('');
  }

  var catGrid = $('#category-grid');
  if (catGrid) {
    var counts = {};
    SITE.parts.forEach(function (p) { counts[p.category] = (counts[p.category] || 0) + 1; });
    catGrid.innerHTML = SITE.partCategories.map(function (c) {
      return '' +
        '<a class="tile" href="parts.html?category=' + encodeURIComponent(c.id) + '">' +
          '<span class="tile-icon" aria-hidden="true">' +
            '<img src="assets/img/parts/' + esc(c.id) + '.svg" alt="" width="46" height="46">' +
          '</span>' +
          '<h3>' + esc(c.name) + '</h3>' +
          '<p>' + esc(c.blurb) + '</p>' +
          '<span class="count">' + (counts[c.id] || 0) + ' lines listed</span>' +
        '</a>';
    }).join('');
  }

  /* Quick search on the home page hands off to the vehicles page. */
  var quick = $('#quick-search');
  if (quick) {
    quick.addEventListener('submit', function (e) {
      e.preventDefault();
      var qs = new URLSearchParams();
      ['make', 'body', 'budget'].forEach(function (k) {
        var el = quick.elements[k];
        if (el && el.value) { qs.set(k, el.value); }
      });
      window.location.href = 'vehicles.html' + (qs.toString() ? '?' + qs : '');
    });
  }

  /* -------------------------------------------------- vehicles page -- */

  var vGrid = $('#vehicle-grid');
  if (vGrid) {
    var vForm = $('#vehicle-filters');
    var vCount = $('#vehicle-count');
    var statusChips = $$('[data-status]');
    var status = 'all';

    /* Populate the make dropdown from the data itself. */
    var makeSel = vForm.elements.make;
    var makes = SITE.vehicles.map(function (v) { return v.make; })
      .filter(function (m, i, a) { return a.indexOf(m) === i; }).sort();
    makes.forEach(function (m) {
      var o = document.createElement('option');
      o.value = m; o.textContent = m;
      makeSel.appendChild(o);
    });

    /* Seed from the URL so the home-page search and category links work. */
    ['make', 'body', 'budget'].forEach(function (k) {
      var val = param(k);
      if (val && vForm.elements[k]) { vForm.elements[k].value = val; }
    });

    function renderVehicles() {
      var q = vForm.elements.q.value.trim().toLowerCase();
      var make = vForm.elements.make.value;
      var body = vForm.elements.body.value;
      var fuel = vForm.elements.fuel.value;
      var gear = vForm.elements.transmission.value;
      var budget = Number(vForm.elements.budget.value || 0);
      var sort = vForm.elements.sort.value;

      var rows = SITE.vehicles.filter(function (v) {
        if (status !== 'all' && v.status !== status) { return false; }
        if (make && v.make !== make) { return false; }
        if (body && v.body !== body) { return false; }
        if (fuel && v.fuel !== fuel) { return false; }
        if (gear && v.transmission !== gear) { return false; }
        if (budget && v.price > budget) { return false; }
        if (q) {
          var hay = [v.make, v.model, v.year, v.body, v.fuel, v.colour, v.id, v.note].join(' ').toLowerCase();
          if (hay.indexOf(q) === -1) { return false; }
        }
        return true;
      });

      rows.sort(function (a, b) {
        if (sort === 'price-asc') { return a.price - b.price; }
        if (sort === 'price-desc') { return b.price - a.price; }
        if (sort === 'year-desc') { return b.year - a.year; }
        if (sort === 'mileage-asc') { return a.mileage - b.mileage; }
        return 0;
      });

      vGrid.innerHTML = rows.length ? rows.map(vehicleCard).join('') : emptyState('vehicle');
      vCount.innerHTML = '<b>' + rows.length + '</b> of ' + SITE.vehicles.length + ' vehicles shown';
    }

    vForm.addEventListener('input', renderVehicles);
    vForm.addEventListener('change', renderVehicles);
    vForm.addEventListener('submit', function (e) { e.preventDefault(); renderVehicles(); });

    var vReset = $('#vehicle-reset');
    if (vReset) {
      vReset.addEventListener('click', function () {
        vForm.reset();
        status = 'all';
        statusChips.forEach(function (c) {
          c.setAttribute('aria-pressed', c.getAttribute('data-status') === 'all' ? 'true' : 'false');
        });
        renderVehicles();
      });
    }

    statusChips.forEach(function (chip) {
      chip.addEventListener('click', function () {
        status = chip.getAttribute('data-status');
        statusChips.forEach(function (c) { c.setAttribute('aria-pressed', c === chip ? 'true' : 'false'); });
        renderVehicles();
      });
    });

    renderVehicles();
  }

  /* ----------------------------------------------------- parts page -- */

  var pGrid = $('#part-grid');
  if (pGrid) {
    var pForm = $('#part-filters');
    var pCount = $('#part-count');
    var catChips = $$('[data-category]');
    var category = param('category') || 'all';

    if (category !== 'all' && !SITE.partCategories.some(function (c) { return c.id === category; })) {
      category = 'all';
    }
    catChips.forEach(function (c) {
      c.setAttribute('aria-pressed', c.getAttribute('data-category') === category ? 'true' : 'false');
    });

    function renderParts() {
      var q = pForm.elements.q.value.trim().toLowerCase();
      var size = pForm.elements.size.value;
      var type = pForm.elements.type.value;
      var stock = pForm.elements.stock.value;
      var sort = pForm.elements.sort.value;

      var rows = SITE.parts.filter(function (p) {
        if (category !== 'all' && p.category !== category) { return false; }
        if (size && p.size !== size) { return false; }
        if (type && p.type !== type) { return false; }
        if (stock && p.stock !== stock) { return false; }
        if (q) {
          var hay = [p.name, p.sku, p.brand, p.category, p.fits.join(' '), p.note].join(' ').toLowerCase();
          if (hay.indexOf(q) === -1) { return false; }
        }
        return true;
      });

      rows.sort(function (a, b) {
        if (sort === 'price-asc') { return a.price - b.price; }
        if (sort === 'price-desc') { return b.price - a.price; }
        if (sort === 'name') { return a.name.localeCompare(b.name); }
        return 0;
      });

      pGrid.innerHTML = rows.length ? rows.map(partCard).join('') : emptyState('part');
      pCount.innerHTML = '<b>' + rows.length + '</b> of ' + SITE.parts.length + ' part lines shown';
    }

    pForm.addEventListener('input', renderParts);
    pForm.addEventListener('change', renderParts);
    pForm.addEventListener('submit', function (e) { e.preventDefault(); renderParts(); });

    catChips.forEach(function (chip) {
      chip.addEventListener('click', function () {
        category = chip.getAttribute('data-category');
        catChips.forEach(function (c) { c.setAttribute('aria-pressed', c === chip ? 'true' : 'false'); });
        renderParts();
      });
    });

    var pReset = $('#part-reset');
    if (pReset) {
      pReset.addEventListener('click', function () {
        pForm.reset();
        category = 'all';
        catChips.forEach(function (c) {
          c.setAttribute('aria-pressed', c.getAttribute('data-category') === 'all' ? 'true' : 'false');
        });
        renderParts();
      });
    }

    renderParts();
  }

  /* -------------------------------------------------- contact form -- */

  var form = $('#enquiry-form');
  if (form) {
    var statusBox = $('#form-status');

    /* Let other pages deep-link with a pre-filled subject. */
    var ref = param('ref');
    if (ref && form.elements.message) {
      form.elements.message.value = 'I would like more information about ' + ref + '.';
    }

    var rules = {
      name: function (v) { return v.trim().length >= 2 || 'Please tell us your name.'; },
      email: function (v) { return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(v.trim()) || 'Enter a valid email address.'; },
      phone: function (v) { return v.trim() === '' || /^[+0-9 ()-]{7,}$/.test(v.trim()) || 'Enter a valid phone number.'; },
      message: function (v) { return v.trim().length >= 10 || 'Please give us a little more detail (10+ characters).'; }
    };

    function validateField(name) {
      var field = form.elements[name];
      if (!field) { return true; }
      var out = rules[name](field.value);
      var errEl = $('#err-' + name);
      if (errEl) { errEl.textContent = out === true ? '' : out; }
      field.setAttribute('aria-invalid', out === true ? 'false' : 'true');
      return out === true;
    }

    Object.keys(rules).forEach(function (name) {
      var field = form.elements[name];
      if (field) {
        field.addEventListener('blur', function () { validateField(name); });
      }
    });

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var ok = Object.keys(rules).map(validateField).every(Boolean);

      statusBox.className = 'form-status show ' + (ok ? 'ok' : 'bad');
      if (!ok) {
        statusBox.textContent = 'Please correct the highlighted fields and send again.';
        var firstBad = $('[aria-invalid="true"]', form);
        if (firstBad) { firstBad.focus(); }
        return;
      }

      /* No back end is wired up yet — hand the enquiry to the user's mail
         client so nothing is silently lost. Replace this block with a POST
         to your CRM or form endpoint when one is available. */
      var d = {
        name: form.elements.name.value.trim(),
        email: form.elements.email.value.trim(),
        phone: form.elements.phone.value.trim(),
        topic: form.elements.topic.value,
        message: form.elements.message.value.trim()
      };
      var body = [
        'Name: ' + d.name,
        'Email: ' + d.email,
        'Phone: ' + (d.phone || '—'),
        'Enquiry type: ' + d.topic,
        '',
        d.message
      ].join('\n');
      var to = d.topic === 'Spare parts' ? (CO.parts_email || CO.email) : CO.email;

      statusBox.textContent = 'Thanks ' + d.name + ' — opening your email app to send this enquiry to ' + to +
        '. If nothing opens, WhatsApp or call us on ' + CO.phone + '.';
      window.location.href = 'mailto:' + to +
        '?subject=' + encodeURIComponent('Website enquiry — ' + d.topic) +
        '&body=' + encodeURIComponent(body);
      form.reset();
    });
  }
}());
