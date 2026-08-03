/* Landing page: live activity map and a worked pricing example. */
/* global window, document */

(function () {
  'use strict';

  const H = window.Haulr;
  const M = window.HaulrMap;

  document.addEventListener('DOMContentLoaded', async () => {
    // Signed-in visitors should land in their own app, not the brochure.
    const user = H.Session.user;
    if (user) {
      const cta = document.querySelector('.hero .row');
      if (cta) {
        cta.innerHTML = `<a href="${H.Session.homePath()}" class="btn btn-accent btn-lg">Open my dashboard</a>`;
      }
    }

    await H.loadMeta();
    renderVehicleStrip();
    renderExampleQuote();
    renderActivityMap();
  });

  function renderVehicleStrip() {
    const host = document.getElementById('vehicleStrip');
    if (!host) return;
    const meta = H.getMeta();

    host.innerHTML = meta.vehicleClasses
      .map(
        (v) => `
        <div class="vclass">
          <div class="vclass-icon">${v.icon}</div>
          <div class="bold" style="margin-top:.3rem">${H.esc(v.name)}</div>
          <div class="muted tiny">${H.esc(v.blurb)}</div>
          <div class="badge" style="margin-top:.5rem">up to ${v.capacityKg.toLocaleString()} kg</div>
        </div>`
      )
      .join('');
  }

  /**
   * Mirrors the server's pricing formula for a representative job so the
   * marketing page can show a real breakdown without an API round trip.
   */
  function renderExampleQuote() {
    const host = document.getElementById('exampleQuote');
    if (!host) return;
    const meta = H.getMeta();

    const vehicle = meta.vehicleById.pickup;
    const distanceKm = 14;
    const helpers = 2;
    const stairFloors = 2;

    const rows = [
      [`${vehicle.icon} ${vehicle.name} base fare`, vehicle.baseFare],
      [`${distanceKm} km × ${meta.currency.symbol}${vehicle.perKm}`, vehicle.perKm * distanceKm],
      [`${helpers} helpers`, helpers * meta.helperFeePerPerson],
      [`${stairFloors} floors, no lift`, stairFloors * meta.floorFee],
    ];
    const total = rows.reduce((sum, [, amount]) => sum + amount, 0);

    host.innerHTML = `
      <dl class="kv">
        ${rows.map(([label, amount]) => `<dt>${H.esc(label)}</dt><dd>${H.money(amount)}</dd>`).join('')}
      </dl>
      <div class="divider"></div>
      <div class="row-between">
        <span class="bold">Suggested fare</span>
        <span class="price">${H.money(total)}</span>
      </div>
      <div class="muted small">
        Typical offers land between ${H.money(total * 0.85)} and ${H.money(total * 1.2)}.
      </div>`;
  }

  async function renderActivityMap() {
    const host = document.getElementById('heroMap');
    const counter = document.getElementById('heroCount');
    if (!host) return;

    let activity;
    try {
      activity = await H.api.get('/api/public/activity');
    } catch {
      counter.textContent = 'Unavailable';
      return;
    }

    // The headline number is worth showing even if the map itself cannot draw.
    counter.textContent = `${activity.online} on duty`;
    if (typeof window.L === 'undefined') return;

    const centre = activity.centre
      ? [activity.centre.lat, activity.centre.lng]
      : M.DEFAULT_CENTRE;

    const map = M.createMap('heroMap', { center: centre, zoom: 11, scrollWheelZoom: false });
    const swarm = M.vehicleSwarm(map);

    swarm.update(activity.cells, (cls) => H.vehicleIcon(cls));
    counter.textContent = `${activity.online} on duty`;

    if (activity.cells.length > 1) {
      M.fitTo(map, activity.cells.map((c) => [c.lat, c.lng]), { maxZoom: 12 });
    }

    // Refresh occasionally so the page feels alive without polling hard.
    setInterval(async () => {
      try {
        const next = await H.api.get('/api/public/activity');
        swarm.update(next.cells, (cls) => H.vehicleIcon(cls));
        counter.textContent = `${next.online} on duty`;
      } catch {
        /* leave the last good state on screen */
      }
    }, 30000);
  }
})();
