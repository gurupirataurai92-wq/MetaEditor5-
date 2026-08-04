/* ==========================================================================
   Lymond Services — manager panel
   --------------------------------------------------------------------------
   Everything the panel does happens inside the browser. Edits and photos are
   staged in the local store (assets/js/store.js) and become part of the live
   site only when they are published — see the Publish tab.
   ========================================================================== */
(function () {
  'use strict';

  var CFG = window.MANAGER_CONFIG || {};
  var STORE = window.LymondStore;
  var SITE = window.SITE || {};

  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };

  var state = {
    company: {},
    vehicles: [],
    parts: [],
    partCategories: (SITE.partCategories || []).slice()
  };
  var photos = {};        /* filename -> data URL, staged and not yet published */
  var editing = { vehicle: null, part: null };
  var draftPhotos = { vehicle: [], part: [] };

  /* ------------------------------------------------------------ helpers -- */

  function esc(v) {
    return String(v == null ? '' : v)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function money(n) { return '$' + Number(n || 0).toLocaleString('en-US'); }

  var toastTimer;
  function toast(msg, bad) {
    var el = $('#toast');
    el.textContent = msg;
    el.className = 'toast show' + (bad ? ' bad' : '');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.className = 'toast'; }, bad ? 6000 : 3200);
  }

  function setErr(id, msg) {
    var el = $('#err-' + id);
    if (el) { el.textContent = msg || ''; }
    var field = $('#' + id);
    if (field) { field.setAttribute('aria-invalid', msg ? 'true' : 'false'); }
    return !msg;
  }

  function download(filename, blob) {
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 10000);
  }

  function dataUrlToBlob(dataUrl) {
    var parts = dataUrl.split(',');
    var mime = (parts[0].match(/:(.*?);/) || [])[1] || 'image/jpeg';
    var bin = atob(parts[1]);
    var arr = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) { arr[i] = bin.charCodeAt(i); }
    return new Blob([arr], { type: mime });
  }

  /* ------------------------------------------------------------- sha256 -- */
  /* crypto.subtle where it exists, with a plain fallback so the sign-in
     still works if the page is opened in a context that lacks it. */

  function sha256(text) {
    if (window.crypto && window.crypto.subtle && window.TextEncoder) {
      return window.crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))
        .then(function (buf) {
          return Array.prototype.map.call(new Uint8Array(buf), function (b) {
            return ('0' + b.toString(16)).slice(-2);
          }).join('');
        })
        .catch(function () { return Promise.resolve(sha256Fallback(text)); });
    }
    return Promise.resolve(sha256Fallback(text));
  }

  function sha256Fallback(ascii) {
    /* Compact reference implementation — only used when crypto.subtle is absent. */
    function rrot(v, a) { return (v >>> a) | (v << (32 - a)); }
    var K = [], H = [], primes = [], n = 2;
    while (primes.length < 64) {
      var isP = true;
      for (var d = 2; d * d <= n; d++) { if (n % d === 0) { isP = false; break; } }
      if (isP) { primes.push(n); }
      n++;
    }
    for (var i = 0; i < 64; i++) {
      K[i] = (Math.pow(primes[i], 1 / 3) % 1 * Math.pow(2, 32)) | 0;
      if (i < 8) { H[i] = (Math.pow(primes[i], 1 / 2) % 1 * Math.pow(2, 32)) | 0; }
    }
    var bytes = [];
    for (var c = 0; c < ascii.length; c++) {
      var cp = ascii.charCodeAt(c);
      if (cp < 128) { bytes.push(cp); }
      else if (cp < 2048) { bytes.push(192 | (cp >> 6), 128 | (cp & 63)); }
      else { bytes.push(224 | (cp >> 12), 128 | ((cp >> 6) & 63), 128 | (cp & 63)); }
    }
    var bitLen = bytes.length * 8;
    bytes.push(0x80);
    while (bytes.length % 64 !== 56) { bytes.push(0); }
    for (var s = 7; s >= 0; s--) { bytes.push((bitLen / Math.pow(2, s * 8)) & 255); }

    var w = new Array(64);
    for (var blk = 0; blk < bytes.length; blk += 64) {
      for (var t = 0; t < 16; t++) {
        w[t] = (bytes[blk + t * 4] << 24) | (bytes[blk + t * 4 + 1] << 16) |
               (bytes[blk + t * 4 + 2] << 8) | bytes[blk + t * 4 + 3];
      }
      for (var t2 = 16; t2 < 64; t2++) {
        var s0 = rrot(w[t2 - 15], 7) ^ rrot(w[t2 - 15], 18) ^ (w[t2 - 15] >>> 3);
        var s1 = rrot(w[t2 - 2], 17) ^ rrot(w[t2 - 2], 19) ^ (w[t2 - 2] >>> 10);
        w[t2] = (w[t2 - 16] + s0 + w[t2 - 7] + s1) | 0;
      }
      var a = H[0], b = H[1], cc = H[2], d2 = H[3], e = H[4], f = H[5], g = H[6], h = H[7];
      for (var j = 0; j < 64; j++) {
        var S1 = rrot(e, 6) ^ rrot(e, 11) ^ rrot(e, 25);
        var ch = (e & f) ^ (~e & g);
        var t1 = (h + S1 + ch + K[j] + w[j]) | 0;
        var S0 = rrot(a, 2) ^ rrot(a, 13) ^ rrot(a, 22);
        var maj = (a & b) ^ (a & cc) ^ (b & cc);
        var t22 = (S0 + maj) | 0;
        h = g; g = f; f = e; e = (d2 + t1) | 0;
        d2 = cc; cc = b; b = a; a = (t1 + t22) | 0;
      }
      H[0] = (H[0] + a) | 0; H[1] = (H[1] + b) | 0; H[2] = (H[2] + cc) | 0; H[3] = (H[3] + d2) | 0;
      H[4] = (H[4] + e) | 0; H[5] = (H[5] + f) | 0; H[6] = (H[6] + g) | 0; H[7] = (H[7] + h) | 0;
    }
    return H.map(function (x) { return ('00000000' + (x >>> 0).toString(16)).slice(-8); }).join('');
  }

  /* ------------------------------------------------------------- sign in -- */

  var SESSION_KEY = 'lymond.session';

  function signedIn() {
    try { return window.sessionStorage.getItem(SESSION_KEY) === 'yes'; } catch (e) { return false; }
  }

  function showApp() {
    $('#auth').hidden = true;
    $('#app').hidden = false;
    $('#who').textContent = CFG.USERNAME || 'manager';
    boot();
  }

  function signOut() {
    try { window.sessionStorage.removeItem(SESSION_KEY); } catch (e) { /* ignore */ }
    window.location.reload();
  }

  $('#auth-form').addEventListener('submit', function (e) {
    e.preventDefault();
    var user = $('#au-user').value.trim();
    var pass = $('#au-pass').value;
    var err = $('#auth-err');
    err.textContent = '';

    sha256((CFG.SALT || '') + pass).then(function (hash) {
      var ok = user.toLowerCase() === String(CFG.USERNAME || '').toLowerCase() &&
               hash === CFG.PASSWORD_HASH;
      if (!ok) {
        err.textContent = 'That user name or password is not right.';
        $('#au-pass').value = '';
        $('#au-pass').focus();
        return;
      }
      try { window.sessionStorage.setItem(SESSION_KEY, 'yes'); } catch (e2) { /* ignore */ }
      showApp();
    });
  });

  $$('#sign-out, #sign-out-2').forEach(function (b) { b.addEventListener('click', signOut); });

  /* Idle timeout. */
  var idleTimer;
  function resetIdle() {
    clearTimeout(idleTimer);
    var mins = Number(CFG.IDLE_TIMEOUT_MINUTES || 30);
    idleTimer = setTimeout(function () {
      toast('Signed out after ' + mins + ' minutes of inactivity.');
      setTimeout(signOut, 1200);
    }, mins * 60000);
  }
  ['click', 'keydown', 'pointermove'].forEach(function (evt) {
    document.addEventListener(evt, function () { if (signedIn()) { resetIdle(); } }, { passive: true });
  });

  /* ---------------------------------------------------------------- tabs -- */

  $$('.mgr-tab').forEach(function (tab) {
    tab.addEventListener('click', function () {
      $$('.mgr-tab').forEach(function (t) { t.setAttribute('aria-selected', String(t === tab)); });
      $$('.mgr-panel').forEach(function (p) { p.hidden = true; });
      $('#panel-' + tab.getAttribute('data-tab')).hidden = false;
      window.scrollTo(0, 0);
      if (tab.getAttribute('data-tab') === 'publish') { refreshPublish(); }
    });
  });

  /* ------------------------------------------------------------ state io -- */

  function loadState() {
    return Promise.all([STORE.getCatalogue(), STORE.allPhotos()]).then(function (res) {
      var staged = res[0];
      photos = res[1] || {};
      state.company = Object.assign({}, SITE.company, (staged && staged.company) || {});
      state.vehicles = (staged && staged.vehicles) || JSON.parse(JSON.stringify(SITE.vehicles || []));
      state.parts = (staged && staged.parts) || JSON.parse(JSON.stringify(SITE.parts || []));
      state.partCategories = (staged && staged.partCategories) || (SITE.partCategories || []).slice();
      $('#unsaved-pill').hidden = !staged;
    });
  }

  function save() {
    return STORE.saveCatalogue({
      company: state.company,
      vehicles: state.vehicles,
      parts: state.parts,
      partCategories: state.partCategories
    }).then(function () {
      $('#unsaved-pill').hidden = false;
      return STORE.prunePhotos(usedPhotoNames());
    }).then(function () {
      return refreshMeter();
    }).catch(function (err) {
      toast(err.message || 'Could not save. The browser may be out of storage room.', true);
      throw err;
    });
  }

  function usedPhotoNames() {
    var out = [];
    state.vehicles.concat(state.parts).forEach(function (item) {
      (item.photos || []).forEach(function (f) { out.push(f); });
    });
    draftPhotos.vehicle.concat(draftPhotos.part).forEach(function (f) { out.push(f); });
    return out;
  }

  function nextId(prefix, list) {
    var max = 0;
    list.forEach(function (item) {
      var m = /(\d+)$/.exec(item.id || '');
      if (m) { max = Math.max(max, Number(m[1])); }
    });
    return prefix + '-' + ('00' + (max + 1)).slice(-3);
  }

  /* ---------------------------------------------------------- photo work -- */

  function compress(file) {
    return new Promise(function (resolve, reject) {
      if (!/^image\//.test(file.type)) {
        return reject(new Error('"' + file.name + '" is not an image.'));
      }
      var url = URL.createObjectURL(file);
      var img = new Image();
      img.onload = function () {
        URL.revokeObjectURL(url);
        var maxEdge = Number(CFG.PHOTO_MAX_EDGE || 1400);
        var scale = Math.min(1, maxEdge / Math.max(img.naturalWidth, img.naturalHeight));
        var w = Math.max(1, Math.round(img.naturalWidth * scale));
        var h = Math.max(1, Math.round(img.naturalHeight * scale));
        var canvas = document.createElement('canvas');
        canvas.width = w; canvas.height = h;
        var ctx = canvas.getContext('2d');
        ctx.fillStyle = '#ffffff';
        ctx.fillRect(0, 0, w, h);
        ctx.drawImage(img, 0, 0, w, h);
        resolve(canvas.toDataURL('image/jpeg', Number(CFG.PHOTO_QUALITY || 0.78)));
      };
      img.onerror = function () {
        URL.revokeObjectURL(url);
        reject(new Error('Could not read "' + file.name + '".'));
      };
      img.src = url;
    });
  }

  function addPhotos(kind, fileList) {
    var files = Array.prototype.slice.call(fileList);
    if (!files.length) { return; }

    var limit = Number(CFG.PHOTOS_PER_ITEM || 8);
    var room = limit - draftPhotos[kind].length;
    if (room <= 0) {
      toast('That is the limit of ' + limit + ' photos for one item.', true);
      return;
    }
    if (files.length > room) {
      toast('Only the first ' + room + ' photos were added — the limit is ' + limit + '.', true);
      files = files.slice(0, room);
    }

    var id = editing[kind] || nextId(kind === 'vehicle' ? 'v' : 'p',
                                    kind === 'vehicle' ? state.vehicles : state.parts);

    /* Number photos 1, 2, 3… per item, skipping names already taken. */
    var taken = Object.keys(photos).concat(draftPhotos.vehicle, draftPhotos.part);
    var seq = 0;
    function nextName() {
      var name;
      do { seq++; name = 'uploads/' + id + '-' + seq + '.jpg'; } while (taken.indexOf(name) > -1);
      taken.push(name);
      return name;
    }

    files.reduce(function (chain, file) {
      return chain.then(function () {
        return compress(file).then(function (dataUrl) {
          var name = nextName();
          return STORE.putPhoto(name, dataUrl).then(function () {
            photos[name] = dataUrl;
            draftPhotos[kind].push(name);
          });
        });
      }).catch(function (err) {
        toast(err.message || 'One photo could not be added.', true);
      });
    }, Promise.resolve()).then(function () {
      renderThumbs(kind);
      refreshMeter();
    });
  }

  function photoUrl(name) {
    return photos[name] || ('assets/img/' + name);
  }

  function renderThumbs(kind) {
    var wrap = $(kind === 'vehicle' ? '#v-thumbs' : '#p-thumbs');
    var list = draftPhotos[kind];
    wrap.innerHTML = list.map(function (name, i) {
      return '' +
        '<div class="thumb-card">' +
          (i === 0 ? '<span class="cover-flag">Cover</span>' : '') +
          '<img src="' + esc(photoUrl(name)) + '" alt="">' +
          '<div class="thumb-tools">' +
            (i === 0
              ? '<button type="button" disabled>Cover</button>'
              : '<button type="button" data-cover="' + i + '">Cover</button>') +
            '<button type="button" class="danger" data-remove="' + i + '">Remove</button>' +
          '</div>' +
        '</div>';
    }).join('');

    $$('[data-cover]', wrap).forEach(function (b) {
      b.addEventListener('click', function () {
        var i = Number(b.getAttribute('data-cover'));
        list.unshift(list.splice(i, 1)[0]);
        renderThumbs(kind);
      });
    });
    $$('[data-remove]', wrap).forEach(function (b) {
      b.addEventListener('click', function () {
        var i = Number(b.getAttribute('data-remove'));
        list.splice(i, 1);
        renderThumbs(kind);
      });
    });
  }

  function wirePhotoInput(kind, dropId, inputId) {
    var drop = $(dropId);
    var input = $(inputId);
    drop.addEventListener('click', function () { input.click(); });
    drop.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); input.click(); }
    });
    input.addEventListener('change', function () {
      addPhotos(kind, input.files);
      input.value = '';
    });
    ['dragenter', 'dragover'].forEach(function (evt) {
      drop.addEventListener(evt, function (e) { e.preventDefault(); drop.classList.add('over'); });
    });
    ['dragleave', 'drop'].forEach(function (evt) {
      drop.addEventListener(evt, function (e) { e.preventDefault(); drop.classList.remove('over'); });
    });
    drop.addEventListener('drop', function (e) {
      if (e.dataTransfer && e.dataTransfer.files) { addPhotos(kind, e.dataTransfer.files); }
    });
  }

  /* -------------------------------------------------------- vehicle list -- */

  var BODY_LABEL = {
    sedan: 'Sedan', hatchback: 'Hatchback', suv: 'SUV', van: 'Van', pickup: 'Pickup', truck: 'Truck'
  };
  var STATUS_LABEL = {
    'in-stock': ['In stock', 'ok'], 'in-transit': ['In transit', 'warn'], 'to-order': ['To order', '']
  };

  function renderVehicles() {
    var list = $('#vehicle-list');
    if (!state.vehicles.length) {
      list.innerHTML = '<div class="empty"><h3>No vehicles yet</h3><p>Add your first unit to see it on the website.</p></div>';
    } else {
      list.innerHTML = state.vehicles.map(function (v) {
        var s = STATUS_LABEL[v.status] || ['', ''];
        var cover = (v.photos && v.photos[0]) ? photoUrl(v.photos[0]) : 'assets/img/' + v.body + '.svg';
        var count = (v.photos || []).length;
        return '' +
          '<div class="item-row">' +
            '<img class="thumb" src="' + esc(cover) + '" alt="">' +
            '<div>' +
              '<h3>' + esc(v.year + ' ' + v.make + ' ' + v.model) +
                '<span class="badge-mini ' + s[1] + '">' + esc(s[0]) + '</span>' +
                (count ? '<span class="badge-mini ok">' + count + ' photo' + (count > 1 ? 's' : '') + '</span>'
                       : '<span class="badge-mini none">No photo</span>') +
              '</h3>' +
              '<p class="meta">' + esc(v.id.toUpperCase()) + ' · ' + esc(BODY_LABEL[v.body] || v.body) +
                ' · ' + esc(v.fuel) + ' · ' + Number(v.mileage || 0).toLocaleString('en-US') + ' km · ' +
                money(v.price) + '</p>' +
            '</div>' +
            '<div class="item-actions">' +
              '<button class="btn btn--ghost btn--sm" type="button" data-edit-v="' + esc(v.id) + '">Edit</button>' +
            '</div>' +
          '</div>';
      }).join('');

      $$('[data-edit-v]').forEach(function (b) {
        b.addEventListener('click', function () { openVehicle(b.getAttribute('data-edit-v')); });
      });
    }

    var withPhotos = state.vehicles.filter(function (v) { return (v.photos || []).length; }).length;
    $('#vehicle-summary').textContent = state.vehicles.length + ' vehicles · ' +
      withPhotos + ' with photos · ' + (state.vehicles.length - withPhotos) + ' still showing a placeholder';
  }

  function openVehicle(id) {
    var form = $('#vehicle-form');
    var v = id ? state.vehicles.filter(function (x) { return x.id === id; })[0] : null;
    editing.vehicle = v ? v.id : null;
    draftPhotos.vehicle = v && v.photos ? v.photos.slice() : [];

    $('#vehicle-form-title').textContent = v ? 'Edit ' + v.year + ' ' + v.make + ' ' + v.model : 'Add vehicle';
    $('#vehicle-delete').hidden = !v;

    form.elements.make.value = v ? v.make : '';
    form.elements.model.value = v ? v.model : '';
    form.elements.year.value = v ? v.year : new Date().getFullYear() - 6;
    form.elements.price.value = v ? v.price : '';
    form.elements.body.value = v ? v.body : 'suv';
    form.elements.fuel.value = v ? v.fuel : 'Petrol';
    form.elements.transmission.value = v ? v.transmission : 'Automatic';
    form.elements.status.value = v ? v.status : 'in-stock';
    form.elements.engine.value = v ? (v.engine || '') : '';
    form.elements.mileage.value = v ? (v.mileage || '') : '';
    form.elements.drive.value = v ? (v.drive || '2WD') : '2WD';
    form.elements.colour.value = v ? (v.colour || '') : '';
    form.elements.grade.value = v ? (v.grade || '4') : '4';
    form.elements.steering.value = v ? (v.steering || 'RHD') : 'RHD';
    form.elements.note.value = v ? (v.note || '') : '';

    ['v-make', 'v-model', 'v-year', 'v-price', 'v-mileage'].forEach(function (f) { setErr(f, ''); });
    renderThumbs('vehicle');
    form.hidden = false;
    form.scrollIntoView({ behavior: 'smooth', block: 'start' });
    form.elements.make.focus();
  }

  $('#vehicle-add').addEventListener('click', function () { openVehicle(null); });

  $('#vehicle-form').addEventListener('submit', function (e) {
    e.preventDefault();
    var form = e.target;
    var year = Number(form.elements.year.value);
    var price = Number(form.elements.price.value);
    var mileage = form.elements.mileage.value === '' ? 0 : Number(form.elements.mileage.value);

    var ok = [
      setErr('v-make', form.elements.make.value.trim() ? '' : 'Which make is it?'),
      setErr('v-model', form.elements.model.value.trim() ? '' : 'Which model is it?'),
      setErr('v-year', (year >= 1970 && year <= 2100) ? '' : 'Enter a year between 1970 and 2100.'),
      setErr('v-price', (price > 0) ? '' : 'Enter the price in US dollars.'),
      setErr('v-mileage', (mileage >= 0) ? '' : 'Mileage cannot be negative.')
    ].every(Boolean);
    if (!ok) { toast('Please correct the highlighted fields.', true); return; }

    var record = {
      id: editing.vehicle || nextId('v', state.vehicles),
      make: form.elements.make.value.trim(),
      model: form.elements.model.value.trim(),
      year: year,
      body: form.elements.body.value,
      fuel: form.elements.fuel.value,
      transmission: form.elements.transmission.value,
      engine: form.elements.engine.value.trim(),
      mileage: mileage,
      drive: form.elements.drive.value,
      colour: form.elements.colour.value.trim(),
      price: price,
      status: form.elements.status.value,
      grade: form.elements.grade.value,
      steering: form.elements.steering.value,
      photos: draftPhotos.vehicle.slice()
    };
    var note = form.elements.note.value.trim();
    if (note) { record.note = note; }

    var idx = state.vehicles.map(function (x) { return x.id; }).indexOf(record.id);
    if (idx > -1) { state.vehicles[idx] = record; } else { state.vehicles.unshift(record); }

    save().then(function () {
      form.hidden = true;
      editing.vehicle = null;
      draftPhotos.vehicle = [];
      renderVehicles();
      toast(idx > -1 ? 'Vehicle updated.' : 'Vehicle added.');
    });
  });

  $('#vehicle-delete').addEventListener('click', function () {
    if (!editing.vehicle) { return; }
    var v = state.vehicles.filter(function (x) { return x.id === editing.vehicle; })[0];
    if (!window.confirm('Delete ' + v.year + ' ' + v.make + ' ' + v.model + '? This cannot be undone.')) { return; }
    state.vehicles = state.vehicles.filter(function (x) { return x.id !== editing.vehicle; });
    editing.vehicle = null;
    draftPhotos.vehicle = [];
    save().then(function () {
      $('#vehicle-form').hidden = true;
      renderVehicles();
      toast('Vehicle deleted.');
    });
  });

  /* ----------------------------------------------------------- part list -- */

  function categoryName(id) {
    var c = state.partCategories.filter(function (x) { return x.id === id; })[0];
    return c ? c.name : id;
  }

  function renderParts() {
    var list = $('#part-list');
    if (!state.parts.length) {
      list.innerHTML = '<div class="empty"><h3>No parts yet</h3><p>Add your first part to see it on the website.</p></div>';
    } else {
      list.innerHTML = state.parts.map(function (p) {
        var cover = (p.photos && p.photos[0]) ? photoUrl(p.photos[0]) : 'assets/img/parts/' + p.category + '.svg';
        var count = (p.photos || []).length;
        var stockOk = p.stock === 'in-stock';
        return '' +
          '<div class="item-row">' +
            '<img class="thumb" src="' + esc(cover) + '" alt="">' +
            '<div>' +
              '<h3>' + esc(p.name) +
                '<span class="badge-mini ' + (stockOk ? 'ok' : 'warn') + '">' +
                  (stockOk ? 'In stock' : 'On order') + '</span>' +
                (count ? '<span class="badge-mini ok">' + count + ' photo' + (count > 1 ? 's' : '') + '</span>'
                       : '<span class="badge-mini none">No photo</span>') +
              '</h3>' +
              '<p class="meta">' + esc(p.sku) + ' · ' + esc(categoryName(p.category)) +
                ' · ' + esc(p.size) + ' · ' + money(p.price) + '</p>' +
            '</div>' +
            '<div class="item-actions">' +
              '<button class="btn btn--ghost btn--sm" type="button" data-edit-p="' + esc(p.id) + '">Edit</button>' +
            '</div>' +
          '</div>';
      }).join('');

      $$('[data-edit-p]').forEach(function (b) {
        b.addEventListener('click', function () { openPart(b.getAttribute('data-edit-p')); });
      });
    }

    var withPhotos = state.parts.filter(function (p) { return (p.photos || []).length; }).length;
    $('#part-summary').textContent = state.parts.length + ' part lines · ' +
      withPhotos + ' with photos · ' + (state.parts.length - withPhotos) + ' still showing a placeholder';
  }

  function openPart(id) {
    var form = $('#part-form');
    var p = id ? state.parts.filter(function (x) { return x.id === id; })[0] : null;
    editing.part = p ? p.id : null;
    draftPhotos.part = p && p.photos ? p.photos.slice() : [];

    $('#part-form-title').textContent = p ? 'Edit ' + p.name : 'Add part';
    $('#part-delete').hidden = !p;

    form.elements.name.value = p ? p.name : '';
    form.elements.sku.value = p ? p.sku : '';
    form.elements.price.value = p ? p.price : '';
    form.elements.category.value = p ? p.category : (state.partCategories[0] || {}).id;
    form.elements.size.value = p ? p.size : 'small';
    form.elements.type.value = p ? p.type : 'oem';
    form.elements.stock.value = p ? p.stock : 'in-stock';
    form.elements.brand.value = p ? (p.brand || '') : '';
    form.elements.fits.value = p ? (p.fits || []).join(', ') : '';
    form.elements.note.value = p ? (p.note || '') : '';

    ['p-name', 'p-sku', 'p-price', 'p-fits'].forEach(function (f) { setErr(f, ''); });
    renderThumbs('part');
    form.hidden = false;
    form.scrollIntoView({ behavior: 'smooth', block: 'start' });
    form.elements.name.focus();
  }

  $('#part-add').addEventListener('click', function () { openPart(null); });

  $('#part-form').addEventListener('submit', function (e) {
    e.preventDefault();
    var form = e.target;
    var price = Number(form.elements.price.value);
    var fits = form.elements.fits.value.split(',').map(function (s) { return s.trim(); })
      .filter(function (s) { return s.length; });

    var ok = [
      setErr('p-name', form.elements.name.value.trim() ? '' : 'Give the part a name.'),
      setErr('p-sku', form.elements.sku.value.trim() ? '' : 'Add a part number or SKU.'),
      setErr('p-price', (price > 0) ? '' : 'Enter the price in US dollars.'),
      setErr('p-fits', fits.length ? '' : 'List at least one vehicle this fits.')
    ].every(Boolean);
    if (!ok) { toast('Please correct the highlighted fields.', true); return; }

    var record = {
      id: editing.part || nextId('p', state.parts),
      name: form.elements.name.value.trim(),
      category: form.elements.category.value,
      sku: form.elements.sku.value.trim(),
      brand: form.elements.brand.value.trim() || 'Unbranded',
      type: form.elements.type.value,
      price: price,
      stock: form.elements.stock.value,
      size: form.elements.size.value,
      fits: fits,
      photos: draftPhotos.part.slice()
    };
    var note = form.elements.note.value.trim();
    if (note) { record.note = note; }

    var idx = state.parts.map(function (x) { return x.id; }).indexOf(record.id);
    if (idx > -1) { state.parts[idx] = record; } else { state.parts.unshift(record); }

    save().then(function () {
      form.hidden = true;
      editing.part = null;
      draftPhotos.part = [];
      renderParts();
      toast(idx > -1 ? 'Part updated.' : 'Part added.');
    });
  });

  $('#part-delete').addEventListener('click', function () {
    if (!editing.part) { return; }
    var p = state.parts.filter(function (x) { return x.id === editing.part; })[0];
    if (!window.confirm('Delete "' + p.name + '"? This cannot be undone.')) { return; }
    state.parts = state.parts.filter(function (x) { return x.id !== editing.part; });
    editing.part = null;
    draftPhotos.part = [];
    save().then(function () {
      $('#part-form').hidden = true;
      renderParts();
      toast('Part deleted.');
    });
  });

  $$('[data-cancel]').forEach(function (b) {
    b.addEventListener('click', function () {
      var kind = b.getAttribute('data-cancel');
      $('#' + kind + '-form').hidden = true;
      editing[kind] = null;
      draftPhotos[kind] = [];
      STORE.prunePhotos(usedPhotoNames());
    });
  });

  /* -------------------------------------------------------------- company -- */

  function fillCompany() {
    var f = $('#company-form');
    ['name', 'phone', 'whatsapp', 'email', 'parts_email', 'address', 'hours'].forEach(function (k) {
      if (f.elements[k]) { f.elements[k].value = state.company[k] || ''; }
    });
  }

  $('#company-form').addEventListener('submit', function (e) {
    e.preventDefault();
    var f = e.target;
    var email = f.elements.email.value.trim();
    var pemail = f.elements.parts_email.value.trim();
    var wa = f.elements.whatsapp.value.trim();
    var mailOk = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

    var ok = [
      setErr('co-email', !email || mailOk.test(email) ? '' : 'That email address does not look right.'),
      setErr('co-parts_email', !pemail || mailOk.test(pemail) ? '' : 'That email address does not look right.'),
      setErr('co-whatsapp', !wa || /[0-9]{6,}/.test(wa.replace(/[^0-9]/g, '')) ? '' :
        'Use the full international number, e.g. +255 754 000 111.')
    ].every(Boolean);
    if (!ok) { toast('Please correct the highlighted fields.', true); return; }

    ['name', 'phone', 'whatsapp', 'email', 'parts_email', 'address', 'hours'].forEach(function (k) {
      if (f.elements[k]) { state.company[k] = f.elements[k].value.trim(); }
    });
    save().then(function () { toast('Company details saved.'); });
  });

  /* -------------------------------------------------------------- publish -- */

  function buildDataJs() {
    var header = '/* ==========================================================================\n' +
      '   ' + (state.company.name || 'Lymond Services') + ' — catalogue\n' +
      '   Generated by the manager panel on ' + new Date().toISOString().slice(0, 10) + '.\n' +
      '   Photo files listed here belong in website/assets/img/.\n' +
      '   ========================================================================== */\n\n';
    return header + 'window.SITE = ' + JSON.stringify({
      company: state.company,
      vehicles: state.vehicles,
      partCategories: state.partCategories,
      parts: state.parts
    }, null, 2) + ';\n';
  }

  function stagedPhotoNames() {
    return usedPhotoNames().filter(function (name, i, arr) {
      return photos[name] && arr.indexOf(name) === i;
    });
  }

  function refreshPublish() {
    var n = stagedPhotoNames().length;
    $('#photo-count').textContent = n ? (n + ' photo' + (n > 1 ? 's' : '') + ' to download') : 'No new photos';
    refreshMeter();
  }

  $('#dl-data').addEventListener('click', function () {
    download('data.js', new Blob([buildDataJs()], { type: 'text/javascript' }));
    toast('data.js downloaded. Replace website/assets/js/data.js with it.');
  });

  $('#dl-photos').addEventListener('click', function () {
    var names = stagedPhotoNames();
    if (!names.length) { toast('There are no new photos to download.'); return; }
    names.forEach(function (name, i) {
      setTimeout(function () {
        download(name.replace(/^.*\//, ''), dataUrlToBlob(photos[name]));
        if (i === names.length - 1) {
          toast(names.length + ' photo' + (names.length > 1 ? 's' : '') +
                ' downloaded. Put them in website/assets/img/uploads/.');
        }
      }, i * 400);
    });
  });

  $('#dl-backup').addEventListener('click', function () {
    var backup = {
      format: 'lymond-backup-v1',
      savedAt: new Date().toISOString(),
      catalogue: {
        company: state.company,
        vehicles: state.vehicles,
        parts: state.parts,
        partCategories: state.partCategories
      },
      photos: photos
    };
    download('lymond-backup-' + new Date().toISOString().slice(0, 10) + '.json',
             new Blob([JSON.stringify(backup)], { type: 'application/json' }));
    toast('Backup downloaded. Keep it somewhere safe.');
  });

  $('#restore-btn').addEventListener('click', function () { $('#restore-file').click(); });

  $('#restore-file').addEventListener('change', function () {
    var file = this.files[0];
    if (!file) { return; }
    this.value = '';
    if (!window.confirm('Restoring replaces everything currently staged in this browser. Continue?')) { return; }

    var reader = new FileReader();
    reader.onload = function () {
      var data;
      try { data = JSON.parse(reader.result); } catch (e) {
        toast('That file is not a backup this panel can read.', true);
        return;
      }
      if (!data || data.format !== 'lymond-backup-v1' || !data.catalogue) {
        toast('That file is not a backup this panel can read.', true);
        return;
      }
      var incoming = data.photos || {};
      Promise.all(Object.keys(incoming).map(function (name) {
        return STORE.putPhoto(name, incoming[name]);
      })).then(function () {
        photos = Object.assign({}, photos, incoming);
        state.company = data.catalogue.company || state.company;
        state.vehicles = data.catalogue.vehicles || [];
        state.parts = data.catalogue.parts || [];
        state.partCategories = data.catalogue.partCategories || state.partCategories;
        return save();
      }).then(function () {
        renderVehicles();
        renderParts();
        fillCompany();
        refreshPublish();
        toast('Backup restored.');
      }).catch(function (err) {
        toast(err.message || 'The backup could not be restored.', true);
      });
    };
    reader.readAsText(file);
  });

  $('#reset-all').addEventListener('click', function () {
    if (!window.confirm('Discard every unpublished change and photo in this browser? There is no undo.')) { return; }
    STORE.clearCatalogue()
      .then(function () { return STORE.prunePhotos([]); })
      .then(function () {
        photos = {};
        return loadState();
      })
      .then(function () {
        renderVehicles();
        renderParts();
        fillCompany();
        refreshPublish();
        $('#unsaved-pill').hidden = true;
        toast('Back to what is published on the site.');
      });
  });

  /* -------------------------------------------------------------- account -- */

  $('#pw-form').addEventListener('submit', function (e) {
    e.preventDefault();
    var a = $('#pw-new').value;
    var b = $('#pw-confirm').value;
    if (a.length < 10) { setErr('pw', 'Use at least 10 characters.'); return; }
    if (a !== b) { setErr('pw', 'The two passwords do not match.'); return; }
    setErr('pw', '');
    sha256((CFG.SALT || '') + a).then(function (hash) {
      $('#pw-out').value = "  PASSWORD_HASH: '" + hash + "',";
      $('#pw-out-wrap').hidden = false;
      $('#pw-out').select();
      $('#pw-new').value = '';
      $('#pw-confirm').value = '';
      toast('Paste the line into assets/js/manager-config.js, then publish that file.');
    });
  });

  /* --------------------------------------------------------- storage meter -- */

  function refreshMeter() {
    return STORE.usage().then(function (u) {
      var text = $('#storage-text');
      var fill = $('#storage-fill');
      var mb = function (n) { return (n / 1048576).toFixed(1) + ' MB'; };
      if (!u.quota) {
        text.textContent = 'Storage: ' + STORE.backend();
        fill.style.width = '0%';
        return;
      }
      var pct = Math.min(100, (u.bytes / u.quota) * 100);
      text.textContent = 'Storage ' + mb(u.bytes) + ' of ' + mb(u.quota);
      fill.style.width = Math.max(2, pct) + '%';
      fill.className = 'meter-fill' + (pct > 90 ? ' full' : pct > 70 ? ' warn' : '');
    }).catch(function () { /* meter is cosmetic */ });
  }

  /* ------------------------------------------------------------------ boot -- */

  function boot() {
    var catSelect = $('#p-cat');
    catSelect.innerHTML = state.partCategories.map(function (c) {
      return '<option value="' + esc(c.id) + '">' + esc(c.name) + '</option>';
    }).join('');

    wirePhotoInput('vehicle', '#v-drop', '#v-files');
    wirePhotoInput('part', '#p-drop', '#p-files');

    loadState().then(function () {
      catSelect.innerHTML = state.partCategories.map(function (c) {
        return '<option value="' + esc(c.id) + '">' + esc(c.name) + '</option>';
      }).join('');
      renderVehicles();
      renderParts();
      fillCompany();
      refreshPublish();
      resetIdle();
      if (STORE.backend() === 'localstorage') {
        toast('Photos are being kept in the smaller browser store. Serve the site over http for more room.');
      } else if (STORE.backend() === 'memory') {
        toast('This browser will not keep anything after you close the tab. Publish or back up before leaving.', true);
      }
    });
  }

  if (signedIn()) { showApp(); } else { $('#au-user').focus(); }
}());
