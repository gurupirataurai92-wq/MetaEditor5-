/* Shared client runtime: session, API access, realtime socket, UI helpers. */
/* global window, document, fetch, setTimeout, clearTimeout */

(function () {
  'use strict';

  const CSRF_COOKIE = 'haulr_csrf';

  /**
   * Where the API lives, relative to wherever the app was dropped in htdocs.
   *
   * Derived from this script's own URL rather than hard-coded, so the same
   * files work at http://localhost/haulr/ and at a virtual host root without
   * anyone editing a path.
   */
  const BASE_URL = (() => {
    const self = document.currentScript?.src
      || [...document.getElementsByTagName('script')].map((s) => s.src).find((src) => src.includes('/js/app.js'));
    if (!self) return './';
    return new URL('../', self).pathname;
  })();

  /** Turn '/api/trips?x=1' or 'api/trips' into a URL under BASE_URL. */
  function apiUrl(path) {
    return BASE_URL + String(path).replace(/^\/?(api\/)?/, 'api/');
  }

  /** Resolve an in-app page path ('customer.html') against BASE_URL. */
  function pageUrl(path) {
    if (!path) return BASE_URL;
    if (/^https?:/i.test(path)) return path;
    return BASE_URL + String(path).replace(/^\.?\//, '');
  }

  /** Read one of our own readable cookies. */
  function readCookie(name) {
    for (const part of document.cookie.split(';')) {
      const eq = part.indexOf('=');
      if (eq === -1) continue;
      if (part.slice(0, eq).trim() === name) {
        try {
          return decodeURIComponent(part.slice(eq + 1).trim());
        } catch {
          return part.slice(eq + 1).trim();
        }
      }
    }
    return null;
  }

  /* ------------------------------------------------------------------ */
  /* Session                                                             */
  /* ------------------------------------------------------------------ */

  /**
   * The session token itself lives in an httpOnly cookie this script cannot
   * read — that is the point. What we keep here is only the profile needed to
   * render, refreshed from the server; the browser attaches the real
   * credential automatically on every request.
   */
  const Session = {
    user: null,
    operatorProfile: null,
    homePath: '/',
    loaded: false,

    get csrfToken() {
      return readCookie(CSRF_COOKIE);
    },

    /** Fetch the signed-in user once per page load. */
    async load({ force = false } = {}) {
      if (this.loaded && !force) return this.user;
      try {
        const data = await api.get('/api/auth/me');
        this.adopt(data);
      } catch {
        this.user = null;
        this.operatorProfile = null;
      }
      this.loaded = true;
      return this.user;
    },

    /** Take the payload returned by login/register/2fa. */
    adopt(data) {
      this.user = data.user || null;
      this.operatorProfile = data.operatorProfile || null;
      // The server decides where each role belongs, so a new role never needs
      // a matching change in the client's routing table.
      this.homePath = data.homePath || '/';
      this.loaded = true;
      return this.user;
    },

    clear() {
      this.user = null;
      this.operatorProfile = null;
      this.homePath = '/';
      this.loaded = true;
    },

    /**
     * Gate a page on a role. Call after `load()`.
     *
     * This is a convenience for the person using the site, not a security
     * boundary — every endpoint enforces the same rule server-side.
     */
    require(...roles) {
      if (!this.user) {
        window.location.href = pageUrl('auth.html') + '?next='
          + encodeURIComponent(window.location.pathname + window.location.search);
        return null;
      }
      if (roles.length && !roles.includes(this.user.role)) {
        window.location.href = pageUrl(this.homePath);
        return null;
      }
      return this.user;
    },

    async signOut() {
      try {
        await api.post('/api/auth/logout');
      } catch {
        /* the cookie is cleared server-side either way */
      }
      realtime.disconnect();
      this.clear();
      window.location.href = pageUrl('index.html');
    },
  };

  /* ------------------------------------------------------------------ */
  /* API                                                                 */
  /* ------------------------------------------------------------------ */

  class ApiError extends Error {
    constructor(message, status, body) {
      super(message);
      this.status = status;
      this.body = body;
    }
  }

  const SAFE_METHODS = new Set(['GET', 'HEAD']);

  async function request(method, path, body) {
    const headers = {};
    if (body !== undefined) headers['Content-Type'] = 'application/json';

    // Echo the CSRF token on anything that changes state. The value comes from
    // a cookie only same-origin script can read, which is what makes it proof
    // the request did not originate on somebody else's page.
    if (!SAFE_METHODS.has(method)) {
      const csrf = readCookie(CSRF_COOKIE);
      if (csrf) headers['X-CSRF-Token'] = csrf;
    }

    let response;
    try {
      response = await fetch(apiUrl(path), {
        method,
        headers,
        // Send the session cookie, and never to a different origin.
        credentials: 'same-origin',
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch {
      throw new ApiError('Cannot reach the server. Check your connection.', 0, null);
    }

    const isJson = (response.headers.get('content-type') || '').includes('application/json');
    const payload = isJson ? await response.json().catch(() => null) : null;

    if (!response.ok) {
      // An expired, revoked or suspended session should drop the stale state
      // rather than leave the page half-broken.
      if (response.status === 401 && Session.user) {
        Session.clear();
        if (!window.location.pathname.endsWith('auth.html')) {
          window.location.href = pageUrl('auth.html');
        }
      }
      throw new ApiError(payload?.error || `Request failed (${response.status})`, response.status, payload);
    }
    return payload;
  }

  const api = {
    get: (path) => request('GET', path),
    post: (path, body) => request('POST', path, body ?? {}),
    patch: (path, body) => request('PATCH', path, body ?? {}),
    del: (path) => request('DELETE', path),
  };

  /* ------------------------------------------------------------------ */
  /* Reference data (vehicle classes, categories, currency)              */
  /* ------------------------------------------------------------------ */

  let metaPromise = null;
  let meta = null;

  function loadMeta() {
    if (!metaPromise) {
      metaPromise = api.get('/api/meta').then((data) => {
        meta = data;
        meta.vehicleById = Object.fromEntries(data.vehicleClasses.map((v) => [v.id, v]));
        meta.categoryById = Object.fromEntries(data.categories.map((c) => [c.id, c]));
        return meta;
      });
    }
    return metaPromise;
  }

  const getMeta = () => meta;

  function money(amount) {
    if (amount == null) return '—';
    const symbol = meta?.currency?.symbol || 'R';
    return `${symbol}${Number(amount).toLocaleString(undefined, {
      minimumFractionDigits: 0,
      maximumFractionDigits: 0,
    })}`;
  }

  function vehicleName(id) {
    return meta?.vehicleById?.[id]?.name || id;
  }
  function vehicleIcon(id) {
    return meta?.vehicleById?.[id]?.icon || '📦';
  }
  function categoryName(id) {
    return meta?.categoryById?.[id]?.name || id;
  }

  /* ------------------------------------------------------------------ */
  /* Realtime socket                                                     */
  /* ------------------------------------------------------------------ */

  /**
   * Live updates, by polling.
   *
   * Apache + PHP has no persistent connection to push down, so where the
   * Node build used a WebSocket this asks `api/events?since=N` on a short
   * interval and replays whatever is new. The public surface — `on(type, fn)`,
   * `subscribe(tripId)`, connection status — is unchanged, so no page had to
   * be rewritten around it.
   *
   * Polling backs off when the tab is hidden and after repeated failures, so
   * a forgotten background tab does not hammer XAMPP all afternoon.
   */
  class Realtime {
    constructor() {
      this.handlers = new Map();
      this.subscriptions = new Set();
      this.statusListeners = new Set();

      this.timer = null;
      this.running = false;
      this.since = 0;
      this.failures = 0;
      this.status = 'off';

      // Poll faster while something is actually moving on screen.
      this.activeIntervalMs = 3000;
      this.idleIntervalMs = 10000;
    }

    connect() {
      if (this.running || !Session.user) return;
      this.running = true;
      this.setStatus('live');
      this.tick();

      // A hidden tab does not need second-by-second updates; coming back
      // should refresh immediately rather than wait out the interval.
      document.addEventListener('visibilitychange', () => {
        if (!document.hidden && this.running) this.schedule(250);
      });
    }

    disconnect() {
      this.running = false;
      clearTimeout(this.timer);
      this.timer = null;
      this.setStatus('off');
    }

    schedule(delayMs) {
      clearTimeout(this.timer);
      if (!this.running) return;
      this.timer = setTimeout(() => this.tick(), delayMs);
    }

    async tick() {
      if (!this.running) return;

      try {
        const data = await api.get(`/api/events?since=${this.since}`);
        this.since = data.lastId ?? this.since;
        this.failures = 0;
        this.setStatus('live');

        for (const message of data.events || []) {
          for (const fn of this.handlers.get(message.type) || []) fn(message);
          for (const fn of this.handlers.get('*') || []) fn(message);
        }
      } catch (err) {
        // A dropped session is terminal; anything else is worth retrying.
        if (err.status === 401) {
          this.disconnect();
          return;
        }
        this.failures += 1;
        this.setStatus('down');
      }

      // Exponential backoff, capped, so a stopped MySQL does not turn into a
      // request flood.
      const base = document.hidden ? this.idleIntervalMs : this.activeIntervalMs;
      const delay = this.failures > 0
        ? Math.min(30000, base * 2 ** Math.min(this.failures, 4))
        : base;

      this.schedule(delay);
    }

    on(type, fn) {
      if (!this.handlers.has(type)) this.handlers.set(type, new Set());
      this.handlers.get(type).add(fn);
      return () => this.handlers.get(type)?.delete(fn);
    }

    /**
     * Kept for source compatibility with the WebSocket version. The server
     * decides what each poller is allowed to see from the session, so there
     * is nothing to send — but pages still call this, and tracking one job
     * means we want the faster cadence.
     */
    subscribe(tripId) {
      this.subscriptions.add(tripId);
      this.activeIntervalMs = 2500;
    }

    unsubscribe(tripId) {
      this.subscriptions.delete(tripId);
      if (this.subscriptions.size === 0) this.activeIntervalMs = 3000;
    }

    /** No-op: there is no socket to write to. */
    send() {
      return false;
    }

    onStatus(fn) {
      this.statusListeners.add(fn);
      return () => this.statusListeners.delete(fn);
    }

    setStatus(status) {
      if (this.status === status) return;
      this.status = status;
      for (const fn of this.statusListeners) fn(status);
    }
  }

  const realtime = new Realtime();

  /** Wire a `.conn` element up to the socket's connection state. */
  function bindConnectionPill(el) {
    if (!el) return;
    const render = (status) => {
      el.className = `conn ${status === 'live' ? 'live' : status === 'down' ? 'down' : ''}`;
      el.innerHTML = `<span class="dot ${status === 'live' ? 'dot-pulse' : ''}"></span>${
        status === 'live' ? 'Live' : status === 'down' ? 'Reconnecting…' : 'Offline'
      }`;
    };
    render(realtime.status || 'off');
    realtime.onStatus(render);
  }

  /* ------------------------------------------------------------------ */
  /* DOM helpers                                                         */
  /* ------------------------------------------------------------------ */

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

  /** Escape text destined for an innerHTML template. */
  function esc(value) {
    return String(value ?? '').replace(
      /[&<>"']/g,
      (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch]
    );
  }

  function el(tag, attrs = {}, ...children) {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs)) {
      if (value == null || value === false) continue;
      if (key === 'class') node.className = value;
      else if (key === 'html') node.innerHTML = value;
      else if (key.startsWith('on') && typeof value === 'function') {
        node.addEventListener(key.slice(2).toLowerCase(), value);
      } else node.setAttribute(key, value === true ? '' : value);
    }
    for (const child of children.flat()) {
      if (child == null || child === false) continue;
      node.append(child instanceof Node ? child : document.createTextNode(String(child)));
    }
    return node;
  }

  function toast(message, tone = '') {
    let host = $('#toasts');
    if (!host) {
      host = el('div', { id: 'toasts' });
      document.body.append(host);
    }
    const node = el('div', { class: `toast ${tone ? `toast-${tone}` : ''}` }, message);
    host.append(node);
    setTimeout(() => {
      node.style.opacity = '0';
      node.style.transition = 'opacity .3s';
      setTimeout(() => node.remove(), 320);
    }, 4200);
  }

  /** Promise-based confirm dialog. Resolves true when the user confirms. */
  function confirmDialog({ title, body, confirmText = 'Confirm', tone = 'red', withReason = false }) {
    return new Promise((resolve) => {
      const input = withReason
        ? el('input', { type: 'text', placeholder: 'Reason (optional)', maxlength: '300' })
        : null;

      const close = (result) => {
        backdrop.remove();
        document.removeEventListener('keydown', onKey);
        resolve(result);
      };
      const onKey = (e) => {
        if (e.key === 'Escape') close(false);
      };

      const backdrop = el(
        'div',
        { class: 'modal-backdrop', onclick: (e) => e.target === backdrop && close(false) },
        el(
          'div',
          { class: 'modal', role: 'dialog', 'aria-modal': 'true' },
          el('h3', {}, title),
          el('p', { class: 'muted small' }, body),
          input ? el('div', { class: 'field' }, input) : null,
          el(
            'div',
            { class: 'row', style: 'justify-content:flex-end;margin-top:1rem' },
            el('button', { class: 'btn btn-ghost', onclick: () => close(false) }, 'Never mind'),
            el(
              'button',
              {
                class: `btn btn-${tone}`,
                onclick: () => close(withReason ? { reason: input.value.trim() } : true),
              },
              confirmText
            )
          )
        )
      );

      document.body.append(backdrop);
      document.addEventListener('keydown', onKey);
      (input || backdrop.querySelector('.btn-ghost')).focus();
    });
  }

  /** Run an async action while showing a busy state on the button. */
  async function withBusy(button, fn) {
    if (!button) return fn();
    const label = button.textContent;
    button.disabled = true;
    button.setAttribute('aria-busy', 'true');
    button.textContent = 'Working…';
    try {
      return await fn();
    } finally {
      button.disabled = false;
      button.removeAttribute('aria-busy');
      button.textContent = label;
    }
  }

  /* ------------------------------------------------------------------ */
  /* Formatting                                                          */
  /* ------------------------------------------------------------------ */

  /** SQLite writes naive UTC strings; make them unambiguous before parsing. */
  function parseDate(value) {
    if (!value) return null;
    const iso = /[TZ]|[+-]\d\d:\d\d$/.test(value) ? value : `${value.replace(' ', 'T')}Z`;
    const date = new Date(iso);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  function timeAgo(value) {
    const date = parseDate(value);
    if (!date) return '';
    const seconds = Math.round((Date.now() - date.getTime()) / 1000);
    if (seconds < 45) return 'just now';
    const minutes = Math.round(seconds / 60);
    if (minutes < 60) return `${minutes} min ago`;
    const hours = Math.round(minutes / 60);
    if (hours < 24) return `${hours} hr ago`;
    const days = Math.round(hours / 24);
    if (days < 7) return `${days} day${days === 1 ? '' : 's'} ago`;
    return date.toLocaleDateString();
  }

  function clockTime(value) {
    const date = parseDate(value);
    return date ? date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '';
  }

  function dateTime(value) {
    const date = parseDate(value);
    return date
      ? date.toLocaleString([], {
          day: 'numeric',
          month: 'short',
          hour: '2-digit',
          minute: '2-digit',
        })
      : '';
  }

  function duration(minutes) {
    if (minutes == null) return '—';
    if (minutes < 60) return `${Math.round(minutes)} min`;
    const hours = Math.floor(minutes / 60);
    const rest = Math.round(minutes % 60);
    return rest ? `${hours} hr ${rest} min` : `${hours} hr`;
  }

  function ratingStars(rating, count) {
    if (rating == null) return '<span class="muted tiny">New</span>';
    return `<span class="tiny bold">★ ${rating.toFixed(1)}</span>${
      count ? `<span class="muted tiny"> (${count})</span>` : ''
    }`;
  }

  const STATUS_TONE = {
    requested: 'amber',
    accepted: 'blue',
    en_route_pickup: 'blue',
    at_pickup: 'blue',
    in_transit: 'accent',
    delivered: 'green',
    completed: 'green',
    cancelled: 'red',
  };

  function statusBadge(trip) {
    const tone = STATUS_TONE[trip.status] || '';
    const live = ['en_route_pickup', 'at_pickup', 'in_transit'].includes(trip.status);
    return `<span class="badge badge-${tone}">${
      live ? '<span class="dot dot-pulse"></span>' : ''
    }${esc(trip.statusLabel)}</span>`;
  }

  /** Renders the pickup → drop-off rail used on every job card. */
  function routeBlock(trip) {
    return `
      <div class="route">
        <div class="route-rail">
          <span class="route-dot"></span>
          <span class="route-line"></span>
          <span class="route-dot route-dot-end"></span>
        </div>
        <div>
          <div class="route-stop">
            <div class="route-addr">${esc(trip.pickup.address)}</div>
            <div class="route-meta">Pickup${
              trip.pickup.floor ? ` · floor ${trip.pickup.floor}${trip.pickup.hasLift ? ' (lift)' : ' (stairs)'}` : ''
            }</div>
          </div>
          <div class="route-stop">
            <div class="route-addr">${esc(trip.dropoff.address)}</div>
            <div class="route-meta">Drop-off${
              trip.dropoff.floor ? ` · floor ${trip.dropoff.floor}${trip.dropoff.hasLift ? ' (lift)' : ' (stairs)'}` : ''
            }</div>
          </div>
        </div>
      </div>`;
  }

  /* ------------------------------------------------------------------ */
  /* Page chrome                                                         */
  /* ------------------------------------------------------------------ */

  /** Fills in the shared header: nav links and the account menu. */
  function renderHeader() {
    const nav = $('#nav');
    if (!nav) return;
    const user = Session.user;

    if (!user) {
      nav.innerHTML = `
        <a href="index.html#how" class="nav-hide-sm">How it works</a>
        <a href="index.html#vehicles" class="nav-hide-sm">Vehicles</a>
        <a href="index.html#drive" class="nav-hide-sm">Drive with us</a>
        <a href="auth.html" class="btn btn-ghost btn-sm">Sign in</a>
        <a href="auth.html?mode=register" class="btn btn-accent btn-sm">Get started</a>`;
      return;
    }

    const links = {
      operator: '<a href="operator.html">Jobs board</a>',
      manager:
        '<a href="manager.html">Operations</a><a href="manager.html#security" class="nav-hide-sm">Security</a>',
      customer:
        '<a href="customer.html">My deliveries</a><a href="request.html" class="nav-hide-sm">New delivery</a>',
    }[user.role] || '';

    const roleBadge = {
      operator: '<span class="badge badge-blue nav-hide-sm">Driver</span>',
      manager: '<span class="badge badge-accent nav-hide-sm">Manager</span>',
      customer: '',
    }[user.role] || '';

    nav.innerHTML = `
      ${links}
      ${roleBadge}
      <span class="badge badge-ink nav-hide-sm">${esc(user.fullName.split(' ')[0])}</span>
      <button class="btn btn-ghost btn-sm" id="signOut">Sign out</button>`;

    $('#signOut')?.addEventListener('click', () => Session.signOut());

    // Highlight the current page.
    for (const link of $$('#nav a')) {
      if (link.getAttribute('href') === window.location.pathname) link.classList.add('active');
    }
  }

  window.Haulr = {
    Session,
    readCookie,
    apiUrl,
    pageUrl,
    BASE_URL,
    api,
    ApiError,
    realtime,
    loadMeta,
    getMeta,
    money,
    vehicleName,
    vehicleIcon,
    categoryName,
    $,
    $$,
    el,
    esc,
    toast,
    confirmDialog,
    withBusy,
    bindConnectionPill,
    parseDate,
    timeAgo,
    clockTime,
    dateTime,
    duration,
    ratingStars,
    statusBadge,
    routeBlock,
    renderHeader,
  };

  /**
   * Every page starts here: resolve who is signed in (from the cookie), then
   * paint the header. Pages await this before gating on a role.
   */
  async function boot() {
    await Session.load();
    renderHeader();
    return Session.user;
  }

  window.Haulr.boot = boot;
})();
