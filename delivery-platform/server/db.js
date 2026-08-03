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
  role            TEXT    NOT NULL CHECK (role IN ('customer', 'operator', 'admin')),
  full_name       TEXT    NOT NULL,
  email           TEXT    NOT NULL UNIQUE,
  phone           TEXT    NOT NULL,
  password_hash   TEXT    NOT NULL,
  rating_sum      REAL    NOT NULL DEFAULT 0,
  rating_count    INTEGER NOT NULL DEFAULT 0,
  is_suspended    INTEGER NOT NULL DEFAULT 0,
  created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
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
