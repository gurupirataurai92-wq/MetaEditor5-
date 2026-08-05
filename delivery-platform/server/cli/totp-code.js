'use strict';

// Prints the authenticator code an account's second factor is currently
// showing, so the seeded demo can be explored without setting up a phone.
//
//   npm run totp-code manager@example.com
//
// Refuses to run in production: being able to mint a valid second factor from
// a shell would make the second factor meaningless.

const { get } = require('../db');
const config = require('../config');
const totp = require('../totp');

if (config.isProduction) {
  console.error('totp-code is a development helper and is disabled in production.');
  process.exit(1);
}

const email = (process.argv[2] || '').toLowerCase();
if (!email) {
  console.error('Usage: npm run totp-code <email>');
  process.exit(1);
}

const user = get('SELECT email, totp_secret, totp_enabled FROM users WHERE email = ?', email);
if (!user) {
  console.error(`No account found for ${email}.`);
  process.exit(1);
}
if (!user.totp_secret) {
  console.error(`${email} has no second factor set up.`);
  process.exit(1);
}

const code = totp.currentCode(user.totp_secret);
const secondsLeft = totp.STEP_SECONDS - (Math.floor(Date.now() / 1000) % totp.STEP_SECONDS);

console.log(`\n  ${code}\n`);
console.log(`  valid for another ${secondsLeft}s${user.totp_enabled ? '' : '  (2FA not yet enabled on this account)'}`);
