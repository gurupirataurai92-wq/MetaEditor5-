'use strict';

const http = require('node:http');
const path = require('node:path');
const express = require('express');

const config = require('./config');
const { attachUser } = require('./auth');
const realtime = require('./realtime');
const domain = require('./domain');
const { ValidationError } = require('./validate');

const authRoutes = require('./routes/auth.routes');
const tripRoutes = require('./routes/trips.routes');
const offerRoutes = require('./routes/offers.routes');
const operatorRoutes = require('./routes/operator.routes');
const trackingRoutes = require('./routes/tracking.routes');

const app = express();

app.disable('x-powered-by');
app.set('trust proxy', 1);

app.use(express.json({ limit: '256kb' }));

// Baseline hardening. Leaflet is vendored under /vendor, so no third-party
// scripts are permitted at all. The only outbound reach is to OpenStreetMap
// for map tiles and to Nominatim for address lookup.
app.use((_req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('Permissions-Policy', 'geolocation=(self), camera=(), microphone=()');
  res.setHeader(
    'Content-Security-Policy',
    [
      "default-src 'self'",
      "script-src 'self'",
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data: blob: https://*.tile.openstreetmap.org",
      "connect-src 'self' ws: wss: https://nominatim.openstreetmap.org",
      "font-src 'self' data:",
      "object-src 'none'",
      "base-uri 'self'",
      "frame-ancestors 'none'",
    ].join('; ')
  );
  next();
});

app.use(attachUser);

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
