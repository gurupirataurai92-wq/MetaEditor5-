'use strict';

const http = require('node:http');
const path = require('node:path');
const express = require('express');

const config = require('./config');
const { attachUser, csrfProtection } = require('./auth');
const realtime = require('./realtime');
const domain = require('./domain');
const { ValidationError } = require('./validate');
const { migrate } = require('./migrate');
const { RateLimiter, limit } = require('./security');

const authRoutes = require('./routes/auth.routes');
const tripRoutes = require('./routes/trips.routes');
const offerRoutes = require('./routes/offers.routes');
const operatorRoutes = require('./routes/operator.routes');
const trackingRoutes = require('./routes/tracking.routes');
const managerRoutes = require('./routes/manager.routes');

// Bring an older database up to the current schema before serving anything.
migrate({ quiet: true });

const app = express();

app.disable('x-powered-by');
// Only trust the single proxy we expect to sit in front of us. A larger number
// (or `true`) lets a client forge X-Forwarded-For and defeat rate limiting by
// pretending to be a new address on every request.
app.set('trust proxy', 1);

// Redirect to HTTPS in production. Cookies are marked Secure there, so a plain
// HTTP request would otherwise arrive with no session and look like a bug.
if (config.isProduction) {
  app.use((req, res, next) => {
    if (req.secure || req.headers['x-forwarded-proto'] === 'https') return next();
    return res.redirect(308, `https://${req.headers.host}${req.originalUrl}`);
  });
}

app.use(express.json({ limit: '128kb' }));

// A broad ceiling on API traffic. Individual endpoints that are worth
// attacking (login, register, manager creation) carry their own tighter
// limits closer to the logic they protect.
const apiLimiter = new RateLimiter({ windowMs: 60_000, max: 300, name: 'api' });
app.use('/api', limit(apiLimiter));

// Baseline hardening. Leaflet is vendored under /vendor, so no third-party
// scripts are permitted at all. The only outbound reach is to OpenStreetMap
// for map tiles and to Nominatim for address lookup.
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('Permissions-Policy', 'geolocation=(self), camera=(), microphone=(), payment=()');
  // Keep this origin out of other pages' process and stop cross-origin reads
  // of our responses, which blunts speculative-execution side channels.
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
  res.setHeader('X-DNS-Prefetch-Control', 'off');

  if (config.isProduction) {
    res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains; preload');
  }

  // Never let a browser or proxy cache an authenticated API response — a
  // shared cache serving one user's job list to the next would be severe.
  if (req.path.startsWith('/api')) {
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, private');
    res.setHeader('Pragma', 'no-cache');
  }

  res.setHeader(
    'Content-Security-Policy',
    [
      "default-src 'self'",
      // Leaflet is vendored locally, so no third-party script is ever allowed.
      "script-src 'self'",
      // Styles come from our stylesheet; 'unsafe-inline' remains only for the
      // inline style attributes in the markup. It cannot execute script.
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data: blob: https://*.tile.openstreetmap.org",
      "connect-src 'self' ws: wss: https://nominatim.openstreetmap.org",
      "font-src 'self' data:",
      "object-src 'none'",
      "base-uri 'self'",
      "form-action 'self'",
      "frame-ancestors 'none'",
      ...(config.isProduction ? ['upgrade-insecure-requests'] : []),
    ].join('; ')
  );
  next();
});

app.use(attachUser);
// Applies to cookie-authenticated state changes only; bearer callers are
// exempt because a browser never attaches that header on its own.
app.use(csrfProtection);

/** GET /api/meta — catalogue + pricing constants the UI renders from. */
app.get('/api/meta', (_req, res) => {
  res.json({
    currency: config.currency,
    vehicleClasses: domain.VEHICLE_CLASSES,
    categories: domain.CATEGORIES,
    paymentMethods: domain.PAYMENT_METHODS,
    statusLabels: domain.STATUS_LABELS,
    helperFeePerPerson: domain.HELPER_FEE_PER_PERSON,
    floorFee: domain.FLOOR_FEE,
    dispatchRadiusKm: config.dispatchRadiusKm,
  });
});

app.get('/api/health', (_req, res) => {
  res.json({ ok: true, uptimeSeconds: Math.round(process.uptime()) });
});

app.use('/api/auth', authRoutes);
app.use('/api', tripRoutes);
app.use('/api', offerRoutes);
app.use('/api', operatorRoutes);
app.use('/api', trackingRoutes);
app.use('/api', managerRoutes);

app.use('/api', (_req, res) => res.status(404).json({ error: 'No such endpoint.' }));

app.use(
  express.static(path.join(config.rootDir, 'public'), {
    extensions: ['html'],
    maxAge: config.isProduction ? '1h' : 0,
  })
);

// Anything else is a page request — let the static index handle it.
app.use((req, res) => {
  res.status(404).sendFile(path.join(config.rootDir, 'public', '404.html'), (err) => {
    if (err) res.status(404).type('txt').send('Not found');
  });
});

// eslint-disable-next-line no-unused-vars -- Express identifies error handlers by arity
app.use((err, _req, res, _next) => {
  // Body-parser failures also carry status 400, so they must be matched first
  // — otherwise the raw parser message leaks out as if it were our own.
  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({ error: 'Request body is not valid JSON.' });
  }
  if (err.type === 'entity.too.large') {
    return res.status(413).json({ error: 'Request body is too large.' });
  }
  if (err instanceof ValidationError) {
    return res.status(400).json({ error: err.message });
  }
  console.error('[error]', err);
  res.status(500).json({ error: 'Something went wrong on our side.' });
});

const server = http.createServer(app);
realtime.attach(server);

if (require.main === module) {
  server.listen(config.port, () => {
    console.log(`Haulr listening on http://localhost:${config.port}`);
    console.log(`  database: ${config.dbFile}`);
    console.log(`  currency: ${config.currency.symbol} (${config.currency.code})`);
  });

  for (const signal of ['SIGINT', 'SIGTERM']) {
    process.on(signal, () => {
      console.log(`\n${signal} received, shutting down.`);
      server.close(() => process.exit(0));
      setTimeout(() => process.exit(0), 5000).unref();
    });
  }
}

module.exports = { app, server };
