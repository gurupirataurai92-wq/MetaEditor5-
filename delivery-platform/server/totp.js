'use strict';

// RFC 6238 TOTP, implemented on node:crypto so privileged accounts can be
// protected with any standard authenticator app (Google Authenticator, Aegis,
// 1Password, …) without adding a dependency.

const crypto = require('node:crypto');

const STEP_SECONDS = 30;
const DIGITS = 6;
// Accept one step either side to tolerate clock drift between the server and
// the phone. Wider than ±1 materially weakens the factor.
const DRIFT_STEPS = 1;

const BASE32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

function base32Encode(buffer) {
  let bits = 0;
  let value = 0;
  let output = '';
  for (const byte of buffer) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      output += BASE32_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) output += BASE32_ALPHABET[(value << (5 - bits)) & 31];
  return output;
}

function base32Decode(input) {
  const clean = String(input).toUpperCase().replace(/=+$/, '').replace(/\s/g, '');
  let bits = 0;
  let value = 0;
  const bytes = [];
  for (const char of clean) {
    const index = BASE32_ALPHABET.indexOf(char);
    if (index === -1) throw new Error('Invalid base32 character in secret.');
    value = (value << 5) | index;
    bits += 5;
    if (bits >= 8) {
      bytes.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Buffer.from(bytes);
}

/** A fresh 160-bit secret, base32-encoded for authenticator apps. */
function generateSecret() {
  return base32Encode(crypto.randomBytes(20));
}

function codeForCounter(secretBase32, counter) {
  const key = base32Decode(secretBase32);
  const buf = Buffer.alloc(8);
  buf.writeBigUInt64BE(BigInt(counter));

  const digest = crypto.createHmac('sha1', key).update(buf).digest();
  const offset = digest[digest.length - 1] & 0x0f;
  const binary =
    ((digest[offset] & 0x7f) << 24) |
    ((digest[offset + 1] & 0xff) << 16) |
    ((digest[offset + 2] & 0xff) << 8) |
    (digest[offset + 3] & 0xff);

  return String(binary % 10 ** DIGITS).padStart(DIGITS, '0');
}

/** The code an authenticator would be showing right now. */
function currentCode(secretBase32, at = Date.now()) {
  return codeForCounter(secretBase32, Math.floor(at / 1000 / STEP_SECONDS));
}

/**
 * Verify a submitted code, allowing for clock drift.
 *
 * Returns the matching counter (so the caller can store it and refuse a
 * replay of the same code) or null.
 */
function verify(secretBase32, submitted, { at = Date.now(), lastUsedCounter = null } = {}) {
  const code = String(submitted ?? '').replace(/\D/g, '');
  if (code.length !== DIGITS) return null;

  const current = Math.floor(at / 1000 / STEP_SECONDS);

  for (let drift = -DRIFT_STEPS; drift <= DRIFT_STEPS; drift += 1) {
    const counter = current + drift;
    // A code is single-use: replaying one an attacker shoulder-surfed or
    // captured within its 30-second window must fail.
    if (lastUsedCounter != null && counter <= lastUsedCounter) continue;

    const expected = codeForCounter(secretBase32, counter);
    if (crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(code))) {
      return counter;
    }
  }
  return null;
}

/** `otpauth://` URI — what an authenticator app's QR code encodes. */
function provisioningUri(secretBase32, { account, issuer = 'Haulr' }) {
  const label = encodeURIComponent(`${issuer}:${account}`);
  const params = new URLSearchParams({
    secret: secretBase32,
    issuer,
    algorithm: 'SHA1',
    digits: String(DIGITS),
    period: String(STEP_SECONDS),
  });
  return `otpauth://totp/${label}?${params}`;
}

/**
 * Single-use recovery codes for when the authenticator device is lost.
 * Only the hashes are stored, so a database read cannot be replayed as a login.
 */
function generateRecoveryCodes(count = 8) {
  const codes = [];
  for (let i = 0; i < count; i += 1) {
    const raw = crypto.randomBytes(5).toString('hex').toUpperCase();
    codes.push(`${raw.slice(0, 5)}-${raw.slice(5)}`);
  }
  return codes;
}

const hashRecoveryCode = (code) =>
  crypto.createHash('sha256').update(String(code).toUpperCase().replace(/\s/g, '')).digest('hex');

module.exports = {
  generateSecret,
  currentCode,
  verify,
  provisioningUri,
  generateRecoveryCodes,
  hashRecoveryCode,
  STEP_SECONDS,
  DIGITS,
};
