/* Booking flow: pick two points on the map, describe the load, name a price. */
/* global window, document, setTimeout, clearTimeout, setInterval */

(function () {
  'use strict';

  const H = window.Haulr;
  const M = window.HaulrMap;
  const { $ } = H;

  const state = {
    pickup: null, // {lat, lng, address}
    dropoff: null,
    placing: 'pickup', // which pin the next map click sets
    quote: null,
    priceTouched: false,
  };

  let map;
  let swarm;
  let pickupMarker = null;
  let dropoffMarker = null;
  let routeLine = null;
  let quoteTimer = null;

  document.addEventListener('DOMContentLoaded', async () => {
    await H.boot();
    if (!H.Session.require('customer')) return;

    await H.loadMeta();
    buildForm();
    initMap();
    wireEvents();
    refreshSummary();
  });

  /* ------------------------------------------------------------------ */
  /* Form scaffolding                                                    */
  /* ------------------------------------------------------------------ */

  function buildForm() {
    const meta = H.getMeta();

    $('#currencySymbol').textContent = meta.currency.symbol;

    $('#category').innerHTML = meta.categories
      .map((c) => `<option value="${c.id}">${H.esc(c.name)}</option>`)
      .join('');

    $('#paymentMethod').innerHTML = meta.paymentMethods
      .map((p) => `<option value="${p.id}">${H.esc(p.name)}</option>`)
      .join('');

    $('#vehicleChoices').innerHTML = meta.vehicleClasses
      .map(
        (v, index) => `
        <label class="choice">
          <input type="radio" name="vehicleClass" value="${v.id}" ${index === 3 ? 'checked' : ''} />
          <div class="choice-icon">${v.icon}</div>
          <div class="choice-name">${H.esc(v.name)}</div>
          <div class="choice-note">${H.esc(v.blurb)}</div>
        </label>`
      )
      .join('');

    syncVehicleConstraints();
  }

  const selectedVehicle = () => {
    const id = $('input[name="vehicleClass"]:checked')?.value;
    return H.getMeta().vehicleById[id];
  };

  /** Keep the helper dropdown and the capacity hint in step with the vehicle. */
  function syncVehicleConstraints() {
    const vehicle = selectedVehicle();
    if (!vehicle) return;

    const select = $('#helpersRequired');
    const previous = Number(select.value || 0);
    const options = [];
    for (let n = 0; n <= vehicle.maxHelpers; n += 1) {
      options.push(
        `<option value="${n}">${n === 0 ? 'None — I will load' : `${n} helper${n > 1 ? 's' : ''}`}</option>`
      );
    }
    select.innerHTML = options.join('');
    select.value = String(Math.min(previous, vehicle.maxHelpers));
    select.disabled = vehicle.maxHelpers === 0;

    $('#vehicleHint').textContent =
      `${vehicle.name}: up to ${vehicle.capacityKg.toLocaleString()} kg` +
      (vehicle.maxHelpers ? `, up to ${vehicle.maxHelpers} helpers.` : ', driver only.');

    $('#weightEstimateKg').max = String(vehicle.capacityKg);
  }

  /* ------------------------------------------------------------------ */
  /* Map                                                                 */
  /* ------------------------------------------------------------------ */

  function initMap() {
    map = M.createMap('map');
    swarm = M.vehicleSwarm(map);

    map.on('click', async (event) => {
      const { lat, lng } = event.latlng;
      await setPoint(state.placing, lat, lng);
      // After the pickup lands, the natural next click is the drop-off.
      if (state.placing === 'pickup' && !state.dropoff) setPlacing('dropoff');
    });

    M.attachAddressSearch($('#pickupSearch'), {
      near: () => [map.getCenter().lat, map.getCenter().lng],
      onPick: (result) => setPoint('pickup', result.lat, result.lng, result.label),
    });
    M.attachAddressSearch($('#dropoffSearch'), {
      near: () => [map.getCenter().lat, map.getCenter().lng],
      onPick: (result) => setPoint('dropoff', result.lat, result.lng, result.label),
    });

    // Centre on the customer if they allow it; otherwise the default city view.
    M.locateOnce()
      .then((fix) => {
        if (!state.pickup) map.setView([fix.lat, fix.lng], 14);
        refreshNearby();
      })
      .catch(() => refreshNearby());

    map.on('moveend', refreshNearby);
    setInterval(refreshNearby, 20000);
  }

  function setPlacing(which) {
    state.placing = which;
    $('#mapMode').textContent =
      which === 'pickup'
        ? 'Click the map to place your pickup pin (A).'
        : 'Click the map to place your drop-off pin (B).';
  }

  /** Set one end of the route, reverse-geocoding when no label was supplied. */
  async function setPoint(which, lat, lng, label) {
    const address = label || (await M.describePoint(lat, lng));
    state[which] = { lat, lng, address };

    const isPickup = which === 'pickup';
    const marker = isPickup ? pickupMarker : dropoffMarker;
    const icon = M.pinIcon(isPickup ? 'pickup' : 'dropoff', isPickup ? 'A' : 'B');

    if (marker) {
      marker.setLatLng([lat, lng]);
    } else {
      const created = window.L.marker([lat, lng], { icon, draggable: true }).addTo(map);
      created.on('dragend', async () => {
        const pos = created.getLatLng();
        await setPoint(which, pos.lat, pos.lng);
      });
      if (isPickup) pickupMarker = created;
      else dropoffMarker = created;
    }

    $(isPickup ? '#pickupSearch' : '#dropoffSearch').value = address;
    $(isPickup ? '#pickupHint' : '#dropoffHint').textContent =
      `${lat.toFixed(5)}, ${lng.toFixed(5)} — drag the pin to fine-tune.`;

    drawRoute();
    scheduleQuote();
    refreshSummary();
  }

  function drawRoute() {
    if (routeLine) {
      map.removeLayer(routeLine);
      routeLine = null;
    }
    if (!state.pickup || !state.dropoff) return;

    const points = [
      [state.pickup.lat, state.pickup.lng],
      [state.dropoff.lat, state.dropoff.lng],
    ];
    routeLine = window.L.polyline(points, {
      color: '#0b1220',
      weight: 2.5,
      opacity: 0.55,
      dashArray: '7 9',
    }).addTo(map);
    M.fitTo(map, points);
  }

  async function refreshNearby() {
    const centre = map.getCenter();
    try {
      const data = await H.api.get(
        `/api/operators/nearby?lat=${centre.lat}&lng=${centre.lng}&radiusKm=20&vehicleClass=${
          selectedVehicle()?.id || ''
        }`
      );
      swarm.update(data.vehicles, (cls) => H.vehicleIcon(cls));
      $('#nearbyText').textContent = data.count
        ? `${data.count} nearby · closest ~${H.duration(data.nearestMinutes)}`
        : 'None on duty here';
      $('#nearbyBadge').className = data.count ? 'badge badge-green' : 'badge';
    } catch {
      $('#nearbyText').textContent = '—';
    }
  }

  /* ------------------------------------------------------------------ */
  /* Pricing                                                             */
  /* ------------------------------------------------------------------ */

  function scheduleQuote() {
    clearTimeout(quoteTimer);
    quoteTimer = setTimeout(fetchQuote, 250);
  }

  async function fetchQuote() {
    if (!state.pickup || !state.dropoff) {
      $('#priceGuide').innerHTML =
        '<p class="muted small" style="margin:0">Set both points to see a suggested price.</p>';
      return;
    }

    try {
      state.quote = await H.api.post('/api/quote', {
        vehicleClass: selectedVehicle().id,
        pickupLat: state.pickup.lat,
        pickupLng: state.pickup.lng,
        dropoffLat: state.dropoff.lat,
        dropoffLng: state.dropoff.lng,
        helpersRequired: Number($('#helpersRequired').value || 0),
        pickupFloor: Number($('#pickupFloor').value || 0),
        dropoffFloor: Number($('#dropoffFloor').value || 0),
        pickupHasLift: $('#pickupHasLift').checked,
        dropoffHasLift: $('#dropoffHasLift').checked,
      });
    } catch (err) {
      $('#priceGuide').innerHTML = `<p class="small muted" style="margin:0">${H.esc(err.message)}</p>`;
      return;
    }

    renderQuote();
    refreshSummary();
  }

  function renderQuote() {
    const quote = state.quote;
    if (!quote) return;
    const b = quote.breakdown;

    const rows = [
      ['Base fare', b.baseFare],
      [`Distance · ${quote.distanceKm} km`, b.distanceFare],
      b.helperFee > 0 && ['Helpers', b.helperFee],
      b.stairFee > 0 && ['Stairs, no lift', b.stairFee],
    ].filter(Boolean);

    $('#priceGuide').innerHTML = `
      <dl class="kv">
        ${rows.map(([label, amount]) => `<dt>${H.esc(label)}</dt><dd>${H.money(amount)}</dd>`).join('')}
      </dl>
      <div class="divider"></div>
      <div class="row-between">
        <div>
          <div class="bold">Suggested</div>
          <div class="muted tiny">about ${H.duration(quote.driveMinutes)} on the road</div>
        </div>
        <span class="price">${H.money(quote.recommended)}</span>
      </div>`;

    $('#rangeLow').textContent = H.money(quote.min);
    $('#rangeHigh').textContent = H.money(quote.max);
    $('#rangeMid').textContent = `Suggested ${H.money(quote.recommended)}`;
    $('#distanceBadge').textContent = `${quote.distanceKm} km`;

    if (!state.priceTouched) {
      $('#offerPrice').value = String(quote.recommended);
      syncSliderFromPrice();
    }
    updateOfferFeedback();
  }

  const sliderToPrice = (value) => {
    const { min, max } = state.quote;
    return Math.round(min + ((max - min) * value) / 100);
  };

  function syncSliderFromPrice() {
    if (!state.quote) return;
    const { min, max } = state.quote;
    const price = Number($('#offerPrice').value || 0);
    const pct = max > min ? ((price - min) / (max - min)) * 100 : 50;
    $('#offerSlider').value = String(Math.max(0, Math.min(100, pct)));
  }

  function updateOfferFeedback() {
    const feedback = $('#offerFeedback');
    if (!state.quote) {
      feedback.textContent = '';
      return;
    }
    const price = Number($('#offerPrice').value || 0);
    const { min, recommended, max } = state.quote;

    if (!price) {
      feedback.textContent = '';
    } else if (price < min * 0.9) {
      feedback.innerHTML =
        '<span style="color:var(--red)">Well below the going rate — you may get no offers at all.</span>';
    } else if (price < recommended) {
      feedback.innerHTML =
        '<span style="color:var(--amber)">Below suggested. Expect a slower response or counter-offers.</span>';
    } else if (price <= max) {
      feedback.innerHTML =
        '<span style="color:var(--green)">In the sweet spot — operators usually take these quickly.</span>';
    } else {
      feedback.innerHTML =
        '<span style="color:var(--green)">Generous. You should get offers almost immediately.</span>';
    }
  }

  /* ------------------------------------------------------------------ */
  /* Summary panel                                                       */
  /* ------------------------------------------------------------------ */

  function refreshSummary() {
    const vehicle = selectedVehicle();
    const helpers = Number($('#helpersRequired').value || 0);
    const meta = H.getMeta();
    const category = meta.categoryById[$('#category').value];

    const rows = [
      ['Job type', category ? category.name : '—'],
      ['Vehicle', vehicle ? `${vehicle.icon} ${vehicle.name}` : '—'],
      ['Helpers', helpers || 'None'],
      ['Distance', state.quote ? `${state.quote.distanceKm} km` : '—'],
      ['Drive time', state.quote ? H.duration(state.quote.driveMinutes) : '—'],
      ['Your offer', $('#offerPrice').value ? H.money(Number($('#offerPrice').value)) : '—'],
    ];

    $('#summary').innerHTML = rows
      .map(([label, value]) => `<dt>${H.esc(label)}</dt><dd>${H.esc(value)}</dd>`)
      .join('');
  }

  /* ------------------------------------------------------------------ */
  /* Events                                                              */
  /* ------------------------------------------------------------------ */

  function wireEvents() {
    $('#setPickupMode').addEventListener('click', () => setPlacing('pickup'));
    $('#setDropoffMode').addEventListener('click', () => setPlacing('dropoff'));

    $('#useMyLocation').addEventListener('click', async (event) => {
      await H.withBusy(event.currentTarget, async () => {
        try {
          const fix = await M.locateOnce();
          await setPoint('pickup', fix.lat, fix.lng);
          map.setView([fix.lat, fix.lng], 15);
          setPlacing('dropoff');
        } catch (err) {
          H.toast(err.message, 'red');
        }
      });
    });

    $('#swapPoints').addEventListener('click', async () => {
      if (!state.pickup || !state.dropoff) return;
      const [a, b] = [state.pickup, state.dropoff];
      await setPoint('pickup', b.lat, b.lng, b.address);
      await setPoint('dropoff', a.lat, a.lng, a.address);
    });

    for (const radio of document.querySelectorAll('input[name="vehicleClass"]')) {
      radio.addEventListener('change', () => {
        syncVehicleConstraints();
        state.priceTouched = false;
        scheduleQuote();
        refreshNearby();
        refreshSummary();
      });
    }

    // Anything that changes the price should re-quote.
    for (const id of [
      '#helpersRequired',
      '#pickupFloor',
      '#dropoffFloor',
      '#pickupHasLift',
      '#dropoffHasLift',
    ]) {
      $(id).addEventListener('change', () => {
        state.priceTouched = false;
        scheduleQuote();
        refreshSummary();
      });
    }

    $('#category').addEventListener('change', () => {
      // Nudge the vehicle towards what this category usually needs.
      const suggested = H.getMeta().categoryById[$('#category').value]?.suggests;
      const radio = document.querySelector(`input[name="vehicleClass"][value="${suggested}"]`);
      if (radio && !radio.checked) {
        radio.checked = true;
        syncVehicleConstraints();
        state.priceTouched = false;
        scheduleQuote();
        refreshNearby();
      }
      refreshSummary();
    });

    $('#offerPrice').addEventListener('input', () => {
      state.priceTouched = true;
      syncSliderFromPrice();
      updateOfferFeedback();
      refreshSummary();
    });

    $('#offerSlider').addEventListener('input', () => {
      if (!state.quote) return;
      state.priceTouched = true;
      $('#offerPrice').value = String(sliderToPrice(Number($('#offerSlider').value)));
      updateOfferFeedback();
      refreshSummary();
    });

    $('#submitBtn').addEventListener('click', submit);

    setPlacing('pickup');
  }

  function showAlert(message) {
    const box = $('#alert');
    box.textContent = message;
    box.classList.remove('hidden');
    box.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }

  async function submit(event) {
    $('#alert').classList.add('hidden');

    if (!state.pickup) return showAlert('Set a pickup point first.');
    if (!state.dropoff) return showAlert('Set a drop-off point.');

    const description = $('#itemDescription').value.trim();
    if (description.length < 4) {
      return showAlert('Describe what is being moved — operators price on that description.');
    }

    const offerPrice = Number($('#offerPrice').value || 0);
    if (!offerPrice || offerPrice < 1) return showAlert('Enter the price you want to offer.');

    const vehicle = selectedVehicle();
    const weight = Number($('#weightEstimateKg').value || 0);
    if (weight > vehicle.capacityKg) {
      return showAlert(
        `${weight} kg is over the ${vehicle.name.toLowerCase()} limit of ${vehicle.capacityKg} kg. Choose a bigger vehicle.`
      );
    }

    const scheduledLocal = $('#scheduledAt').value;

    const payload = {
      category: $('#category').value,
      vehicleClass: vehicle.id,
      pickupAddress: state.pickup.address,
      pickupLat: state.pickup.lat,
      pickupLng: state.pickup.lng,
      pickupContact: $('#pickupContact').value.trim() || undefined,
      pickupFloor: Number($('#pickupFloor').value || 0),
      pickupHasLift: $('#pickupHasLift').checked,
      dropoffAddress: state.dropoff.address,
      dropoffLat: state.dropoff.lat,
      dropoffLng: state.dropoff.lng,
      dropoffContact: $('#dropoffContact').value.trim() || undefined,
      dropoffFloor: Number($('#dropoffFloor').value || 0),
      dropoffHasLift: $('#dropoffHasLift').checked,
      itemDescription: description,
      weightEstimateKg: weight,
      helpersRequired: Number($('#helpersRequired').value || 0),
      offerPrice,
      paymentMethod: $('#paymentMethod').value,
      scheduledAt: scheduledLocal ? new Date(scheduledLocal).toISOString() : undefined,
    };

    await H.withBusy(event.currentTarget, async () => {
      try {
        const { trip } = await H.api.post('/api/trips', payload);
        H.toast('Job posted. Operators can see it now.', 'green');
        window.location.href = `/track.html?trip=${trip.id}`;
      } catch (err) {
        showAlert(err.message);
      }
    });
  }
})();
