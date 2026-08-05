'use strict';

// Brings a database created by an older build up to the current schema.
//
// `db.js` uses CREATE TABLE IF NOT EXISTS, which silently does nothing when a
// table already exists — so new columns and changed CHECK constraints have to
// be applied here. Runs automatically on boot and is safe to run repeatedly.

const { db, all, get, run } = require('./db');

function columnNames(table) {
  return all(`PRAGMA table_info(${table})`).map((c) => c.name);
}

function addColumnIfMissing(table, column, definition) {
  if (columnNames(table).includes(column)) return false;
  run(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
  return true;
}

/**
 * SQLite cannot alter a CHECK constraint in place, so widening the role set
 * means rebuilding the table. Detected by reading the stored DDL.
 */
function migrateRoleConstraint(applied) {
  const ddl = get("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'users'")?.sql;
  if (!ddl || ddl.includes("'manager'")) return;

  // Foreign keys must be off for the rename-and-copy dance, and PRAGMA
  // foreign_keys is a no-op inside a transaction — so it is toggled outside.
  db.exec('PRAGMA foreign_keys = OFF');
  db.exec('BEGIN');
  try {
    db.exec(`
      CREATE TABLE users_migrated (
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
        totp_secret     TEXT,
        totp_enabled    INTEGER NOT NULL DEFAULT 0,
        totp_last_counter INTEGER,
        recovery_codes  TEXT,
        must_change_password INTEGER NOT NULL DEFAULT 0,
        password_changed_at  TEXT,
        locked_until    TEXT,
        created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
      )`);

    // The old schema's third role was 'admin'; it becomes 'manager'.
    db.exec(`
      INSERT INTO users_migrated
        (id, role, full_name, email, phone, password_hash, rating_sum, rating_count,
         is_suspended, created_at)
      SELECT id,
             CASE role WHEN 'admin' THEN 'manager' ELSE role END,
             full_name, email, phone, password_hash, rating_sum, rating_count,
             is_suspended, created_at
        FROM users`);

    db.exec('DROP TABLE users');
    db.exec('ALTER TABLE users_migrated RENAME TO users');
    db.exec('COMMIT');
    applied.push("users.role now allows 'manager' (existing 'admin' accounts migrated)");
  } catch (err) {
    db.exec('ROLLBACK');
    throw err;
  } finally {
    db.exec('PRAGMA foreign_keys = ON');
  }
}

function migrate({ quiet = false } = {}) {
  const applied = [];

  // Older databases predate the role rebuild; do that before adding columns,
  // since the rebuild already creates them.
  migrateRoleConstraint(applied);

  const userColumns = [
    ['suspended_reason', 'TEXT'],
    ['totp_secret', 'TEXT'],
    ['totp_enabled', 'INTEGER NOT NULL DEFAULT 0'],
    ['totp_last_counter', 'INTEGER'],
    ['recovery_codes', 'TEXT'],
    ['must_change_password', 'INTEGER NOT NULL DEFAULT 0'],
    ['password_changed_at', 'TEXT'],
    ['locked_until', 'TEXT'],
  ];
  for (const [column, definition] of userColumns) {
    if (addColumnIfMissing('users', column, definition)) {
      applied.push(`users.${column} added`);
    }
  }

  if (addColumnIfMissing('trips', 'assigned_by', 'TEXT')) {
    applied.push('trips.assigned_by added');
  }
  if (addColumnIfMissing('trips', 'flagged_reason', 'TEXT')) {
    applied.push('trips.flagged_reason added');
  }
  if (addColumnIfMissing('trips', 'flagged_at', 'TEXT')) {
    applied.push('trips.flagged_at added');
  }

  if (applied.length && !quiet) {
    console.log('[migrate] applied:');
    for (const line of applied) console.log(`  - ${line}`);
  }
  return applied;
}

module.exports = { migrate };

if (require.main === module) {
  const applied = migrate();
  if (!applied.length) console.log('[migrate] database already up to date.');
}
