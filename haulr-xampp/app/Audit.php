<?php
declare(strict_types=1);

namespace Haulr;

/**
 * Append-only audit trail.
 *
 * Managers can see every job, every customer and every driver in the system.
 * That power is only acceptable if it is observable, so both the interventions
 * they make and the personal data they open are recorded here — and the log is
 * itself visible to every other manager.
 */
final class Audit
{
    public const LOGIN_SUCCESS   = 'auth.login.success';
    public const LOGIN_FAILED    = 'auth.login.failed';
    public const LOGIN_LOCKED    = 'auth.login.locked';
    public const LOGOUT          = 'auth.logout';
    public const REGISTER        = 'auth.register';
    public const PASSWORD_CHANGED = 'auth.password.changed';
    public const TWO_FACTOR_ENABLED  = 'auth.2fa.enabled';
    public const TWO_FACTOR_DISABLED = 'auth.2fa.disabled';
    public const TWO_FACTOR_FAILED   = 'auth.2fa.failed';
    public const SESSIONS_REVOKED    = 'auth.sessions.revoked';

    public const MANAGER_CREATED           = 'manager.created';
    public const MANAGER_VIEWED_TRIP       = 'manager.trip.viewed';
    public const MANAGER_REASSIGNED        = 'manager.trip.reassigned';
    public const MANAGER_CANCELLED         = 'manager.trip.cancelled';
    public const MANAGER_FLAGGED           = 'manager.trip.flagged';
    public const MANAGER_UNFLAGGED         = 'manager.trip.unflagged';
    public const MANAGER_VERIFIED_OPERATOR = 'manager.operator.verified';
    public const MANAGER_SUSPENDED_USER    = 'manager.user.suspended';
    public const MANAGER_REINSTATED_USER   = 'manager.user.reinstated';
    public const MANAGER_FORCED_LOGOUT     = 'manager.user.forced_logout';
    public const MANAGER_VIEWED_FLEET      = 'manager.fleet.viewed';

    /**
     * Write one audit row.
     *
     * Never allowed to break the request it is recording: losing a delivery is
     * worse than losing a log line. A real deployment should ship these
     * somewhere the application itself cannot rewrite.
     */
    public static function record(
        string $action,
        ?array $actor = null,
        ?string $subjectType = null,
        int|string|null $subjectId = null,
        ?string $detail = null
    ): void {
        try {
            $actor ??= Auth::user();
            Database::run(
                'INSERT INTO audit_log (actor_id, actor_role, action, subject_type, subject_id, detail, ip)
                 VALUES (?, ?, ?, ?, ?, ?, ?)',
                [
                    $actor['id'] ?? null,
                    $actor['role'] ?? null,
                    $action,
                    $subjectType,
                    $subjectId === null ? null : (string) $subjectId,
                    $detail === null ? null : mb_substr($detail, 0, 500),
                    Security::clientIp(),
                ]
            );
        } catch (\Throwable $e) {
            error_log('[audit] failed to record ' . $action . ': ' . $e->getMessage());
        }
    }

    public static function listEntries(int $limit = 100, int $offset = 0, ?string $action = null, ?int $actorId = null): array
    {
        $where = [];
        $params = [];
        if ($actorId !== null) {
            $where[] = 'a.actor_id = ?';
            $params[] = $actorId;
        }
        if ($action !== null && $action !== '') {
            $where[] = 'a.action LIKE ?';
            $params[] = $action . '%';
        }
        $clause = $where === [] ? '' : ('WHERE ' . implode(' AND ', $where));

        $total = (int) Database::value("SELECT COUNT(*) FROM audit_log a $clause", $params, 0);

        $rows = Database::all(
            "SELECT a.*, u.full_name AS actor_name, u.email AS actor_email
               FROM audit_log a
               LEFT JOIN users u ON u.id = a.actor_id
               $clause
              ORDER BY a.id DESC
              LIMIT $limit OFFSET $offset",
            $params
        );

        return [
            'total'   => $total,
            'entries' => array_map(static fn (array $r): array => [
                'id'          => (int) $r['id'],
                'actorId'     => $r['actor_id'] === null ? null : (int) $r['actor_id'],
                'actorName'   => $r['actor_name'],
                'actorEmail'  => $r['actor_email'],
                'actorRole'   => $r['actor_role'],
                'action'      => $r['action'],
                'subjectType' => $r['subject_type'],
                'subjectId'   => $r['subject_id'],
                'detail'      => $r['detail'],
                'ip'          => $r['ip'],
                'createdAt'   => $r['created_at'],
            ], $rows),
        ];
    }
}
