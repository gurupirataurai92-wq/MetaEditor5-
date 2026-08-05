'use strict';

const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const crypto = require('node:crypto');
const config = require('./config');
const { get, run, all } = require('./db');
const {
  SESSION_COOKIE,
  parseCookies,
  safeEqual,
  randomToken,
} = require('./security');

const BCRYPT_ROUNDS = 12;

// Comparing against a real hash on the "no such user" path keeps the response
// time of a bad email indistinguishable from a bad password. Without it, the
// login endpoint is an account-enumeration oracle.
const DUMMY_HASH = bcrypt.hashSync('a-password-that-is-never-valid', BCRYPT_ROUNDS);

function hashPassword(plain) {
  return bcrypt.hash(plain, BCRYPT_ROUNDS);
}

function verifyPassword(plain, hash) {
  return bcrypt.compare(plain, hash || DUMMY_HASH);
}

/** Burn the same CPU as a real check, then fail. */
async function fakePasswordCheck(plain) {
  await bcrypt.compare(String(plain ?? ''), DUMMY_HASH);
  return false;
}

/* ==========================================================================
   Sessions
   ========================================================================== */

function ttlMs() {
  const match = /^(\d+)([smhd])$/.exec(config.tokenTtl);
  if (!match) return 7 * 24 * 3600 * 1000;
  const units = { s: 1000, m: 60_000, h: 3_600_000, d: 86_400_000 };
  return Number(match[1]) * units[match[2]];
}

/**
 * Create a session row and the JWT that points at it.
 *
 * The token is only an assertion about which session it is; authority lives in
 * the database row, so a session can be revoked the instant it needs to be.
 */
function createSession(user, { ip = null, userAgent = null } = {}) {
  const sessionId = crypto.randomUUID();
  const csrfToken = randomToken(32);
  const lifetimeMs = ttlMs();
  const expiresAt = new Date(Date.now() + lifetimeMs).toISOString();

  run(
    `INSERT INTO sessions (id, user_id, csrf_token, ip, user_agent, expires_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
    sessionId,
    user.id,
    csrfToken,
    ip,
    userAgent ? String(userAgent).slice(0, 300) : null,
    expiresAt
  );

  const token = jwt.sign(
    { sub: String(user.id), role: user.role, sid: sessionId },
    config.jwtSecret,
    { expiresIn: Math.floor(lifetimeMs / 1000) }
  );

  return { token, csrfToken, sessionId, lifetimeMs, expiresAt };
}

function revokeSession(sessionId, revokedBy = null) {
  run(
    "UPDATE sessions SET revoked_at = datetime('now'), revoked_by = ? WHERE id = ? AND revoked_at IS NULL",
    revokedBy,
    sessionId
  );
}

/** Revoke every live session for a user. Returns how many were killed. */
function revokeAllSessions(userId, { revokedBy = null, exceptSessionId = null } = {}) {
  const result = run(
    `UPDATE sessions
        SET revoked_at = datetime('now'), revoked_by = ?
      WHERE user_id = ? AND revoked_at IS NULL
        ${exceptSessionId ? 'AND id != ?' : ''}`,
    ...(exceptSessionId ? [revokedBy, userId, exceptSessionId] : [revokedBy, userId])
  );
  return result.changes;
}

function listSessions(userId) {
  return all(
    `SELECT id, ip, user_agent, created_at, last_seen_at, expires_at, revoked_at
       FROM sessions
      WHERE user_id = ?
      ORDER BY created_at DESC
      LIMIT 50`,
    userId
  );
}

/**
 * Resolve a token to a live user + session.
 *
 * Every request re-reads the database, so a suspension, a revoked session or a
 * deleted account takes effect immediately rather than at token expiry.
 */
function resolveToken(token) {
  if (!token) return null;

  let payload;
  try {
    payload = jwt.verify(token, config.jwtSecret, { algorithms: ['HS256'] });
  } catch {
    return null;
  }
  if (!payload.sid) return null;

  const session = get(
    `SELECT * FROM sessions
      WHERE id = ? AND revoked_at IS NULL AND expires_at > datetime('now')`,
    payload.sid
  );
  if (!session) return null;
  if (session.user_id !== Number(payload.sub)) return null;

  const user = get(
    `SELECT id, role, full_name, email, phone, rating_sum, rating_count,
            is_suspended, suspended_reason, totp_enabled, must_change_password,
            created_at
       FROM users WHERE id = ?`,
    session.user_id
  );
  if (!user || user.is_suspended) return null;

  // A token minted before a role change must not keep the old privileges.
  if (payload.role !== user.role) return null;

  return { user, session };
}

function tokenFromRequest(req) {
  // Browser sessions ride in an httpOnly cookie. The bearer header stays
  // supported for scripts and integrations, which are not subject to CSRF
  // because a browser never attaches it automatically.
  const cookies = parseCookies(req);
  if (cookies[SESSION_COOKIE]) return { token: cookies[SESSION_COOKIE], via: 'cookie' };

  const header = req.headers.authorization;
  if (header && header.startsWith('Bearer ')) {
    return { token: header.slice(7).trim(), via: 'bearer' };
  }
  return { token: null, via: null };
}

/** Populates `req.user` / `req.session` when valid; never rejects. */
function attachUser(req, _res, next) {
  const { token, via } = tokenFromRequest(req);
  const resolved = resolveToken(token);

  if (resolved) {
    req.user = resolved.user;
    req.session = resolved.session;
    req.authVia = via;
    // Cheap liveness tracking for the "your active sessions" screen. Written
    // at most once a minute so a chatty client cannot hammer the row.
    const lastSeen = new Date(`${resolved.session.last_seen_at.replace(' ', 'T')}Z`).getTime();
    if (Date.now() - lastSeen > 60_000) {
      run("UPDATE sessions SET last_seen_at = datetime('now') WHERE id = ?", resolved.session.id);
    }
  } else {
    req.user = null;
    req.session = null;
    req.authVia = null;
  }
  next();
}

/* ==========================================================================
   Guards
   ========================================================================== */

function requireAuth(req, res, next) {
  if (!req.user) return res.status(401).json({ error: 'Sign in to continue.' });
  next();
}

/** Rejects the request unless the caller holds one of `roles`. */
function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user) return res.status(401).json({ error: 'Sign in to continue.' });
    if (!roles.includes(req.user.role)) {
      return res.status(403).json({ error: 'Your account cannot perform this action.' });
    }
    next();
  };
}

const isManager = (user) => user?.role === 'manager';

/**
 * A manager who has not yet enrolled a second factor holds a deliberately
 * crippled session: it exists only so they can complete enrolment. Everything
 * the manager console can actually do is gated behind this being false.
 */
function mustEnrolTwoFactor(user) {
  return Boolean(
    user && user.role === 'manager' && !user.totp_enabled && config.requireManagerTwoFactor
  );
}

/** Blocks manager work until the second factor is in place. */
function requireEnrolledTwoFactor(req, res, next) {
  if (mustEnrolTwoFactor(req.user)) {
    return res.status(403).json({
      error:
        'Set up two-factor authentication before using the manager console. It is mandatory for manager accounts.',
      code: 'ENROL_2FA',
    });
  }
  next();
}

/* ==========================================================================
   CSRF
   ========================================================================== */

const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

/**
 * Reject cookie-authenticated state changes that do not echo the session's
 * CSRF token.
 *
 * SameSite=Strict already blocks the classic cross-site form post; this is the
 * belt to that braces, and covers browsers or proxies that mishandle SameSite.
 * Bearer-authenticated calls are exempt: the browser never attaches that
 * header on its own, so there is nothing to forge.
 */
function csrfProtection(req, res, next) {
  if (SAFE_METHODS.has(req.method)) return next();
  if (req.authVia !== 'cookie') return next();
  if (!req.session) return next();

  const submitted = req.headers['x-csrf-token'];
  if (!submitted || !safeEqual(submitted, req.session.csrf_token)) {
    return res.status(403).json({
      error: 'Security check failed. Refresh the page and try again.',
      code: 'CSRF',
    });
  }
  next();
}

/** Public shape of a user — never leaks hashes, secrets or lock state. */
function publicUser(user) {
  if (!user) return null;
  return {
    id: user.id,
    role: user.role,
    fullName: user.full_name,
    email: user.email,
    phone: user.phone,
    rating: user.rating_count > 0 ? Number((user.rating_sum / user.rating_count).toFixed(2)) : null,
    ratingCount: user.rating_count,
    twoFactorEnabled: Boolean(user.totp_enabled),
    mustEnrolTwoFactor: mustEnrolTwoFactor(user),
    mustChangePassword: Boolean(user.must_change_password),
    createdAt: user.created_at,
  };
}

module.exports = {
  hashPassword,
  verifyPassword,
  fakePasswordCheck,
  createSession,
  revokeSession,
  revokeAllSessions,
  listSessions,
  resolveToken,
  tokenFromRequest,
  attachUser,
  requireAuth,
  requireRole,
  isManager,
  mustEnrolTwoFactor,
  requireEnrolledTwoFactor,
  csrfProtection,
  publicUser,
  ttlMs,
};
