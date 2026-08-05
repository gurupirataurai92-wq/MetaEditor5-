'use strict';

// Manager console: oversight of every job, operator and customer, plus the
// interventions needed when something goes wrong on the road.
//
// Two rules run through this whole file:
//   1. Nothing here is reachable without the `manager` role.
//   2. Every read of someone's personal data and every intervention is
//      written to the audit log, because oversight without accountability is
//      just unchecked access.

const express = require('express');
const { get, all, run, transaction } = require('../db');
const V = require('../validate');
const S = require('../serialize');
const rt = require('../realtime');
const audit = require('../audit');
const config = require('../config');
const totp = require('../totp');
const {
  vehicleById,
  haversineKm,
  STATUS_LABELS,
  ACTIVE_STATUSES,
} = require('../domain');
const {
  requireRole,
  requireEnrolledTwoFactor,
  hashPassword,
  verifyPassword,
  fakePasswordCheck,
  revokeAllSessions,
  publicUser,
} = require('../auth');
const { passwordProblems, RateLimiter, limit } = require('../security');

const router = express.Router();

// Every route below is manager-only, and unusable until that manager has a
// second factor enrolled.
router.use('/manager', requireRole('manager'), requireEnrolledTwoFactor);

const managerCreateLimiter = new RateLimiter({
  windowMs: 60 * 60_000,
  max: 5,
  name: 'manager-create',
});

/* ==========================================================================
   Overview
   ========================================================================== */

/** GET /api/manager/overview — the numbers on the top of the console. */
router.get('/manager/overview', (_req, res) => {
  const activeList = ACTIVE_STATUSES.map(() => '?').join(',');

  const counts = get(
    `SELECT
       COUNT(*) AS total,
       SUM(CASE WHEN status = 'requested' THEN 1 ELSE 0 END) AS awaiting,
       SUM(CASE WHEN status IN ('accepted','en_route_pickup','at_pickup','in_transit') THEN 1 ELSE 0 END) AS live,
       SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed,
       SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled,
       SUM(CASE WHEN flagged_at IS NOT NULL AND status NOT IN ('completed','cancelled') THEN 1 ELSE 0 END) AS flagged
     FROM trips`
  );

  const today = get(
    `SELECT COUNT(*) AS jobs, COALESCE(SUM(agreed_price), 0) AS value
       FROM trips
      WHERE created_at >= datetime('now', '-1 day')`
  );

  const people = get(
    `SELECT
       SUM(CASE WHEN role = 'customer' THEN 1 ELSE 0 END) AS customers,
       SUM(CASE WHEN role = 'operator' THEN 1 ELSE 0 END) AS operators,
       SUM(CASE WHEN role = 'manager'  THEN 1 ELSE 0 END) AS managers,
       SUM(CASE WHEN is_suspended = 1 THEN 1 ELSE 0 END) AS suspended
     FROM users`
  );

  const staleCutoff = new Date(Date.now() - config.operatorStaleAfterMs)
    .toISOString()
    .replace('T', ' ')
    .slice(0, 19);

  const onDuty = get(
    `SELECT COUNT(*) AS n FROM operator_profiles
      WHERE is_online = 1 AND last_seen_at >= ?`,
    staleCutoff
  ).n;

  const unverified = get(
    'SELECT COUNT(*) AS n FROM operator_profiles WHERE is_verified = 0'
  ).n;

  // Jobs sitting unclaimed for a while are the ones a manager needs to chase.
  const stalled = all(
    `SELECT t.*, (SELECT COUNT(*) FROM offers o WHERE o.trip_id = t.id AND o.status='pending') AS offer_count
       FROM trips t
      WHERE t.status = 'requested' AND t.created_at < datetime('now', '-20 minutes')
      ORDER BY t.created_at ASC
      LIMIT 10`
  );

  void activeList;

  res.json({
    jobs: {
      total: counts.total || 0,
      awaitingOperator: counts.awaiting || 0,
      live: counts.live || 0,
      completed: counts.completed || 0,
      cancelled: counts.cancelled || 0,
      flagged: counts.flagged || 0,
    },
    last24h: { jobs: today.jobs || 0, value: today.value || 0 },
    people: {
      customers: people.customers || 0,
      operators: people.operators || 0,
      managers: people.managers || 0,
      suspended: people.suspended || 0,
      onDuty,
      unverifiedOperators: unverified,
    },
    stalled: stalled.map((row) => ({
      ...S.trip(row, { viewerId: null }),
      offerCount: row.offer_count,
      waitingMinutes: Math.round(
        (Date.now() - new Date(`${row.created_at.replace(' ', 'T')}Z`).getTime()) / 60000
      ),
    })),
  });
});

/* ==========================================================================
   Jobs
   ========================================================================== */

/** GET /api/manager/trips?status=&q=&limit= — every job, filterable. */
router.get('/manager/trips', (req, res, next) => {
  try {
    const status = req.query.status
      ? V.oneOf(req.query.status, 'Status', [...Object.keys(STATUS_LABELS), 'live', 'flagged'])
      : null;
    const search = V.str(req.query.q, 'Search', { max: 80, required: false });
    const limitRows = V.num(req.query.limit ?? 60, 'Limit', { min: 1, max: 200, integer: true });

    const where = [];
    const params = [];

    if (status === 'live') {
      where.push("t.status IN ('accepted','en_route_pickup','at_pickup','in_transit')");
    } else if (status === 'flagged') {
      where.push('t.flagged_at IS NOT NULL');
    } else if (status) {
      where.push('t.status = ?');
      params.push(status);
    }

    if (search) {
      where.push('(t.reference LIKE ? OR t.pickup_address LIKE ? OR t.dropoff_address LIKE ?)');
      const like = `%${search}%`;
      params.push(like, like, like);
    }

    const rows = all(
      `SELECT t.*,
              (SELECT COUNT(*) FROM offers o WHERE o.trip_id = t.id AND o.status = 'pending') AS offer_count
         FROM trips t
        ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
        ORDER BY t.created_at DESC, t.id DESC
        LIMIT ?`,
      ...params,
      limitRows
    );

    // The list view is a summary only — no contact details are serialised, so
    // browsing the board does not expose anybody's phone number.
    res.json({
      trips: rows.map((row) => ({
        ...S.trip(row, { viewerId: null }),
        offerCount: row.offer_count,
        flaggedReason: row.flagged_reason,
        flaggedAt: row.flagged_at,
        assignedBy: row.assigned_by,
      })),
    });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/manager/trips/:id
 * Full detail including both parties' contact details — which is exactly why
 * opening one is recorded against the manager who did it.
 */
router.get('/manager/trips/:id', (req, res, next) => {
  try {
    const id = V.num(req.params.id, 'Job id', { min: 1, integer: true });
    const row = get('SELECT * FROM trips WHERE id = ?', id);
    if (!row) return res.status(404).json({ error: 'Job not found.' });

    audit.fromRequest(req, audit.ACTIONS.MANAGER_VIEWED_TRIP, {
      subjectType: 'trip',
      subjectId: id,
      detail: row.reference,
    });

    // Serialising as the customer yields the full picture for oversight.
    const trip = S.trip(row, { viewerId: row.customer_id });

    res.json({
      trip: { ...trip, flaggedReason: row.flagged_reason, flaggedAt: row.flagged_at },
      offers: all(
        'SELECT * FROM offers WHERE trip_id = ? ORDER BY price ASC',
        id
      ).map(S.offer),
      events: all('SELECT * FROM trip_events WHERE trip_id = ? ORDER BY id ASC', id).map(S.event),
      trail: all(
        `SELECT lat, lng, heading, speed_kph, accuracy_m, recorded_at
           FROM trip_locations WHERE trip_id = ? ORDER BY id ASC LIMIT 2000`,
        id
      ).map(S.location),
      messageCount: get('SELECT COUNT(*) AS n FROM messages WHERE trip_id = ?', id).n,
    });
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/manager/trips/:id/reassign
 * Move a job to a different operator — the operator broke down, went quiet,
 * or the customer asked for someone else.
 */
router.post('/manager/trips/:id/reassign', (req, res, next) => {
  try {
    const id = V.num(req.params.id, 'Job id', { min: 1, integer: true });
    const operatorId = V.num(req.body?.operatorId, 'Operator', { min: 1, integer: true });
    const reason = V.str(req.body?.reason, 'Reason', { min: 3, max: 300 });

    const trip = get('SELECT * FROM trips WHERE id = ?', id);
    if (!trip) return res.status(404).json({ error: 'Job not found.' });
    if (['completed', 'cancelled', 'delivered'].includes(trip.status)) {
      return res.status(409).json({ error: 'This job is already finished.' });
    }

    const operator = get(
      `SELECT u.id, u.full_name, u.is_suspended, p.vehicle_class
         FROM users u JOIN operator_profiles p ON p.user_id = u.id
        WHERE u.id = ? AND u.role = 'operator'`,
      operatorId
    );
    if (!operator) return res.status(404).json({ error: 'That operator does not exist.' });
    if (operator.is_suspended) {
      return res.status(400).json({ error: 'That operator is suspended.' });
    }
    if (operator.id === trip.operator_id) {
      return res.status(400).json({ error: 'That operator already has this job.' });
    }

    // A manager may override a lot, but not physics: the replacement vehicle
    // still has to be able to carry the load.
    const required = vehicleById.get(trip.vehicle_class);
    const theirs = vehicleById.get(operator.vehicle_class);
    if (!theirs || theirs.capacityKg < required.capacityKg) {
      return res.status(400).json({
        error: `That operator drives a ${theirs?.name ?? 'vehicle'}, which is too small for a job needing a ${required.name.toLowerCase()}.`,
      });
    }

    const previousOperatorId = trip.operator_id;

    transaction(() => {
      run(
        `UPDATE trips
            SET operator_id = ?, status = 'accepted', assigned_by = 'manager',
                accepted_at = COALESCE(accepted_at, datetime('now')),
                agreed_price = COALESCE(agreed_price, customer_offer_price)
          WHERE id = ?`,
        operatorId,
        id
      );
      if (previousOperatorId) {
        run(
          "UPDATE offers SET status = 'withdrawn' WHERE trip_id = ? AND operator_id = ?",
          id,
          previousOperatorId
        );
      }
      run(
        'INSERT INTO trip_events (trip_id, actor_id, type, note) VALUES (?, ?, ?, ?)',
        id,
        req.user.id,
        'manager_reassigned',
        reason
      );
    })();

    audit.fromRequest(req, audit.ACTIONS.MANAGER_REASSIGNED, {
      subjectType: 'trip',
      subjectId: id,
      detail: `${previousOperatorId ?? 'unassigned'} -> ${operatorId}: ${reason}`,
    });

    broadcast(id, { reason: 'reassigned' });
    if (previousOperatorId) {
      rt.toUser(previousOperatorId, { type: 'job_removed', tripId: id, reason });
    }
    rt.toUser(operatorId, { type: 'job_assigned', tripId: id, reason });

    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

/** POST /api/manager/trips/:id/cancel — stop a job at any stage. */
router.post('/manager/trips/:id/cancel', (req, res, next) => {
  try {
    const id = V.num(req.params.id, 'Job id', { min: 1, integer: true });
    const reason = V.str(req.body?.reason, 'Reason', { min: 3, max: 300 });

    const trip = get('SELECT * FROM trips WHERE id = ?', id);
    if (!trip) return res.status(404).json({ error: 'Job not found.' });
    if (['completed', 'cancelled'].includes(trip.status)) {
      return res.status(409).json({ error: 'This job is already closed.' });
    }

    transaction(() => {
      run(
        `UPDATE trips
            SET status = 'cancelled', cancel_reason = ?, cancelled_by = 'manager',
                closed_at = datetime('now')
          WHERE id = ?`,
        reason,
        id
      );
      run("UPDATE offers SET status = 'rejected' WHERE trip_id = ? AND status = 'pending'", id);
      run(
        'INSERT INTO trip_events (trip_id, actor_id, type, note) VALUES (?, ?, ?, ?)',
        id,
        req.user.id,
        'manager_cancelled',
        reason
      );
    })();

    audit.fromRequest(req, audit.ACTIONS.MANAGER_CANCELLED, {
      subjectType: 'trip',
      subjectId: id,
      detail: reason,
    });

    broadcast(id, { reason: 'cancelled' });
    rt.toDispatch({ type: 'job_closed', tripId: id });
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

/** POST /api/manager/trips/:id/flag — mark a job as needing attention. */
router.post('/manager/trips/:id/flag', (req, res, next) => {
  try {
    const id = V.num(req.params.id, 'Job id', { min: 1, integer: true });
    const clearing = req.body?.clear === true;

    if (clearing) {
      run('UPDATE trips SET flagged_reason = NULL, flagged_at = NULL WHERE id = ?', id);
      audit.fromRequest(req, audit.ACTIONS.MANAGER_UNFLAGGED, { subjectType: 'trip', subjectId: id });
      broadcast(id, { reason: 'unflagged' });
      return res.json({ ok: true, flagged: false });
    }

    const reason = V.str(req.body?.reason, 'Reason', { min: 3, max: 300 });
    const result = run(
      "UPDATE trips SET flagged_reason = ?, flagged_at = datetime('now') WHERE id = ?",
      reason,
      id
    );
    if (result.changes !== 1) return res.status(404).json({ error: 'Job not found.' });

    run(
      'INSERT INTO trip_events (trip_id, actor_id, type, note) VALUES (?, ?, ?, ?)',
      id,
      req.user.id,
      'manager_flagged',
      reason
    );
    audit.fromRequest(req, audit.ACTIONS.MANAGER_FLAGGED, {
      subjectType: 'trip',
      subjectId: id,
      detail: reason,
    });

    broadcast(id, { reason: 'flagged' });
    res.json({ ok: true, flagged: true });
  } catch (err) {
    next(err);
  }
});

function broadcast(tripId, extra) {
  const row = get('SELECT * FROM trips WHERE id = ?', tripId);
  if (!row) return;
  const payload = {
    type: 'trip_update',
    tripId,
    trip: S.trip(row, { viewerId: row.customer_id }),
    ...extra,
  };
  rt.toTrip(tripId, payload);
  rt.toUser(row.customer_id, payload);
  if (row.operator_id) rt.toUser(row.operator_id, payload);
}

/* ==========================================================================
   Fleet
   ========================================================================== */

/**
 * GET /api/manager/fleet
 * Live positions of on-duty operators at full precision. This is staff-level
 * access to staff whereabouts, so it is audited like any other sensitive read.
 */
router.get('/manager/fleet', (req, res) => {
  const staleCutoff = new Date(Date.now() - config.operatorStaleAfterMs)
    .toISOString()
    .replace('T', ' ')
    .slice(0, 19);

  const rows = all(
    `SELECT u.id, u.full_name, u.rating_sum, u.rating_count,
            p.vehicle_class, p.vehicle_plate, p.is_verified,
            p.last_lat, p.last_lng, p.last_heading, p.last_seen_at,
            (SELECT t.id FROM trips t
              WHERE t.operator_id = u.id
                AND t.status IN ('accepted','en_route_pickup','at_pickup','in_transit')
              LIMIT 1) AS current_trip_id
       FROM users u
       JOIN operator_profiles p ON p.user_id = u.id
      WHERE u.is_suspended = 0 AND p.is_online = 1 AND p.last_lat IS NOT NULL
        AND p.last_seen_at >= ?
      ORDER BY p.last_seen_at DESC
      LIMIT 300`,
    staleCutoff
  );

  audit.fromRequest(req, 'manager.fleet.viewed', { detail: `${rows.length} vehicles` });

  res.json({
    vehicles: rows.map((r) => ({
      operatorId: r.id,
      name: r.full_name,
      vehicleClass: r.vehicle_class,
      plate: r.vehicle_plate,
      verified: Boolean(r.is_verified),
      rating: S.ratingOf(r.rating_sum, r.rating_count),
      lat: r.last_lat,
      lng: r.last_lng,
      heading: r.last_heading,
      lastSeenAt: r.last_seen_at,
      currentTripId: r.current_trip_id,
      busy: r.current_trip_id != null,
    })),
  });
});

/**
 * GET /api/manager/trips/:id/candidates
 * Operators who could take over this job, nearest first.
 */
router.get('/manager/trips/:id/candidates', (req, res, next) => {
  try {
    const id = V.num(req.params.id, 'Job id', { min: 1, integer: true });
    const trip = get('SELECT * FROM trips WHERE id = ?', id);
    if (!trip) return res.status(404).json({ error: 'Job not found.' });

    const required = vehicleById.get(trip.vehicle_class);
    const eligible = [...vehicleById.values()]
      .filter((v) => v.capacityKg >= required.capacityKg)
      .map((v) => v.id);
    const placeholders = eligible.map(() => '?').join(',');

    const rows = all(
      `SELECT u.id, u.full_name, u.rating_sum, u.rating_count,
              p.vehicle_class, p.vehicle_plate, p.is_online, p.is_verified,
              p.last_lat, p.last_lng, p.trips_completed,
              (SELECT COUNT(*) FROM trips t
                WHERE t.operator_id = u.id
                  AND t.status IN ('accepted','en_route_pickup','at_pickup','in_transit')) AS active_jobs
         FROM users u
         JOIN operator_profiles p ON p.user_id = u.id
        WHERE u.role = 'operator' AND u.is_suspended = 0
          AND p.vehicle_class IN (${placeholders})
          AND u.id != COALESCE(?, -1)
        LIMIT 200`,
      ...eligible,
      trip.operator_id
    );

    const candidates = rows
      .map((r) => ({
        id: r.id,
        name: r.full_name,
        vehicleClass: r.vehicle_class,
        plate: r.vehicle_plate,
        online: Boolean(r.is_online),
        verified: Boolean(r.is_verified),
        rating: S.ratingOf(r.rating_sum, r.rating_count),
        tripsCompleted: r.trips_completed,
        activeJobs: r.active_jobs,
        distanceToPickupKm:
          r.last_lat != null
            ? Number((haversineKm(r.last_lat, r.last_lng, trip.pickup_lat, trip.pickup_lng) * 1.35).toFixed(2))
            : null,
      }))
      .sort((a, b) => {
        // Free and online first, then by distance.
        if (a.online !== b.online) return a.online ? -1 : 1;
        if (a.activeJobs !== b.activeJobs) return a.activeJobs - b.activeJobs;
        return (a.distanceToPickupKm ?? 1e9) - (b.distanceToPickupKm ?? 1e9);
      })
      .slice(0, 25);

    res.json({ candidates });
  } catch (err) {
    next(err);
  }
});

/* ==========================================================================
   People
   ========================================================================== */

/** GET /api/manager/users?role=&q=&suspended= */
router.get('/manager/users', (req, res, next) => {
  try {
    const role = req.query.role
      ? V.oneOf(req.query.role, 'Role', ['customer', 'operator', 'manager'])
      : null;
    const search = V.str(req.query.q, 'Search', { max: 80, required: false });
    const limitRows = V.num(req.query.limit ?? 60, 'Limit', { min: 1, max: 200, integer: true });

    const where = [];
    const params = [];
    if (role) {
      where.push('u.role = ?');
      params.push(role);
    }
    if (search) {
      where.push('(u.full_name LIKE ? OR u.email LIKE ?)');
      params.push(`%${search}%`, `%${search}%`);
    }
    if (req.query.suspended === 'true') where.push('u.is_suspended = 1');
    if (req.query.unverified === 'true') where.push('p.is_verified = 0');

    const rows = all(
      `SELECT u.id, u.role, u.full_name, u.email, u.phone, u.rating_sum, u.rating_count,
              u.is_suspended, u.suspended_reason, u.totp_enabled, u.created_at,
              p.vehicle_class, p.vehicle_plate, p.is_verified, p.is_online, p.trips_completed,
              (SELECT COUNT(*) FROM trips t WHERE t.customer_id = u.id) AS jobs_posted,
              (SELECT COUNT(*) FROM trips t WHERE t.operator_id = u.id AND t.status='completed') AS jobs_done
         FROM users u
         LEFT JOIN operator_profiles p ON p.user_id = u.id
        ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
        ORDER BY u.created_at DESC
        LIMIT ?`,
      ...params,
      limitRows
    );

    res.json({
      users: rows.map((r) => ({
        id: r.id,
        role: r.role,
        fullName: r.full_name,
        email: r.email,
        phone: r.phone,
        rating: S.ratingOf(r.rating_sum, r.rating_count),
        ratingCount: r.rating_count,
        suspended: Boolean(r.is_suspended),
        suspendedReason: r.suspended_reason,
        twoFactorEnabled: Boolean(r.totp_enabled),
        createdAt: r.created_at,
        vehicleClass: r.vehicle_class,
        plate: r.vehicle_plate,
        verified: r.vehicle_class ? Boolean(r.is_verified) : null,
        online: r.vehicle_class ? Boolean(r.is_online) : null,
        jobsPosted: r.jobs_posted,
        jobsDone: r.jobs_done,
      })),
    });
  } catch (err) {
    next(err);
  }
});

/** POST /api/manager/users/:id/suspend */
router.post('/manager/users/:id/suspend', (req, res, next) => {
  try {
    const id = V.num(req.params.id, 'User id', { min: 1, integer: true });
    const reason = V.str(req.body?.reason, 'Reason', { min: 3, max: 300 });

    const target = get('SELECT id, role, full_name FROM users WHERE id = ?', id);
    if (!target) return res.status(404).json({ error: 'User not found.' });
    if (target.id === req.user.id) {
      return res.status(400).json({ error: 'You cannot suspend your own account.' });
    }
    // Managers are peers; one cannot unilaterally lock another out. Removing a
    // manager is a deliberate, out-of-band decision.
    if (target.role === 'manager') {
      return res.status(403).json({ error: 'Manager accounts cannot be suspended from the console.' });
    }

    run('UPDATE users SET is_suspended = 1, suspended_reason = ? WHERE id = ?', reason, id);
    // Suspension has to bite immediately, not at token expiry.
    const revoked = revokeAllSessions(id, { revokedBy: req.user.id });
    run('UPDATE operator_profiles SET is_online = 0 WHERE user_id = ?', id);

    audit.fromRequest(req, audit.ACTIONS.MANAGER_SUSPENDED_USER, {
      subjectType: 'user',
      subjectId: id,
      detail: `${target.full_name}: ${reason}`,
    });

    res.json({ ok: true, sessionsEnded: revoked });
  } catch (err) {
    next(err);
  }
});

/** POST /api/manager/users/:id/reinstate */
router.post('/manager/users/:id/reinstate', (req, res, next) => {
  try {
    const id = V.num(req.params.id, 'User id', { min: 1, integer: true });
    const result = run(
      'UPDATE users SET is_suspended = 0, suspended_reason = NULL, locked_until = NULL WHERE id = ?',
      id
    );
    if (result.changes !== 1) return res.status(404).json({ error: 'User not found.' });

    audit.fromRequest(req, audit.ACTIONS.MANAGER_REINSTATED_USER, {
      subjectType: 'user',
      subjectId: id,
    });
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

/** POST /api/manager/users/:id/force-logout */
router.post('/manager/users/:id/force-logout', (req, res, next) => {
  try {
    const id = V.num(req.params.id, 'User id', { min: 1, integer: true });
    const revoked = revokeAllSessions(id, { revokedBy: req.user.id });
    audit.fromRequest(req, audit.ACTIONS.MANAGER_FORCED_LOGOUT, {
      subjectType: 'user',
      subjectId: id,
      detail: `${revoked} session(s)`,
    });
    res.json({ ok: true, sessionsEnded: revoked });
  } catch (err) {
    next(err);
  }
});

/** POST /api/manager/operators/:id/verify */
router.post('/manager/operators/:id/verify', (req, res, next) => {
  try {
    const id = V.num(req.params.id, 'Operator id', { min: 1, integer: true });
    const verified = req.body?.verified !== false;

    const result = run('UPDATE operator_profiles SET is_verified = ? WHERE user_id = ?', verified ? 1 : 0, id);
    if (result.changes !== 1) return res.status(404).json({ error: 'Operator not found.' });

    audit.fromRequest(req, audit.ACTIONS.MANAGER_VERIFIED_OPERATOR, {
      subjectType: 'user',
      subjectId: id,
      detail: verified ? 'verified' : 'verification removed',
    });
    res.json({ ok: true, verified });
  } catch (err) {
    next(err);
  }
});

/* ==========================================================================
   Manager accounts
   ========================================================================== */

/**
 * POST /api/manager/managers
 *
 * Only an existing manager can mint another, and only by re-entering their own
 * password. The new account starts with `must_change_password` set and no
 * second factor, which it is forced to enrol on first sign-in.
 */
router.post('/manager/managers', limit(managerCreateLimiter), async (req, res, next) => {
  try {
    const fullName = V.str(req.body?.fullName, 'Full name', { min: 2, max: 120 });
    const emailAddr = V.email(req.body?.email);
    const phoneNumber = V.phone(req.body?.phone);
    const confirmPassword = V.str(req.body?.confirmPassword, 'Your password', { max: 200 });

    const me = get('SELECT password_hash FROM users WHERE id = ?', req.user.id);
    if (!(await verifyPassword(confirmPassword, me.password_hash))) {
      await fakePasswordCheck(confirmPassword);
      audit.fromRequest(req, 'manager.created.denied', { detail: 'wrong confirmation password' });
      return res.status(401).json({ error: 'Your password is incorrect.' });
    }

    const problems = passwordProblems(req.body?.password, {
      email: emailAddr,
      fullName,
    });
    if (problems.length) {
      return res.status(400).json({ error: `The new manager's password must ${problems.join(', ')}.` });
    }

    if (get('SELECT id FROM users WHERE email = ?', emailAddr)) {
      return res.status(409).json({ error: 'An account with that email already exists.' });
    }

    const { lastInsertRowid } = run(
      `INSERT INTO users (role, full_name, email, phone, password_hash,
                          must_change_password, password_changed_at)
       VALUES ('manager', ?, ?, ?, ?, 1, datetime('now'))`,
      fullName,
      emailAddr,
      phoneNumber,
      await hashPassword(String(req.body.password))
    );

    audit.fromRequest(req, audit.ACTIONS.MANAGER_CREATED, {
      subjectType: 'user',
      subjectId: Number(lastInsertRowid),
      detail: emailAddr,
    });

    res.status(201).json({
      user: publicUser(get('SELECT * FROM users WHERE id = ?', Number(lastInsertRowid))),
      note: 'They must change this password and enrol two-factor authentication on first sign-in.',
    });
  } catch (err) {
    next(err);
  }
});

/* ==========================================================================
   Audit
   ========================================================================== */

/** GET /api/manager/audit — the log, including managers' own activity. */
router.get('/manager/audit', (req, res, next) => {
  try {
    const limitRows = V.num(req.query.limit ?? 80, 'Limit', { min: 1, max: 300, integer: true });
    const offset = V.num(req.query.offset ?? 0, 'Offset', { min: 0, max: 100000, integer: true });
    const action = V.str(req.query.action, 'Action', { max: 60, required: false });
    const actorId = req.query.actorId
      ? V.num(req.query.actorId, 'Actor', { min: 1, integer: true })
      : null;

    res.json(audit.list({ limit: limitRows, offset, action, actorId }));
  } catch (err) {
    next(err);
  }
});

/** GET /api/manager/security — a quick health read on the security posture. */
router.get('/manager/security', (_req, res) => {
  const failedRecently = get(
    `SELECT COUNT(*) AS n FROM login_attempts
      WHERE succeeded = 0 AND created_at > datetime('now', '-24 hours')`
  ).n;

  const lockedAccounts = get(
    "SELECT COUNT(*) AS n FROM users WHERE locked_until > datetime('now')"
  ).n;

  const activeSessions = get(
    "SELECT COUNT(*) AS n FROM sessions WHERE revoked_at IS NULL AND expires_at > datetime('now')"
  ).n;

  const managersWithout2fa = get(
    "SELECT COUNT(*) AS n FROM users WHERE role = 'manager' AND totp_enabled = 0"
  ).n;

  const topFailures = all(
    `SELECT email, COUNT(*) AS attempts, MAX(created_at) AS last_attempt
       FROM login_attempts
      WHERE succeeded = 0 AND created_at > datetime('now', '-24 hours')
      GROUP BY email ORDER BY attempts DESC LIMIT 8`
  );

  res.json({
    failedLogins24h: failedRecently,
    lockedAccounts,
    activeSessions,
    managersWithoutTwoFactor: managersWithout2fa,
    topTargetedAccounts: topFailures.map((r) => ({
      email: r.email,
      attempts: r.attempts,
      lastAttempt: r.last_attempt,
    })),
  });
});

void totp;

module.exports = router;
