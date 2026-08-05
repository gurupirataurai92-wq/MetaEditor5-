<?php
declare(strict_types=1);

namespace Haulr;

/**
 * Live updates without WebSockets.
 *
 * Apache + PHP has no persistent connection to push down — each request is a
 * separate short-lived process — so the Node version's WebSocket hub becomes a
 * queue table plus short polling. The browser calls `GET api/events?since=N`
 * every few seconds and gets anything newer addressed to it.
 *
 * The delivery guarantees the UI relies on are unchanged: every event is
 * addressed, ordered by id, and authorisation-checked on read. The only real
 * difference is latency — a couple of seconds instead of instant.
 */
final class Events
{
    /** Deliver to one specific user's feed. */
    public static function toUser(int $userId, string $type, array $payload = []): void
    {
        self::push('user', $type, $payload, $userId, null);
    }

    /** Deliver to everyone watching one job. */
    public static function toTrip(int $tripId, string $type, array $payload = []): void
    {
        self::push('trip', $type, $payload, null, $tripId);
    }

    /** The open-jobs board every on-duty driver watches. */
    public static function toDispatch(string $type, array $payload = []): void
    {
        self::push('dispatch', $type, $payload, null, null);
    }

    /** Oversight feed, managers only. */
    public static function toManagers(string $type, array $payload = []): void
    {
        self::push('managers', $type, $payload, null, null);
    }

    private static function push(
        string $audience,
        string $type,
        array $payload,
        ?int $userId,
        ?int $tripId
    ): void {
        try {
            $body = array_merge(['type' => $type], $payload);
            Database::run(
                'INSERT INTO event_queue (user_id, trip_id, audience, type, payload)
                 VALUES (?, ?, ?, ?, ?)',
                [$userId, $tripId, $audience, $type, json_encode($body, JSON_UNESCAPED_UNICODE)]
            );
        } catch (\Throwable $e) {
            // A dropped notification must never fail the action that caused
            // it — the next poll of the underlying data still corrects the UI.
            error_log('[events] could not queue ' . $type . ': ' . $e->getMessage());
        }
    }

    /**
     * Everything this user should see with an id greater than $since.
     *
     * Authorisation is applied here, not at write time: a job's audience can
     * change (a driver is assigned, a manager reassigns it), so who may read
     * an event is decided against the current state of the world.
     *
     * @return array{events: list<array>, lastId: int}
     */
    public static function pollFor(array $user, int $since, int $limit = 100): array
    {
        $userId = (int) $user['id'];
        $role   = (string) $user['role'];

        // Jobs this user is a party to — trip-addressed events for these are
        // theirs to see.
        $tripIds = array_map(
            static fn (array $r): int => (int) $r['id'],
            Database::all(
                'SELECT id FROM trips WHERE customer_id = ? OR operator_id = ?',
                [$userId, $userId]
            )
        );

        $conditions = ['(e.audience = \'user\' AND e.user_id = ?)'];
        $params = [$userId];

        if ($tripIds !== []) {
            $placeholders = implode(',', array_fill(0, count($tripIds), '?'));
            $conditions[] = "(e.audience = 'trip' AND e.trip_id IN ($placeholders))";
            $params = array_merge($params, $tripIds);
        }

        // Drivers and managers both watch the dispatch board.
        if ($role === 'operator' || $role === 'manager') {
            $conditions[] = "e.audience = 'dispatch'";
        }
        if ($role === 'manager') {
            $conditions[] = "e.audience = 'managers'";
            // A manager may also watch any single job they have open.
            $conditions[] = "e.audience = 'trip'";
        }

        $where = implode(' OR ', $conditions);

        $rows = Database::all(
            "SELECT e.id, e.payload
               FROM event_queue e
              WHERE e.id > ? AND ($where)
              ORDER BY e.id ASC
              LIMIT $limit",
            array_merge([$since], $params)
        );

        $events = [];
        $lastId = $since;
        foreach ($rows as $row) {
            $lastId = (int) $row['id'];
            $decoded = json_decode((string) $row['payload'], true);
            if (is_array($decoded)) {
                $events[] = $decoded;
            }
        }

        // On a first poll (since=0) there is no backlog worth replaying —
        // start the client at the current head so it only sees what happens
        // from now on.
        if ($since === 0) {
            $head = (int) Database::value('SELECT COALESCE(MAX(id), 0) FROM event_queue', [], 0);
            return ['events' => [], 'lastId' => $head];
        }

        return ['events' => $events, 'lastId' => $lastId];
    }
}
