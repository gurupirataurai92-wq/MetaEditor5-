/* Live job view. Serves the customer (watching) and the operator (driving). */
/* global window, document, setInterval */

(function () {
  'use strict';

  const H = window.Haulr;
  const M = window.HaulrMap;
  const { $, esc } = H;

  const STEP_ORDER = ['accepted', 'en_route_pickup', 'at_pickup', 'in_transit', 'delivered'];

  const NEXT_STEP_LABEL = {
    accepted: "I'm on my way to pickup",
    en_route_pickup: "I've arrived at pickup",
    at_pickup: 'Loaded — start the trip',
    in_transit: 'Mark as delivered',
  };

  const state = {
    tripId: null,
    trip: null,
    role: null,
    isCustomer: false,
    isOperator: false,
    myRating: 0,
    gpsStop: null,
    gpsSearching: false,
    lastFixAt: null,
  };

  let map;
  let route = null;
  let vehicle = null;

  document.addEventListener('DOMContentLoaded', async () => {
    await H.boot();
    // Managers open jobs through their own console, but the live map is the
    // same view, so they are allowed here too.
    const user = H.Session.require('customer', 'operator', 'manager');
    if (!user) return;

    state.role = user.role;
    state.tripId = Number(new URLSearchParams(window.location.search).get('trip'));

    if (!Number.isInteger(state.tripId) || state.tripId <= 0) {
      return fail('No job was specified.');
    }

    $('#backLink').href = H.Session.homePath;

    await H.loadMeta();
    H.bindConnectionPill($('#conn'));

    initMap();
    wireEvents();

    await load();

    H.realtime.connect();
    H.realtime.subscribe(state.tripId);

    H.realtime.on('location_update', (msg) => {
      if (msg.tripId !== state.tripId) return;
      applyLocation(msg.position, msg.remainingKm, msg.etaMinutes);
    });

    H.realtime.on('trip_update', (msg) => {
      if (msg.tripId !== state.tripId) return;
      const previous = state.trip?.status;
      const wasMine = state.isOperator;

      state.trip = msg.trip;
      // Recompute which side of the job we are on. A manager can reassign a
      // job out from under a driver, and a page that keeps showing "you have
      // this job" would send them to a pickup that is no longer theirs.
      applyViewerRole();

      if (wasMine && !state.isOperator) {
        stopGps();
        H.toast('This job has been reassigned and is no longer yours.', 'red');
      }

      render();
      loadOffers();
      loadTimeline();

      if (previous && previous !== msg.trip.status) {
        H.toast(msg.trip.statusLabel, 'accent');
      }
    });

    // A manager took the job away and handed it to someone else.
    H.realtime.on('job_removed', (msg) => {
      if (msg.tripId !== state.tripId) return;
      stopGps();
      H.toast(
        msg.reason ? `Job reassigned: ${msg.reason}` : 'This job has been reassigned.',
        'red'
      );
      setTimeout(() => window.location.replace('/operator.html'), 2500);
    });

    H.realtime.on('job_assigned', (msg) => {
      if (msg.tripId !== state.tripId) return;
      H.toast('A manager assigned this job to you.', 'green');
      load();
    });

    for (const type of ['offer_new', 'offer_withdrawn']) {
      H.realtime.on(type, (msg) => msg.tripId === state.tripId && loadOffers());
    }

    H.realtime.on('offer_accepted', (msg) => {
      if (msg.tripId !== state.tripId) return;
      H.toast(`Your offer of ${H.money(msg.price)} was accepted.`, 'green');
      load();
    });

    H.realtime.on('message', (msg) => {
      if (msg.tripId !== state.tripId) return;
      appendMessage(msg.message);
    });

    // "Last fix" is a relative time, so it needs a ticker of its own.
    setInterval(updateLastFixLabel, 10000);
  });

  /** Work out which side of this job the viewer is on, from the current trip. */
  function applyViewerRole() {
    const me = H.Session.user;
    state.isCustomer = state.trip.customerId === me.id;
    state.isOperator = state.trip.operatorId === me.id;
  }

  function fail(message) {
    const box = $('#alert');
    box.textContent = message;
    box.classList.remove('hidden');
    $('#statusHeading').textContent = 'Unavailable';
  }

  /* ------------------------------------------------------------------ */
  /* Load                                                                */
  /* ------------------------------------------------------------------ */

  async function load() {
    try {
      // The operator browsing an open job is not a party yet, so /track is
      // closed to them — fall back to the plain job endpoint.
      let data;
      try {
        data = await H.api.get(`/api/trips/${state.tripId}/track`);
      } catch (err) {
        if (err.status !== 403) throw err;
        const plain = await H.api.get(`/api/trips/${state.tripId}`);
        data = { trip: plain.trip, trail: [], current: null, events: [] };
      }

      state.trip = data.trip;
      applyViewerRole();

      render();
      drawRoute();

      if (data.trail?.length) {
        drawTrail(data.trail);
        applyLocation(data.current, data.remainingKm, data.etaMinutes, { silent: true });
      }

      renderTimeline(data.events || []);
      loadOffers();
      if (state.trip.operatorId) loadMessages();
    } catch (err) {
      fail(err.message);
    }
  }

  /* ------------------------------------------------------------------ */
  /* Map                                                                 */
  /* ------------------------------------------------------------------ */

  function initMap() {
    map = M.createMap('map');
    $('#recentre').addEventListener('click', recentre);
  }

  function drawRoute() {
    route?.remove();
    route = M.routeLayer(map, state.trip);
    recentre();
  }

  function drawTrail(trail) {
    const points = trail.map((p) => [p.lat, p.lng]);
    const last = points[points.length - 1];
    vehicle?.remove();
    vehicle = M.liveVehicle(map, {
      lat: last[0],
      lng: last[1],
      glyph: H.vehicleIcon(state.trip.vehicleClass),
      trail: points,
    });
    state.lastFixAt = H.parseDate(trail[trail.length - 1].recordedAt);
  }

  function recentre() {
    const points = [
      [state.trip.pickup.lat, state.trip.pickup.lng],
      [state.trip.dropoff.lat, state.trip.dropoff.lng],
    ];
    if (vehicle) {
      const pos = vehicle.latLng();
      points.push([pos.lat, pos.lng]);
    }
    M.fitTo(map, points);
  }

  function applyLocation(position, remainingKm, etaMinutes, { silent = false } = {}) {
    if (!position) return;

    if (vehicle) {
      vehicle.move(position.lat, position.lng);
    } else {
      vehicle = M.liveVehicle(map, {
        lat: position.lat,
        lng: position.lng,
        glyph: H.vehicleIcon(state.trip.vehicleClass),
      });
      if (!silent) recentre();
    }

    state.lastFixAt = H.parseDate(position.recordedAt) || new Date();
    updateLastFixLabel();

    $('#etaValue').textContent = etaMinutes != null ? H.duration(etaMinutes) : '—';
    $('#remainingValue').textContent = remainingKm != null ? `${remainingKm} km` : '—';
  }

  function updateLastFixLabel() {
    $('#lastFix').textContent = state.lastFixAt ? H.timeAgo(state.lastFixAt.toISOString()) : '—';
  }

  /* ------------------------------------------------------------------ */
  /* Render                                                              */
  /* ------------------------------------------------------------------ */

  function render() {
    const trip = state.trip;
    const meta = H.getMeta();
    const vehicleSpec = meta.vehicleById[trip.vehicleClass];

    document.title = `${trip.reference} · ${trip.statusLabel} · Haulr`;
    $('#statusHeading').textContent = headline();
    $('#statusBadge').innerHTML = H.statusBadge(trip);
    $('#reference').textContent = trip.reference;
    $('#subLine').innerHTML = ` · ${esc(H.categoryName(trip.category))} · ${trip.distanceKm} km · posted ${H.timeAgo(
      trip.createdAt
    )}`;

    renderSteps();

    // ---- details
    const price = trip.agreedPrice ?? trip.customerOfferPrice;
    const rows = [
      [trip.agreedPrice ? 'Agreed price' : 'Customer offer', H.money(price)],
      ['Vehicle', vehicleSpec ? `${vehicleSpec.icon} ${vehicleSpec.name}` : trip.vehicleClass],
      ['Distance', `${trip.distanceKm} km`],
      ['Helpers', trip.helpersRequired || 'None'],
      ['Weight', trip.weightEstimateKg ? `~${trip.weightEstimateKg} kg` : 'Not stated'],
      ['Payment', meta.paymentMethods.find((p) => p.id === trip.paymentMethod)?.name || trip.paymentMethod],
      trip.scheduledAt && ['Scheduled', H.dateTime(trip.scheduledAt)],
      trip.pickup.contact && ['Pickup note', trip.pickup.contact],
      trip.dropoff.contact && ['Drop-off note', trip.dropoff.contact],
    ].filter(Boolean);

    $('#details').innerHTML = rows
      .map(([label, value]) => `<dt>${esc(label)}</dt><dd>${esc(value)}</dd>`)
      .join('');

    $('#itemDescription').textContent = trip.itemDescription;

    renderParty();
    renderOperatorControls();
    renderBidPanel();
    renderRating();

    $('#chatCard').classList.toggle('hidden', !trip.operatorId || (!state.isCustomer && !state.isOperator));

    const cancellable =
      state.isCustomer && ['requested', 'accepted', 'en_route_pickup', 'at_pickup'].includes(trip.status);
    $('#cancelBtn').classList.toggle('hidden', !cancellable);

    if (!trip.trackable) {
      $('#etaValue').textContent = trip.status === 'completed' || trip.status === 'delivered' ? 'Arrived' : '—';
    }
  }

  function headline() {
    const trip = state.trip;
    if (state.isOperator) {
      return (
        {
          accepted: 'You have this job',
          en_route_pickup: 'Heading to the pickup',
          at_pickup: 'Loading up',
          in_transit: 'On the road',
          delivered: 'Delivered — waiting on the rating',
          completed: 'Job complete',
          cancelled: 'Job cancelled',
        }[trip.status] || trip.statusLabel
      );
    }
    if (trip.status === 'requested') {
      return trip.offerCount ? `${trip.offerCount} operator${trip.offerCount === 1 ? '' : 's'} want this job` : 'Collecting offers';
    }
    return (
      {
        accepted: 'Your operator is confirmed',
        en_route_pickup: 'Your operator is on the way',
        at_pickup: 'Loading at the pickup',
        in_transit: 'Your delivery is on the road',
        delivered: 'Delivered',
        completed: 'Completed',
        cancelled: 'Cancelled',
      }[trip.status] || trip.statusLabel
    );
  }

  function renderSteps() {
    const index = STEP_ORDER.indexOf(state.trip.status);
    const reached = state.trip.status === 'completed' ? STEP_ORDER.length : index + 1;
    $('#steps').innerHTML = STEP_ORDER.map(
      (_, i) => `<span class="step ${i < reached ? 'on' : ''}"></span>`
    ).join('');
    $('#steps').classList.toggle('hidden', state.trip.status === 'cancelled' || state.trip.status === 'requested');
  }

  function renderParty() {
    const trip = state.trip;
    const host = $('#partyCard');

    // Operators looking at an open job see the customer; everyone else sees
    // whoever is on the other end.
    const other = state.isCustomer ? trip.operator : trip.customer;

    if (!other) {
      host.innerHTML = `
        <div class="section-title">Operator</div>
        <div class="row" style="gap:.6rem">
          <span class="badge badge-amber"><span class="dot dot-pulse"></span>Not assigned yet</span>
        </div>
        <p class="muted small" style="margin:.7rem 0 0">
          Pick one of the offers below and their details will appear here.
        </p>`;
      return;
    }

    const vehicleLine = other.vehicle
      ? `${H.vehicleIcon(other.vehicle.class)} ${esc(H.vehicleName(other.vehicle.class))}${
          other.vehicle.make ? ` · ${esc(other.vehicle.make)} ${esc(other.vehicle.model || '')}` : ''
        }${other.vehicle.plate ? ` · <span class="mono">${esc(other.vehicle.plate)}</span>` : ''}`
      : '';

    host.innerHTML = `
      <div class="section-title">${state.isCustomer ? 'Your operator' : 'Customer'}</div>
      <div class="row-between">
        <div>
          <div class="bold" style="font-size:1.05rem">${esc(other.fullName)}</div>
          <div class="small">${H.ratingStars(other.rating, other.ratingCount)}${
            other.tripsCompleted ? `<span class="muted tiny"> · ${other.tripsCompleted} jobs</span>` : ''
          }${other.verified ? ' <span class="badge badge-green">Verified</span>' : ''}</div>
        </div>
        ${
          other.phone
            ? `<a class="btn btn-quiet btn-sm" href="tel:${esc(other.phone.replace(/[^\d+]/g, ''))}">📞 Call</a>`
            : ''
        }
      </div>
      ${vehicleLine ? `<div class="small muted" style="margin-top:.5rem">${vehicleLine}</div>` : ''}`;
  }

  /* ------------------------------------------------------------------ */
  /* Offers                                                              */
  /* ------------------------------------------------------------------ */

  async function loadOffers() {
    const card = $('#offersCard');
    const showToCustomer = state.isCustomer && state.trip.status === 'requested';

    if (!showToCustomer) {
      card.classList.add('hidden');
      return;
    }
    card.classList.remove('hidden');

    let offers = [];
    try {
      ({ offers } = await H.api.get(`/api/trips/${state.tripId}/offers`));
    } catch {
      return;
    }

    $('#offerCount').textContent = offers.length;
    const host = $('#offersList');

    if (!offers.length) {
      host.innerHTML = `
        <div class="empty" style="padding:1.5rem">
          <div class="empty-icon">📡</div>
          <p class="muted" style="margin:0">
            No offers yet. Your job is on the board for every operator within
            ${H.getMeta().dispatchRadiusKm} km.
          </p>
        </div>`;
      return;
    }

    const asking = state.trip.customerOfferPrice;

    host.innerHTML = offers
      .map((offer) => {
        const delta = offer.price - asking;
        const deltaBadge =
          delta === 0
            ? '<span class="badge badge-green">At your price</span>'
            : delta < 0
              ? `<span class="badge badge-green">${H.money(Math.abs(delta))} under</span>`
              : `<span class="badge badge-amber">${H.money(delta)} over</span>`;

        return `
        <div class="job-card">
          <div class="row-between">
            <div>
              <div class="bold">${esc(offer.operator.fullName)}</div>
              <div class="small">${H.ratingStars(offer.operator.rating, offer.operator.ratingCount)}
                ${offer.operator.tripsCompleted ? `<span class="muted tiny">· ${offer.operator.tripsCompleted} jobs</span>` : ''}
                ${offer.operator.verified ? '<span class="badge badge-green">Verified</span>' : ''}
              </div>
              ${
                offer.operator.vehicle
                  ? `<div class="muted tiny" style="margin-top:.25rem">
                       ${H.vehicleIcon(offer.operator.vehicle.class)} ${esc(H.vehicleName(offer.operator.vehicle.class))}
                       ${offer.operator.vehicle.make ? `· ${esc(offer.operator.vehicle.make)} ${esc(offer.operator.vehicle.model || '')}` : ''}
                     </div>`
                  : ''
              }
            </div>
            <div style="text-align:right">
              <div class="price">${H.money(offer.price)}</div>
              <div class="muted tiny">arrives in ~${H.duration(offer.etaMinutes)}</div>
            </div>
          </div>
          ${offer.message ? `<p class="small" style="margin:.6rem 0 0">“${esc(offer.message)}”</p>` : ''}
          <div class="row-between" style="margin-top:.7rem">
            ${deltaBadge}
            <button class="btn btn-accent btn-sm" data-accept="${offer.id}">Choose this operator</button>
          </div>
        </div>`;
      })
      .join('');

    for (const button of host.querySelectorAll('[data-accept]')) {
      button.addEventListener('click', () => acceptOffer(button, Number(button.dataset.accept)));
    }
  }

  async function acceptOffer(button, offerId) {
    const confirmed = await H.confirmDialog({
      title: 'Confirm this operator?',
      body: 'They will be assigned immediately and the other offers will be turned down.',
      confirmText: 'Yes, book them',
      tone: 'accent',
    });
    if (!confirmed) return;

    await H.withBusy(button, async () => {
      try {
        await H.api.post(`/api/offers/${offerId}/accept`);
        H.toast('Operator booked. Tracking starts when they set off.', 'green');
        await load();
      } catch (err) {
        H.toast(err.message, 'red');
        loadOffers();
      }
    });
  }

  /* ------------------------------------------------------------------ */
  /* Operator controls                                                   */
  /* ------------------------------------------------------------------ */

  function renderOperatorControls() {
    const card = $('#operatorCard');
    const active = state.isOperator && state.trip.trackable;
    card.classList.toggle('hidden', !active);
    if (!active) {
      stopGps();
      return;
    }

    const label = NEXT_STEP_LABEL[state.trip.status];
    const advance = $('#advanceBtn');
    advance.textContent = label || 'Next step';
    advance.classList.toggle('hidden', !label);

    $('#advanceHint').textContent = label
      ? 'Your customer sees each step as you tap it.'
      : 'Waiting on the customer to close the job.';

    $('#releaseBtn').classList.toggle('hidden', state.trip.status === 'in_transit');
  }

  function renderBidPanel() {
    const card = $('#bidCard');
    const canBid = state.role === 'operator' && !state.isOperator && state.trip.status === 'requested';
    card.classList.toggle('hidden', !canBid);
    if (!canBid) return;

    const asking = state.trip.customerOfferPrice;
    $('#bidGuide').textContent = `Customer offers ${H.money(asking)}`;
    $('#acceptJob').textContent = `Accept at ${H.money(asking)}`;
    if (!$('#bidPrice').value) $('#bidPrice').value = String(asking);

    const mine = state.trip.myOffer;
    $('#bidWithdraw').classList.toggle('hidden', !mine || mine.status !== 'pending');
    if (mine) {
      $('#bidPrice').value = String(mine.price);
      $('#bidEta').value = String(mine.etaMinutes);
      $('#bidMessage').value = mine.message || '';
      $('#bidSubmit').textContent = 'Update my offer';
    }
  }

  /* ------------------------------------------------------------------ */
  /* GPS broadcasting (operator side)                                    */
  /* ------------------------------------------------------------------ */

  function startGps() {
    if (state.gpsStop) return;

    let lastSentAt = 0;
    state.gpsStop = M.watchPosition(
      async (fix) => {
        setGpsBadge('live');

        // The device fires far more often than anyone needs; 4s is smooth on
        // the customer's map without hammering the API.
        const now = Date.now();
        if (now - lastSentAt < 4000) return;
        lastSentAt = now;

        try {
          const result = await H.api.post(`/api/trips/${state.tripId}/location`, {
            lat: fix.lat,
            lng: fix.lng,
            heading: fix.heading ?? undefined,
            speedKph: fix.speedKph ?? undefined,
            accuracyM: fix.accuracyM ?? undefined,
          });
          $('#gpsDetail').textContent = `${result.remainingKm} km to go · ETA ${H.duration(result.etaMinutes)}`;
          applyLocation(
            { ...fix, recordedAt: new Date().toISOString() },
            result.remainingKm,
            result.etaMinutes,
            { silent: true }
          );
        } catch (err) {
          // 409 means the job left a trackable state — genuinely done.
          if (err.status === 409) stopGps();
        }
      },
      (err) => {
        if (err.fatal) {
          H.toast(err.message, 'red');
          stopGps();
          return;
        }
        // Transient signal loss. Keep the watch alive — the browser feeds the
        // next good fix to this same callback — and just show the state.
        setGpsBadge('searching', err.message);
      }
    );

    setGpsBadge('live');
    $('#gpsToggle').textContent = '■ Stop live location';
    $('#gpsToggle').className = 'btn btn-red';
    $('#gpsNote').classList.add('hidden');
  }

  function stopGps() {
    if (state.gpsStop) {
      state.gpsStop();
      state.gpsStop = null;
    }
    if (!$('#gpsBadge')) return;
    setGpsBadge('off');
    $('#gpsToggle').textContent = '▶ Start live location';
    $('#gpsToggle').className = 'btn btn-green';
    $('#gpsDetail').textContent = '';
  }

  function setGpsBadge(mode, note) {
    const badge = $('#gpsBadge');
    if (!badge) return;

    if (mode === 'live') {
      badge.className = 'badge badge-green';
      badge.innerHTML = '<span class="dot dot-pulse"></span>GPS live';
      // Clear a lingering "no signal" note; the next ping refills this line
      // with the live distance and ETA.
      if (state.gpsSearching) $('#gpsDetail').textContent = '';
      state.gpsSearching = false;
    } else if (mode === 'searching') {
      badge.className = 'badge badge-amber';
      badge.innerHTML = '<span class="dot dot-pulse"></span>Searching for signal';
      state.gpsSearching = true;
      if (note) $('#gpsDetail').textContent = note;
    } else {
      badge.className = 'badge';
      badge.textContent = 'GPS off';
    }
  }

  /* ------------------------------------------------------------------ */
  /* Rating                                                              */
  /* ------------------------------------------------------------------ */

  function renderRating() {
    const trip = state.trip;
    const alreadyRated = state.isCustomer ? trip.operatorRating != null : trip.customerRating != null;
    const canRate =
      ['delivered', 'completed'].includes(trip.status) &&
      (state.isCustomer || state.isOperator) &&
      !alreadyRated;

    $('#rateCard').classList.toggle('hidden', !canRate);
    if (!canRate) return;

    $('#rateTitle').textContent = state.isCustomer
      ? `How did ${trip.operator?.fullName.split(' ')[0] || 'your operator'} do?`
      : `How was ${trip.customer?.fullName.split(' ')[0] || 'the customer'}?`;

    $('#reviewText').classList.toggle('hidden', !state.isCustomer);

    $('#stars').innerHTML = [1, 2, 3, 4, 5]
      .map((n) => `<button type="button" data-star="${n}" aria-label="${n} stars">★</button>`)
      .join('');

    for (const button of $('#stars').querySelectorAll('[data-star]')) {
      button.addEventListener('click', () => {
        state.myRating = Number(button.dataset.star);
        for (const other of $('#stars').querySelectorAll('[data-star]')) {
          other.classList.toggle('on', Number(other.dataset.star) <= state.myRating);
        }
      });
    }
  }

  /* ------------------------------------------------------------------ */
  /* Timeline and chat                                                   */
  /* ------------------------------------------------------------------ */

  async function loadTimeline() {
    try {
      const { events } = await H.api.get(`/api/trips/${state.tripId}/events`);
      renderTimeline(events);
    } catch {
      /* the timeline is not worth an error banner */
    }
  }

  const EVENT_LABELS = {
    created: 'Job posted',
    offer_made: 'Offer received',
    offer_updated: 'Offer revised',
    offer_withdrawn: 'Offer withdrawn',
    offer_accepted: 'Operator booked',
    operator_accepted: 'Driver accepted the job',
    manager_reassigned: 'Manager reassigned the driver',
    manager_cancelled: 'Manager cancelled the job',
    manager_flagged: 'Manager flagged the job',
    released: 'Operator released the job',
    cancelled: 'Job cancelled',
    rated: 'Rating submitted',
    'status:en_route_pickup': 'Operator set off for the pickup',
    'status:at_pickup': 'Arrived at the pickup',
    'status:in_transit': 'Loaded and on the road',
    'status:delivered': 'Delivered',
  };

  function renderTimeline(events) {
    const host = $('#timeline');
    if (!events.length) {
      host.innerHTML = '<li class="muted small">Nothing yet.</li>';
      return;
    }
    // Offer events store the bare price; render it as currency.
    const PRICE_EVENTS = new Set(['offer_made', 'offer_updated', 'offer_accepted']);

    host.innerHTML = events
      .map((event, index) => {
        const isLast = index === events.length - 1;
        const label = EVENT_LABELS[event.type] || event.type;
        const note =
          event.note && PRICE_EVENTS.has(event.type) && !Number.isNaN(Number(event.note))
            ? H.money(Number(event.note))
            : event.note;

        return `
        <li class="${isLast ? 'current' : 'done'}">
          <div>${esc(label)}${note ? ` <span class="muted">· ${esc(note)}</span>` : ''}</div>
          <div class="timeline-time">${H.dateTime(event.createdAt)} · ${H.timeAgo(event.createdAt)}</div>
        </li>`;
      })
      .join('');
  }

  async function loadMessages() {
    try {
      const { messages } = await H.api.get(`/api/trips/${state.tripId}/messages`);
      $('#chatLog').innerHTML = '';
      messages.forEach(appendMessage);
    } catch {
      /* chat is optional */
    }
  }

  function appendMessage(message) {
    const log = $('#chatLog');
    if (log.querySelector(`[data-msg="${message.id}"]`)) return;

    const mine = message.senderId === H.Session.user.id;
    const node = document.createElement('div');
    node.className = `bubble ${mine ? 'bubble-mine' : ''}`;
    node.dataset.msg = message.id;
    node.innerHTML = `${esc(message.body)}<span class="bubble-time">${
      mine ? 'You' : esc(message.senderName || '')
    } · ${H.clockTime(message.createdAt)}</span>`;
    log.append(node);
    log.scrollTop = log.scrollHeight;
  }

  /* ------------------------------------------------------------------ */
  /* Events                                                              */
  /* ------------------------------------------------------------------ */

  function wireEvents() {
    $('#gpsToggle').addEventListener('click', () => {
      if (state.gpsStop) stopGps();
      else startGps();
    });

    $('#advanceBtn').addEventListener('click', async (event) => {
      const next = {
        accepted: 'en_route_pickup',
        en_route_pickup: 'at_pickup',
        at_pickup: 'in_transit',
        in_transit: 'delivered',
      }[state.trip.status];
      if (!next) return;

      await H.withBusy(event.currentTarget, async () => {
        try {
          let fix = null;
          try {
            fix = await M.locateOnce({ timeout: 6000 });
          } catch {
            /* stamping the step with a position is a nice-to-have */
          }
          await H.api.post(`/api/trips/${state.tripId}/status`, {
            status: next,
            lat: fix?.lat,
            lng: fix?.lng,
          });
          await load();
          if (next === 'delivered') {
            stopGps();
            H.toast('Delivered. Thanks — the customer can rate you now.', 'green');
          }
        } catch (err) {
          H.toast(err.message, 'red');
        }
      });
    });

    $('#releaseBtn').addEventListener('click', async () => {
      const result = await H.confirmDialog({
        title: 'Release this job?',
        body: 'It goes straight back on the open board for other operators. Releasing jobs often affects your rating.',
        confirmText: 'Release it',
        withReason: true,
      });
      if (!result) return;
      try {
        await H.api.post(`/api/trips/${state.tripId}/release`, { reason: result.reason || undefined });
        H.toast('Job released.', '');
        window.location.href = '/operator.html';
      } catch (err) {
        H.toast(err.message, 'red');
      }
    });

    $('#cancelBtn').addEventListener('click', async () => {
      const result = await H.confirmDialog({
        title: 'Cancel this job?',
        body: 'Any offers on it will be turned down. You can post a new job at any time.',
        confirmText: 'Cancel the job',
        withReason: true,
      });
      if (!result) return;
      try {
        await H.api.post(`/api/trips/${state.tripId}/cancel`, { reason: result.reason || undefined });
        H.toast('Job cancelled.', '');
        window.location.href = '/customer.html';
      } catch (err) {
        H.toast(err.message, 'red');
      }
    });

    $('#bidSubmit').addEventListener('click', (event) => submitBid(event.currentTarget));

    $('#acceptJob').addEventListener('click', async (event) => {
      const confirmed = await H.confirmDialog({
        title: `Accept at ${H.money(state.trip.customerOfferPrice)}?`,
        body: 'The job becomes yours immediately — the customer does not have to choose between bids.',
        confirmText: 'Accept the job',
        tone: 'green',
      });
      if (!confirmed) return;

      await H.withBusy(event.currentTarget, async () => {
        try {
          await H.api.post(`/api/trips/${state.tripId}/accept`);
          H.toast('Job accepted. Head to the pickup.', 'green');
          await load();
        } catch (err) {
          H.toast(err.message, 'red');
          await load();
        }
      });
    });

    $('#bidWithdraw').addEventListener('click', async (event) => {
      const offerId = state.trip.myOffer?.id;
      if (!offerId) return;
      await H.withBusy(event.currentTarget, async () => {
        try {
          await H.api.del(`/api/offers/${offerId}`);
          H.toast('Offer withdrawn.', '');
          await load();
        } catch (err) {
          H.toast(err.message, 'red');
        }
      });
    });

    $('#rateSubmit').addEventListener('click', async (event) => {
      if (!state.myRating) return H.toast('Pick a star rating first.', 'red');
      await H.withBusy(event.currentTarget, async () => {
        try {
          await H.api.post(`/api/trips/${state.tripId}/rate`, {
            rating: state.myRating,
            review: $('#reviewText').value.trim() || undefined,
          });
          H.toast('Thanks for the rating.', 'green');
          await load();
        } catch (err) {
          H.toast(err.message, 'red');
        }
      });
    });

    $('#chatForm').addEventListener('submit', async (event) => {
      event.preventDefault();
      const input = $('#chatInput');
      const body = input.value.trim();
      if (!body) return;
      input.value = '';
      try {
        const { message } = await H.api.post(`/api/trips/${state.tripId}/messages`, { body });
        appendMessage(message);
      } catch (err) {
        input.value = body;
        H.toast(err.message, 'red');
      }
    });
  }

  async function submitBid(button) {
    const price = Number($('#bidPrice').value || 0);
    if (!price || price < 1) return H.toast('Enter the price you want for this job.', 'red');

    await H.withBusy(button, async () => {
      try {
        await H.api.post(`/api/trips/${state.tripId}/offers`, {
          price,
          etaMinutes: Number($('#bidEta').value) || undefined,
          message: $('#bidMessage').value.trim() || undefined,
        });
        H.toast('Offer sent. The customer sees it right away.', 'green');
        await load();
      } catch (err) {
        H.toast(err.message, 'red');
      }
    });
  }

  window.addEventListener('beforeunload', stopGps);
})();
