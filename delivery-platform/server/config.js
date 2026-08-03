'use strict';

const fs = require('node:fs');
const path = require('node:path');

// Minimal .env loader so the project stays dependency-light. Values already
// present in the real environment always win over the file.
function loadEnvFile(file) {
  if (!fs.existsSync(file)) return;
  for (const rawLine of fs.readFileSync(file, 'utf8').split('\n')) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq === -1) continue;
    const key = line.slice(0, eq).trim();
    let value = line.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (!(key in process.env)) process.env[key] = value;
  }
}

const rootDir = path.resolve(__dirname, '..');
loadEnvFile(path.join(rootDir, '.env'));

const isProduction = process.env.NODE_ENV === 'production';
const jwtSecret = process.env.JWT_SECRET;

if (isProduction && (!jwtSecret || jwtSecret.length < 32)) {
  throw new Error(
    'JWT_SECRET must be set to a random string of at least 32 characters in production.'
  );
}

if (!jwtSecret) {
  console.warn(
    '[config] JWT_SECRET is not set — using an ephemeral development key. ' +
      'All sessions will be invalidated on restart.'
  );
}

const config = {
  rootDir,
  port: Number(process.env.PORT || 3000),
  isProduction,
  // A random per-boot key keeps development safe-by-default: nobody can forge a
  // token against a checked-in placeholder secret.
  jwtSecret: jwtSecret || require('node:crypto').randomBytes(48).toString('hex'),
  tokenTtl: process.env.TOKEN_TTL || '7d',
  dbFile: path.resolve(rootDir, process.env.DB_FILE || './data/haulr.db'),
  currency: {
    code: process.env.CURRENCY_CODE || 'ZAR',
    symbol: process.env.CURRENCY_SYMBOL || 'R',
  },
  dispatchRadiusKm: Number(process.env.DISPATCH_RADIUS_KM || 25),
  // An on-duty operator whose device has not reported a position in this long
  // is hidden from the nearby-vehicle maps. On-duty devices ping every ~30s,
  // so this tolerates a long run of missed fixes (tunnels, backgrounded app)
  // before we stop showing a stale position to customers.
  operatorStaleAfterMs: Number(process.env.OPERATOR_STALE_MINUTES || 10) * 60 * 1000,
};

module.exports = config;
