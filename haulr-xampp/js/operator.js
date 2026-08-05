/* Operator console: duty toggle, open jobs board, bidding, active jobs. */
/* global window, document, setInterval */

(function () {
  'use strict';

  const H = window.Haulr;
  const M = window.HaulrMap;
  const { $, $$, esc } = H;

  const state = {
    view: 'board',
    profile: null,
    position: null,
    jobs: [],
    dutyStop: null, // position watcher while on duty
  };

  let map;
  let pins = [];

  document.addEventListener('DOMContentLoaded', async () => {
    await H.boot();
    const user = H.Session.require('operator');
    if (!user) return;

    $('#greeting').textContent = `Hello, ${user.fullName.split(' ')[0]}`;

    await H.loadMeta();
    H.bindConnectionPill($('#conn'));

    map = M.createMap('map', { zoom: 11 });

    await loadProfile();
    wireEvents();

    H.realtime.connect();

    // A new job posted anywhere in the system refreshes the board; the server
    // has already filtered what this operator is allowed to see.
    H.realtime.on('job_posted', () => {
      if (state.view === 'board') loadBoard({ quiet: true });
    });
    H.realtime.on('job_closed', () => {
      if (state.view === 'board') loadBoard({ quiet: true });
    });
    H.realtime.on('offer_accepted', (msg) => {
      H.toast(`Your offer of ${H.money(msg.price)} was accepted.`, 'green');
      loadStats();
      if (state.view === 'board') loadBoard({ quiet: true });
    });
    H.realtime.on('offer_rejected', () => {
      if (state.view === 'board') loadBoard({ quiet: true });
    });
    H.realtime.on('trip_update', () => loadStats());

    await Promise.all([loadStats(), refresh()]);

    setInterval(() => state.view === 'board' && loadBoard({ quiet: true }), 45000);
  });

  /* ------------------------------------------------------------------ */
  /* Profile and duty                                                    */
  /* ------------------------------------------------------------------ */

  async function loadProfile() {
    const { operatorProfile } = await H.api.get('/api/auth/me');
    state.profile = operatorProfile;
    if (operatorProfile?.lastPosition) state.position = operatorProfile.lastPosition;
    renderProfile();
  }

  function renderProfile() {
    const profile = state.profile;
    if (!profile) return;

    const meta = H.getMeta();
    const vehicle = meta.vehicleById[profile.vehicleClass];

    $('#vehicleLine').innerHTML = vehicle
      ? `${vehicle.icon} ${esc(vehicle.name)} · up to ${vehicle.capacityKg.toLocaleString()} kg${
          profile.vehiclePlate ? ` · <span class="mono">${esc(profile.vehiclePlate)}</span>` : ''
        }`
      : '';

    const rows = [
      ['Type', vehicle ? `${vehicle.icon} ${vehicle.name}` : profile.vehicleClass],
      ['Vehicle', [profile.vehicleMake, profile.vehicleModel].filter(Boolean).join(' ') || '—'],
      ['Plate', profile.vehiclePlate || '—'],
      ['Capacity', `${(profile.capacityKg || 0).toLocaleString()} kg`],
      ['Helpers', profile.helpersAvailable || 'None'],
      ['Tail lift', profile.hasTailLift ? 'Yes' : 'No'],
      ['Verified', profile.isVerified ? 'Yes' : 'Pending review'],
      ['Jobs done', profile.tripsCompleted],
    ];

    $('#vehicleDetails').innerHTML = rows
      .map(([label, value]) => `<dt>${esc(label)}</dt><dd>${esc(value)}</dd>`)
      .join('');

    renderDuty(profile.isOnline);
  }

  function renderDuty(isOnline) {
    const badge = $('#dutyBadge');
    const toggle = $('#dutyToggle');

    if (isOnline) {
      badge.className = 'badge badge-green';
      badge.innerHTML = '<span class="dot dot-pulse"></span>On duty';
      toggle.textContent = 'Go off duty';
      toggle.className = 'btn btn-ghost';
    } else {
      badge.className = 'badge';
      badge.textContent = 'Off duty';
      toggle.textContent = 'Go on duty';
      toggle.className = 'btn btn-green';
    }
  }

  async function setDuty(isOnline, button) {
    await H.withBusy(button, async () => {
      try {
        let fix = state.position;
        if (isOnline) {
          fix = await M.locateOnce();
          state.position = fix;
        }

        const { operatorProfile } = await H.api.post('/api/operator/status', {
          isOnline,
          lat: fix?.lat,
          lng: fix?.lng,
          heading: fix?.heading ?? undefined,
        });
        state.profile = operatorProfile;
        renderDuty(operatorProfile.isOnline);

        if (isOnline) {
          startDutyBeacon();
          H.toast('You are on duty. Jobs near you are listed below.', 'green');
          await refresh();
        } else {
          stopDutyBeacon();
          H.toast('You are off duty. Customers no longer see you on the map.', '');
        }
      } catch (err) {
        H.toast(err.message, 'red');
      }
    });
  }

  /**
   * While on duty the operator's position is republished periodically so the
   * jobs board stays sorted by real distance and customers see them on the
   * nearby-vehicles map.
   */
  function startDutyBeacon() {
    if (state.dutyStop) return;
    let lastSentAt = 0;

    state.dutyStop = M.watchPosition(
      async (fix) => {
        state.position = fix;
        const now = Date.now();
        if (now - lastSentAt < 30000) return; // a fix every 30s is plenty when idle
        lastSentAt = now;
        try {
          await H.api.post('/api/operator/status', {
            isOnline: true,
            lat: fix.lat,
            lng: fix.lng,
            heading: fix.heading ?? undefined,
          });
        } catch {
          /* transient; the next fix retries */
        }
      },
      () => {
        /* a lost fix should not knock the operator off duty */
      }
    );
  }

  function stopDutyBeacon() {
    state.dutyStop?.();
    state.dutyStop = null;
  }

  /* ------------------------------------------------------------------ */
  /* Data                                                                */
  /* ------------------------------------------------------------------ */

  async function loadStats() {
    try {
      const stats = await H.api.get('/api/operator/stats');
      const meta = H.getMeta();

      const cards = [
        ['Earned this week', H.money(stats.last7Days.earnings)],
        ['Jobs this week', stats.last7Days.jobs],
        ['Active jobs', stats.activeJobs],
        ['Open offers', stats.pendingOffers],
        ['Rating', stats.rating != null ? `★ ${stats.rating.toFixed(1)}` : 'New'],
        ['All-time earned', H.money(stats.allTime.earnings)],
      ];
      void meta;

      $('#stats').innerHTML = cards
        .map(
          ([label, value]) => `
          <div class="stat">
            <div class="stat-label">${esc(label)}</div>
            <div class="stat-value">${esc(value)}</div>
          </div>`
        )
        .join('');
    } catch {
      /* stats are decorative; never block the board on them */
    }
  }

  async function refresh() {
    if (state.view === 'board') return loadBoard();
    return loadMyJobs(state.view);
  }

  async function loadBoard({ quiet = false } = {}) {
    if (!quiet) $('#jobList').innerHTML = '<div class="skeleton" style="height:130px"></div>';

    const radiusKm = $('#radius').value;
    const params = new URLSearchParams({ radiusKm });
    if (state.position) {
      params.set('lat', state.position.lat);
      params.set('lng', state.position.lng);
    }

    try {
      const data = await H.api.get(`/api/operator/board?${params}`);
      state.jobs = data.jobs;
      renderBoard(data.jobs);
      drawPins(data.jobs);
    } catch (err) {
      showAlert(err.message);
    }
  }

  async function loadMyJobs(scope) {
    $('#jobList').innerHTML = '<div class="skeleton" style="height:130px"></div>';
    try {
      const { trips } = await H.api.get(`/api/trips?scope=${scope}`);
      state.jobs = trips;
      renderMyJobs(trips, scope);
      drawPins(trips);
    } catch (err) {
      showAlert(err.message);
    }
  }

  /* ------------------------------------------------------------------ */
  /* Rendering                                                           */
  /* ------------------------------------------------------------------ */

  function renderBoard(jobs) {
    $('#listSummary').textContent = jobs.length
      ? `${jobs.length} open job${jobs.length === 1 ? '' : 's'} your vehicle can take`
      : '';

    if (!jobs.length) {
      $('#jobList').innerHTML = `
        <div class="empty">
          <div class="empty-icon">🛣️</div>
          <h3>${state.profile?.isOnline ? 'No open jobs nearby' : 'Go on duty to see jobs'}</h3>
          <p>${
            state.profile?.isOnline
              ? 'Widen the radius, or check back shortly — new jobs post all day.'
              : 'Share your location and go on duty to see what is available around you.'
          }</p>
        </div>`;
      return;
    }

    $('#jobList').innerHTML = jobs.map(boardCard).join('');
    wireBoardCards();
  }

  function boardCard(job) {
    const meta = H.getMeta();
    const vehicle = meta.vehicleById[job.vehicleClass];
    const asking = job.customerOfferPrice;
    const guide = job.guide?.recommended;

    const verdict =
      guide == null
        ? ''
        : asking >= guide
          ? '<span class="badge badge-green">At or above the guide</span>'
          : asking >= guide * 0.85
            ? '<span class="badge badge-amber">A little under the guide</span>'
            : '<span class="badge badge-red">Well under the guide</span>';

    const mine = job.myOfferId
      ? `<span class="badge badge-blue">You offered ${H.money(job.myOfferPrice)}</span>`
      : '';

    return `
      <article class="job-card" data-job="${job.id}">
        <div class="row-between" style="margin-bottom:.7rem">
          <div class="row" style="gap:.5rem">
            <span class="badge">${vehicle ? `${vehicle.icon} ${esc(vehicle.name)}` : esc(job.vehicleClass)}</span>
            <span class="badge">${esc(H.categoryName(job.category))}</span>
            ${job.helpersRequired ? `<span class="badge">${job.helpersRequired} helper${job.helpersRequired > 1 ? 's' : ''}</span>` : ''}
            ${mine}
          </div>
          <div style="text-align:right">
            <div class="price">${H.money(asking)}</div>
            <div class="muted tiny">${guide != null ? `guide ${H.money(guide)}` : 'customer offer'}</div>
          </div>
        </div>

        ${H.routeBlock(job)}

        <p class="small muted" style="margin:.7rem 0 0">${esc(job.itemDescription)}</p>

        <div class="divider" style="margin:.8rem 0"></div>

        <div class="row-between">
          <div class="row" style="gap:.4rem">
            <span class="badge badge-blue">${job.distanceKm} km trip</span>
            ${
              job.distanceToPickupKm != null
                ? `<span class="badge">${job.distanceToPickupKm} km to pickup · ~${H.duration(job.minutesToPickup)}</span>`
                : ''
            }
            ${job.offerCount ? `<span class="badge badge-amber">${job.offerCount} bid${job.offerCount === 1 ? '' : 's'}</span>` : '<span class="badge badge-green">No bids yet</span>'}
            ${verdict}
          </div>
          <div class="row" style="gap:.4rem">
            <button class="btn btn-green btn-sm" data-quick="${job.id}" data-price="${asking}">
              Accept at ${H.money(asking)}
            </button>
            <a class="btn btn-accent btn-sm" href="track.html?trip=${job.id}">
              ${job.myOfferId ? 'Update offer' : 'Bid'} →
            </a>
          </div>
        </div>
      </article>`;
  }

  function renderMyJobs(jobs, scope) {
    $('#listSummary').textContent = jobs.length
      ? `${jobs.length} ${scope === 'active' ? 'active' : 'past'} job${jobs.length === 1 ? '' : 's'}`
      : '';

    if (!jobs.length) {
      $('#jobList').innerHTML = `
        <div class="empty">
          <div class="empty-icon">${scope === 'active' ? '🚚' : '🗂️'}</div>
          <h3>${scope === 'active' ? 'No jobs on the go' : 'No history yet'}</h3>
          <p>${
            scope === 'active'
              ? 'Bid on something from the open jobs board.'
              : 'Completed and cancelled jobs land here.'
          }</p>
        </div>`;
      return;
    }

    $('#jobList').innerHTML = jobs
      .map((job) => {
        const meta = H.getMeta();
        const vehicle = meta.vehicleById[job.vehicleClass];
        const price = job.agreedPrice ?? job.customerOfferPrice;

        return `
        <article class="job-card is-clickable" data-open="${job.id}">
          <div class="row-between" style="margin-bottom:.7rem">
            <div class="row" style="gap:.5rem">
              ${H.statusBadge(job)}
              <span class="job-ref">${esc(job.reference)}</span>
            </div>
            <div style="text-align:right">
              <div class="price-sm">${H.money(price)}</div>
              <div class="muted tiny">${job.agreedPrice ? 'agreed' : 'offered'}</div>
            </div>
          </div>

          ${H.routeBlock(job)}

          <div class="divider" style="margin:.8rem 0"></div>

          <div class="row-between">
            <div class="row" style="gap:.4rem">
              <span class="badge">${vehicle ? `${vehicle.icon} ${esc(vehicle.name)}` : ''}</span>
              <span class="badge">${job.distanceKm} km</span>
              ${job.customer ? `<span class="badge badge-blue">${esc(job.customer.fullName)}</span>` : ''}
              ${job.operatorRating ? `<span class="badge badge-green">★ ${job.operatorRating}</span>` : ''}
            </div>
            <span class="btn btn-ghost btn-sm">${job.trackable ? 'Open job →' : 'View →'}</span>
          </div>
        </article>`;
      })
      .join('');

    for (const node of $$('[data-open]')) {
      node.addEventListener('click', () => {
        window.location.href = `track.html?trip=${node.dataset.open}`;
      });
    }
  }

  function wireBoardCards() {
    for (const button of $$('[data-quick]')) {
      button.addEventListener('click', async (event) => {
        event.stopPropagation();
        const tripId = Number(button.dataset.quick);
        const price = Number(button.dataset.price);

        const confirmed = await H.confirmDialog({
          title: `Accept this job at ${H.money(price)}?`,
          body: "The job is yours straight away at the customer's asking price — there is no waiting for them to choose. Bid a different price instead if you want to negotiate.",
          confirmText: 'Accept the job',
          tone: 'green',
        });
        if (!confirmed) return;

        await H.withBusy(button, async () => {
          try {
            await H.api.post(`/api/trips/${tripId}/accept`);
            H.toast('Job accepted. Head to the pickup.', 'green');
            window.location.href = `track.html?trip=${tripId}`;
          } catch (err) {
            H.toast(err.message, 'red');
            loadBoard({ quiet: true });
          }
        });
      });
    }
  }

  /* ------------------------------------------------------------------ */
  /* Map                                                                 */
  /* ------------------------------------------------------------------ */

  function drawPins(jobs) {
    for (const pin of pins) map.removeLayer(pin);
    pins = [];

    const points = [];

    if (state.position) {
      const me = window.L.marker([state.position.lat, state.position.lng], {
        icon: M.vehicleIcon(H.vehicleIcon(state.profile?.vehicleClass), { live: true }),
        zIndexOffset: 900,
      })
        .addTo(map)
        .bindPopup('You are here');
      pins.push(me);
      points.push([state.position.lat, state.position.lng]);
    }

    for (const job of jobs) {
      const marker = window.L.marker([job.pickup.lat, job.pickup.lng], {
        icon: M.pinIcon('pickup', 'A'),
      })
        .addTo(map)
        .bindPopup(
          `<strong>${H.money(job.agreedPrice ?? job.customerOfferPrice)}</strong><br>` +
            `${esc(job.pickup.address)}<br>` +
            `<a href="track.html?trip=${job.id}">Open job</a>`
        );
      pins.push(marker);
      points.push([job.pickup.lat, job.pickup.lng]);
    }

    M.fitTo(map, points, { maxZoom: 13 });
    $('#mapCaption').textContent = jobs.length
      ? `${jobs.length} pickup point${jobs.length === 1 ? '' : 's'} shown.`
      : 'Nothing to show on the map yet.';
  }

  /* ------------------------------------------------------------------ */
  /* Events                                                              */
  /* ------------------------------------------------------------------ */

  function wireEvents() {
    $('#dutyToggle').addEventListener('click', (event) =>
      setDuty(!state.profile?.isOnline, event.currentTarget)
    );

    for (const tab of $$('.tab')) {
      tab.addEventListener('click', () => {
        $$('.tab').forEach((t) => t.classList.toggle('active', t === tab));
        state.view = tab.dataset.view;
        $('#boardControls').classList.toggle('hidden', state.view !== 'board');
        refresh();
      });
    }

    $('#radius').addEventListener('change', () => loadBoard());
    $('#refreshBtn').addEventListener('click', () => refresh());

    // Keep the duty beacon alive if the operator was already on duty.
    if (state.profile?.isOnline) startDutyBeacon();
  }

  function showAlert(message) {
    const box = $('#alert');
    box.textContent = message;
    box.classList.remove('hidden');
  }

  window.addEventListener('beforeunload', stopDutyBeacon);
})();
