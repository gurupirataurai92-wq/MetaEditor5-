'use strict';

const express = require('express');
const { get, all, run, transaction } = require('../db');
const V = require('../validate');
const S = require('../serialize');
const rt = require('../realtime');
const { vehicleById, haversineKm, etaMinutes } = require('../domain');
const { requireAuth, requireRole } = require('../auth');
const { loadTrip, logEvent, broadcastTrip } = require('./trips.routes');

const router = express.Router();

/**
 * POST /api/trips/:id/offers
 * An operator bids on an open job — either taking the customer's price or
 * countering with their own, exactly like inDrive.
 */
router.post('/trips/:id/offers', requireRole('operator'), loadTrip, (req, res, next) => {
  try {
    const trip = req.trip;

    if (trip.status !== 'requested') {
      return res.status(409).json({ error: 'This job is no longer open for offers.' });
    }
    if (trip.customer_id === req.user.id) {
      return res.status(400).json({ error: 'You cannot bid on your own job.' });
    }

    const profile = get('SELECT * FROM operator_profiles WHERE user_id = ?', req.user.id);
    if (!profile) {
      return res.status(400).json({ error: 'Add your vehicle details before bidding.' });
    }

    // An operator may take a job that needs their vehicle class or anything
    // smaller — a 4-ton truck can do a parcel run, a motorbike cannot move a couch.
    const required = vehicleById.get(trip.vehicle_class);
    const mine = vehicleById.get(profile.vehicle_class);
    if (!mine || mine.capacityKg < required.capacityKg) {
      return res.status(400).json({
        error: `This job needs a ${required.name.toLowerCase()} or bigger. Your ${
          mine ? mine.name.toLowerCase() : 'vehicle'
        } is too small.`,
      });
    }
    if (trip.helpers_required > mine.maxHelpers) {
      return res
        .status(400)
        .json({ error: `This job needs ${trip.helpers_required} helper(s); your vehicle class cannot carry that many.` });
    }

    const price = V.num(req.body?.price, 'Your price', { min: 1, max: 1_000_000 });
    const message = V.str(req.body?.message, 'Message', { max: 300, required: false });

    // If the operator did not supply an ETA, derive one from where they are.
    let eta = V.num(req.body?.etaMinutes, 'ETA', { min: 1, max: 24 * 60, required: false, integer: true });
    if (eta == null) {
      eta =
        profile.last_lat != null && profile.last_lng != null
          ? etaMinutes(haversineKm(profile.last_lat, profile.last_lng, trip.pickup_lat, trip.pickup_lng) * 1.35)
          : 20;
    }

    const existing = get(
      'SELECT * FROM offers WHERE trip_id = ? AND operator_id = ?',
      trip.id,
      req.user.id
    );

    let offerId;
    if (existing) {
      if (existing.status === 'accepted') {
        return res.status(409).json({ error: 'Your offer was already accepted.' });
      }
      // Let an operator revise their bid while the job is still open.
      run(
        `UPDATE offers
            SET price = ?, eta_minutes = ?, message = ?, status = 'pending',
                created_at = datetime('now')
          WHERE id = ?`,
        price,
        eta,
        message,
        existing.id
      );
      offerId = existing.id;
    } else {
      const inserted = run(
        'INSERT INTO offers (trip_id, operator_id, price, eta_minutes, message) VALUES (?, ?, ?, ?, ?)',
        trip.id,
        req.user.id,
        price,
        eta,
        message
      );
      offerId = Number(inserted.lastInsertRowid);
    }

    const offer = S.offer(get('SELECT * FROM offers WHERE id = ?', offerId));
    logEvent(trip.id, req.user.id, existing ? 'offer_updated' : 'offer_made', `${price}`);

    const payload = { type: 'offer_new', tripId: trip.id, offer };
    rt.toTrip(trip.id, payload);
    rt.toUser(trip.customer_id, payload);

    res.status(existing ? 200 : 201).json({ offer });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/trips/:id/offers
 * The customer sees every bid; an operator only ever sees their own.
 */
router.get('/trips/:id/offers', requireAuth, loadTrip, (req, res) => {
  const isCustomer = req.trip.customer_id === req.user.id;

  if (!isCustomer && req.user.role !== 'operator' && req.user.role !== 'admin') {
    return res.status(403).json({ error: 'This job is not yours.' });
  }

  const rows = isCustomer || req.user.role === 'admin'
    ? all(
        `SELECT o.* FROM offers o
          WHERE o.trip_id = ? AND o.status IN ('pending','accepted')
          ORDER BY o.price ASC, o.eta_minutes ASC`,
        req.trip.id
      )
    : all('SELECT * FROM offers WHERE trip_id = ? AND operator_id = ?', req.trip.id, req.user.id);

  res.json({ offers: rows.map(S.offer) });
});

/**
 * POST /api/offers/:offerId/accept
 * The customer picks a bid. This assigns the operator and closes the auction
 * in a single transaction so two operators can never both "win" a job.
 */
router.post('/offers/:offerId/accept', requireRole('customer'), (req, res, next) => {
  try {
    const offerId = Number(req.params.offerId);
    if (!Number.isInteger(offerId)) return res.status(400).json({ error: 'Invalid offer id.' });

    const offer = get('SELECT * FROM offers WHERE id = ?', offerId);
    if (!offer) return res.status(404).json({ error: 'Offer not found.' });

    const trip = get('SELECT * FROM trips WHERE id = ?', offer.trip_id);
    if (!trip) return res.status(404).json({ error: 'Job not found.' });
    if (trip.customer_id !== req.user.id) {
      return res.status(403).json({ error: 'This job is not yours.' });
    }
    if (trip.status !== 'requested') {
      return res.status(409).json({ error: 'This job already has an operator.' });
    }
    if (offer.status !== 'pending') {
      return res.status(409).json({ error: 'That offer is no longer available.' });
    }

    const assign = transaction(() => {
      // Guarded UPDATE: only succeeds while the job is still unassigned.
      const result = run(
        `UPDATE trips
            SET status = 'accepted', operator_id = ?, agreed_price = ?,
                accepted_at = datetime('now')
          WHERE id = ? AND status = 'requested' AND operator_id IS NULL`,
        offer.operator_id,
        offer.price,
        trip.id
      );
      if (result.changes !== 1) return false;

      run("UPDATE offers SET status = 'accepted' WHERE id = ?", offer.id);
      run(
        "UPDATE offers SET status = 'rejected' WHERE trip_id = ? AND id != ? AND status = 'pending'",
        trip.id,
        offer.id
      );
      return true;
    });

    if (!assign()) {
      return res.status(409).json({ error: 'This job was just assigned to someone else.' });
    }

    logEvent(trip.id, req.user.id, 'offer_accepted', `${offer.price}`);
    broadcastTrip(trip.id, { reason: 'accepted' });

    // Tell the winner, the losers, and the open board.
    rt.toUser(offer.operator_id, {
      type: 'offer_accepted',
      tripId: trip.id,
      offerId: offer.id,
      price: offer.price,
    });
    for (const lost of all(
      "SELECT operator_id FROM offers WHERE trip_id = ? AND status = 'rejected'",
      trip.id
    )) {
      rt.toUser(lost.operator_id, { type: 'offer_rejected', tripId: trip.id });
    }
    rt.toDispatch({ type: 'job_closed', tripId: trip.id });

    res.json({
      trip: S.trip(get('SELECT * FROM trips WHERE id = ?', trip.id), { viewerId: req.user.id }),
    });
  } catch (err) {
    next(err);
  }
});

/** DELETE /api/offers/:offerId — an operator pulls their bid. */
router.delete('/offers/:offerId', requireRole('operator'), (req, res, next) => {
  try {
    const offerId = Number(req.params.offerId);
    const offer = get('SELECT * FROM offers WHERE id = ?', offerId);

    if (!offer || offer.operator_id !== req.user.id) {
      return res.status(404).json({ error: 'Offer not found.' });
    }
    if (offer.status !== 'pending') {
      return res.status(409).json({ error: 'Only a pending offer can be withdrawn.' });
    }

    run("UPDATE offers SET status = 'withdrawn' WHERE id = ?", offerId);
    logEvent(offer.trip_id, req.user.id, 'offer_withdrawn', null);

    const payload = { type: 'offer_withdrawn', tripId: offer.trip_id, offerId };
    rt.toTrip(offer.trip_id, payload);
    const trip = get('SELECT customer_id FROM trips WHERE id = ?', offer.trip_id);
    if (trip) rt.toUser(trip.customer_id, payload);

    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
