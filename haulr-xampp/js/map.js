/* Leaflet helpers: pin markers, live vehicle markers, route lines, geocoding. */
/* global L, window, document, fetch, AbortController */

(function () {
  'use strict';

  const { esc } = window.Haulr;

  const TILE_URL = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
  const TILE_ATTRIBUTION = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>';

  // Fallback view when we have no position at all yet.
  const DEFAULT_CENTRE = [-26.2041, 28.0473];
  const DEFAULT_ZOOM = 12;

  function createMap(elementId, options = {}) {
    const map = L.map(elementId, {
      center: options.center || DEFAULT_CENTRE,
      zoom: options.zoom || DEFAULT_ZOOM,
      zoomControl: options.zoomControl !== false,
      scrollWheelZoom: options.scrollWheelZoom !== false,
      attributionControl: true,
    });
    L.tileLayer(TILE_URL, { attribution: TILE_ATTRIBUTION, maxZoom: 19 }).addTo(map);
    return map;
  }

  function pinIcon(kind, glyph) {
    return L.divIcon({
      className: '',
      html: `<div class="pin pin-${kind}"><span>${glyph}</span></div>`,
      iconSize: [30, 30],
      iconAnchor: [15, 30],
      popupAnchor: [0, -28],
    });
  }

  function vehicleIcon(glyph, { live = false, ghost = false } = {}) {
    if (ghost) {
      return L.divIcon({
        className: '',
        html: `<div class="vehicle-ghost">${glyph}</div>`,
        iconSize: [26, 26],
        iconAnchor: [13, 13],
      });
    }
    return L.divIcon({
      className: '',
      html: `<div class="vehicle-marker ${live ? 'vehicle-marker-live' : ''}">${glyph}</div>`,
      iconSize: [32, 32],
      iconAnchor: [16, 16],
      popupAnchor: [0, -18],
    });
  }

  /** Fit the view to everything we care about, with sane padding. */
  function fitTo(map, latLngs, { padding = [40, 40], maxZoom = 16 } = {}) {
    const points = latLngs.filter((p) => p && Number.isFinite(p[0]) && Number.isFinite(p[1]));
    if (points.length === 0) return;
    if (points.length === 1) {
      map.setView(points[0], Math.min(15, maxZoom));
      return;
    }
    map.fitBounds(L.latLngBounds(points), { padding, maxZoom });
  }

  /**
   * Draws (and keeps updated) the pickup pin, drop-off pin and the dashed
   * line between them. Returns a handle for later updates.
   */
  function routeLayer(map, trip) {
    const pickup = [trip.pickup.lat, trip.pickup.lng];
    const dropoff = [trip.dropoff.lat, trip.dropoff.lng];

    const pickupMarker = L.marker(pickup, { icon: pinIcon('pickup', 'A') })
      .addTo(map)
      .bindPopup(`<strong>Pickup</strong><br>${esc(trip.pickup.address)}`);
    const dropoffMarker = L.marker(dropoff, { icon: pinIcon('dropoff', 'B') })
      .addTo(map)
      .bindPopup(`<strong>Drop-off</strong><br>${esc(trip.dropoff.address)}`);

    const line = L.polyline([pickup, dropoff], {
      color: '#8b96ab',
      weight: 2.5,
      opacity: 0.7,
      dashArray: '7 9',
    }).addTo(map);

    return {
      pickupMarker,
      dropoffMarker,
      line,
      bounds: [pickup, dropoff],
      remove() {
        map.removeLayer(pickupMarker);
        map.removeLayer(dropoffMarker);
        map.removeLayer(line);
      },
    };
  }

  /**
   * A single moving vehicle. `move()` animates the marker to the new fix and
   * extends the travelled-path polyline behind it.
   */
  function liveVehicle(map, { lat, lng, glyph = '🚚', trail = [] }) {
    const marker = L.marker([lat, lng], {
      icon: vehicleIcon(glyph, { live: true }),
      zIndexOffset: 1000,
    }).addTo(map);

    const path = L.polyline(trail.length ? trail : [[lat, lng]], {
      color: '#ff5a1f',
      weight: 4,
      opacity: 0.85,
      lineJoin: 'round',
      lineCap: 'round',
    }).addTo(map);

    return {
      marker,
      path,
      move(nextLat, nextLng) {
        marker.setLatLng([nextLat, nextLng]);
        path.addLatLng([nextLat, nextLng]);
      },
      latLng() {
        return marker.getLatLng();
      },
      remove() {
        map.removeLayer(marker);
        map.removeLayer(path);
      },
    };
  }

  /**
   * The anonymised "vehicles near you" swarm on the booking map. Reconciles
   * an incoming list against what is already drawn so markers glide instead
   * of flickering.
   */
  function vehicleSwarm(map) {
    const markers = new Map();

    return {
      update(vehicles, iconFor) {
        const seen = new Set();
        for (const vehicle of vehicles) {
          seen.add(vehicle.key);
          const existing = markers.get(vehicle.key);
          if (existing) {
            existing.setLatLng([vehicle.lat, vehicle.lng]);
          } else {
            markers.set(
              vehicle.key,
              L.marker([vehicle.lat, vehicle.lng], {
                icon: vehicleIcon(iconFor(vehicle.vehicleClass), { ghost: true }),
                interactive: false,
                zIndexOffset: -200,
              }).addTo(map)
            );
          }
        }
        for (const [key, marker] of markers) {
          if (!seen.has(key)) {
            map.removeLayer(marker);
            markers.delete(key);
          }
        }
      },
      clear() {
        for (const marker of markers.values()) map.removeLayer(marker);
        markers.clear();
      },
    };
  }

  /* ------------------------------------------------------------------ */
  /* Geocoding (OpenStreetMap Nominatim)                                 */
  /* ------------------------------------------------------------------ */

  let searchController = null;

  /** Forward geocode. Returns `[{label, lat, lng}]`, or [] if unavailable. */
  async function searchAddress(query, { limit = 6, near = null } = {}) {
    if (!query || query.trim().length < 3) return [];
    searchController?.abort();
    searchController = new AbortController();

    const params = new URLSearchParams({
      q: query,
      format: 'jsonv2',
      addressdetails: '0',
      limit: String(limit),
    });
    // Bias results towards the map's current area so "Main Road" resolves locally.
    if (near) {
      const [lat, lng] = near;
      const d = 0.6;
      params.set('viewbox', `${lng - d},${lat + d},${lng + d},${lat - d}`);
      params.set('bounded', '0');
    }

    try {
      const response = await fetch(`https://nominatim.openstreetmap.org/search?${params}`, {
        signal: searchController.signal,
        headers: { Accept: 'application/json' },
      });
      if (!response.ok) return [];
      const results = await response.json();
      return results.map((r) => ({
        label: r.display_name,
        lat: Number(r.lat),
        lng: Number(r.lon),
      }));
    } catch {
      // Offline, blocked, or aborted — the pin-drop flow still works.
      return [];
    }
  }

  /** Reverse geocode a dropped pin into a street address. */
  async function describePoint(lat, lng) {
    const params = new URLSearchParams({
      lat: String(lat),
      lon: String(lng),
      format: 'jsonv2',
      zoom: '18',
    });
    try {
      const response = await fetch(`https://nominatim.openstreetmap.org/reverse?${params}`, {
        headers: { Accept: 'application/json' },
      });
      if (!response.ok) throw new Error('reverse failed');
      const data = await response.json();
      if (data?.display_name) return data.display_name;
    } catch {
      /* fall through to coordinates */
    }
    return `Pinned location (${lat.toFixed(5)}, ${lng.toFixed(5)})`;
  }

  /**
   * Wires a text input to address search with a dropdown of suggestions.
   * `onPick({label, lat, lng})` fires when a suggestion is chosen.
   */
  function attachAddressSearch(input, { onPick, near = () => null }) {
    const wrap = input.closest('.ac-wrap');
    if (!wrap) return;

    let list = null;
    let timer = null;

    const closeList = () => {
      list?.remove();
      list = null;
    };

    input.addEventListener('input', () => {
      clearTimeout(timer);
      const query = input.value.trim();
      if (query.length < 3) return closeList();
      // Debounce: Nominatim asks for at most one request per second.
      timer = setTimeout(async () => {
        const results = await searchAddress(query, { near: near() });
        closeList();
        if (!results.length) return;

        list = document.createElement('div');
        list.className = 'ac-list';
        for (const result of results) {
          const item = document.createElement('div');
          item.className = 'ac-item';
          item.textContent = result.label;
          item.addEventListener('mousedown', (e) => {
            e.preventDefault();
            input.value = result.label;
            closeList();
            onPick(result);
          });
          list.append(item);
        }
        wrap.append(list);
      }, 450);
    });

    input.addEventListener('blur', () => setTimeout(closeList, 150));
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') closeList();
    });
  }

  /* ------------------------------------------------------------------ */
  /* Geolocation                                                         */
  /* ------------------------------------------------------------------ */

  const readFix = (position) => ({
    lat: position.coords.latitude,
    lng: position.coords.longitude,
    accuracyM: position.coords.accuracy,
    heading: position.coords.heading,
    speedKph: position.coords.speed != null ? position.coords.speed * 3.6 : null,
  });

  function getPosition(options) {
    return new Promise((resolve, reject) => {
      navigator.geolocation.getCurrentPosition(
        (position) => resolve(readFix(position)),
        (error) => reject(geolocationError(error)),
        options
      );
    });
  }

  /**
   * One-shot position fix.
   *
   * Asks for a high-accuracy GPS fix first, then falls back to a coarse
   * network fix (and an older cached one) if that fails for any reason other
   * than a refused permission. Indoors — a warehouse, a basement parking
   * garage — the high-accuracy attempt fails routinely, and a driver should
   * still be able to go on duty.
   */
  async function locateOnce(options = {}) {
    if (!navigator.geolocation) throw unsupportedError();

    try {
      return await getPosition({
        enableHighAccuracy: true,
        timeout: 12000,
        maximumAge: 30000,
        ...options,
      });
    } catch (err) {
      if (err.fatal) throw err;
      return getPosition({
        enableHighAccuracy: false,
        timeout: 15000,
        maximumAge: 300000,
        ...options,
      });
    }
  }

  /**
   * Continuous position feed. Returns a `stop()` function.
   *
   * `onError` receives errors flagged `fatal` (the user refused permission, or
   * the browser has no geolocation at all) versus transient ones. A moving
   * vehicle loses its fix routinely — tunnels, parking basements, tall
   * buildings — and those must NOT tear the watch down, because the browser
   * recovers on its own and delivers the next fix to the same watch.
   */
  function watchPosition(onFix, onError) {
    if (!navigator.geolocation) {
      onError?.(unsupportedError());
      return () => {};
    }
    const id = navigator.geolocation.watchPosition(
      (position) => onFix(readFix(position)),
      (error) => onError?.(geolocationError(error)),
      { enableHighAccuracy: true, timeout: 20000, maximumAge: 5000 }
    );
    return () => navigator.geolocation.clearWatch(id);
  }

  function unsupportedError() {
    const err = new Error('This browser cannot share your location.');
    err.fatal = true;
    return err;
  }

  function geolocationError(error) {
    const messages = {
      1: 'Location permission was denied. Enable it in your browser settings to use tracking.',
      2: 'No GPS signal right now — trying again.',
      3: 'Waiting for a GPS fix…',
    };
    const err = new Error(messages[error.code] || 'Could not read your location.');
    err.code = error.code;
    // Only a refused permission is worth giving up on; everything else clears.
    err.fatal = error.code === 1;
    return err;
  }

  window.HaulrMap = {
    createMap,
    pinIcon,
    vehicleIcon,
    fitTo,
    routeLayer,
    liveVehicle,
    vehicleSwarm,
    searchAddress,
    describePoint,
    attachAddressSearch,
    locateOnce,
    watchPosition,
    DEFAULT_CENTRE,
  };
})();
