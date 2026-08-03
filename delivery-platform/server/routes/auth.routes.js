'use strict';

const express = require('express');
const { get, run, transaction } = require('../db');
const V = require('../validate');
const { VEHICLE_CLASSES, vehicleById } = require('../domain');
const {
  hashPassword,
  verifyPassword,
  issueToken,
  requireAuth,
  publicUser,
} = require('../auth');

const router = express.Router();

// Constant-ish delay on failed logins to blunt credential stuffing without
// pulling in a rate-limit dependency. Real deployments should add one.
const FAILED_LOGIN_DELAY_MS = 400;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function operatorProfile(userId) {
  const row = get('SELECT * FROM operator_profiles WHERE user_id = ?', userId);
  if (!row) return null;
  return {
    vehicleClass: row.vehicle_class,
    vehicleMake: row.vehicle_make,
    vehicleModel: row.vehicle_model,
    vehiclePlate: row.vehicle_plate,
    capacityKg: row.capacity_kg,
    helpersAvailable: row.helpers_available,
    hasTailLift: Boolean(row.has_tail_lift),
    licenceNumber: row.licence_number,
    bio: row.bio,
    isVerified: Boolean(row.is_verified),
    isOnline: Boolean(row.is_online),
    lastSeenAt: row.last_seen_at,
    tripsCompleted: row.trips_completed,
    lastPosition:
      row.last_lat != null && row.last_lng != null
        ? { lat: row.last_lat, lng: row.last_lng, heading: row.last_heading }
        : null,
  };
}

function sessionPayload(user) {
  const payload = { token: issueToken(user), user: publicUser(user) };
  if (user.role === 'operator') payload.operatorProfile = operatorProfile(user.id);
  return payload;
}

/**
 * POST /api/auth/register
 * Creates a customer or an operator. Operators additionally supply vehicle
 * details, which land in `operator_profiles` in the same transaction.
 */
router.post('/register', async (req, res, next) => {
  try {
    const body = req.body || {};
    const role = V.oneOf(body.role, 'Account type', ['customer', 'operator']);
    const fullName = V.str(body.fullName, 'Full name', { min: 2, max: 120 });
    const emailAddr = V.email(body.email);
    const phoneNumber = V.phone(body.phone);
    const plainPassword = V.password(body.password);

    let vehicle = null;
    if (role === 'operator') {
      const vehicleClass = V.oneOf(
        body.vehicleClass,
        'Vehicle type',
        VEHICLE_CLASSES.map((v) => v.id)
      );
      const spec = vehicleById.get(vehicleClass);
      vehicle = {
        vehicleClass,
        make: V.str(body.vehicleMake, 'Vehicle make', { max: 60, required: false }),
        model: V.str(body.vehicleModel, 'Vehicle model', { max: 60, required: false }),
        plate: V.str(body.vehiclePlate, 'Number plate', { min: 2, max: 16 }),
        licenceNumber: V.str(body.licenceNumber, 'Licence number', { max: 40, required: false }),
        capacityKg: V.num(body.capacityKg, 'Payload capacity', {
          min: 1,
          max: 40000,
          required: false,
          integer: true,
        }) ?? spec.capacityKg,
        helpersAvailable:
          V.num(body.helpersAvailable, 'Helpers available', {
            min: 0,
            max: 6,
            required: false,
            integer: true,
          }) ?? 0,
        hasTailLift: V.bool(body.hasTailLift),
        bio: V.str(body.bio, 'About you', { max: 400, required: false }),
      };
    }

    if (get('SELECT id FROM users WHERE email = ?', emailAddr)) {
      return res.status(409).json({ error: 'An account with that email already exists.' });
    }

    const passwordHash = await hashPassword(plainPassword);

    const createUser = transaction(() => {
      const { lastInsertRowid } = run(
        `INSERT INTO users (role, full_name, email, phone, password_hash)
         VALUES (?, ?, ?, ?, ?)`,
        role,
        fullName,
        emailAddr,
        phoneNumber,
        passwordHash
      );
      const userId = Number(lastInsertRowid);

      if (vehicle) {
        run(
          `INSERT INTO operator_profiles
             (user_id, vehicle_class, vehicle_make, vehicle_model, vehicle_plate,
              capacity_kg, helpers_available, has_tail_lift, licence_number, bio)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          userId,
          vehicle.vehicleClass,
          vehicle.make,
          vehicle.model,
          vehicle.plate,
          vehicle.capacityKg,
          vehicle.helpersAvailable,
          vehicle.hasTailLift ? 1 : 0,
          vehicle.licenceNumber,
          vehicle.bio
        );
      }
      return userId;
    });

    const userId = createUser();
    const user = get('SELECT * FROM users WHERE id = ?', userId);
    res.status(201).json(sessionPayload(user));
  } catch (err) {
    next(err);
  }
});

/** POST /api/auth/login */
router.post('/login', async (req, res, next) => {
  try {
    const body = req.body || {};
    const emailAddr = V.email(body.email);
    const plainPassword = V.str(body.password, 'Password', { max: 200 });

    const user = get('SELECT * FROM users WHERE email = ?', emailAddr);
    const ok = user ? await verifyPassword(plainPassword, user.password_hash) : false;

    if (!ok) {
      await sleep(FAILED_LOGIN_DELAY_MS);
      return res.status(401).json({ error: 'Email or password is incorrect.' });
    }
    if (user.is_suspended) {
      return res
        .status(403)
        .json({ error: 'This account is suspended. Contact support@haulr.example.' });
    }

    res.json(sessionPayload(user));
  } catch (err) {
    next(err);
  }
});

/** GET /api/auth/me — rehydrate the session on page load. */
router.get('/me', requireAuth, (req, res) => {
  const payload = { user: publicUser(req.user) };
  if (req.user.role === 'operator') payload.operatorProfile = operatorProfile(req.user.id);
  res.json(payload);
});

/** PATCH /api/auth/me — update the caller's own name/phone. */
router.patch('/me', requireAuth, (req, res, next) => {
  try {
    const body = req.body || {};
    const fullName = V.str(body.fullName, 'Full name', { min: 2, max: 120, required: false });
    const phoneNumber = body.phone ? V.phone(body.phone) : null;

    if (!fullName && !phoneNumber) {
      return res.status(400).json({ error: 'Nothing to update.' });
    }

    run(
      `UPDATE users
          SET full_name = COALESCE(?, full_name),
              phone     = COALESCE(?, phone)
        WHERE id = ?`,
      fullName,
      phoneNumber,
      req.user.id
    );

    res.json({ user: publicUser(get('SELECT * FROM users WHERE id = ?', req.user.id)) });
  } catch (err) {
    next(err);
  }
});

/** POST /api/auth/password — change password, old one required. */
router.post('/password', requireAuth, async (req, res, next) => {
  try {
    const body = req.body || {};
    const current = V.str(body.currentPassword, 'Current password', { max: 200 });
    const next_ = V.password(body.newPassword);

    const row = get('SELECT password_hash FROM users WHERE id = ?', req.user.id);
    if (!(await verifyPassword(current, row.password_hash))) {
      await sleep(FAILED_LOGIN_DELAY_MS);
      return res.status(401).json({ error: 'Current password is incorrect.' });
    }

    run('UPDATE users SET password_hash = ? WHERE id = ?', await hashPassword(next_), req.user.id);
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
module.exports.operatorProfile = operatorProfile;
