'use strict';

// Append-only audit trail.
//
// Managers can see every job, every customer and every operator in the system.
// That power is only acceptable if it is observable, so both the interventions
// they make and the sensitive data they open are recorded here — and the log
// is itself visible to every other manager.

const { run, all, get } = require('./db');

/** Actions that change state or expose someone's personal data. */
const ACTIONS = {
  LOGIN_SUCCESS: 'auth.login.success',
  LOGIN_FAILED: 'auth.login.failed',
  LOGIN_LOCKED: 'auth.login.locked',
  LOGOUT: 'auth.logout',
  REGISTER: 'auth.register',
  PASSWORD_CHANGED: 'auth.password.changed',
  TWO_FACTOR_ENABLED: 'auth.2fa.enabled',
  TWO_FACTOR_DISABLED: 'auth.2fa.disabled',
  TWO_FACTOR_FAILED: 'auth.2fa.failed',
  SESSIONS_REVOKED: 'auth.sessions.revoked',

  MANAGER_CREATED: 'manager.created',
  MANAGER_VIEWED_TRIP: 'manager.trip.viewed',
  MANAGER_VIEWED_USER: 'manager.user.viewed',
  MANAGER_REASSIGNED: 'manager.trip.reassigned',
  MANAGER_CANCELLED: 'manager.trip.cancelled',
  MANAGER_FLAGGED: 'manager.trip.flagged',
  MANAGER_UNFLAGGED: 'manager.trip.unflagged',
  MANAGER_VERIFIED_OPERATOR: 'manager.operator.verified',
  MANAGER_SUSPENDED_USER: 'manager.user.suspended',
  MANAGER_REINSTATED_USER: 'manager.user.reinstated',
  MANAGER_FORCED_LOGOUT: 'manager.user.forced_logout',
};

/**
 * Write one audit row.
 *
 * Never allowed to break the request it is recording: an audit failure is
 * logged to stderr rather than thrown, because losing a delivery is worse
 * than losing a log line. A real deployment should ship these to a store the
 * application cannot rewrite.
 */
function record({ actor, action, subjectType = null, subjectId = null, detail = null, ip = null }) {
  try {
    run(
      `INSERT INTO audit_log (actor_id, actor_role, action, subject_type, subject_id, detail, ip)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      actor?.id ?? null,
      actor?.role ?? null,
      action,
      subjectType,
      subjectId == null ? null : String(subjectId),
      detail == null ? null : String(detail).slice(0, 500),
      ip
    );
  } catch (err) {
    console.error('[audit] failed to record', action, err.message);
  }
}

/** Convenience wrapper that pulls actor and IP straight off the request. */
function fromRequest(req, action, extra = {}) {
  record({ actor: req.user, action, ip: req.ip, ...extra });
}

function list({ limit = 100, offset = 0, actorId = null, action = null } = {}) {
  const where = [];
  const params = [];
  if (actorId) {
    where.push('a.actor_id = ?');
    params.push(actorId);
  }
  if (action) {
    where.push('a.action LIKE ?');
    params.push(`${action}%`);
  }

  const rows = all(
    `SELECT a.*, u.full_name AS actor_name, u.email AS actor_email
       FROM audit_log a
       LEFT JOIN users u ON u.id = a.actor_id
      ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
      ORDER BY a.id DESC
      LIMIT ? OFFSET ?`,
    ...params,
    limit,
    offset
  );

  const total = get(
    `SELECT COUNT(*) AS n FROM audit_log a
      ${where.length ? `WHERE ${where.join(' AND ')}` : ''}`,
    ...params
  ).n;

  return {
    total,
    entries: rows.map((r) => ({
      id: r.id,
      actorId: r.actor_id,
      actorName: r.actor_name,
      actorEmail: r.actor_email,
      actorRole: r.actor_role,
      action: r.action,
      subjectType: r.subject_type,
      subjectId: r.subject_id,
      detail: r.detail,
      ip: r.ip,
      createdAt: r.created_at,
    })),
  };
}

module.exports = { ACTIONS, record, fromRequest, list };
