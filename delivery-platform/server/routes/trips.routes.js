'use strict';

const express = require('express');
const { get, all, run, transaction } = require('../db');
const V = require('../validate');
const S = require('../serialize');
const rt = require('../realtime');
const {
  VEHICLE_CLASSES,
  CATEGORIES,
  PAYMENT_METHODS,
  OPERATOR_TRANSITIONS,
  ACTIVE_STATUSES,
  vehicleById,
  roadDistanceKm,
  priceGuide,
  etaMinutes,
  makeReference,
} = require('../domain');
const { requireAuth, requireRole } = require('../auth');

const router = express.Router();

const VEHICLE_IDS = VEHICLE_CLASSES.map((v) => v.id);
const CATEGORY_IDS = CATEGORIES.map((c) => c.id);
const PAYMENT_IDS = PAYMENT_METHODS.map((p) => p.id);

/** Load `:id` into `req.trip`, 404 if missing. */
function loadTrip(req, res, next) {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) return res.status(400).json({ error: 'Invalid job id.' });
  const trip = get('SELECT * FROM trips WHERE id = ?', id);
  if (!trip) return res.status(404).json({ error: 'Job not found.' });
  req.trip = trip;
  next();
}

const isCustomer = (req) => req.trip.customer_id === req.user.id;
const isOperator = (req) => req.trip.operator_id === req.user.id;
const isParty = (req) => isCustomer(req) || isOperator(req) || req.user.role === 'manager';

function requireParty(req, res, next) {
  if (!isParty(req)) return res.status(403).json({ error: 'This job is not yours.' });
  next();
}

function logEvent(tripId, actorId, type, note, lat = null, lng = null) {
  const { lastInsertRowid } = run(
    'INSERT INTO trip_events (trip_id, actor_id, type, note, lat, lng) VALUES (?, ?, ?, ?, ?, ?)',
    tripId,
    actorId,
    type,
    note,
    lat,
    lng
  );
  return Number(lastInsertRowid);
}

/** Re-read a trip and push it to everyone watching, plus both parties' feeds. */
function broadcastTrip(tripId, extra = {}) {
  const row = get('SELECT * FROM trips WHERE id = ?', tripId);
  if (!row) return;
  const payload = {
    type: 'trip_update',
    tripId,
    // Serialize from the customer's viewpoint for the trip channel; both
    // parties are entitled to the same contact details once assigned.
    trip: S.trip(row, { viewerId: row.customer_id }),
    ...extra,
  };
  rt.toTrip(tripId, payload);
  rt.toUser(row.customer_id, payload);
  if (row.operator_id) rt.toUser(row.operator_id, payload);
}

/**
 * POST /api/quote
 * Price guidance for a prospective job. Open to signed-in users so the
 * booking form can show a live estimate as the pins move.
 */
router.post('/quote', requireAuth, (req, res, next) => {
  try {
    const b = req.body || {};
    const vehicleClass = V.oneOf(b.vehicleClass, 'Vehicle type', VEHICLE_IDS);
    const pickupLat = V.latitude(b.pickupLat, 'Pickup latitude');
    const pickupLng = V.longitude(b.pickupLng, 'Pickup longitude');
    const dropoffLat = V.latitude(b.dropoffLat, 'Drop-off latitude');
    const dropoffLng = V.longitude(b.dropoffLng, 'Drop-off longitude');

    const distanceKm = roadDistanceKm(pickupLat, pickupLng, dropoffLat, dropoffLng);
    const guide = priceGuide({
      vehicleClass,
      distanceKm,
      helpers: b.helpersRequired,
      pickupFloor: b.pickupFloor,
      dropoffFloor: b.dropoffFloor,
      pickupHasLift: V.bool(b.pickupHasLift),
      dropoffHasLift: V.bool(b.dropoffHasLift),
    });

    res.json({ ...guide, driveMinutes: etaMinutes(distanceKm) });
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/trips
 * Customer posts a job with the price they want to pay. Operators bid on it.
 */
router.post('/trips', requireRole('customer'), (req, res, next) => {
  try {
    const b = req.body || {};

    const category = V.oneOf(b.category, 'Category', CATEGORY_IDS);
    const vehicleClass = V.oneOf(b.vehicleClass, 'Vehicle type', VEHICLE_IDS);
    const spec = vehicleById.get(vehicleClass);

    const pickup = {
      address: V.str(b.pickupAddress, 'Pickup address', { min: 4, max: 300 }),
      lat: V.latitude(b.pickupLat, 'Pickup latitude'),
      lng: V.longitude(b.pickupLng, 'Pickup longitude'),
      contact: V.str(b.pickupContact, 'Pickup contact', { max: 120, required: false }),
      floor: V.num(b.pickupFloor, 'Pickup floor', { min: 0, max: 60, required: false, integer: true }) ?? 0,
      hasLift: V.bool(b.pickupHasLift),
    };
    const dropoff = {
      address: V.str(b.dropoffAddress, 'Drop-off address', { min: 4, max: 300 }),
      lat: V.latitude(b.dropoffLat, 'Drop-off latitude'),
      lng: V.longitude(b.dropoffLng, 'Drop-off longitude'),
      contact: V.str(b.dropoffContact, 'Drop-off contact', { max: 120, required: false }),
      floor: V.num(b.dropoffFloor, 'Drop-off floor', { min: 0, max: 60, required: false, integer: true }) ?? 0,
      hasLift: V.bool(b.dropoffHasLift),
    };

    const itemDescription = V.str(b.itemDescription, 'What are we moving', { min: 4, max: 1000 });
    const weightEstimateKg =
      V.num(b.weightEstimateKg, 'Estimated weight', { min: 0, max: 40000, required: false, integer: true }) ?? 0;
    const helpersRequired =
      V.num(b.helpersRequired, 'Helpers', { min: 0, max: 6, required: false, integer: true }) ?? 0;
    const offerPrice = V.num(b.offerPrice, 'Your offer', { min: 1, max: 1_000_000 });
    const paymentMethod = V.oneOf(b.paymentMethod || 'cash', 'Payment method', PAYMENT_IDS);

    if (helpersRequired > spec.maxHelpers) {
      return res.status(400).json({
        error: `A ${spec.name.toLowerCase()} can bring at most ${spec.maxHelpers} helper(s). Pick a bigger vehicle.`,
      });
    }
    if (weightEstimateKg > spec.capacityKg) {
      return res.status(400).json({
        error: `A ${spec.name.toLowerCase()} carries up to ${spec.capacityKg} kg. Pick a bigger vehicle.`,
      });
    }

    let scheduledAt = null;
    if (b.scheduledAt) {
      const when = new Date(b.scheduledAt);
      if (Number.isNaN(when.getTime())) {
        return res.status(400).json({ error: 'Scheduled time is not a valid date.' });
      }
      if (when.getTime() < Date.now() - 60_000) {
        return res.status(400).json({ error: 'Scheduled time cannot be in the past.' });
      }
      scheduledAt = when.toISOString();
    }

    const openJobs = get(
      `SELECT COUNT(*) AS n FROM trips
        WHERE customer_id = ? AND status IN ('requested','accepted','en_route_pickup','at_pickup','in_transit')`,
      req.user.id
    ).n;
    if (openJobs >= 10) {
      return res
        .status(429)
        .json({ error: 'You already have 10 jobs in flight. Finish or cancel one first.' });
    }

    const distanceKm = roadDistanceKm(pickup.lat, pickup.lng, dropoff.lat, dropoff.lng);

    // References are random, so retry on the (very unlikely) collision.
    let tripId = null;
    for (let attempt = 0; attempt < 5 && tripId === null; attempt += 1) {
      try {
        const { lastInsertRowid } = run(
          `INSERT INTO trips (
             reference, customer_id, category, vehicle_class,
             pickup_address, pickup_lat, pickup_lng, pickup_contact, pickup_floor, pickup_has_lift,
             dropoff_address, dropoff_lat, dropoff_lng, dropoff_contact, dropoff_floor, dropoff_has_lift,
             distance_km, item_description, weight_estimate_kg, helpers_required, scheduled_at,
             customer_offer_price, payment_method
           ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          makeReference(),
          req.user.id,
          category,
          vehicleClass,
          pickup.address, pickup.lat, pickup.lng, pickup.contact, pickup.floor, pickup.hasLift ? 1 : 0,
          dropoff.address, dropoff.lat, dropoff.lng, dropoff.contact, dropoff.floor, dropoff.hasLift ? 1 : 0,
          distanceKm,
          itemDescription,
          weightEstimateKg,
          helpersRequired,
          scheduledAt,
          offerPrice,
          paymentMethod
        );
        tripId = Number(lastInsertRowid);
      } catch (err) {
        if (!String(err.message).includes('UNIQUE') || attempt === 4) throw err;
      }
    }

    logEvent(tripId, req.user.id, 'created', null, pickup.lat, pickup.lng);

    const row = get('SELECT * FROM trips WHERE id = ?', tripId);
    const payload = S.trip(row, { viewerId: req.user.id });

    // Put it on the open board every online operator is watching.
    rt.toDispatch({ type: 'job_posted', trip: S.trip(row, { viewerId: null }) });

    res.status(201).json({ trip: payload });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/trips?scope=active|history|all
 * Customers see the jobs they posted; operators see the jobs assigned to them.
 */
router.get('/trips', requireAuth, (req, res, next) => {
  try {
    const scope = V.oneOf(req.query.scope || 'all', 'Scope', ['active', 'history', 'all']);
    const limit = V.num(req.query.limit ?? 50, 'Limit', { min: 1, max: 200, integer: true });

    const column = req.user.role === 'operator' ? 'operator_id' : 'customer_id';
    const activeList = ACTIVE_STATUSES.map(() => '?').join(',');

    let sql = `
      SELECT t.*,
             (SELECT COUNT(*) FROM offers o WHERE o.trip_id = t.id AND o.status = 'pending') AS offer_count,
             (SELECT MIN(o.price) FROM offers o WHERE o.trip_id = t.id AND o.status = 'pending') AS best_offer
        FROM trips t
       WHERE t.${column} = ?`;
    const params = [req.user.id];

    if (scope === 'active') {
      sql += ` AND t.status IN (${activeList})`;
      params.push(...ACTIVE_STATUSES);
    } else if (scope === 'history') {
      sql += ` AND t.status NOT IN (${activeList})`;
      params.push(...ACTIVE_STATUSES);
    }

    sql += ' ORDER BY t.created_at DESC, t.id DESC LIMIT ?';
    params.push(limit);

    const rows = all(sql, ...params);
    res.json({ trips: rows.map((r) => S.trip(r, { viewerId: req.user.id })) });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/trips/:id
 * Visible to both parties, and to any operator while the job is still open
 * for bidding (contact details stay hidden until assignment).
 */
router.get('/trips/:id', requireAuth, loadTrip, (req, res) => {
  const openToBidders = req.user.role === 'operator' && req.trip.status === 'requested';
  if (!isParty(req) && !openToBidders) {
    return res.status(403).json({ error: 'This job is not yours.' });
  }

  const trip = S.trip(req.trip, { viewerId: req.user.id });
  trip.offerCount = get(
    "SELECT COUNT(*) AS n FROM offers WHERE trip_id = ? AND status = 'pending'",
    req.trip.id
  ).n;

  if (req.user.role === 'operator') {
    trip.myOffer = S.offer(
      get('SELECT * FROM offers WHERE trip_id = ? AND operator_id = ?', req.trip.id, req.user.id)
    );
  }

  res.json({ trip });
});

/**
 * POST /api/trips/:id/status
 * The operator walks the job forward one step at a time.
 */
router.post('/trips/:id/status', requireRole('operator'), loadTrip, (req, res, next) => {
  try {
    if (!isOperator(req)) return res.status(403).json({ error: 'This job is not yours.' });

    const target = V.str(req.body?.status, 'Status');
    const allowed = OPERATOR_TRANSITIONS[req.trip.status] || [];
    if (!allowed.includes(target)) {
      return res.status(409).json({
        error: `Cannot move a job from "${req.trip.status}" to "${target}".`,
        allowed,
      });
    }

    const lat = req.body?.lat != null ? V.latitude(req.body.lat) : null;
    const lng = req.body?.lng != null ? V.longitude(req.body.lng) : null;

    const stamps = {
      in_transit: 'picked_up_at',
      delivered: 'delivered_at',
    };
    const stampColumn = stamps[target];

    run(
      `UPDATE trips
          SET status = ?${stampColumn ? `, ${stampColumn} = datetime('now')` : ''}
        WHERE id = ?`,
      target,
      req.trip.id
    );

    logEvent(req.trip.id, req.user.id, `status:${target}`, null, lat, lng);
    broadcastTrip(req.trip.id, { reason: 'status' });

    res.json({ trip: S.trip(get('SELECT * FROM trips WHERE id = ?', req.trip.id), { viewerId: req.user.id }) });
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/trips/:id/cancel
 * Customers may cancel until the goods are loaded. After that it needs
 * support, because the operator is already carrying the load.
 */
router.post('/trips/:id/cancel', requireAuth, loadTrip, requireParty, (req, res, next) => {
  try {
    if (!isCustomer(req) && req.user.role !== 'manager') {
      return res
        .status(403)
        .json({ error: 'Operators release a job instead of cancelling it.' });
    }

    const cancellable = ['requested', 'accepted', 'en_route_pickup', 'at_pickup'];
    if (!cancellable.includes(req.trip.status)) {
      return res.status(409).json({
        error:
          req.trip.status === 'in_transit'
            ? 'The load is already on the vehicle. Contact support to stop this job.'
            : `A ${req.trip.status} job cannot be cancelled.`,
      });
    }

    const reason = V.str(req.body?.reason, 'Reason', { min: 3, max: 300, required: false });

    transaction(() => {
      run(
        `UPDATE trips
            SET status = 'cancelled', cancel_reason = ?, cancelled_by = ?,
                closed_at = datetime('now')
          WHERE id = ?`,
        reason,
        req.user.role,
        req.trip.id
      );
      run("UPDATE offers SET status = 'rejected' WHERE trip_id = ? AND status = 'pending'", req.trip.id);
    })();

    logEvent(req.trip.id, req.user.id, 'cancelled', reason);
    broadcastTrip(req.trip.id, { reason: 'cancelled' });
    rt.toDispatch({ type: 'job_closed', tripId: req.trip.id });

    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/trips/:id/release
 * The assigned operator drops the job; it goes straight back on the open
 * board so another operator can pick it up.
 */
router.post('/trips/:id/release', requireRole('operator'), loadTrip, (req, res, next) => {
  try {
    if (!isOperator(req)) return res.status(403).json({ error: 'This job is not yours.' });
    if (!['accepted', 'en_route_pickup', 'at_pickup'].includes(req.trip.status)) {
      return res.status(409).json({ error: 'This job can no longer be released.' });
    }

    const reason = V.str(req.body?.reason, 'Reason', { min: 3, max: 300, required: false });

    transaction(() => {
      run(
        `UPDATE trips
            SET status = 'requested', operator_id = NULL, agreed_price = NULL, accepted_at = NULL
          WHERE id = ?`,
        req.trip.id
      );
      run(
        "UPDATE offers SET status = 'withdrawn' WHERE trip_id = ? AND operator_id = ?",
        req.trip.id,
        req.user.id
      );
    })();

    logEvent(req.trip.id, req.user.id, 'released', reason);
    broadcastTrip(req.trip.id, { reason: 'released' });

    const row = get('SELECT * FROM trips WHERE id = ?', req.trip.id);
    rt.toDispatch({ type: 'job_posted', trip: S.trip(row, { viewerId: null }) });

    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/trips/:id/rate
 * Both sides rate each other once the goods are delivered. The customer's
 * rating is what closes the job.
 */
router.post('/trips/:id/rate', requireAuth, loadTrip, requireParty, (req, res, next) => {
  try {
    if (!['delivered', 'completed'].includes(req.trip.status)) {
      return res.status(409).json({ error: 'You can only rate a job once it has been delivered.' });
    }

    const stars = V.num(req.body?.rating, 'Rating', { min: 1, max: 5, integer: true });
    const review = V.str(req.body?.review, 'Review', { max: 600, required: false });

    const customerRating = isCustomer(req);
    const column = customerRating ? 'operator_rating' : 'customer_rating';
    const ratedUserId = customerRating ? req.trip.operator_id : req.trip.customer_id;

    if (req.trip[column] != null) {
      return res.status(409).json({ error: 'You have already rated this job.' });
    }
    if (!ratedUserId) {
      return res.status(409).json({ error: 'There is nobody to rate on this job.' });
    }

    transaction(() => {
      run(
        `UPDATE trips
            SET ${column} = ?${customerRating ? ', customer_review = ?' : ''}
          WHERE id = ?`,
        ...(customerRating ? [stars, review, req.trip.id] : [stars, req.trip.id])
      );

      run(
        'UPDATE users SET rating_sum = rating_sum + ?, rating_count = rating_count + 1 WHERE id = ?',
        stars,
        ratedUserId
      );

      if (customerRating) {
        run(
          "UPDATE trips SET status = 'completed', closed_at = datetime('now') WHERE id = ?",
          req.trip.id
        );
        run(
          'UPDATE operator_profiles SET trips_completed = trips_completed + 1 WHERE user_id = ?',
          req.trip.operator_id
        );
      }
    })();

    logEvent(req.trip.id, req.user.id, 'rated', `${stars}★`);
    broadcastTrip(req.trip.id, { reason: 'rated' });

    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

/** GET /api/trips/:id/events — the job timeline. */
router.get('/trips/:id/events', requireAuth, loadTrip, requireParty, (req, res) => {
  const rows = all('SELECT * FROM trip_events WHERE trip_id = ? ORDER BY id ASC', req.trip.id);
  res.json({ events: rows.map(S.event) });
});

/** GET /api/trips/:id/messages */
router.get('/trips/:id/messages', requireAuth, loadTrip, requireParty, (req, res) => {
  const rows = all(
    `SELECT m.*, u.full_name AS sender_name
       FROM messages m JOIN users u ON u.id = m.sender_id
      WHERE m.trip_id = ? ORDER BY m.id ASC LIMIT 300`,
    req.trip.id
  );
  res.json({ messages: rows.map(S.message) });
});

/** POST /api/trips/:id/messages — in-job chat between customer and operator. */
router.post('/trips/:id/messages', requireAuth, loadTrip, requireParty, (req, res, next) => {
  try {
    if (!req.trip.operator_id) {
      return res.status(409).json({ error: 'Chat opens once an operator is assigned.' });
    }
    const body = V.str(req.body?.body, 'Message', { min: 1, max: 1000 });

    const { lastInsertRowid } = run(
      'INSERT INTO messages (trip_id, sender_id, body) VALUES (?, ?, ?)',
      req.trip.id,
      req.user.id,
      body
    );

    const row = get(
      `SELECT m.*, u.full_name AS sender_name
         FROM messages m JOIN users u ON u.id = m.sender_id
        WHERE m.id = ?`,
      Number(lastInsertRowid)
    );
    const payload = { type: 'message', tripId: req.trip.id, message: S.message(row) };

    rt.toTrip(req.trip.id, payload);
    const otherId =
      req.user.id === req.trip.customer_id ? req.trip.operator_id : req.trip.customer_id;
    rt.toUser(otherId, payload);

    res.status(201).json({ message: S.message(row) });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
module.exports.loadTrip = loadTrip;
module.exports.logEvent = logEvent;
module.exports.broadcastTrip = broadcastTrip;
