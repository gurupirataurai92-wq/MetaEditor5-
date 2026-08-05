'use strict';

const express = require('express');
const { get, all, run } = require('../db');
const V = require('../validate');
const S = require('../serialize');
const rt = require('../realtime');
const { TRACKABLE_STATUSES, haversineKm, etaMinutes } = require('../domain');
const { requireAuth, requireRole } = require('../auth');
const { loadTrip } = require('./trips.routes');

const router = express.Router();

// A phone emits GPS several times a second. Broadcast every ping so the map
// stays smooth, but only persist a breadcrumb when the vehicle has actually
// moved or enough time has passed — otherwise a two-hour job writes 20k rows.
const MIN_BREADCRUMB_METRES = 25;
const MIN_BREADCRUMB_MS = 15_000;

/** Where is this trip heading right now? */
function nextWaypoint(trip) {
  const beforePickup = ['accepted', 'en_route_pickup', 'at_pickup'].includes(trip.status);
  return beforePickup
    ? { label: 'pickup', lat: trip.pickup_lat, lng: trip.pickup_lng, address: trip.pickup_address }
    : { label: 'dropoff', lat: trip.dropoff_lat, lng: trip.dropoff_lng, address: trip.dropoff_address };
}

/**
 * POST /api/trips/:id/location
 * The operator's device pushes its GPS fix here (or over the WebSocket).
 * Everything watching the job gets it in real time.
 */
router.post('/trips/:id/location', requireRole('operator'), loadTrip, (req, res, next) => {
  try {
    const trip = req.trip;
    if (trip.operator_id !== req.user.id) {
      return res.status(403).json({ error: 'This job is not yours.' });
    }
    if (!TRACKABLE_STATUSES.includes(trip.status)) {
      return res.status(409).json({ error: 'Tracking is not active for this job.' });
    }

    const lat = V.latitude(req.body?.lat);
    const lng = V.longitude(req.body?.lng);
    const heading = req.body?.heading != null ? V.num(req.body.heading, 'Heading', { min: 0, max: 360 }) : null;
    const speedKph = req.body?.speedKph != null ? V.num(req.body.speedKph, 'Speed', { min: 0, max: 300 }) : null;
    const accuracyM = req.body?.accuracyM != null ? V.num(req.body.accuracyM, 'Accuracy', { min: 0, max: 10000 }) : null;

    const last = get(
      'SELECT lat, lng, recorded_at FROM trip_locations WHERE trip_id = ? ORDER BY id DESC LIMIT 1',
      trip.id
    );

    let stored = false;
    if (!last) {
      stored = true;
    } else {
      const movedM = haversineKm(last.lat, last.lng, lat, lng) * 1000;
      const agedMs = Date.now() - new Date(`${last.recorded_at}Z`).getTime();
      stored = movedM >= MIN_BREADCRUMB_METRES || agedMs >= MIN_BREADCRUMB_MS;
    }

    if (stored) {
      run(
        `INSERT INTO trip_locations (trip_id, operator_id, lat, lng, heading, speed_kph, accuracy_m)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        trip.id,
        req.user.id,
        lat,
        lng,
        heading,
        speedKph,
        accuracyM
      );
    }

    // Keep the operator's "last known position" fresh for dispatch and for
    // the nearby-vehicles map.
    run(
      `UPDATE operator_profiles
          SET last_lat = ?, last_lng = ?, last_heading = COALESCE(?, last_heading),
              last_seen_at = datetime('now')
        WHERE user_id = ?`,
      lat,
      lng,
      heading,
      req.user.id
    );

    const waypoint = nextWaypoint(trip);
    const remainingKm = Number((haversineKm(lat, lng, waypoint.lat, waypoint.lng) * 1.35).toFixed(2));
    const eta = etaMinutes(remainingKm, speedKph && speedKph > 8 ? Math.min(speedKph, 80) : 32);

    const update = {
      type: 'location_update',
      tripId: trip.id,
      position: { lat, lng, heading, speedKph, accuracyM, recordedAt: new Date().toISOString() },
      heading_to: waypoint.label,
      remainingKm,
      etaMinutes: eta,
      etaAt: new Date(Date.now() + eta * 60_000).toISOString(),
    };

    rt.toTrip(trip.id, update);
    rt.toUser(trip.customer_id, update);

    res.json({ ok: true, stored, remainingKm, etaMinutes: eta });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/trips/:id/track
 * Everything the tracking screen needs in one call: the job, the operator's
 * current fix, the breadcrumb trail so far, and a live ETA.
 */
router.get('/trips/:id/track', requireAuth, loadTrip, (req, res) => {
  const trip = req.trip;
  const isParty =
    trip.customer_id === req.user.id || trip.operator_id === req.user.id || req.user.role === 'manager';
  if (!isParty) return res.status(403).json({ error: 'This job is not yours.' });

  const trail = all(
    `SELECT lat, lng, heading, speed_kph, accuracy_m, recorded_at
       FROM trip_locations WHERE trip_id = ? ORDER BY id ASC LIMIT 2000`,
    trip.id
  ).map(S.location);

  const current = trail.length ? trail[trail.length - 1] : null;
  const waypoint = nextWaypoint(trip);

  let remainingKm = null;
  let eta = null;
  if (current && TRACKABLE_STATUSES.includes(trip.status)) {
    remainingKm = Number((haversineKm(current.lat, current.lng, waypoint.lat, waypoint.lng) * 1.35).toFixed(2));
    eta = etaMinutes(remainingKm);
  }

  res.json({
    trip: S.trip(trip, { viewerId: req.user.id }),
    current,
    trail,
    headingTo: waypoint,
    remainingKm,
    etaMinutes: eta,
    etaAt: eta != null ? new Date(Date.now() + eta * 60_000).toISOString() : null,
    events: all('SELECT * FROM trip_events WHERE trip_id = ? ORDER BY id ASC', trip.id).map(S.event),
  });
});

module.exports = router;
