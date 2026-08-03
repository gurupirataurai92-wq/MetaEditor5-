'use strict';

const express = require('express');
const { get, all, run } = require('../db');
const V = require('../validate');
const S = require('../serialize');
const rt = require('../realtime');
const config = require('../config');
const {
  VEHICLE_CLASSES,
  vehicleById,
  haversineKm,
  etaMinutes,
  priceGuide,
} = require('../domain');
const { requireAuth, requireRole } = require('../auth');
const { operatorProfile } = require('./auth.routes');

const router = express.Router();

function profileOrFail(userId, res) {
  const profile = get('SELECT * FROM operator_profiles WHERE user_id = ?', userId);
  if (!profile) {
    res.status(400).json({ error: 'Your operator profile is incomplete.' });
    return null;
  }
  return profile;
}

/**
 * POST /api/operator/status
 * Go on/off duty. Going online with a position immediately puts the operator
 * on the customer-facing "vehicles near you" map.
 */
router.post('/operator/status', requireRole('operator'), (req, res, next) => {
  try {
    const isOnline = V.bool(req.body?.isOnline);
    const lat = req.body?.lat != null ? V.latitude(req.body.lat) : null;
    const lng = req.body?.lng != null ? V.longitude(req.body.lng) : null;
    const heading = req.body?.heading != null ? V.num(req.body.heading, 'Heading', { min: 0, max: 360 }) : null;

    if (isOnline && (lat == null || lng == null)) {
      return res
        .status(400)
        .json({ error: 'Share your location before going online — jobs are matched by distance.' });
    }

    run(
      `UPDATE operator_profiles
          SET is_online = ?,
              last_lat = COALESCE(?, last_lat),
              last_lng = COALESCE(?, last_lng),
              last_heading = COALESCE(?, last_heading),
              last_seen_at = datetime('now')
        WHERE user_id = ?`,
      isOnline ? 1 : 0,
      lat,
      lng,
      heading,
      req.user.id
    );

    res.json({ operatorProfile: operatorProfile(req.user.id) });
  } catch (err) {
    next(err);
  }
});

/** PATCH /api/operator/profile — vehicle and bio details. */
router.patch('/operator/profile', requireRole('operator'), (req, res, next) => {
  try {
    const b = req.body || {};
    const vehicleClass = b.vehicleClass
      ? V.oneOf(b.vehicleClass, 'Vehicle type', VEHICLE_CLASSES.map((v) => v.id))
      : null;

    run(
      `UPDATE operator_profiles
          SET vehicle_class     = COALESCE(?, vehicle_class),
              vehicle_make      = COALESCE(?, vehicle_make),
              vehicle_model     = COALESCE(?, vehicle_model),
              vehicle_plate     = COALESCE(?, vehicle_plate),
              capacity_kg       = COALESCE(?, capacity_kg),
              helpers_available = COALESCE(?, helpers_available),
              has_tail_lift     = COALESCE(?, has_tail_lift),
              bio               = COALESCE(?, bio)
        WHERE user_id = ?`,
      vehicleClass,
      V.str(b.vehicleMake, 'Vehicle make', { max: 60, required: false }),
      V.str(b.vehicleModel, 'Vehicle model', { max: 60, required: false }),
      V.str(b.vehiclePlate, 'Number plate', { min: 2, max: 16, required: false }),
      V.num(b.capacityKg, 'Capacity', { min: 1, max: 40000, required: false, integer: true }),
      V.num(b.helpersAvailable, 'Helpers', { min: 0, max: 6, required: false, integer: true }),
      b.hasTailLift === undefined ? null : V.bool(b.hasTailLift) ? 1 : 0,
      V.str(b.bio, 'About you', { max: 400, required: false }),
      req.user.id
    );

    res.json({ operatorProfile: operatorProfile(req.user.id) });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/operator/board
 * The open-jobs board: everything still up for grabs that this operator's
 * vehicle can actually handle, nearest first.
 */
router.get('/operator/board', requireRole('operator'), (req, res, next) => {
  try {
    const profile = profileOrFail(req.user.id, res);
    if (!profile) return;

    const lat = req.query.lat != null ? V.latitude(req.query.lat) : profile.last_lat;
    const lng = req.query.lng != null ? V.longitude(req.query.lng) : profile.last_lng;
    const radiusKm = V.num(req.query.radiusKm ?? config.dispatchRadiusKm, 'Radius', {
      min: 1,
      max: 500,
    });

    const mine = vehicleById.get(profile.vehicle_class);
    const eligibleClasses = VEHICLE_CLASSES.filter(
      (v) => mine && v.capacityKg <= mine.capacityKg
    ).map((v) => v.id);

    if (eligibleClasses.length === 0) return res.json({ jobs: [] });

    const placeholders = eligibleClasses.map(() => '?').join(',');
    const rows = all(
      `SELECT t.*,
              (SELECT COUNT(*) FROM offers o WHERE o.trip_id = t.id AND o.status = 'pending') AS offer_count,
              (SELECT MIN(o.price) FROM offers o WHERE o.trip_id = t.id AND o.status = 'pending') AS best_offer,
              (SELECT o.id FROM offers o WHERE o.trip_id = t.id AND o.operator_id = ?) AS my_offer_id,
              (SELECT o.price FROM offers o WHERE o.trip_id = t.id AND o.operator_id = ?) AS my_offer_price
         FROM trips t
        WHERE t.status = 'requested'
          AND t.customer_id != ?
          AND t.vehicle_class IN (${placeholders})
          AND t.helpers_required <= ?
        ORDER BY t.created_at DESC
        LIMIT 100`,
      req.user.id,
      req.user.id,
      req.user.id,
      ...eligibleClasses,
      mine.maxHelpers
    );

    const jobs = rows
      .map((row) => {
        const job = S.trip(row, { viewerId: null });
        job.myOfferId = row.my_offer_id;
        job.myOfferPrice = row.my_offer_price;
        job.guide = priceGuide({
          vehicleClass: row.vehicle_class,
          distanceKm: row.distance_km,
          helpers: row.helpers_required,
          pickupFloor: row.pickup_floor,
          dropoffFloor: row.dropoff_floor,
          pickupHasLift: Boolean(row.pickup_has_lift),
          dropoffHasLift: Boolean(row.dropoff_has_lift),
        });
        if (lat != null && lng != null) {
          job.distanceToPickupKm = Number(
            (haversineKm(lat, lng, row.pickup_lat, row.pickup_lng) * 1.35).toFixed(2)
          );
          job.minutesToPickup = etaMinutes(job.distanceToPickupKm);
        }
        return job;
      })
      .filter((job) => job.distanceToPickupKm == null || job.distanceToPickupKm <= radiusKm)
      .sort((a, b) => (a.distanceToPickupKm ?? 1e9) - (b.distanceToPickupKm ?? 1e9));

    res.json({ jobs, radiusKm, origin: lat != null ? { lat, lng } : null });
  } catch (err) {
    next(err);
  }
});

/** GET /api/operator/stats — earnings and volume summary for the dashboard. */
router.get('/operator/stats', requireRole('operator'), (req, res) => {
  const totals = get(
    `SELECT COUNT(*) AS jobs,
            COALESCE(SUM(agreed_price), 0) AS earnings
       FROM trips
      WHERE operator_id = ? AND status = 'completed'`,
    req.user.id
  );
  const week = get(
    `SELECT COUNT(*) AS jobs,
            COALESCE(SUM(agreed_price), 0) AS earnings
       FROM trips
      WHERE operator_id = ? AND status = 'completed'
        AND closed_at >= datetime('now', '-7 days')`,
    req.user.id
  );
  const active = get(
    `SELECT COUNT(*) AS n FROM trips
      WHERE operator_id = ? AND status IN ('accepted','en_route_pickup','at_pickup','in_transit')`,
    req.user.id
  ).n;
  const pendingOffers = get(
    "SELECT COUNT(*) AS n FROM offers WHERE operator_id = ? AND status = 'pending'",
    req.user.id
  ).n;

  const me = get('SELECT rating_sum, rating_count FROM users WHERE id = ?', req.user.id);

  res.json({
    allTime: { jobs: totals.jobs, earnings: totals.earnings },
    last7Days: { jobs: week.jobs, earnings: week.earnings },
    activeJobs: active,
    pendingOffers,
    rating: S.ratingOf(me.rating_sum, me.rating_count),
    ratingCount: me.rating_count,
  });
});

/**
 * GET /api/public/activity
 * Marketing-page feed: how many vehicles are on duty, and roughly where.
 *
 * Positions are snapped to a ~1.1 km grid and de-duplicated before they leave
 * the server, so a signed-out visitor can see that the service is busy without
 * being able to follow an individual operator around.
 */
router.get('/public/activity', (_req, res) => {
  const staleCutoff = new Date(Date.now() - config.operatorStaleAfterMs)
    .toISOString()
    .replace('T', ' ')
    .slice(0, 19);

  const rows = all(
    `SELECT vehicle_class, last_lat, last_lng
       FROM operator_profiles
      WHERE is_online = 1 AND last_lat IS NOT NULL AND last_seen_at >= ?
      LIMIT 500`,
    staleCutoff
  );

  const GRID = 0.01; // ≈1.1 km
  const cells = new Map();
  for (const row of rows) {
    const lat = Math.round(row.last_lat / GRID) * GRID;
    const lng = Math.round(row.last_lng / GRID) * GRID;
    const key = `${lat.toFixed(2)},${lng.toFixed(2)}`;
    if (!cells.has(key)) {
      cells.set(key, { key, lat, lng, vehicleClass: row.vehicle_class, count: 0 });
    }
    cells.get(key).count += 1;
  }

  const centre = rows.length
    ? {
        lat: rows.reduce((sum, r) => sum + r.last_lat, 0) / rows.length,
        lng: rows.reduce((sum, r) => sum + r.last_lng, 0) / rows.length,
      }
    : null;

  res.json({ online: rows.length, centre, cells: [...cells.values()].slice(0, 80) });
});

/**
 * GET /api/operators/nearby?lat=&lng=&radiusKm=
 * Anonymised live vehicle positions for the customer's booking map — the
 * "cars moving around you" view. No identities are exposed.
 */
router.get('/operators/nearby', requireAuth, (req, res, next) => {
  try {
    const lat = V.latitude(req.query.lat);
    const lng = V.longitude(req.query.lng);
    const radiusKm = V.num(req.query.radiusKm ?? 15, 'Radius', { min: 1, max: 200 });
    const vehicleClass = req.query.vehicleClass
      ? V.oneOf(req.query.vehicleClass, 'Vehicle type', VEHICLE_CLASSES.map((v) => v.id))
      : null;

    const staleCutoff = new Date(Date.now() - config.operatorStaleAfterMs)
      .toISOString()
      .replace('T', ' ')
      .slice(0, 19);

    const rows = all(
      `SELECT user_id, vehicle_class, last_lat, last_lng, last_heading, last_seen_at
         FROM operator_profiles
        WHERE is_online = 1
          AND last_lat IS NOT NULL
          AND last_seen_at >= ?
          ${vehicleClass ? 'AND vehicle_class = ?' : ''}
        LIMIT 500`,
      staleCutoff,
      ...(vehicleClass ? [vehicleClass] : [])
    );

    const vehicles = rows
      .map((r) => ({
        // Opaque per-vehicle key so the map can animate markers between polls
        // without revealing which operator is which.
        key: `v${r.user_id}`,
        vehicleClass: r.vehicle_class,
        lat: r.last_lat,
        lng: r.last_lng,
        heading: r.last_heading,
        distanceKm: Number(haversineKm(lat, lng, r.last_lat, r.last_lng).toFixed(2)),
      }))
      .filter((v) => v.distanceKm <= radiusKm)
      .sort((a, b) => a.distanceKm - b.distanceKm)
      .slice(0, 60);

    res.json({
      vehicles: vehicles.map(({ distanceKm, ...v }) => v),
      count: vehicles.length,
      nearestKm: vehicles[0]?.distanceKm ?? null,
      nearestMinutes: vehicles[0] ? etaMinutes(vehicles[0].distanceKm * 1.35) : null,
    });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
