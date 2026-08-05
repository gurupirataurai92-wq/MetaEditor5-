'use strict';

const express = require('express');
const { get, run, all, transaction } = require('../db');
const V = require('../validate');
const config = require('../config');
const totp = require('../totp');
const audit = require('../audit');
const {
  VEHICLE_CLASSES,
  vehicleById,
} = require('../domain');
const {
  hashPassword,
  verifyPassword,
  fakePasswordCheck,
  createSession,
  revokeSession,
  revokeAllSessions,
  listSessions,
  requireAuth,
  publicUser,
} = require('../auth');
const {
  setSessionCookie,
  setCsrfCookie,
  clearAuthCookies,
  passwordProblems,
  describePasswordPolicy,
  randomToken,
  safeEqual,
  RateLimiter,
  limit,
  clientKey,
} = require('../security');

const router = express.Router();

/* ==========================================================================
   Brute-force defences
   ========================================================================== */

// Two independent limits. The per-IP one stops one machine spraying many
// accounts; the per-account one stops a botnet converging on a single inbox.
const loginIpLimiter = new RateLimiter({ windowMs: 15 * 60_000, max: 30, name: 'login-ip' });
const loginEmailLimiter = new RateLimiter({ windowMs: 15 * 60_000, max: 12, name: 'login-email' });
const registerLimiter = new RateLimiter({ windowMs: 60 * 60_000, max: 8, name: 'register' });

const FAILURE_WINDOW_MINUTES = 15;
const LOCK_THRESHOLD = 5;

function recordAttempt(email, ip, succeeded) {
  run(
    'INSERT INTO login_attempts (email, ip, succeeded) VALUES (?, ?, ?)',
    email || null,
    ip || null,
    succeeded ? 1 : 0
  );
}

function recentFailures(email) {
  return get(
    `SELECT COUNT(*) AS n FROM login_attempts
      WHERE email = ? AND succeeded = 0
        AND created_at > datetime('now', ?)`,
    email,
    `-${FAILURE_WINDOW_MINUTES} minutes`
  ).n;
}

/**
 * Progressive lockout: each failure past the threshold doubles the wait, up
 * to an hour. Slow enough to make online guessing hopeless, short enough that
 * a legitimate user who fat-fingered their password is not locked out for the
 * day (and a password reset would clear it in a real deployment).
 */
function applyLockout(user, failures) {
  if (failures < LOCK_THRESHOLD) return null;
  const minutes = Math.min(60, 2 ** (failures - LOCK_THRESHOLD));
  run("UPDATE users SET locked_until = datetime('now', ?) WHERE id = ?", `+${minutes} minutes`, user.id);
  return minutes;
}

function lockRemainingSeconds(user) {
  if (!user?.locked_until) return 0;
  const until = new Date(`${user.locked_until.replace(' ', 'T')}Z`).getTime();
  const remaining = Math.ceil((until - Date.now()) / 1000);
  return remaining > 0 ? remaining : 0;
}

/* ==========================================================================
   Helpers
   ========================================================================== */

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

/** Where this role's dashboard lives. The client follows this, not its own guess. */
function homePathFor(role) {
  return { customer: '/customer.html', operator: '/operator.html', manager: '/manager.html' }[role] || '/';
}

/** Issue cookies + body for a successful authentication. */
function establishSession(req, res, user, statusCode = 200) {
  const { token, csrfToken, lifetimeMs } = createSession(user, {
    ip: req.ip,
    userAgent: req.headers['user-agent'],
  });

  setSessionCookie(res, token, lifetimeMs);
  setCsrfCookie(res, csrfToken, lifetimeMs);

  const payload = {
    user: publicUser(user),
    csrfToken,
    homePath: homePathFor(user.role),
  };
  if (user.role === 'operator') payload.operatorProfile = operatorProfile(user.id);

  return res.status(statusCode).json(payload);
}

/* ==========================================================================
   Registration
   ========================================================================== */

/**
 * POST /api/auth/register
 *
 * Self-service registration creates customers and operators only. Manager
 * accounts are never obtainable this way — they are created by an existing
 * manager, or by the `create-manager` CLI for the very first one. Allowing a
 * stranger to self-assign the role that can read every job in the system
 * would be the single worst hole in the product.
 */
router.post(
  '/register',
  limit(registerLimiter, { message: 'Too many accounts created from here. Try again later.' }),
  async (req, res, next) => {
    try {
      const body = req.body || {};
      const role = V.oneOf(body.role, 'Account type', ['customer', 'operator']);
      const fullName = V.str(body.fullName, 'Full name', { min: 2, max: 120 });
      const emailAddr = V.email(body.email);
      const phoneNumber = V.phone(body.phone);

      const problems = passwordProblems(body.password, { email: emailAddr, fullName });
      if (problems.length) {
        return res.status(400).json({ error: `Your password must ${problems.join(', ')}.` });
      }
      const plainPassword = String(body.password);

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
          capacityKg:
            V.num(body.capacityKg, 'Payload capacity', {
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
          `INSERT INTO users (role, full_name, email, phone, password_hash, password_changed_at)
           VALUES (?, ?, ?, ?, ?, datetime('now'))`,
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

      audit.record({
        actor: user,
        action: audit.ACTIONS.REGISTER,
        subjectType: 'user',
        subjectId: userId,
        detail: role,
        ip: req.ip,
      });

      establishSession(req, res, user, 201);
    } catch (err) {
      next(err);
    }
  }
);

/* ==========================================================================
   Login
   ========================================================================== */

/**
 * POST /api/auth/login
 *
 * Accounts with two-factor enabled do not get a session here: they get a
 * short-lived challenge that must be completed at /login/2fa.
 */
router.post(
  '/login',
  limit(loginIpLimiter, { message: 'Too many sign-in attempts from here. Try again in a few minutes.' }),
  async (req, res, next) => {
    try {
      const body = req.body || {};
      const emailAddr = V.email(body.email);
      const submitted = String(body.password ?? '');

      const perEmail = loginEmailLimiter.check(emailAddr);
      if (!perEmail.allowed) {
        res.setHeader('Retry-After', String(perEmail.retryAfterSeconds));
        return res.status(429).json({
          error: 'Too many attempts on this account. Try again shortly.',
          retryAfterSeconds: perEmail.retryAfterSeconds,
        });
      }

      const user = get('SELECT * FROM users WHERE email = ?', emailAddr);

      // Always spend the same work whether or not the account exists, so the
      // endpoint cannot be used to discover who has an account here.
      const ok = user
        ? await verifyPassword(submitted, user.password_hash)
        : await fakePasswordCheck(submitted);

      if (!user || !ok) {
        recordAttempt(emailAddr, req.ip, false);
        if (user) {
          const minutes = applyLockout(user, recentFailures(emailAddr));
          audit.record({
            actor: user,
            action: minutes ? audit.ACTIONS.LOGIN_LOCKED : audit.ACTIONS.LOGIN_FAILED,
            subjectType: 'user',
            subjectId: user.id,
            detail: minutes ? `locked ${minutes}m` : null,
            ip: req.ip,
          });
        }
        // One message for both cases — never confirm which half was wrong.
        return res.status(401).json({ error: 'Email or password is incorrect.' });
      }

      const lockedFor = lockRemainingSeconds(user);
      if (lockedFor > 0) {
        recordAttempt(emailAddr, req.ip, false);
        return res.status(423).json({
          error: `This account is temporarily locked after repeated failed sign-ins. Try again in ${Math.ceil(
            lockedFor / 60
          )} minute(s).`,
          retryAfterSeconds: lockedFor,
        });
      }

      if (user.is_suspended) {
        recordAttempt(emailAddr, req.ip, false);
        return res.status(403).json({
          error: user.suspended_reason
            ? `This account is suspended: ${user.suspended_reason}`
            : 'This account is suspended. Contact support.',
        });
      }

      // Password was right: clear the failure state.
      run("UPDATE users SET locked_until = NULL WHERE id = ?", user.id);
      recordAttempt(emailAddr, req.ip, true);
      loginEmailLimiter.reset(emailAddr);

      if (user.totp_enabled) {
        const challenge = createChallenge(user.id, req.ip);
        return res.json({
          twoFactorRequired: true,
          challengeId: challenge.id,
          expiresInSeconds: Math.round(CHALLENGE_TTL_MS / 1000),
        });
      }

      audit.record({
        actor: user,
        action: audit.ACTIONS.LOGIN_SUCCESS,
        subjectType: 'user',
        subjectId: user.id,
        ip: req.ip,
      });
      establishSession(req, res, user);
    } catch (err) {
      next(err);
    }
  }
);

/* ==========================================================================
   Two-factor challenge
   ========================================================================== */

const CHALLENGE_TTL_MS = 5 * 60_000;
const CHALLENGE_MAX_ATTEMPTS = 5;

// Held in memory only: a half-finished login is worthless after a restart,
// and keeping it out of the database means it cannot leak.
const challenges = new Map();

setInterval(() => {
  const now = Date.now();
  for (const [id, challenge] of challenges) {
    if (challenge.expiresAt < now) challenges.delete(id);
  }
}, 60_000).unref?.();

function createChallenge(userId, ip) {
  const id = randomToken(24);
  challenges.set(id, { id, userId, ip, attempts: 0, expiresAt: Date.now() + CHALLENGE_TTL_MS });
  return challenges.get(id);
}

/** POST /api/auth/login/2fa — finish a login with an authenticator code. */
router.post('/login/2fa', limit(loginIpLimiter), (req, res, next) => {
  try {
    const challengeId = V.str(req.body?.challengeId, 'Challenge', { max: 100 });
    const code = V.str(req.body?.code, 'Code', { min: 6, max: 20 });

    const challenge = challenges.get(challengeId);
    if (!challenge || challenge.expiresAt < Date.now()) {
      challenges.delete(challengeId);
      return res.status(400).json({ error: 'That sign-in expired. Start again.' });
    }

    challenge.attempts += 1;
    if (challenge.attempts > CHALLENGE_MAX_ATTEMPTS) {
      challenges.delete(challengeId);
      return res.status(429).json({ error: 'Too many codes tried. Start the sign-in again.' });
    }

    const user = get('SELECT * FROM users WHERE id = ?', challenge.userId);
    if (!user || user.is_suspended) {
      challenges.delete(challengeId);
      return res.status(403).json({ error: 'This account is not available.' });
    }

    const counter = totp.verify(user.totp_secret, code, {
      lastUsedCounter: user.totp_last_counter,
    });

    if (counter == null) {
      const usedRecovery = consumeRecoveryCode(user, code);
      if (!usedRecovery) {
        audit.record({
          actor: user,
          action: audit.ACTIONS.TWO_FACTOR_FAILED,
          subjectType: 'user',
          subjectId: user.id,
          ip: req.ip,
        });
        return res.status(401).json({ error: 'That code is not valid.' });
      }
    } else {
      // Remember the counter so the same code cannot be replayed.
      run('UPDATE users SET totp_last_counter = ? WHERE id = ?', counter, user.id);
    }

    challenges.delete(challengeId);
    audit.record({
      actor: user,
      action: audit.ACTIONS.LOGIN_SUCCESS,
      subjectType: 'user',
      subjectId: user.id,
      detail: counter == null ? 'recovery code' : '2fa',
      ip: req.ip,
    });

    establishSession(req, res, get('SELECT * FROM users WHERE id = ?', user.id));
  } catch (err) {
    next(err);
  }
});

/** Burn a recovery code if it matches. Returns true when one was consumed. */
function consumeRecoveryCode(user, submitted) {
  if (!user.recovery_codes) return false;
  let codes;
  try {
    codes = JSON.parse(user.recovery_codes);
  } catch {
    return false;
  }

  const submittedHash = totp.hashRecoveryCode(submitted);
  const index = codes.findIndex((stored) => safeEqual(stored, submittedHash));
  if (index === -1) return false;

  codes.splice(index, 1);
  run('UPDATE users SET recovery_codes = ? WHERE id = ?', JSON.stringify(codes), user.id);
  return true;
}

/* ==========================================================================
   Session lifecycle
   ========================================================================== */

/** POST /api/auth/logout */
router.post('/logout', requireAuth, (req, res) => {
  revokeSession(req.session.id, req.user.id);
  clearAuthCookies(res);
  audit.fromRequest(req, audit.ACTIONS.LOGOUT, { subjectType: 'user', subjectId: req.user.id });
  res.json({ ok: true });
});

/** GET /api/auth/me — rehydrate on page load. */
router.get('/me', requireAuth, (req, res) => {
  const payload = {
    user: publicUser(req.user),
    csrfToken: req.session.csrf_token,
    homePath: homePathFor(req.user.role),
  };
  if (req.user.role === 'operator') payload.operatorProfile = operatorProfile(req.user.id);
  res.json(payload);
});

/** GET /api/auth/sessions — where this account is signed in. */
router.get('/sessions', requireAuth, (req, res) => {
  res.json({
    sessions: listSessions(req.user.id).map((s) => ({
      id: s.id,
      current: s.id === req.session.id,
      ip: s.ip,
      userAgent: s.user_agent,
      createdAt: s.created_at,
      lastSeenAt: s.last_seen_at,
      expiresAt: s.expires_at,
      revokedAt: s.revoked_at,
    })),
  });
});

/** POST /api/auth/sessions/revoke-others — sign out everywhere else. */
router.post('/sessions/revoke-others', requireAuth, (req, res) => {
  const count = revokeAllSessions(req.user.id, {
    revokedBy: req.user.id,
    exceptSessionId: req.session.id,
  });
  audit.fromRequest(req, audit.ACTIONS.SESSIONS_REVOKED, {
    subjectType: 'user',
    subjectId: req.user.id,
    detail: `${count} session(s)`,
  });
  res.json({ ok: true, revoked: count });
});

/* ==========================================================================
   Profile and password
   ========================================================================== */

router.patch('/me', requireAuth, (req, res, next) => {
  try {
    const body = req.body || {};
    const fullName = V.str(body.fullName, 'Full name', { min: 2, max: 120, required: false });
    const phoneNumber = body.phone ? V.phone(body.phone) : null;

    if (!fullName && !phoneNumber) {
      return res.status(400).json({ error: 'Nothing to update.' });
    }

    run(
      `UPDATE users SET full_name = COALESCE(?, full_name), phone = COALESCE(?, phone) WHERE id = ?`,
      fullName,
      phoneNumber,
      req.user.id
    );

    res.json({ user: publicUser(get('SELECT * FROM users WHERE id = ?', req.user.id)) });
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/auth/password
 *
 * Changing a password kills every other session — the usual reason someone
 * changes it is that they think somebody else has it.
 */
router.post('/password', requireAuth, async (req, res, next) => {
  try {
    const body = req.body || {};
    const current = V.str(body.currentPassword, 'Current password', { max: 200 });

    const row = get('SELECT password_hash, email, full_name FROM users WHERE id = ?', req.user.id);
    if (!(await verifyPassword(current, row.password_hash))) {
      await fakePasswordCheck(current);
      return res.status(401).json({ error: 'Current password is incorrect.' });
    }

    const problems = passwordProblems(body.newPassword, {
      email: row.email,
      fullName: row.full_name,
    });
    if (problems.length) {
      return res.status(400).json({ error: `Your password must ${problems.join(', ')}.` });
    }
    if (await verifyPassword(String(body.newPassword), row.password_hash)) {
      return res.status(400).json({ error: 'That is your current password. Choose a different one.' });
    }

    run(
      `UPDATE users
          SET password_hash = ?, must_change_password = 0,
              password_changed_at = datetime('now'), locked_until = NULL
        WHERE id = ?`,
      await hashPassword(String(body.newPassword)),
      req.user.id
    );

    const revoked = revokeAllSessions(req.user.id, {
      revokedBy: req.user.id,
      exceptSessionId: req.session.id,
    });

    audit.fromRequest(req, audit.ACTIONS.PASSWORD_CHANGED, {
      subjectType: 'user',
      subjectId: req.user.id,
      detail: `${revoked} other session(s) ended`,
    });

    res.json({ ok: true, otherSessionsEnded: revoked });
  } catch (err) {
    next(err);
  }
});

/* ==========================================================================
   Two-factor enrolment
   ========================================================================== */

/** POST /api/auth/2fa/start — issue a secret and its provisioning URI. */
router.post('/2fa/start', requireAuth, (req, res) => {
  if (req.user.totp_enabled) {
    return res.status(409).json({ error: 'Two-factor is already switched on.' });
  }
  const secret = totp.generateSecret();
  // Stored but not yet enabled: enrolment only completes once the user proves
  // their authenticator is producing matching codes.
  run('UPDATE users SET totp_secret = ? WHERE id = ?', secret, req.user.id);

  res.json({
    secret,
    otpauthUri: totp.provisioningUri(secret, { account: req.user.email }),
  });
});

/** POST /api/auth/2fa/enable — confirm a code and switch it on. */
router.post('/2fa/enable', requireAuth, (req, res, next) => {
  try {
    const code = V.str(req.body?.code, 'Code', { min: 6, max: 10 });
    const row = get('SELECT totp_secret FROM users WHERE id = ?', req.user.id);

    if (!row?.totp_secret) {
      return res.status(400).json({ error: 'Start two-factor setup first.' });
    }

    const counter = totp.verify(row.totp_secret, code);
    if (counter == null) {
      return res.status(401).json({ error: 'That code is not valid. Check your authenticator app.' });
    }

    const recoveryCodes = totp.generateRecoveryCodes();
    run(
      `UPDATE users
          SET totp_enabled = 1, totp_last_counter = ?, recovery_codes = ?
        WHERE id = ?`,
      counter,
      JSON.stringify(recoveryCodes.map(totp.hashRecoveryCode)),
      req.user.id
    );

    audit.fromRequest(req, audit.ACTIONS.TWO_FACTOR_ENABLED, {
      subjectType: 'user',
      subjectId: req.user.id,
    });

    // Shown exactly once — only their hashes are kept.
    res.json({ ok: true, recoveryCodes });
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/auth/2fa/disable
 *
 * Requires the current password. Managers may not turn it off at all — the
 * role that can see every job in the system keeps its second factor.
 */
router.post('/2fa/disable', requireAuth, async (req, res, next) => {
  try {
    if (req.user.role === 'manager') {
      return res.status(403).json({
        error: 'Two-factor authentication is mandatory for manager accounts and cannot be switched off.',
      });
    }

    const password = V.str(req.body?.password, 'Password', { max: 200 });
    const row = get('SELECT password_hash FROM users WHERE id = ?', req.user.id);
    if (!(await verifyPassword(password, row.password_hash))) {
      await fakePasswordCheck(password);
      return res.status(401).json({ error: 'Password is incorrect.' });
    }

    run(
      `UPDATE users
          SET totp_enabled = 0, totp_secret = NULL, totp_last_counter = NULL, recovery_codes = NULL
        WHERE id = ?`,
      req.user.id
    );

    audit.fromRequest(req, audit.ACTIONS.TWO_FACTOR_DISABLED, {
      subjectType: 'user',
      subjectId: req.user.id,
    });

    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

/** GET /api/auth/policy — so the sign-up form states the real rules. */
router.get('/policy', (_req, res) => {
  res.json({ password: describePasswordPolicy() });
});

module.exports = router;
module.exports.operatorProfile = operatorProfile;
module.exports.homePathFor = homePathFor;
