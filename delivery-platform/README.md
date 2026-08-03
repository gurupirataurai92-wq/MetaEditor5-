# Haulr — an on-demand delivery & moving marketplace

Customers post what they need moved and **name the price they want to pay**.
Nearby operators accept that price or counter with their own. The customer picks
one, then watches the vehicle move on a live map from pickup to door.

Anything from an envelope on a motorbike to a full house move on an 8-ton truck.

```
customer posts a job  →  operators bid  →  customer picks  →  live GPS  →  delivered  →  both rate
```

---

## Quick start

```bash
cd delivery-platform
npm install
npm run seed      # demo accounts, open jobs, a job already on the road
npm start         # http://localhost:3000
```

Sign in with any seeded account — the password for all of them is `haulr1234`:

| Role     | Email                | Notes                                     |
| -------- | -------------------- | ----------------------------------------- |
| Customer | `thandi@example.com` | Has open jobs with offers waiting         |
| Customer | `aisha@example.com`  | Quieter account, good for posting new jobs |
| Operator | `nomsa@example.com`  | Pickup / bakkie — can take furniture jobs |
| Operator | `ahmed@example.com`  | 4-ton truck — can take house moves        |
| Operator | `sipho@example.com`  | Motorbike — parcels only                  |

The landing page has one-click buttons for the first three.

> **Seeing the demo properly:** open a customer in one browser window and an
> operator in another (use a private window so the two sessions do not share
> `localStorage`). Post a job as the customer and watch the offer arrive on the
> customer's screen without a refresh.

### Other commands

```bash
npm run dev     # auto-restart on file changes
npm run reset   # delete the database and re-seed from scratch
```

---

## What is built

### Accounts

- **Customers** register with name, email, phone and password.
- **Operators** additionally register a vehicle: class, make/model, number
  plate, payload capacity, how many helpers they can bring, and a licence
  number.
- Passwords are hashed with bcrypt (12 rounds). Sessions are JWTs.
- Both sides rate each other after every job; ratings ride along on every offer.

### Posting a job

A map-driven booking flow: drop pins (or search an address), pick a vehicle
class, describe the load, set floors and lift availability, add helpers, and
name your price. A live price guide breaks down base fare, distance, helpers and
stairs, and shows the band operators usually bid within.

The server refuses jobs that don't add up — 1,200 kg on a motorbike, or three
helpers on a vehicle that seats one.

### Bidding (the inDrive-style part)

Open jobs land on a board that every on-duty operator sees, **filtered to what
their vehicle can actually carry** and sorted by distance to the pickup. An
operator can take the customer's price in one tap, or counter with their own
price, ETA and a message. Customers see every bid side by side — price, ETA,
rating, vehicle, jobs completed — and pick one.

Accepting is a guarded transaction: two operators can never both win a job.

### Live GPS tracking

Once assigned, the operator taps **Start live location**. Their device streams
GPS fixes to the server, which:

- persists a breadcrumb trail (throttled — only when the vehicle has actually
  moved 25 m or 15 s have passed, so a two-hour job doesn't write 20,000 rows),
- recalculates distance remaining and an ETA from the vehicle's real speed,
- pushes the fix over WebSocket to everyone watching the job.

The customer's map shows the vehicle moving with the travelled path drawn behind
it, a live ETA, and how long ago the last fix arrived.

The GPS feed is built to survive real driving: a lost signal in a tunnel or a
basement shows "Searching for signal" and **keeps the watch alive**, recovering
on its own when fixes resume. Only a refused location permission stops it.

### Also included

- **In-job chat** between customer and operator.
- **Job timeline** — every state change, offer and cancellation, timestamped.
- **Status flow** the operator walks forward: on the way → arrived → loaded →
  delivered. Illegal jumps are rejected server-side.
- **Cancel / release** — customers cancel up until the goods are loaded;
  operators release a job back onto the open board.
- **Operator dashboard** — earnings this week and all time, active jobs, open
  offers, rating.
- **Nearby vehicles** on the booking map so customers can see who is around.

---

## Privacy decisions worth knowing

- **Phone numbers are exchanged only after a job is assigned.** An operator
  browsing the open board never sees a customer's number, and vice versa.
- **The public landing map does not show real vehicle positions.** Positions are
  snapped to a ~1.1 km grid and de-duplicated server-side before they leave the
  process, so a signed-out visitor can see the service is busy without being
  able to follow an individual operator.
- **The signed-in "vehicles near you" map is anonymised** — opaque per-vehicle
  keys, no names, no plates.
- A job is only visible to its two parties, plus operators while it is still
  open for bidding.

---

## Architecture

```
server/
  index.js              Express app, security headers, static hosting
  config.js             env loading and defaults
  db.js                 SQLite schema (node:sqlite) + query helpers
  domain.js             vehicle classes, categories, pricing, geo maths
  auth.js               bcrypt, JWT, route guards
  realtime.js           WebSocket hub (channels: trip / user / dispatch)
  validate.js           input validation
  serialize.js          API response shapes (contact-detail gating lives here)
  seed.js               demo data
  routes/
    auth.routes.js      register, login, profile, password
    trips.routes.js     post, list, status, cancel, rate, timeline, chat
    offers.routes.js    bid, list, accept, withdraw
    operator.routes.js  duty, jobs board, stats, nearby vehicles
    tracking.routes.js  GPS ingest and the tracking payload
public/
  index.html            landing page
  auth.html             sign in / register
  request.html          booking flow
  customer.html         customer dashboard
  operator.html         operator console
  track.html            live tracking (serves both sides of a job)
  js/                   app.js (session/API/realtime), map.js, per-page scripts
  vendor/leaflet/       Leaflet, vendored — no CDN dependency
```

**Stack:** Node 22+, Express 5, `node:sqlite` (built in — no native build step),
`ws`, bcryptjs, jsonwebtoken. The front end is plain HTML/CSS/JS with Leaflet —
no build step anywhere.

**Maps:** Leaflet is served from `public/vendor/`, so the app has no third-party
script dependency and the Content-Security-Policy blocks external scripts
entirely. Map tiles come from OpenStreetMap and address search from Nominatim;
if either is unreachable the app still works — pins, tracking and pricing are
all computed locally, and address lookup falls back to coordinates.

### Realtime protocol

Clients connect to `/ws?token=<jwt>` and subscribe to a job:

```jsonc
// client → server
{ "type": "subscribe", "tripId": 42 }

// server → client
{ "type": "location_update", "tripId": 42, "position": {...},
  "remainingKm": 4.8, "etaMinutes": 9 }
{ "type": "trip_update",  "tripId": 42, "trip": {...} }
{ "type": "offer_new",    "tripId": 42, "offer": {...} }
{ "type": "message",      "tripId": 42, "message": {...} }
```

Subscriptions are authorisation-checked against the database, replayed
automatically after a reconnect, and dead sockets are reaped by a heartbeat.

---

## Configuration

Copy `.env.example` to `.env`. Every value has a working development default.

| Variable                 | Default            | Purpose                                    |
| ------------------------ | ------------------ | ------------------------------------------ |
| `PORT`                   | `3000`             | HTTP port                                  |
| `JWT_SECRET`             | random per boot    | Token signing key                          |
| `TOKEN_TTL`              | `7d`               | Session lifetime                           |
| `DB_FILE`                | `./data/haulr.db`  | SQLite location                            |
| `CURRENCY_CODE` / `_SYMBOL` | `ZAR` / `R`     | Currency shown throughout the UI           |
| `DISPATCH_RADIUS_KM`     | `25`               | Default jobs-board radius                  |
| `OPERATOR_STALE_MINUTES` | `10`               | When a quiet operator drops off the maps   |

Pricing (base fares, per-km rates, helper and stair fees) and the vehicle
catalogue live in `server/domain.js` — that is the single source of truth, and
the browser reads the same values from `GET /api/meta`, so the two cannot drift.

The demo data is centred on Johannesburg. To move it, change `CITY` at the top
of `server/seed.js`.

---

## Before running this for real

This is a complete, working application, but a few things are deliberately
out of scope and would need doing before taking real money:

- **Payments.** Payment method is recorded; nothing is charged. Wire up a
  payment provider and hold funds in escrow until delivery.
- **Identity and licence verification.** `is_verified` is a flag with no
  verification pipeline behind it.
- **Rate limiting.** Login has a fixed delay on failure, but there is no
  per-IP rate limiting — put one in front of `/api/auth/*`.
- **Transactional email/SMS.** No password reset or notification delivery.
- **Photos.** Operators should be able to attach proof-of-delivery images.
- **Real routing.** Distance uses great-circle × 1.35, a standard urban detour
  factor. A routing engine (OSRM, Valhalla, a commercial Directions API) would
  give true road distance and turn-by-turn navigation.
- **Postgres + PostGIS** if you outgrow SQLite; the nearby-vehicle query is a
  full scan today, which is fine for hundreds of operators and not for millions.

---

Map data © OpenStreetMap contributors.
