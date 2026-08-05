'use strict';

const crypto = require('node:crypto');
const config = require('./config');

/* ==========================================================================
   Cookies
   ========================================================================== */

const SESSION_COOKIE = 'haulr_session';
const CSRF_COOKIE = 'haulr_csrf';

/**
 * Minimal Cookie header parser. Values are percent-decoded; malformed pairs
 * are skipped rather than throwing, because a hostile client controls this
 * header entirely.
 */
function parseCookies(req) {
  const header = req.headers.cookie;
  if (!header) return {};
  const out = Object.create(null);
  for (const part of header.split(';')) {
    const eq = part.indexOf('=');
    if (eq === -1) continue;
    const key = part.slice(0, eq).trim();
    if (!key) continue;
    const raw = part.slice(eq + 1).trim();
    try {
      out[key] = decodeURIComponent(raw);
    } catch {
      out[key] = raw;
    }
  }
  return out;
}

function baseCookieOptions() {
  return {
    // `Secure` is meaningless over plain HTTP and would break local
    // development, so it tracks the deployment mode.
    secure: config.isProduction,
    sameSite: 'strict',
    path: '/',
  };
}

/**
 * The session token lives in an httpOnly cookie. This is the single most
 * valuable hardening step in the app: script running on the page — injected
 * or third-party — cannot read the token, so an XSS bug can no longer be
 * escalated into a stolen, portable session.
 */
function setSessionCookie(res, token, maxAgeMs) {
  res.cookie(SESSION_COOKIE, token, {
    ...baseCookieOptions(),
    httpOnly: true,
    maxAge: maxAgeMs,
  });
}

/**
 * The CSRF token is deliberately readable by our own scripts — the browser
 * must be able to echo it back in a header. It is worthless on its own: it
 * only proves the caller can read a same-origin cookie.
 */
function setCsrfCookie(res, csrfToken, maxAgeMs) {
  res.cookie(CSRF_COOKIE, csrfToken, {
    ...baseCookieOptions(),
    httpOnly: false,
    maxAge: maxAgeMs,
  });
}

function clearAuthCookies(res) {
  const options = { ...baseCookieOptions() };
  res.clearCookie(SESSION_COOKIE, { ...options, httpOnly: true });
  res.clearCookie(CSRF_COOKIE, options);
}

/* ==========================================================================
   Constant-time comparison
   ========================================================================== */

/** Compare two strings without leaking their contents through timing. */
function safeEqual(a, b) {
  const left = Buffer.from(String(a ?? ''), 'utf8');
  const right = Buffer.from(String(b ?? ''), 'utf8');
  // timingSafeEqual throws on length mismatch, which would itself be a leak,
  // so hash both sides to a fixed width first.
  const leftHash = crypto.createHash('sha256').update(left).digest();
  const rightHash = crypto.createHash('sha256').update(right).digest();
  return crypto.timingSafeEqual(leftHash, rightHash);
}

const randomToken = (bytes = 32) => crypto.randomBytes(bytes).toString('base64url');

/* ==========================================================================
   Rate limiting
   ========================================================================== */

/**
 * Sliding-window counter held in memory.
 *
 * Deliberately process-local: it needs no infrastructure and blunts the
 * attacks that matter here (credential stuffing, scripted enumeration). A
 * multi-instance deployment behind a load balancer should move this to Redis
 * — noted in the README, because a per-process limiter divides the effective
 * limit by the number of instances rather than failing loudly.
 */
class RateLimiter {
  constructor({ windowMs, max, name }) {
    this.windowMs = windowMs;
    this.max = max;
    this.name = name;
    this.hits = new Map();

    // Drop expired buckets so a long-running process cannot be pushed into
    // unbounded memory growth by rotating source addresses.
    this.sweep = setInterval(() => this.prune(), Math.min(windowMs, 60_000));
    this.sweep.unref?.();
  }

  prune() {
    const cutoff = Date.now() - this.windowMs;
    for (const [key, stamps] of this.hits) {
      const kept = stamps.filter((t) => t > cutoff);
      if (kept.length) this.hits.set(key, kept);
      else this.hits.delete(key);
    }
  }

  /** Returns `{ allowed, remaining, retryAfterSeconds }`. */
  check(key) {
    const now = Date.now();
    const cutoff = now - this.windowMs;
    const stamps = (this.hits.get(key) || []).filter((t) => t > cutoff);

    if (stamps.length >= this.max) {
      const retryAfterSeconds = Math.max(1, Math.ceil((stamps[0] + this.windowMs - now) / 1000));
      this.hits.set(key, stamps);
      return { allowed: false, remaining: 0, retryAfterSeconds };
    }

    stamps.push(now);
    this.hits.set(key, stamps);
    return { allowed: true, remaining: this.max - stamps.length, retryAfterSeconds: 0 };
  }

  reset(key) {
    this.hits.delete(key);
  }
}

/**
 * Identify the caller for rate-limiting purposes.
 *
 * `req.ip` already honours `trust proxy`. Never trust a raw X-Forwarded-For
 * here: an attacker would just rotate the header to reset their own bucket.
 */
const clientKey = (req) => req.ip || req.socket?.remoteAddress || 'unknown';

/** Build an Express middleware from a limiter. */
function limit(limiter, { keyFn = clientKey, message } = {}) {
  return (req, res, next) => {
    const { allowed, retryAfterSeconds } = limiter.check(keyFn(req));
    if (allowed) return next();

    res.setHeader('Retry-After', String(retryAfterSeconds));
    res.status(429).json({
      error: message || 'Too many requests. Slow down and try again shortly.',
      retryAfterSeconds,
    });
  };
}

/* ==========================================================================
   Password policy
   ========================================================================== */

// The passwords that actually appear at the top of breach corpora. A short
// exact-match list catches the overwhelming majority of hopeless choices
// without shipping a megabyte of wordlist.
const COMMON_PASSWORDS = new Set([
  'password', 'password1', 'password123', 'passw0rd', '12345678', '123456789',
  '1234567890', 'qwerty123', 'qwertyuiop', 'letmein1', 'welcome1', 'welcome123',
  'admin123', 'administrator', 'iloveyou1', 'sunshine1', 'princess1', 'football1',
  'monkey123', 'abc12345', 'trustno1', 'dragon123', 'baseball1', 'superman1',
  'michael1', 'shadow123', 'master123', 'jennifer1', 'jordan23', 'harley123',
  'changeme', 'changeme1', 'secret123', 'whatever1', 'starwars1', 'computer1',
  'zaq12wsx', '1qaz2wsx', 'qazwsxedc', 'asdfghjkl', 'zxcvbnm1', 'p@ssword',
  'p@ssw0rd', 'haulr1234',
]);

const MIN_PASSWORD_LENGTH = 12;

/**
 * Reject passwords that are short, obvious, or trivially derived from the
 * account's own details. Returns an array of problems (empty means fine).
 */
function passwordProblems(password, { email = '', fullName = '' } = {}) {
  const value = String(password ?? '');
  const problems = [];

  if (value.length < MIN_PASSWORD_LENGTH) {
    problems.push(`be at least ${MIN_PASSWORD_LENGTH} characters`);
  }
  if (value.length > 200) problems.push('be no longer than 200 characters');

  const classes = [/[a-z]/, /[A-Z]/, /[0-9]/, /[^A-Za-z0-9]/].filter((re) => re.test(value)).length;
  if (classes < 3) {
    problems.push('mix at least three of: lowercase, uppercase, numbers, symbols');
  }

  const lower = value.toLowerCase();
  if (COMMON_PASSWORDS.has(lower)) problems.push('not be a commonly used password');

  // A single repeated character or a straight run is long but worthless.
  if (/^(.)\1+$/.test(value)) problems.push('not be a single repeated character');
  if (/^(?:0123456789|1234567890|abcdefghijkl|qwertyuiopas)/.test(lower)) {
    problems.push('not be a keyboard or counting sequence');
  }

  const localPart = String(email).split('@')[0]?.toLowerCase();
  if (localPart && localPart.length >= 4 && lower.includes(localPart)) {
    problems.push('not contain your email address');
  }
  for (const namePart of String(fullName).toLowerCase().split(/\s+/)) {
    if (namePart.length >= 4 && lower.includes(namePart)) {
      problems.push('not contain your name');
      break;
    }
  }

  return [...new Set(problems)];
}

function describePasswordPolicy() {
  return `At least ${MIN_PASSWORD_LENGTH} characters, mixing at least three of lowercase, uppercase, numbers and symbols. It must not be a common password or contain your name or email.`;
}

module.exports = {
  SESSION_COOKIE,
  CSRF_COOKIE,
  parseCookies,
  setSessionCookie,
  setCsrfCookie,
  clearAuthCookies,
  safeEqual,
  randomToken,
  RateLimiter,
  limit,
  clientKey,
  passwordProblems,
  describePasswordPolicy,
  MIN_PASSWORD_LENGTH,
};
