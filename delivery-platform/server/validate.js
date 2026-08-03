'use strict';

/** Thrown by the helpers below; turned into a 400 by the error middleware. */
class ValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ValidationError';
    this.status = 400;
  }
}

function str(value, field, { min = 1, max = 500, required = true } = {}) {
  if (value === undefined || value === null || value === '') {
    if (required) throw new ValidationError(`${field} is required.`);
    return null;
  }
  const s = String(value).trim();
  if (s.length < min) throw new ValidationError(`${field} must be at least ${min} characters.`);
  if (s.length > max) throw new ValidationError(`${field} must be at most ${max} characters.`);
  return s;
}

function num(value, field, { min = -Infinity, max = Infinity, required = true, integer = false } = {}) {
  if (value === undefined || value === null || value === '') {
    if (required) throw new ValidationError(`${field} is required.`);
    return null;
  }
  const n = Number(value);
  if (!Number.isFinite(n)) throw new ValidationError(`${field} must be a number.`);
  if (integer && !Number.isInteger(n)) throw new ValidationError(`${field} must be a whole number.`);
  if (n < min) throw new ValidationError(`${field} must be at least ${min}.`);
  if (n > max) throw new ValidationError(`${field} must be at most ${max}.`);
  return n;
}

function bool(value) {
  return value === true || value === 'true' || value === 1 || value === '1';
}

function oneOf(value, field, allowed) {
  const s = String(value ?? '').trim();
  if (!allowed.includes(s)) {
    throw new ValidationError(`${field} must be one of: ${allowed.join(', ')}.`);
  }
  return s;
}

function latitude(value, field = 'Latitude') {
  return num(value, field, { min: -90, max: 90 });
}

function longitude(value, field = 'Longitude') {
  return num(value, field, { min: -180, max: 180 });
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

function email(value) {
  const s = str(value, 'Email', { max: 254 }).toLowerCase();
  if (!EMAIL_RE.test(s)) throw new ValidationError('Enter a valid email address.');
  return s;
}

// Deliberately permissive: international formats vary wildly and an
// over-strict rule blocks real customers.
const PHONE_RE = /^\+?[0-9][0-9\s\-().]{6,19}$/;

function phone(value) {
  const s = str(value, 'Phone number', { max: 24 });
  if (!PHONE_RE.test(s)) throw new ValidationError('Enter a valid phone number.');
  return s;
}

function password(value) {
  const s = String(value ?? '');
  if (s.length < 8) throw new ValidationError('Password must be at least 8 characters.');
  if (s.length > 200) throw new ValidationError('Password must be at most 200 characters.');
  if (!/[a-zA-Z]/.test(s) || !/[0-9]/.test(s)) {
    throw new ValidationError('Password must contain at least one letter and one number.');
  }
  return s;
}

module.exports = {
  ValidationError,
  str,
  num,
  bool,
  oneOf,
  latitude,
  longitude,
  email,
  phone,
  password,
};
