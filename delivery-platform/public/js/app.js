/* Shared client runtime: session, API access, realtime socket, UI helpers. */
/* global window, document, localStorage, fetch, WebSocket */

(function () {
  'use strict';

  const TOKEN_KEY = 'haulr.token';
  const USER_KEY = 'haulr.user';

  /* ------------------------------------------------------------------ */
  /* Session                                                             */
  /* ------------------------------------------------------------------ */

  const Session = {
    get token() {
      return localStorage.getItem(TOKEN_KEY);
    },
    get user() {
      try {
        return JSON.parse(localStorage.getItem(USER_KEY) || 'null');
      } catch {
        return null;
      }
    },
    save(token, user) {
      if (token) localStorage.setItem(TOKEN_KEY, token);
      if (user) localStorage.setItem(USER_KEY, JSON.stringify(user));
    },
    clear() {
      localStorage.removeItem(TOKEN_KEY);
      localStorage.removeItem(USER_KEY);
    },
    /** Bounce to sign-in unless the visitor holds one of `roles`. */
    require(...roles) {
      const user = this.user;
      if (!this.token || !user) {
        window.location.href = `/auth.html?next=${encodeURIComponent(
          window.location.pathname + window.location.search
        )}`;
        return null;
      }
      if (roles.length && !roles.includes(user.role)) {
        window.location.href = user.role === 'operator' ? '/operator.html' : '/customer.html';
        return null;
      }
      return user;
    },
    homePath() {
      const user = this.user;
      if (!user) return '/auth.html';
      return user.role === 'operator' ? '/operator.html' : '/customer.html';
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

  async function request(method, path, body) {
    const headers = {};
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const token = Session.token;
    if (token) headers.Authorization = `Bearer ${token}`;

    let response;
    try {
      response = await fetch(path, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch {
      throw new ApiError('Cannot reach the server. Check your connection.', 0, null);
    }

    const isJson = (response.headers.get('content-type') || '').includes('application/json');
    const payload = isJson ? await response.json().catch(() => null) : null;

    if (!response.ok) {
      // An expired or revoked token should drop the stale session rather than
      // leave the page half-broken.
      if (response.status === 401 && Session.token) {
        Session.clear();
        if (!window.location.pathname.startsWith('/auth')) {
          window.location.href = '/auth.html';
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
   * Auto-reconnecting WebSocket. Handlers registered with `on(type, fn)`
   * survive reconnects, and any trip subscriptions are replayed on reopen.
   */
  class Realtime {
    constructor() {
      this.socket = null;
      this.handlers = new Map();
      this.subscriptions = new Set();
      this.retries = 0;
      this.closedByUs = false;
      this.statusListeners = new Set();
    }

    connect() {
      const token = Session.token;
      if (!token || this.socket) return;

      const scheme = window.location.protocol === 'https:' ? 'wss' : 'ws';
      const socket = new WebSocket(
        `${scheme}://${window.location.host}/ws?token=${encodeURIComponent(token)}`
      );
      this.socket = socket;
      this.closedByUs = false;

      socket.addEventListener('open', () => {
        this.retries = 0;
        this.setStatus('live');
        for (const tripId of this.subscriptions) {
          socket.send(JSON.stringify({ type: 'subscribe', tripId }));
        }
      });

      socket.addEventListener('message', (event) => {
        let msg;
        try {
          msg = JSON.parse(event.data);
        } catch {
          return;
        }
        for (const fn of this.handlers.get(msg.type) || []) fn(msg);
        for (const fn of this.handlers.get('*') || []) fn(msg);
      });

      socket.addEventListener('close', () => {
        this.socket = null;
        this.setStatus(this.closedByUs ? 'off' : 'down');
        if (this.closedByUs || !Session.token) return;
        // Exponential backoff, capped at 15s, so a flaky mobile connection
        // does not hammer the server.
        const delay = Math.min(15000, 800 * 2 ** this.retries++);
        setTimeout(() => this.connect(), delay);
      });

      socket.addEventListener('error', () => socket.close());
    }

    disconnect() {
      this.closedByUs = true;
      this.socket?.close();
      this.socket = null;
    }

    on(type, fn) {
      if (!this.handlers.has(type)) this.handlers.set(type, new Set());
      this.handlers.get(type).add(fn);
      return () => this.handlers.get(type)?.delete(fn);
    }

    send(payload) {
      if (this.socket?.readyState === WebSocket.OPEN) {
        this.socket.send(JSON.stringify(payload));
        return true;
      }
      return false;
    }

    subscribe(tripId) {
      this.subscriptions.add(tripId);
      this.send({ type: 'subscribe', tripId });
    }

    unsubscribe(tripId) {
      this.subscriptions.delete(tripId);
      this.send({ type: 'unsubscribe', tripId });
    }

    onStatus(fn) {
      this.statusListeners.add(fn);
      return () => this.statusListeners.delete(fn);
    }

    setStatus(status) {
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
        <a href="/#how" class="nav-hide-sm">How it works</a>
        <a href="/#vehicles" class="nav-hide-sm">Vehicles</a>
        <a href="/#drive" class="nav-hide-sm">Drive with us</a>
        <a href="/auth.html" class="btn btn-ghost btn-sm">Sign in</a>
        <a href="/auth.html?mode=register" class="btn btn-accent btn-sm">Get started</a>`;
      return;
    }

    const links =
      user.role === 'operator'
        ? `<a href="/operator.html">Jobs board</a>`
        : `<a href="/customer.html">My deliveries</a>
           <a href="/request.html" class="nav-hide-sm">New delivery</a>`;

    nav.innerHTML = `
      ${links}
      <span class="badge badge-ink nav-hide-sm">${esc(user.fullName.split(' ')[0])}</span>
      <button class="btn btn-ghost btn-sm" id="signOut">Sign out</button>`;

    $('#signOut')?.addEventListener('click', () => {
      realtime.disconnect();
      Session.clear();
      window.location.href = '/';
    });

    // Highlight the current page.
    for (const link of $$('#nav a')) {
      if (link.getAttribute('href') === window.location.pathname) link.classList.add('active');
    }
  }

  window.Haulr = {
    Session,
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

  document.addEventListener('DOMContentLoaded', renderHeader);
})();
