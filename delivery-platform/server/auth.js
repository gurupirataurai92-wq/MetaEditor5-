'use strict';

const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const config = require('./config');
const { get } = require('./db');

const BCRYPT_ROUNDS = 12;

function hashPassword(plain) {
  return bcrypt.hash(plain, BCRYPT_ROUNDS);
}

function verifyPassword(plain, hash) {
  return bcrypt.compare(plain, hash);
}

function issueToken(user) {
  return jwt.sign({ sub: String(user.id), role: user.role }, config.jwtSecret, {
    expiresIn: config.tokenTtl,
  });
}

/** Decode a token and load the live user row. Returns null when invalid. */
function userFromToken(token) {
  if (!token) return null;
  let payload;
  try {
    payload = jwt.verify(token, config.jwtSecret);
  } catch {
    return null;
  }
  const user = get(
    `SELECT id, role, full_name, email, phone, rating_sum, rating_count,
            is_suspended, created_at
       FROM users WHERE id = ?`,
    Number(payload.sub)
  );
  if (!user || user.is_suspended) return null;
  return user;
}

function tokenFromRequest(req) {
  const header = req.headers.authorization;
  if (header && header.startsWith('Bearer ')) return header.slice(7).trim();
  return null;
}

/** Populates `req.user` when a valid token is present; never rejects. */
function attachUser(req, _res, next) {
  req.user = userFromToken(tokenFromRequest(req));
  next();
}

/** Rejects the request unless a valid token is present. */
function requireAuth(req, res, next) {
  if (!req.user) {
    return res.status(401).json({ error: 'Sign in to continue.' });
  }
  next();
}

/** Rejects the request unless the caller holds one of `roles`. */
function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ error: 'Sign in to continue.' });
    }
    if (!roles.includes(req.user.role)) {
      return res
        .status(403)
        .json({ error: `This action is only available to ${roles.join(' or ')} accounts.` });
    }
    next();
  };
}

/** Public shape of a user — never leaks the password hash. */
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
    createdAt: user.created_at,
  };
}

module.exports = {
  hashPassword,
  verifyPassword,
  issueToken,
  userFromToken,
  tokenFromRequest,
  attachUser,
  requireAuth,
  requireRole,
  publicUser,
};
