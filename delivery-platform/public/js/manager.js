/* Manager console: oversight of every job, driver and customer. */
/* global window, document, setInterval */

(function () {
  'use strict';

  const H = window.Haulr;
  const M = window.HaulrMap;
  const { $, $$, esc } = H;

  const state = { view: 'live', fleet: [], jobs: [], people: [] };

  let map;
  let markers = [];

  document.addEventListener('DOMContentLoaded', async () => {
    await H.boot();
    const user = H.Session.require('manager');
    if (!user) return;

    // A manager without a second factor gets the enrolment gate and nothing
    // else — the server refuses every console endpoint until it is done.
    if (user.mustEnrolTwoFactor) {
      $('#enrolGate').classList.remove('hidden');
      wireEnrolment();
      return;
    }

    $('#console').classList.remove('hidden');
    $('#greeting').textContent = `Operations — ${user.fullName.split(' ')[0]}`;

    await H.loadMeta();
    H.bindConnectionPill($('#conn'));
    map = M.createMap('map', { zoom: 11 });

    wireTabs();
    wireFilters();

    H.realtime.connect();
    for (const type of ['job_posted', 'job_closed', 'trip_update']) {
      H.realtime.on(type, () => refreshQuiet());
    }

    await refresh();
    setInterval(refreshQuiet, 25000);
  });

  /* ------------------------------------------------------------------ */
  /* Two-factor enrolment gate                                           */
  /* ------------------------------------------------------------------ */

  function wireEnrolment() {
    const showErr = (message) => {
      const box = $('#enrolAlert');
      box.textContent = message;
      box.classList.remove('hidden');
    };

    $('#enrolStart').addEventListener('click', async (event) => {
      await H.withBusy(event.currentTarget, async () => {
        try {
          const { secret } = await H.api.post('/api/auth/2fa/start');
          $('#enrolSecret').textContent = secret;
          $('#enrolStep1').classList.add('hidden');
          $('#enrolStep2').classList.remove('hidden');
          $('#enrolCode').focus();
        } catch (err) {
          showErr(err.message);
        }
      });
    });

    $('#enrolConfirm').addEventListener('click', async (event) => {
      $('#enrolAlert').classList.add('hidden');
      const code = $('#enrolCode').value.trim();
      if (!code) return showErr('Enter the code your app is showing.');

      await H.withBusy(event.currentTarget, async () => {
        try {
          const { recoveryCodes } = await H.api.post('/api/auth/2fa/enable', { code });
          $('#recoveryCodes').innerHTML = recoveryCodes.map((c) => esc(c)).join('<br>');
          $('#enrolStep2').classList.add('hidden');
          $('#enrolStep3').classList.remove('hidden');
        } catch (err) {
          showErr(err.message);
        }
      });
    });

    $('#enrolDone').addEventListener('click', () => window.location.reload());
  }

  /* ------------------------------------------------------------------ */
  /* Tabs and refresh                                                    */
  /* ------------------------------------------------------------------ */

  function wireTabs() {
    for (const tab of $$('.tab')) {
      tab.addEventListener('click', () => {
        $$('.tab').forEach((t) => t.classList.toggle('active', t === tab));
        state.view = tab.dataset.view;
        for (const id of ['Live', 'Jobs', 'People', 'Audit', 'Security']) {
          $(`#view${id}`).classList.toggle('hidden', id.toLowerCase() !== state.view);
        }
        refresh();
      });
    }
    // Deep link from the header, e.g. /manager.html#security
    const hash = window.location.hash.replace('#', '');
    if (hash) {
      const tab = $(`.tab[data-view="${hash}"]`);
      if (tab) tab.click();
    }
  }

  function wireFilters() {
    $('#refreshBtn').addEventListener('click', () => refresh());
    $('#jobStatus').addEventListener('change', loadJobs);
    $('#jobSearch').addEventListener('input', debounce(loadJobs, 350));
    $('#peopleRole').addEventListener('change', loadPeople);
    $('#peopleSearch').addEventListener('input', debounce(loadPeople, 350));
    $('#auditAction').addEventListener('change', loadAudit);
    $('#addManagerBtn').addEventListener('click', openAddManager);
    $('#revokeOthers').addEventListener('click', revokeOtherSessions);
  }

  function debounce(fn, ms) {
    let timer;
    return (...args) => {
      clearTimeout(timer);
      timer = setTimeout(() => fn(...args), ms);
    };
  }

  async function refresh() {
    await loadOverview();
    if (state.view === 'live') await loadFleet();
    else if (state.view === 'jobs') await loadJobs();
    else if (state.view === 'people') await loadPeople();
    else if (state.view === 'audit') await loadAudit();
    else if (state.view === 'security') await loadSecurity();
  }

  function refreshQuiet() {
    loadOverview().catch(() => {});
    if (state.view === 'live') loadFleet().catch(() => {});
  }

  function showAlert(message) {
    const box = $('#alert');
    box.textContent = message;
    box.classList.remove('hidden');
  }

  /* ------------------------------------------------------------------ */
  /* Overview                                                            */
  /* ------------------------------------------------------------------ */

  async function loadOverview() {
    const data = await H.api.get('/api/manager/overview');

    const cards = [
      ['Live now', data.jobs.live],
      ['Waiting for a driver', data.jobs.awaitingOperator],
      ['Drivers on duty', data.people.onDuty],
      ['Flagged', data.jobs.flagged],
      ['Jobs (24h)', data.last24h.jobs],
      ['Value (24h)', H.money(data.last24h.value)],
    ];

    $('#stats').innerHTML = cards
      .map(
        ([label, value]) => `
        <div class="stat">
          <div class="stat-label">${esc(label)}</div>
          <div class="stat-value">${esc(String(value))}</div>
        </div>`
      )
      .join('');

    renderStalled(data.stalled);
  }

  function renderStalled(stalled) {
    $('#stalledCount').textContent = stalled.length;
    const host = $('#stalledList');

    if (!stalled.length) {
      host.innerHTML = '<p class="muted small" style="margin:0">Nothing waiting. All jobs are moving.</p>';
      return;
    }

    host.innerHTML = stalled
      .map(
        (job) => `
        <div class="job-card card-tight is-clickable" data-job="${job.id}">
          <div class="row-between">
            <span class="job-ref">${esc(job.reference)}</span>
            <span class="badge badge-amber">${job.waitingMinutes} min</span>
          </div>
          <div class="small truncate" style="margin-top:.3rem">${esc(job.pickup.address)}</div>
          <div class="row-between" style="margin-top:.4rem">
            <span class="badge">${H.vehicleIcon(job.vehicleClass)} ${esc(H.vehicleName(job.vehicleClass))}</span>
            <span class="small bold">${H.money(job.customerOfferPrice)}</span>
          </div>
        </div>`
      )
      .join('');

    for (const node of host.querySelectorAll('[data-job]')) {
      node.addEventListener('click', () => openJob(Number(node.dataset.job)));
    }
  }

  /* ------------------------------------------------------------------ */
  /* Live fleet                                                          */
  /* ------------------------------------------------------------------ */

  async function loadFleet() {
    const { vehicles } = await H.api.get('/api/manager/fleet');
    state.fleet = vehicles;

    for (const marker of markers) map.removeLayer(marker);
    markers = [];

    const points = [];
    for (const vehicle of vehicles) {
      const marker = window.L.marker([vehicle.lat, vehicle.lng], {
        icon: M.vehicleIcon(H.vehicleIcon(vehicle.vehicleClass), { live: vehicle.busy }),
      })
        .addTo(map)
        .bindPopup(
          `<strong>${esc(vehicle.name)}</strong><br>` +
            `${esc(H.vehicleName(vehicle.vehicleClass))} · ${esc(vehicle.plate || '')}<br>` +
            (vehicle.currentTripId
              ? `<a href="/track.html?trip=${vehicle.currentTripId}">On a job — open it</a>`
              : 'Free')
        );
      markers.push(marker);
      points.push([vehicle.lat, vehicle.lng]);
    }

    M.fitTo(map, points, { maxZoom: 12 });
    $('#mapCaption').textContent = vehicles.length
      ? `${vehicles.length} driver${vehicles.length === 1 ? '' : 's'} on duty · ${
          vehicles.filter((v) => v.busy).length
        } on a job`
      : 'No drivers on duty right now.';

    $('#fleetList').innerHTML = vehicles.length
      ? vehicles
          .map(
            (v) => `
          <div class="job-card card-tight">
            <div class="row-between">
              <div>
                <div class="bold small">${esc(v.name)}</div>
                <div class="muted tiny">
                  ${H.vehicleIcon(v.vehicleClass)} ${esc(H.vehicleName(v.vehicleClass))}
                  ${v.plate ? `· <span class="mono">${esc(v.plate)}</span>` : ''}
                </div>
              </div>
              <div style="text-align:right">
                ${
                  v.busy
                    ? `<a class="badge badge-accent" href="/track.html?trip=${v.currentTripId}">On a job</a>`
                    : '<span class="badge badge-green">Free</span>'
                }
                <div class="muted tiny">${H.timeAgo(v.lastSeenAt)}</div>
              </div>
            </div>
          </div>`
          )
          .join('')
      : '<p class="muted small" style="margin:0">Nobody on duty.</p>';
  }

  /* ------------------------------------------------------------------ */
  /* Jobs                                                                */
  /* ------------------------------------------------------------------ */

  async function loadJobs() {
    const params = new URLSearchParams();
    if ($('#jobStatus').value) params.set('status', $('#jobStatus').value);
    if ($('#jobSearch').value.trim()) params.set('q', $('#jobSearch').value.trim());

    try {
      const { trips } = await H.api.get(`/api/manager/trips?${params}`);
      state.jobs = trips;

      $('#jobList').innerHTML = trips.length
        ? trips
            .map(
              (job) => `
          <article class="job-card is-clickable" data-job="${job.id}">
            <div class="row-between" style="margin-bottom:.6rem">
              <div class="row" style="gap:.45rem">
                ${H.statusBadge(job)}
                <span class="job-ref">${esc(job.reference)}</span>
                ${job.flaggedAt ? `<span class="badge badge-red">⚑ ${esc(job.flaggedReason || 'Flagged')}</span>` : ''}
                ${job.assignedBy === 'manager' ? '<span class="badge badge-blue">Manager assigned</span>' : ''}
              </div>
              <div style="text-align:right">
                <div class="price-sm">${H.money(job.agreedPrice ?? job.customerOfferPrice)}</div>
                <div class="muted tiny">${H.timeAgo(job.createdAt)}</div>
              </div>
            </div>
            ${H.routeBlock(job)}
            <div class="divider" style="margin:.7rem 0"></div>
            <div class="row" style="gap:.4rem">
              <span class="badge">${H.vehicleIcon(job.vehicleClass)} ${esc(H.vehicleName(job.vehicleClass))}</span>
              <span class="badge">${job.distanceKm} km</span>
              ${job.offerCount ? `<span class="badge badge-amber">${job.offerCount} bid(s)</span>` : ''}
              ${job.operator ? `<span class="badge badge-blue">${esc(job.operator.fullName)}</span>` : '<span class="badge">No driver</span>'}
            </div>
          </article>`
            )
            .join('')
        : '<div class="empty"><div class="empty-icon">🔍</div><p>No jobs match that filter.</p></div>';

      for (const node of $$('#jobList [data-job]')) {
        node.addEventListener('click', () => openJob(Number(node.dataset.job)));
      }
    } catch (err) {
      showAlert(err.message);
    }
  }

  /**
   * Open one job's full record. Note that this is an audited read — the
   * server records which manager looked at whose details.
   */
  async function openJob(tripId) {
    let data;
    try {
      data = await H.api.get(`/api/manager/trips/${tripId}`);
    } catch (err) {
      return H.toast(err.message, 'red');
    }

    const trip = data.trip;
    const canIntervene = !['completed', 'cancelled'].includes(trip.status);

    const body = H.el('div', {}, '');
    body.innerHTML = `
      <div class="row-between" style="margin-bottom:.6rem">
        <span class="job-ref">${esc(trip.reference)}</span>
        ${H.statusBadge(trip)}
      </div>
      ${H.routeBlock(trip)}
      <div class="divider"></div>
      <dl class="kv">
        <dt>Customer</dt><dd>${esc(trip.customer?.fullName || '—')}${
          trip.customer?.phone ? ` · ${esc(trip.customer.phone)}` : ''
        }</dd>
        <dt>Driver</dt><dd>${
          trip.operator ? esc(trip.operator.fullName) + (trip.operator.phone ? ` · ${esc(trip.operator.phone)}` : '') : 'Not assigned'
        }</dd>
        <dt>Price</dt><dd>${H.money(trip.agreedPrice ?? trip.customerOfferPrice)}</dd>
        <dt>Vehicle</dt><dd>${H.vehicleIcon(trip.vehicleClass)} ${esc(H.vehicleName(trip.vehicleClass))}</dd>
        <dt>Distance</dt><dd>${trip.distanceKm} km</dd>
        <dt>GPS points</dt><dd>${data.trail.length}</dd>
        <dt>Messages</dt><dd>${data.messageCount}</dd>
      </dl>
      <div class="divider"></div>
      <p class="small">${esc(trip.itemDescription)}</p>
      ${trip.flaggedAt ? `<div class="alert alert-error small">⚑ ${esc(trip.flaggedReason)}</div>` : ''}
      <div class="row" style="margin-top:1rem">
        <a class="btn btn-quiet btn-sm" href="/track.html?trip=${trip.id}">Open live map</a>
        ${canIntervene ? `<button class="btn btn-quiet btn-sm" id="mReassign">Reassign driver</button>` : ''}
        ${canIntervene ? `<button class="btn btn-quiet btn-sm" id="mFlag">${trip.flaggedAt ? 'Clear flag' : 'Flag'}</button>` : ''}
        ${canIntervene ? `<button class="btn btn-red btn-sm" id="mCancel">Cancel job</button>` : ''}
      </div>`;

    const close = openModal(body);

    body.querySelector('#mCancel')?.addEventListener('click', async () => {
      const result = await H.confirmDialog({
        title: `Cancel ${trip.reference}?`,
        body: 'Both parties are notified immediately and any pending bids are turned down.',
        confirmText: 'Cancel the job',
        withReason: true,
      });
      if (!result) return;
      if (!result.reason) return H.toast('A reason is required.', 'red');
      try {
        await H.api.post(`/api/manager/trips/${trip.id}/cancel`, { reason: result.reason });
        H.toast('Job cancelled.', '');
        close();
        refresh();
      } catch (err) {
        H.toast(err.message, 'red');
      }
    });

    body.querySelector('#mFlag')?.addEventListener('click', async () => {
      if (trip.flaggedAt) {
        await H.api.post(`/api/manager/trips/${trip.id}/flag`, { clear: true });
        H.toast('Flag cleared.', '');
        close();
        return refresh();
      }
      const result = await H.confirmDialog({
        title: `Flag ${trip.reference}?`,
        body: 'Marks the job for attention. Visible to every manager.',
        confirmText: 'Flag it',
        tone: 'accent',
        withReason: true,
      });
      if (!result) return;
      if (!result.reason) return H.toast('A reason is required.', 'red');
      try {
        await H.api.post(`/api/manager/trips/${trip.id}/flag`, { reason: result.reason });
        H.toast('Flagged.', 'accent');
        close();
        refresh();
      } catch (err) {
        H.toast(err.message, 'red');
      }
    });

    body.querySelector('#mReassign')?.addEventListener('click', () => {
      close();
      openReassign(trip);
    });
  }

  async function openReassign(trip) {
    let candidates = [];
    try {
      ({ candidates } = await H.api.get(`/api/manager/trips/${trip.id}/candidates`));
    } catch (err) {
      return H.toast(err.message, 'red');
    }

    const body = H.el('div', {}, '');
    body.innerHTML = `
      <h3>Reassign ${esc(trip.reference)}</h3>
      <p class="muted small">
        Only drivers whose vehicle can carry this load are listed, free and on-duty first.
      </p>
      <div class="field">
        <label for="reassignReason">Reason (recorded in the audit log)</label>
        <input type="text" id="reassignReason" maxlength="300" placeholder="Driver broke down" />
      </div>
      <div class="list scroll-y" style="max-height:320px">
        ${
          candidates.length
            ? candidates
                .map(
                  (c) => `
            <div class="job-card card-tight">
              <div class="row-between">
                <div>
                  <div class="bold small">${esc(c.name)}</div>
                  <div class="muted tiny">
                    ${H.vehicleIcon(c.vehicleClass)} ${esc(H.vehicleName(c.vehicleClass))}
                    ${c.rating != null ? `· ★ ${c.rating}` : '· new'}
                    ${c.activeJobs ? `· ${c.activeJobs} active` : ''}
                    ${c.distanceToPickupKm != null ? `· ${c.distanceToPickupKm} km away` : ''}
                  </div>
                </div>
                <div class="row" style="gap:.35rem">
                  <span class="badge ${c.online ? 'badge-green' : ''}">${c.online ? 'On duty' : 'Off'}</span>
                  <button class="btn btn-accent btn-sm" data-pick="${c.id}">Assign</button>
                </div>
              </div>
            </div>`
                )
                .join('')
            : '<p class="muted small">No eligible driver is available.</p>'
        }
      </div>`;

    const close = openModal(body);

    for (const button of body.querySelectorAll('[data-pick]')) {
      button.addEventListener('click', async () => {
        const reason = body.querySelector('#reassignReason').value.trim();
        if (reason.length < 3) return H.toast('Give a reason first.', 'red');
        await H.withBusy(button, async () => {
          try {
            await H.api.post(`/api/manager/trips/${trip.id}/reassign`, {
              operatorId: Number(button.dataset.pick),
              reason,
            });
            H.toast('Driver reassigned.', 'green');
            close();
            refresh();
          } catch (err) {
            H.toast(err.message, 'red');
          }
        });
      });
    }
  }

  /* ------------------------------------------------------------------ */
  /* People                                                              */
  /* ------------------------------------------------------------------ */

  async function loadPeople() {
    const params = new URLSearchParams();
    if ($('#peopleRole').value) params.set('role', $('#peopleRole').value);
    if ($('#peopleSearch').value.trim()) params.set('q', $('#peopleSearch').value.trim());

    try {
      const { users } = await H.api.get(`/api/manager/users?${params}`);
      state.people = users;

      $('#peopleList').innerHTML = users.length
        ? users.map(personCard).join('')
        : '<div class="empty"><div class="empty-icon">🔍</div><p>Nobody matches that.</p></div>';

      wirePersonActions();
    } catch (err) {
      showAlert(err.message);
    }
  }

  const ROLE_BADGE = {
    customer: '<span class="badge">Customer</span>',
    operator: '<span class="badge badge-blue">Driver</span>',
    manager: '<span class="badge badge-accent">Manager</span>',
  };

  function personCard(person) {
    return `
      <article class="job-card">
        <div class="row-between">
          <div>
            <div class="row" style="gap:.4rem">
              <span class="bold">${esc(person.fullName)}</span>
              ${ROLE_BADGE[person.role] || ''}
              ${person.suspended ? '<span class="badge badge-red">Suspended</span>' : ''}
              ${person.verified === false ? '<span class="badge badge-amber">Unverified</span>' : ''}
              ${person.twoFactorEnabled ? '<span class="badge badge-green">2FA</span>' : ''}
            </div>
            <div class="muted tiny" style="margin-top:.25rem">
              ${esc(person.email)} · ${esc(person.phone)}
              ${person.rating != null ? `· ★ ${person.rating} (${person.ratingCount})` : ''}
              ${person.vehicleClass ? `· ${H.vehicleIcon(person.vehicleClass)} ${esc(H.vehicleName(person.vehicleClass))}` : ''}
            </div>
            ${person.suspendedReason ? `<div class="tiny" style="color:var(--red);margin-top:.25rem">${esc(person.suspendedReason)}</div>` : ''}
          </div>
          <div class="row" style="gap:.35rem">
            ${
              person.role === 'operator'
                ? `<button class="btn btn-quiet btn-sm" data-verify="${person.id}" data-current="${person.verified}">
                     ${person.verified ? 'Un-verify' : 'Verify'}
                   </button>`
                : ''
            }
            ${
              person.role !== 'manager'
                ? person.suspended
                  ? `<button class="btn btn-green btn-sm" data-reinstate="${person.id}">Reinstate</button>`
                  : `<button class="btn btn-red btn-sm" data-suspend="${person.id}" data-name="${esc(person.fullName)}">Suspend</button>`
                : ''
            }
            <button class="btn btn-ghost btn-sm" data-logout="${person.id}">Force sign-out</button>
          </div>
        </div>
      </article>`;
  }

  function wirePersonActions() {
    for (const button of $$('[data-verify]')) {
      button.addEventListener('click', async () => {
        const verified = button.dataset.current !== 'true';
        try {
          await H.api.post(`/api/manager/operators/${button.dataset.verify}/verify`, { verified });
          H.toast(verified ? 'Driver verified.' : 'Verification removed.', 'green');
          loadPeople();
        } catch (err) {
          H.toast(err.message, 'red');
        }
      });
    }

    for (const button of $$('[data-suspend]')) {
      button.addEventListener('click', async () => {
        const result = await H.confirmDialog({
          title: `Suspend ${button.dataset.name}?`,
          body: 'They are signed out everywhere immediately and cannot sign back in.',
          confirmText: 'Suspend',
          withReason: true,
        });
        if (!result) return;
        if (!result.reason) return H.toast('A reason is required.', 'red');
        try {
          const res = await H.api.post(`/api/manager/users/${button.dataset.suspend}/suspend`, {
            reason: result.reason,
          });
          H.toast(`Suspended. ${res.sessionsEnded} session(s) ended.`, '');
          loadPeople();
        } catch (err) {
          H.toast(err.message, 'red');
        }
      });
    }

    for (const button of $$('[data-reinstate]')) {
      button.addEventListener('click', async () => {
        try {
          await H.api.post(`/api/manager/users/${button.dataset.reinstate}/reinstate`);
          H.toast('Account reinstated.', 'green');
          loadPeople();
        } catch (err) {
          H.toast(err.message, 'red');
        }
      });
    }

    for (const button of $$('[data-logout]')) {
      button.addEventListener('click', async () => {
        try {
          const res = await H.api.post(`/api/manager/users/${button.dataset.logout}/force-logout`);
          H.toast(`${res.sessionsEnded} session(s) ended.`, '');
        } catch (err) {
          H.toast(err.message, 'red');
        }
      });
    }
  }

  function openAddManager() {
    const body = H.el('div', {}, '');
    body.innerHTML = `
      <h3>Add a manager</h3>
      <p class="muted small">
        Manager accounts cannot be created by signing up — only an existing manager can make
        one, and only by confirming their own password. The new account must change its
        password and enrol two-factor on first sign-in.
      </p>
      <div class="field"><label for="nmName">Full name</label><input type="text" id="nmName" /></div>
      <div class="field"><label for="nmEmail">Email</label><input type="email" id="nmEmail" /></div>
      <div class="field"><label for="nmPhone">Phone</label><input type="tel" id="nmPhone" /></div>
      <div class="field">
        <label for="nmPassword">Temporary password for them</label>
        <input type="password" id="nmPassword" autocomplete="new-password" />
        <div class="hint">
          At least 12 characters, mixing at least three of lowercase, uppercase, numbers and
          symbols.
        </div>
      </div>
      <div class="divider"></div>
      <div class="field">
        <label for="nmConfirm">Confirm with <em>your own</em> password</label>
        <input type="password" id="nmConfirm" autocomplete="current-password" />
      </div>
      <button class="btn btn-accent btn-block" id="nmSubmit">Create manager account</button>
      <div class="alert alert-error hidden" id="nmAlert" style="margin-top:.8rem"></div>`;

    const close = openModal(body);

    body.querySelector('#nmSubmit').addEventListener('click', async (event) => {
      const alertBox = body.querySelector('#nmAlert');
      alertBox.classList.add('hidden');

      await H.withBusy(event.currentTarget, async () => {
        try {
          const res = await H.api.post('/api/manager/managers', {
            fullName: body.querySelector('#nmName').value.trim(),
            email: body.querySelector('#nmEmail').value.trim(),
            phone: body.querySelector('#nmPhone').value.trim(),
            password: body.querySelector('#nmPassword').value,
            confirmPassword: body.querySelector('#nmConfirm').value,
          });
          H.toast(`Manager account created for ${res.user.email}.`, 'green');
          close();
          loadPeople();
        } catch (err) {
          alertBox.textContent = err.message;
          alertBox.classList.remove('hidden');
        }
      });
    });
  }

  /* ------------------------------------------------------------------ */
  /* Audit                                                               */
  /* ------------------------------------------------------------------ */

  async function loadAudit() {
    const params = new URLSearchParams({ limit: '150' });
    if ($('#auditAction').value) params.set('action', $('#auditAction').value);

    try {
      const data = await H.api.get(`/api/manager/audit?${params}`);
      $('#auditTotal').textContent = `${data.total} entries`;

      $('#auditRows').innerHTML = data.entries.length
        ? data.entries
            .map(
              (entry) => `
          <tr style="border-bottom:1px solid var(--line)">
            <td style="padding:.5rem .9rem;white-space:nowrap" class="muted tiny">
              ${H.dateTime(entry.createdAt)}
            </td>
            <td style="padding:.5rem .9rem">
              ${entry.actorName ? esc(entry.actorName) : '<span class="muted">system</span>'}
              ${entry.actorRole ? `<span class="badge tiny">${esc(entry.actorRole)}</span>` : ''}
            </td>
            <td style="padding:.5rem .9rem"><span class="mono tiny">${esc(entry.action)}</span></td>
            <td style="padding:.5rem .9rem" class="tiny">
              ${entry.subjectType ? `${esc(entry.subjectType)} ${esc(entry.subjectId || '')}` : ''}
              ${entry.detail ? `<span class="muted">— ${esc(entry.detail)}</span>` : ''}
            </td>
          </tr>`
            )
            .join('')
        : '<tr><td colspan="4" class="muted" style="padding:1.5rem;text-align:center">Nothing logged yet.</td></tr>';
    } catch (err) {
      showAlert(err.message);
    }
  }

  /* ------------------------------------------------------------------ */
  /* Security                                                            */
  /* ------------------------------------------------------------------ */

  async function loadSecurity() {
    try {
      const data = await H.api.get('/api/manager/security');

      const cards = [
        ['Failed sign-ins (24h)', data.failedLogins24h],
        ['Locked accounts', data.lockedAccounts],
        ['Active sessions', data.activeSessions],
        ['Managers without 2FA', data.managersWithoutTwoFactor],
      ];

      $('#securityStats').innerHTML = cards
        .map(
          ([label, value]) => `
          <div class="stat">
            <div class="stat-label">${esc(label)}</div>
            <div class="stat-value">${value}</div>
          </div>`
        )
        .join('');

      $('#targetedList').innerHTML = data.topTargetedAccounts.length
        ? data.topTargetedAccounts
            .map(
              (row) => `
          <div class="row-between small" style="padding:.35rem 0;border-bottom:1px solid var(--line)">
            <span class="truncate">${esc(row.email || 'unknown')}</span>
            <span class="badge ${row.attempts >= 5 ? 'badge-red' : 'badge-amber'}">${row.attempts}</span>
          </div>`
            )
            .join('')
        : '<p class="muted small" style="margin:0">No failed sign-ins in the last 24 hours.</p>';

      const me = H.Session.user;
      $('#myAccount').innerHTML = [
        ['Name', me.fullName],
        ['Email', me.email],
        ['Two-factor', me.twoFactorEnabled ? 'On' : 'Off'],
      ]
        .map(([k, v]) => `<dt>${esc(k)}</dt><dd>${esc(v)}</dd>`)
        .join('');

      const { sessions } = await H.api.get('/api/auth/sessions');
      $('#sessionList').innerHTML = sessions
        .filter((s) => !s.revokedAt)
        .map(
          (s) => `
        <div class="small" style="padding:.35rem 0;border-bottom:1px solid var(--line)">
          <div class="row-between">
            <span>${s.current ? '<span class="badge badge-green">This device</span>' : esc(s.ip || 'unknown')}</span>
            <span class="muted tiny">${H.timeAgo(s.lastSeenAt)}</span>
          </div>
          <div class="muted tiny truncate">${esc(s.userAgent || '')}</div>
        </div>`
        )
        .join('');
    } catch (err) {
      showAlert(err.message);
    }
  }

  async function revokeOtherSessions(event) {
    await H.withBusy(event.currentTarget, async () => {
      try {
        const res = await H.api.post('/api/auth/sessions/revoke-others');
        H.toast(`${res.revoked} other session(s) ended.`, 'green');
        loadSecurity();
      } catch (err) {
        H.toast(err.message, 'red');
      }
    });
  }

  /* ------------------------------------------------------------------ */
  /* Modal helper                                                        */
  /* ------------------------------------------------------------------ */

  function openModal(contentNode) {
    const close = () => {
      backdrop.remove();
      document.removeEventListener('keydown', onKey);
    };
    const onKey = (e) => e.key === 'Escape' && close();

    const backdrop = H.el(
      'div',
      { class: 'modal-backdrop', onclick: (e) => e.target === backdrop && close() },
      H.el('div', { class: 'modal', role: 'dialog', 'aria-modal': 'true' }, contentNode)
    );

    document.body.append(backdrop);
    document.addEventListener('keydown', onKey);
    return close;
  }
})();
