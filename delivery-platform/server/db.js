'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');
const config = require('./config');

fs.mkdirSync(path.dirname(config.dbFile), { recursive: true });

const db = new DatabaseSync(config.dbFile);

db.exec('PRAGMA journal_mode = WAL');
db.exec('PRAGMA foreign_keys = ON');
db.exec('PRAGMA busy_timeout = 5000');

db.exec(`
CREATE TABLE IF NOT EXISTS users (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  role            TEXT    NOT NULL CHECK (role IN ('customer', 'operator', 'manager')),
  full_name       TEXT    NOT NULL,
  email           TEXT    NOT NULL UNIQUE,
  phone           TEXT    NOT NULL,
  password_hash   TEXT    NOT NULL,
  rating_sum      REAL    NOT NULL DEFAULT 0,
  rating_count    INTEGER NOT NULL DEFAULT 0,
  is_suspended    INTEGER NOT NULL DEFAULT 0,
  suspended_reason TEXT,
  -- Two-factor. Mandatory for managers, optional for everyone else.
  totp_secret     TEXT,
  totp_enabled    INTEGER NOT NULL DEFAULT 0,
  totp_last_counter INTEGER,
  recovery_codes  TEXT,
  must_change_password INTEGER NOT NULL DEFAULT 0,
  password_changed_at  TEXT,
  locked_until    TEXT,
  created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- Server-side session records. JWTs alone cannot be revoked, so every token
-- carries a session id that is checked on each request: this is what makes
-- "sign out everywhere", forced logout and instant suspension actually work.
CREATE TABLE IF NOT EXISTS sessions (
  id           TEXT    PRIMARY KEY,
  user_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  csrf_token   TEXT    NOT NULL,
  ip           TEXT,
  user_agent   TEXT,
  created_at   TEXT    NOT NULL DEFAULT (datetime('now')),
  last_seen_at TEXT    NOT NULL DEFAULT (datetime('now')),
  expires_at   TEXT    NOT NULL,
  revoked_at   TEXT,
  revoked_by   INTEGER REFERENCES users(id) ON DELETE SET NULL
);

-- Failed-login ledger driving progressive account lockout.
CREATE TABLE IF NOT EXISTS login_attempts (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  email      TEXT,
  ip         TEXT,
  succeeded  INTEGER NOT NULL DEFAULT 0,
  created_at TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- Append-only record of privileged and security-relevant actions. Managers
-- can read everything in the system, so every look and every intervention is
-- written down and is itself visible to other managers.
CREATE TABLE IF NOT EXISTS audit_log (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  actor_id     INTEGER REFERENCES users(id) ON DELETE SET NULL,
  actor_role   TEXT,
  action       TEXT    NOT NULL,
  subject_type TEXT,
  subject_id   TEXT,
  detail       TEXT,
  ip           TEXT,
  created_at   TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS operator_profiles (
  user_id         INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  vehicle_class   TEXT    NOT NULL,
  vehicle_make    TEXT,
  vehicle_model   TEXT,
  vehicle_plate   TEXT,
  capacity_kg     INTEGER NOT NULL DEFAULT 0,
  helpers_available INTEGER NOT NULL DEFAULT 0,
  has_tail_lift   INTEGER NOT NULL DEFAULT 0,
  licence_number  TEXT,
  bio             TEXT,
  is_verified     INTEGER NOT NULL DEFAULT 0,
  is_online       INTEGER NOT NULL DEFAULT 0,
  last_lat        REAL,
  last_lng        REAL,
  last_heading    REAL,
  last_seen_at    TEXT,
  trips_completed INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS trips (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  reference            TEXT    NOT NULL UNIQUE,
  customer_id          INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  operator_id          INTEGER REFERENCES users(id) ON DELETE SET NULL,
  status               TEXT    NOT NULL DEFAULT 'requested',
  category             TEXT    NOT NULL,
  vehicle_class        TEXT    NOT NULL,

  pickup_address       TEXT    NOT NULL,
  pickup_lat           REAL    NOT NULL,
  pickup_lng           REAL    NOT NULL,
  pickup_contact       TEXT,
  pickup_floor         INTEGER NOT NULL DEFAULT 0,
  pickup_has_lift      INTEGER NOT NULL DEFAULT 0,

  dropoff_address      TEXT    NOT NULL,
  dropoff_lat          REAL    NOT NULL,
  dropoff_lng          REAL    NOT NULL,
  dropoff_contact      TEXT,
  dropoff_floor        INTEGER NOT NULL DEFAULT 0,
  dropoff_has_lift     INTEGER NOT NULL DEFAULT 0,

  distance_km          REAL    NOT NULL DEFAULT 0,
  item_description     TEXT    NOT NULL,
  weight_estimate_kg   INTEGER NOT NULL DEFAULT 0,
  helpers_required     INTEGER NOT NULL DEFAULT 0,
  scheduled_at         TEXT,

  customer_offer_price REAL    NOT NULL,
  agreed_price         REAL,
  payment_method       TEXT    NOT NULL DEFAULT 'cash',

  customer_rating      INTEGER,
  operator_rating      INTEGER,
  customer_review      TEXT,

  cancel_reason        TEXT,
  cancelled_by         TEXT,

  -- Manager oversight: who put this operator on the job, and any flag raised.
  assigned_by          TEXT,
  flagged_reason       TEXT,
  flagged_at           TEXT,

  created_at           TEXT    NOT NULL DEFAULT (datetime('now')),
  accepted_at          TEXT,
  picked_up_at         TEXT,
  delivered_at         TEXT,
  closed_at            TEXT
);

CREATE TABLE IF NOT EXISTS offers (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  trip_id      INTEGER NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  operator_id  INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  price        REAL    NOT NULL,
  eta_minutes  INTEGER NOT NULL,
  message      TEXT,
  status       TEXT    NOT NULL DEFAULT 'pending',
  created_at   TEXT    NOT NULL DEFAULT (datetime('now')),
  UNIQUE (trip_id, operator_id)
);

CREATE TABLE IF NOT EXISTS trip_events (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  trip_id     INTEGER NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  actor_id    INTEGER REFERENCES users(id) ON DELETE SET NULL,
  type        TEXT    NOT NULL,
  note        TEXT,
  lat         REAL,
  lng         REAL,
  created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- GPS breadcrumb trail. One row per ping from the operator's device while a
-- trip is live; replayed to build the route line on the tracking map.
CREATE TABLE IF NOT EXISTS trip_locations (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  trip_id     INTEGER NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  operator_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  lat         REAL    NOT NULL,
  lng         REAL    NOT NULL,
  heading     REAL,
  speed_kph   REAL,
  accuracy_m  REAL,
  recorded_at TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS messages (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  trip_id    INTEGER NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  sender_id  INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body       TEXT    NOT NULL,
  created_at TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_trips_customer  ON trips(customer_id, status);
CREATE INDEX IF NOT EXISTS idx_trips_operator  ON trips(operator_id, status);
CREATE INDEX IF NOT EXISTS idx_trips_status    ON trips(status, created_at);
CREATE INDEX IF NOT EXISTS idx_offers_trip     ON offers(trip_id, status);
CREATE INDEX IF NOT EXISTS idx_offers_operator ON offers(operator_id, status);
CREATE INDEX IF NOT EXISTS idx_locations_trip  ON trip_locations(trip_id, id);
CREATE INDEX IF NOT EXISTS idx_events_trip     ON trip_events(trip_id, id);
CREATE INDEX IF NOT EXISTS idx_messages_trip   ON messages(trip_id, id);
CREATE INDEX IF NOT EXISTS idx_operators_online ON operator_profiles(is_online, vehicle_class);
CREATE INDEX IF NOT EXISTS idx_sessions_user   ON sessions(user_id, revoked_at);
CREATE INDEX IF NOT EXISTS idx_attempts_email  ON login_attempts(email, created_at);
CREATE INDEX IF NOT EXISTS idx_attempts_ip     ON login_attempts(ip, created_at);
CREATE INDEX IF NOT EXISTS idx_audit_created   ON audit_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_actor     ON audit_log(actor_id, created_at DESC);
`);

/** Run a statement and return `{ changes, lastInsertRowid }`. */
function run(sql, ...params) {
  return db.prepare(sql).run(...params);
}

/** Return the first matching row, or `undefined`. */
function get(sql, ...params) {
  return db.prepare(sql).get(...params);
}

/** Return every matching row. */
function all(sql, ...params) {
  return db.prepare(sql).all(...params);
}

/** Wrap `fn` in a transaction, rolling back if it throws. */
function transaction(fn) {
  return (...args) => {
    db.exec('BEGIN');
    try {
      const result = fn(...args);
      db.exec('COMMIT');
      return result;
    } catch (err) {
      db.exec('ROLLBACK');
      throw err;
    }
  };
}

module.exports = { db, run, get, all, transaction };
