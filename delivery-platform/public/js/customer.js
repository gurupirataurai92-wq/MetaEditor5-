/* Customer dashboard: jobs in progress, offers waiting, and past deliveries. */
/* global window, document */

(function () {
  'use strict';

  const H = window.Haulr;
  const { $, $$, esc } = H;

  let scope = 'active';
  let trips = [];

  document.addEventListener('DOMContentLoaded', async () => {
    await H.boot();
    const user = H.Session.require('customer');
    if (!user) return;

    $('#greeting').textContent = `Hello, ${user.fullName.split(' ')[0]}`;

    await H.loadMeta();
    H.bindConnectionPill($('#conn'));
    H.realtime.connect();

    // Any change to one of my jobs refreshes the list in place.
    for (const type of ['trip_update', 'offer_new', 'offer_withdrawn']) {
      H.realtime.on(type, () => load());
    }
    H.realtime.on('offer_new', (msg) => {
      const trip = trips.find((t) => t.id === msg.tripId);
      H.toast(
        `New offer${trip ? ` on ${trip.reference}` : ''}: ${H.money(msg.offer.price)} from ${
          msg.offer.operator?.fullName || 'an operator'
        }`,
        'accent'
      );
    });

    for (const tab of $$('.tab')) {
      tab.addEventListener('click', () => {
        $$('.tab').forEach((t) => t.classList.toggle('active', t === tab));
        scope = tab.dataset.scope;
        load();
      });
    }

    load();
  });

  async function load() {
    try {
      const [activeData, allData] = await Promise.all([
        H.api.get('/api/trips?scope=active'),
        H.api.get(`/api/trips?scope=${scope}`),
      ]);
      renderStats(activeData.trips);
      trips = allData.trips;
      renderTrips(trips);
    } catch (err) {
      $('#tripList').innerHTML = `<div class="alert alert-error">${esc(err.message)}</div>`;
    }
  }

  function renderStats(activeTrips) {
    const awaitingOffers = activeTrips.filter((t) => t.status === 'requested');
    const onTheRoad = activeTrips.filter((t) => t.trackable && t.status !== 'accepted');
    const totalOffers = awaitingOffers.reduce((sum, t) => sum + (t.offerCount || 0), 0);

    const stats = [
      ['In progress', activeTrips.length],
      ['Waiting for offers', awaitingOffers.length],
      ['Offers to review', totalOffers],
      ['On the road now', onTheRoad.length],
    ];

    $('#stats').innerHTML = stats
      .map(
        ([label, value]) => `
        <div class="stat">
          <div class="stat-label">${esc(label)}</div>
          <div class="stat-value">${value}</div>
        </div>`
      )
      .join('');
  }

  function renderTrips(list) {
    const host = $('#tripList');

    if (!list.length) {
      host.innerHTML =
        scope === 'active'
          ? `<div class="empty">
               <div class="empty-icon">📦</div>
               <h3>Nothing in flight</h3>
               <p>Post a job and nearby operators will start sending you offers.</p>
               <a href="/request.html" class="btn btn-accent">Post a delivery</a>
             </div>`
          : `<div class="empty">
               <div class="empty-icon">🗂️</div>
               <h3>No past deliveries yet</h3>
               <p>Completed and cancelled jobs will show up here.</p>
             </div>`;
      return;
    }

    host.innerHTML = list.map(card).join('');

    for (const node of $$('[data-trip]')) {
      node.addEventListener('click', (event) => {
        if (event.target.closest('button, a')) return;
        window.location.href = `/track.html?trip=${node.dataset.trip}`;
      });
    }
  }

  function card(trip) {
    const meta = H.getMeta();
    const vehicle = meta.vehicleById[trip.vehicleClass];

    const offersLine =
      trip.status === 'requested'
        ? trip.offerCount
          ? `<span class="badge badge-accent">${trip.offerCount} offer${
              trip.offerCount === 1 ? '' : 's'
            }${trip.bestOffer != null ? ` · from ${H.money(trip.bestOffer)}` : ''}</span>`
          : '<span class="badge">Waiting for offers…</span>'
        : trip.operator
          ? `<span class="badge badge-blue">${esc(trip.operator.fullName)} · ${H.ratingStars(
              trip.operator.rating,
              trip.operator.ratingCount
            )}</span>`
          : '';

    const price = trip.agreedPrice ?? trip.customerOfferPrice;
    const priceLabel = trip.agreedPrice ? 'agreed' : 'your offer';

    const action =
      trip.status === 'requested' && trip.offerCount
        ? '<span class="btn btn-accent btn-sm">Review offers →</span>'
        : trip.trackable
          ? '<span class="btn btn-ghost btn-sm">Track live →</span>'
          : trip.status === 'delivered'
            ? '<span class="btn btn-green btn-sm">Rate this job →</span>'
            : '<span class="btn btn-ghost btn-sm">View →</span>';

    return `
      <article class="job-card is-clickable" data-trip="${trip.id}">
        <div class="row-between" style="margin-bottom:.7rem">
          <div class="row" style="gap:.5rem">
            ${H.statusBadge(trip)}
            <span class="job-ref">${esc(trip.reference)}</span>
          </div>
          <div style="text-align:right">
            <div class="price-sm">${H.money(price)}</div>
            <div class="muted tiny">${priceLabel}</div>
          </div>
        </div>

        ${H.routeBlock(trip)}

        <div class="divider" style="margin:.8rem 0"></div>

        <div class="row-between">
          <div class="row" style="gap:.4rem">
            <span class="badge">${vehicle ? `${vehicle.icon} ${esc(vehicle.name)}` : esc(trip.vehicleClass)}</span>
            <span class="badge">${trip.distanceKm} km</span>
            ${trip.helpersRequired ? `<span class="badge">${trip.helpersRequired} helper${trip.helpersRequired > 1 ? 's' : ''}</span>` : ''}
            ${offersLine}
          </div>
          <div class="row" style="gap:.6rem">
            <span class="muted tiny">${H.timeAgo(trip.createdAt)}</span>
            ${action}
          </div>
        </div>
      </article>`;
  }
})();
