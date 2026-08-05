<?php
declare(strict_types=1);

namespace Haulr\Controllers;

use Haulr\{Audit, Auth, Config, Database, Domain, Events, Response, Security, Serialize, Validate};

/**
 * Manager console: oversight of every job, driver and customer, plus the
 * interventions needed when something goes wrong on the road.
 *
 * Two rules run through this whole class:
 *   1. Nothing here is reachable without the `manager` role and an enrolled
 *      second factor.
 *   2. Every read of someone's personal data and every intervention is written
 *      to the audit log, because oversight without accountability is just
 *      unchecked access.
 */
final class ManagerController
{
    private function gate(): array
    {
        $user = Auth::requireRole('manager');
        Auth::requireEnrolledTwoFactor();
        return $user;
    }

    private function staleMinutes(): int
    {
        return (int) Config::get('operator_stale_minutes', 10);
    }

    /* ==================================================================
       Overview
       ================================================================== */

    public function overview(): never
    {
        $this->gate();

        $counts = Database::first(
            "SELECT
               COUNT(*) AS total,
               SUM(status = 'requested') AS awaiting,
               SUM(status IN ('accepted','en_route_pickup','at_pickup','in_transit')) AS live,
               SUM(status = 'completed') AS completed,
               SUM(status = 'cancelled') AS cancelled,
               SUM(flagged_at IS NOT NULL AND status NOT IN ('completed','cancelled')) AS flagged
             FROM trips"
        );

        $today = Database::first(
            'SELECT COUNT(*) AS jobs, COALESCE(SUM(agreed_price), 0) AS value
               FROM trips WHERE created_at >= (NOW() - INTERVAL 1 DAY)'
        );

        $people = Database::first(
            "SELECT
               SUM(role = 'customer') AS customers,
               SUM(role = 'operator') AS operators,
               SUM(role = 'manager')  AS managers,
               SUM(is_suspended = 1)  AS suspended
             FROM users"
        );

        $onDuty = (int) Database::value(
            'SELECT COUNT(*) FROM operator_profiles
              WHERE is_online = 1 AND last_seen_at >= (NOW() - INTERVAL ? MINUTE)',
            [$this->staleMinutes()],
            0
        );
        $unverified = (int) Database::value('SELECT COUNT(*) FROM operator_profiles WHERE is_verified = 0', [], 0);

        // Jobs sitting unclaimed for a while are what a manager needs to chase.
        $stalled = Database::all(
            "SELECT t.*, (SELECT COUNT(*) FROM offers o WHERE o.trip_id = t.id AND o.status='pending') AS offer_count
               FROM trips t
              WHERE t.status = 'requested' AND t.created_at < (NOW() - INTERVAL 20 MINUTE)
              ORDER BY t.created_at ASC LIMIT 10"
        );

        Response::json([
            'jobs' => [
                'total'            => (int) $counts['total'],
                'awaitingOperator' => (int) $counts['awaiting'],
                'live'             => (int) $counts['live'],
                'completed'        => (int) $counts['completed'],
                'cancelled'        => (int) $counts['cancelled'],
                'flagged'          => (int) $counts['flagged'],
            ],
            'last24h' => ['jobs' => (int) $today['jobs'], 'value' => (float) $today['value']],
            'people'  => [
                'customers'            => (int) $people['customers'],
                'operators'            => (int) $people['operators'],
                'managers'             => (int) $people['managers'],
                'suspended'            => (int) $people['suspended'],
                'onDuty'               => $onDuty,
                'unverifiedOperators'  => $unverified,
            ],
            'stalled' => array_map(static function (array $row): array {
                $trip = Serialize::trip($row, null);
                $trip['offerCount'] = (int) $row['offer_count'];
                $trip['waitingMinutes'] = (int) round((time() - strtotime((string) $row['created_at'])) / 60);
                return $trip;
            }, $stalled),
        ]);
    }

    /* ==================================================================
       Jobs
       ================================================================== */

    public function trips(array $query): never
    {
        $this->gate();

        $statusOptions = array_merge(array_keys(Domain::STATUS_LABELS), ['live', 'flagged']);
        $status = isset($query['status']) && $query['status'] !== ''
            ? Validate::oneOf($query['status'], 'Status', $statusOptions)
            : null;
        $search = Validate::str($query['q'] ?? null, 'Search', 1, 80, false);
        $limit  = (int) Validate::num($query['limit'] ?? 60, 'Limit', 1, 200, false, true);

        $where = [];
        $params = [];

        if ($status === 'live') {
            $where[] = "t.status IN ('accepted','en_route_pickup','at_pickup','in_transit')";
        } elseif ($status === 'flagged') {
            $where[] = 't.flagged_at IS NOT NULL';
        } elseif ($status !== null) {
            $where[] = 't.status = ?';
            $params[] = $status;
        }

        if ($search !== null) {
            $where[] = '(t.reference LIKE ? OR t.pickup_address LIKE ? OR t.dropoff_address LIKE ?)';
            $like = '%' . $search . '%';
            array_push($params, $like, $like, $like);
        }

        $clause = $where === [] ? '' : ('WHERE ' . implode(' AND ', $where));

        $rows = Database::all(
            "SELECT t.*,
                    (SELECT COUNT(*) FROM offers o WHERE o.trip_id = t.id AND o.status = 'pending') AS offer_count
               FROM trips t $clause
              ORDER BY t.created_at DESC, t.id DESC
              LIMIT $limit",
            $params
        );

        // A summary view only: no contact details are serialised, so browsing
        // the board does not expose anybody's phone number.
        Response::json([
            'trips' => array_map(static function (array $row): array {
                $trip = Serialize::trip($row, null);
                $trip['offerCount']    = (int) $row['offer_count'];
                $trip['flaggedReason'] = $row['flagged_reason'];
                $trip['flaggedAt']     = $row['flagged_at'];
                $trip['assignedBy']    = $row['assigned_by'];
                return $trip;
            }, $rows),
        ]);
    }

    /** Full detail — which is exactly why opening one is recorded. */
    public function trip(int $id): never
    {
        $this->gate();

        $row = Database::first('SELECT * FROM trips WHERE id = ?', [$id]);
        if ($row === null) {
            Response::error('Job not found.', 404);
        }

        Audit::record(Audit::MANAGER_VIEWED_TRIP, null, 'trip', $id, (string) $row['reference']);

        $trip = Serialize::trip($row, (int) $row['customer_id']);
        $trip['flaggedReason'] = $row['flagged_reason'];
        $trip['flaggedAt']     = $row['flagged_at'];

        Response::json([
            'trip'   => $trip,
            'offers' => array_map(
                [Serialize::class, 'offer'],
                Database::all('SELECT * FROM offers WHERE trip_id = ? ORDER BY price ASC', [$id])
            ),
            'events' => array_map(
                [Serialize::class, 'event'],
                Database::all('SELECT * FROM trip_events WHERE trip_id = ? ORDER BY id ASC', [$id])
            ),
            'trail' => array_map(
                [Serialize::class, 'location'],
                Database::all(
                    'SELECT lat, lng, heading, speed_kph, accuracy_m, recorded_at
                       FROM trip_locations WHERE trip_id = ? ORDER BY id ASC LIMIT 2000',
                    [$id]
                )
            ),
            'messageCount' => (int) Database::value('SELECT COUNT(*) FROM messages WHERE trip_id = ?', [$id], 0),
        ]);
    }

    /** Move a job to a different driver — a breakdown, a no-show, a complaint. */
    public function reassign(int $id, array $body): never
    {
        $manager = $this->gate();

        $operatorId = (int) Validate::num($body['operatorId'] ?? null, 'Operator', 1, PHP_INT_MAX, true, true);
        $reason     = Validate::str($body['reason'] ?? null, 'Reason', 3, 300);

        $trip = Database::first('SELECT * FROM trips WHERE id = ?', [$id]);
        if ($trip === null) {
            Response::error('Job not found.', 404);
        }
        if (in_array($trip['status'], ['completed', 'cancelled', 'delivered'], true)) {
            Response::error('This job is already finished.', 409);
        }

        $operator = Database::first(
            "SELECT u.id, u.full_name, u.is_suspended, p.vehicle_class
               FROM users u JOIN operator_profiles p ON p.user_id = u.id
              WHERE u.id = ? AND u.role = 'operator'",
            [$operatorId]
        );
        if ($operator === null) {
            Response::error('That operator does not exist.', 404);
        }
        if ((int) $operator['is_suspended'] === 1) {
            Response::error('That operator is suspended.');
        }
        if ($trip['operator_id'] !== null && (int) $trip['operator_id'] === $operatorId) {
            Response::error('That operator already has this job.');
        }

        // A manager may override a lot, but not physics: the replacement
        // vehicle still has to be able to carry the load.
        $required = Domain::vehicle((string) $trip['vehicle_class']);
        $theirs   = Domain::vehicle((string) $operator['vehicle_class']);
        if ($theirs === null || $theirs['capacityKg'] < $required['capacityKg']) {
            Response::error(
                'That operator drives a ' . ($theirs['name'] ?? 'vehicle')
                . ', which is too small for a job needing a ' . mb_strtolower($required['name']) . '.'
            );
        }

        $previousOperatorId = $trip['operator_id'] === null ? null : (int) $trip['operator_id'];

        Database::transaction(static function () use ($id, $operatorId, $previousOperatorId, $reason, $manager): void {
            Database::run(
                "UPDATE trips
                    SET operator_id = ?, status = 'accepted', assigned_by = 'manager',
                        accepted_at = COALESCE(accepted_at, NOW()),
                        agreed_price = COALESCE(agreed_price, customer_offer_price)
                  WHERE id = ?",
                [$operatorId, $id]
            );
            if ($previousOperatorId !== null) {
                Database::run(
                    "UPDATE offers SET status = 'withdrawn' WHERE trip_id = ? AND operator_id = ?",
                    [$id, $previousOperatorId]
                );
            }
            Database::run(
                'INSERT INTO trip_events (trip_id, actor_id, type, note) VALUES (?, ?, ?, ?)',
                [$id, (int) $manager['id'], 'manager_reassigned', $reason]
            );
        });

        Audit::record(
            Audit::MANAGER_REASSIGNED,
            $manager,
            'trip',
            $id,
            ($previousOperatorId ?? 'unassigned') . " -> $operatorId: $reason"
        );

        TripController::broadcast($id, 'reassigned');
        if ($previousOperatorId !== null) {
            Events::toUser($previousOperatorId, 'job_removed', ['tripId' => $id, 'reason' => $reason]);
        }
        Events::toUser($operatorId, 'job_assigned', ['tripId' => $id, 'reason' => $reason]);

        Response::json(['ok' => true]);
    }

    public function cancelTrip(int $id, array $body): never
    {
        $manager = $this->gate();
        $reason  = Validate::str($body['reason'] ?? null, 'Reason', 3, 300);

        $trip = Database::first('SELECT * FROM trips WHERE id = ?', [$id]);
        if ($trip === null) {
            Response::error('Job not found.', 404);
        }
        if (in_array($trip['status'], ['completed', 'cancelled'], true)) {
            Response::error('This job is already closed.', 409);
        }

        Database::transaction(static function () use ($id, $reason, $manager): void {
            Database::run(
                "UPDATE trips
                    SET status = 'cancelled', cancel_reason = ?, cancelled_by = 'manager', closed_at = NOW()
                  WHERE id = ?",
                [$reason, $id]
            );
            Database::run("UPDATE offers SET status = 'rejected' WHERE trip_id = ? AND status = 'pending'", [$id]);
            Database::run(
                'INSERT INTO trip_events (trip_id, actor_id, type, note) VALUES (?, ?, ?, ?)',
                [$id, (int) $manager['id'], 'manager_cancelled', $reason]
            );
        });

        Audit::record(Audit::MANAGER_CANCELLED, $manager, 'trip', $id, $reason);
        TripController::broadcast($id, 'cancelled');
        Events::toDispatch('job_closed', ['tripId' => $id]);

        Response::json(['ok' => true]);
    }

    public function flagTrip(int $id, array $body): never
    {
        $manager = $this->gate();

        if (($body['clear'] ?? false) === true) {
            Database::run('UPDATE trips SET flagged_reason = NULL, flagged_at = NULL WHERE id = ?', [$id]);
            Audit::record(Audit::MANAGER_UNFLAGGED, $manager, 'trip', $id);
            TripController::broadcast($id, 'unflagged');
            Response::json(['ok' => true, 'flagged' => false]);
        }

        $reason = Validate::str($body['reason'] ?? null, 'Reason', 3, 300);
        $changed = Database::affected(
            'UPDATE trips SET flagged_reason = ?, flagged_at = NOW() WHERE id = ?',
            [$reason, $id]
        );
        if ($changed !== 1) {
            Response::error('Job not found.', 404);
        }

        Database::run(
            'INSERT INTO trip_events (trip_id, actor_id, type, note) VALUES (?, ?, ?, ?)',
            [$id, (int) $manager['id'], 'manager_flagged', $reason]
        );
        Audit::record(Audit::MANAGER_FLAGGED, $manager, 'trip', $id, $reason);
        TripController::broadcast($id, 'flagged');

        Response::json(['ok' => true, 'flagged' => true]);
    }

    /* ==================================================================
       Fleet
       ================================================================== */

    /** Live positions at full precision — staff access to staff whereabouts, audited. */
    public function fleet(): never
    {
        $manager = $this->gate();

        $rows = Database::all(
            "SELECT u.id, u.full_name, u.rating_sum, u.rating_count,
                    p.vehicle_class, p.vehicle_plate, p.is_verified,
                    p.last_lat, p.last_lng, p.last_heading, p.last_seen_at,
                    (SELECT t.id FROM trips t
                      WHERE t.operator_id = u.id
                        AND t.status IN ('accepted','en_route_pickup','at_pickup','in_transit')
                      LIMIT 1) AS current_trip_id
               FROM users u
               JOIN operator_profiles p ON p.user_id = u.id
              WHERE u.is_suspended = 0 AND p.is_online = 1 AND p.last_lat IS NOT NULL
                AND p.last_seen_at >= (NOW() - INTERVAL ? MINUTE)
              ORDER BY p.last_seen_at DESC
              LIMIT 300",
            [$this->staleMinutes()]
        );

        Audit::record(Audit::MANAGER_VIEWED_FLEET, $manager, null, null, count($rows) . ' vehicles');

        Response::json([
            'vehicles' => array_map(static fn (array $r): array => [
                'operatorId'    => (int) $r['id'],
                'name'          => $r['full_name'],
                'vehicleClass'  => $r['vehicle_class'],
                'plate'         => $r['vehicle_plate'],
                'verified'      => (bool) $r['is_verified'],
                'rating'        => Serialize::ratingOf($r['rating_sum'], $r['rating_count']),
                'lat'           => (float) $r['last_lat'],
                'lng'           => (float) $r['last_lng'],
                'heading'       => $r['last_heading'] === null ? null : (float) $r['last_heading'],
                'lastSeenAt'    => $r['last_seen_at'],
                'currentTripId' => $r['current_trip_id'] === null ? null : (int) $r['current_trip_id'],
                'busy'          => $r['current_trip_id'] !== null,
            ], $rows),
        ]);
    }

    /** Drivers who could take over a job, nearest and freest first. */
    public function candidates(int $id): never
    {
        $this->gate();

        $trip = Database::first('SELECT * FROM trips WHERE id = ?', [$id]);
        if ($trip === null) {
            Response::error('Job not found.', 404);
        }

        $required = Domain::vehicle((string) $trip['vehicle_class']);
        $eligible = array_values(array_map(
            static fn (array $v): string => $v['id'],
            array_filter(Domain::VEHICLE_CLASSES, static fn (array $v): bool => $v['capacityKg'] >= $required['capacityKg'])
        ));
        $placeholders = implode(',', array_fill(0, count($eligible), '?'));

        $rows = Database::all(
            "SELECT u.id, u.full_name, u.rating_sum, u.rating_count,
                    p.vehicle_class, p.vehicle_plate, p.is_online, p.is_verified,
                    p.last_lat, p.last_lng, p.trips_completed,
                    (SELECT COUNT(*) FROM trips t
                      WHERE t.operator_id = u.id
                        AND t.status IN ('accepted','en_route_pickup','at_pickup','in_transit')) AS active_jobs
               FROM users u
               JOIN operator_profiles p ON p.user_id = u.id
              WHERE u.role = 'operator' AND u.is_suspended = 0
                AND p.vehicle_class IN ($placeholders)
                AND u.id <> COALESCE(?, 0)
              LIMIT 200",
            array_merge($eligible, [$trip['operator_id']])
        );

        $candidates = array_map(static function (array $r) use ($trip): array {
            return [
                'id'                 => (int) $r['id'],
                'name'               => $r['full_name'],
                'vehicleClass'       => $r['vehicle_class'],
                'plate'              => $r['vehicle_plate'],
                'online'             => (bool) $r['is_online'],
                'verified'           => (bool) $r['is_verified'],
                'rating'             => Serialize::ratingOf($r['rating_sum'], $r['rating_count']),
                'tripsCompleted'     => (int) $r['trips_completed'],
                'activeJobs'         => (int) $r['active_jobs'],
                'distanceToPickupKm' => $r['last_lat'] === null ? null : round(
                    Domain::haversineKm(
                        (float) $r['last_lat'],
                        (float) $r['last_lng'],
                        (float) $trip['pickup_lat'],
                        (float) $trip['pickup_lng']
                    ) * 1.35,
                    2
                ),
            ];
        }, $rows);

        usort($candidates, static function (array $a, array $b): int {
            if ($a['online'] !== $b['online']) {
                return $a['online'] ? -1 : 1;
            }
            if ($a['activeJobs'] !== $b['activeJobs']) {
                return $a['activeJobs'] <=> $b['activeJobs'];
            }
            return ($a['distanceToPickupKm'] ?? 1e9) <=> ($b['distanceToPickupKm'] ?? 1e9);
        });

        Response::json(['candidates' => array_slice($candidates, 0, 25)]);
    }

    /* ==================================================================
       People
       ================================================================== */

    public function users(array $query): never
    {
        $this->gate();

        $role = isset($query['role']) && $query['role'] !== ''
            ? Validate::oneOf($query['role'], 'Role', ['customer', 'operator', 'manager'])
            : null;
        $search = Validate::str($query['q'] ?? null, 'Search', 1, 80, false);
        $limit  = (int) Validate::num($query['limit'] ?? 60, 'Limit', 1, 200, false, true);

        $where = [];
        $params = [];
        if ($role !== null) {
            $where[] = 'u.role = ?';
            $params[] = $role;
        }
        if ($search !== null) {
            $where[] = '(u.full_name LIKE ? OR u.email LIKE ?)';
            $params[] = '%' . $search . '%';
            $params[] = '%' . $search . '%';
        }
        if (($query['suspended'] ?? '') === 'true') {
            $where[] = 'u.is_suspended = 1';
        }
        if (($query['unverified'] ?? '') === 'true') {
            $where[] = 'p.is_verified = 0';
        }
        $clause = $where === [] ? '' : ('WHERE ' . implode(' AND ', $where));

        $rows = Database::all(
            "SELECT u.id, u.role, u.full_name, u.email, u.phone, u.rating_sum, u.rating_count,
                    u.is_suspended, u.suspended_reason, u.totp_enabled, u.created_at,
                    p.vehicle_class, p.vehicle_plate, p.is_verified, p.is_online, p.trips_completed,
                    (SELECT COUNT(*) FROM trips t WHERE t.customer_id = u.id) AS jobs_posted,
                    (SELECT COUNT(*) FROM trips t WHERE t.operator_id = u.id AND t.status='completed') AS jobs_done
               FROM users u
               LEFT JOIN operator_profiles p ON p.user_id = u.id
               $clause
              ORDER BY u.created_at DESC
              LIMIT $limit",
            $params
        );

        Response::json([
            'users' => array_map(static fn (array $r): array => [
                'id'               => (int) $r['id'],
                'role'             => $r['role'],
                'fullName'         => $r['full_name'],
                'email'            => $r['email'],
                'phone'            => $r['phone'],
                'rating'           => Serialize::ratingOf($r['rating_sum'], $r['rating_count']),
                'ratingCount'      => (int) $r['rating_count'],
                'suspended'        => (bool) $r['is_suspended'],
                'suspendedReason'  => $r['suspended_reason'],
                'twoFactorEnabled' => (bool) $r['totp_enabled'],
                'createdAt'        => $r['created_at'],
                'vehicleClass'     => $r['vehicle_class'],
                'plate'            => $r['vehicle_plate'],
                'verified'         => $r['vehicle_class'] === null ? null : (bool) $r['is_verified'],
                'online'           => $r['vehicle_class'] === null ? null : (bool) $r['is_online'],
                'jobsPosted'       => (int) $r['jobs_posted'],
                'jobsDone'         => (int) $r['jobs_done'],
            ], $rows),
        ]);
    }

    public function suspendUser(int $id, array $body): never
    {
        $manager = $this->gate();
        $reason  = Validate::str($body['reason'] ?? null, 'Reason', 3, 300);

        $target = Database::first('SELECT id, role, full_name FROM users WHERE id = ?', [$id]);
        if ($target === null) {
            Response::error('User not found.', 404);
        }
        if ((int) $target['id'] === (int) $manager['id']) {
            Response::error('You cannot suspend your own account.');
        }
        // Managers are peers; one cannot unilaterally lock another out.
        if ($target['role'] === 'manager') {
            Response::error('Manager accounts cannot be suspended from the console.', 403);
        }

        Database::run('UPDATE users SET is_suspended = 1, suspended_reason = ? WHERE id = ?', [$reason, $id]);
        // Suspension has to bite immediately, not whenever a token expires.
        $revoked = Auth::revokeAllSessions($id, (int) $manager['id']);
        Database::run('UPDATE operator_profiles SET is_online = 0 WHERE user_id = ?', [$id]);

        Audit::record(Audit::MANAGER_SUSPENDED_USER, $manager, 'user', $id, $target['full_name'] . ': ' . $reason);

        Response::json(['ok' => true, 'sessionsEnded' => $revoked]);
    }

    public function reinstateUser(int $id): never
    {
        $manager = $this->gate();
        $changed = Database::affected(
            'UPDATE users SET is_suspended = 0, suspended_reason = NULL, locked_until = NULL WHERE id = ?',
            [$id]
        );
        if ($changed !== 1) {
            Response::error('User not found.', 404);
        }
        Audit::record(Audit::MANAGER_REINSTATED_USER, $manager, 'user', $id);
        Response::json(['ok' => true]);
    }

    public function forceLogout(int $id): never
    {
        $manager = $this->gate();
        $revoked = Auth::revokeAllSessions($id, (int) $manager['id']);
        Audit::record(Audit::MANAGER_FORCED_LOGOUT, $manager, 'user', $id, "$revoked session(s)");
        Response::json(['ok' => true, 'sessionsEnded' => $revoked]);
    }

    public function verifyOperator(int $id, array $body): never
    {
        $manager  = $this->gate();
        $verified = ($body['verified'] ?? true) !== false;

        $changed = Database::affected(
            'UPDATE operator_profiles SET is_verified = ? WHERE user_id = ?',
            [$verified ? 1 : 0, $id]
        );
        if ($changed !== 1) {
            // MySQL reports 0 changed rows when the value already matches, so
            // check the row actually exists before calling it a 404.
            if (Database::first('SELECT user_id FROM operator_profiles WHERE user_id = ?', [$id]) === null) {
                Response::error('Operator not found.', 404);
            }
        }

        Audit::record(
            Audit::MANAGER_VERIFIED_OPERATOR,
            $manager,
            'user',
            $id,
            $verified ? 'verified' : 'verification removed'
        );
        Response::json(['ok' => true, 'verified' => $verified]);
    }

    /**
     * POST api/manager/managers
     *
     * Only an existing manager can mint another, and only by re-entering their
     * own password. The new account starts with must_change_password set and
     * no second factor, which it is forced to enrol on first sign-in.
     */
    public function createManager(array $body): never
    {
        $manager = $this->gate();

        if (!Security::rateLimit('manager-create', (string) $manager['id'], 5, 3600)) {
            Response::error('Too many manager accounts created. Try again later.', 429);
        }

        $fullName = Validate::str($body['fullName'] ?? null, 'Full name', 2, 120);
        $email    = Validate::email($body['email'] ?? null);
        $phone    = Validate::phone($body['phone'] ?? null);
        $confirm  = Validate::str($body['confirmPassword'] ?? null, 'Your password', 1, 200);

        $me = Database::first('SELECT password_hash FROM users WHERE id = ?', [(int) $manager['id']]);
        if (!Auth::verifyPassword($confirm, (string) $me['password_hash'])) {
            Audit::record('manager.created.denied', $manager, null, null, 'wrong confirmation password');
            Response::error('Your password is incorrect.', 401);
        }

        $problems = Security::passwordProblems($body['password'] ?? null, $email, $fullName);
        if ($problems !== []) {
            Response::error("The new manager's password must " . implode(', ', $problems) . '.');
        }

        if (Database::first('SELECT id FROM users WHERE email = ?', [$email]) !== null) {
            Response::error('An account with that email already exists.', 409);
        }

        $newId = Database::insert(
            "INSERT INTO users (role, full_name, email, phone, password_hash, must_change_password, password_changed_at)
             VALUES ('manager', ?, ?, ?, ?, 1, NOW())",
            [$fullName, $email, $phone, Auth::hashPassword((string) $body['password'])]
        );

        Audit::record(Audit::MANAGER_CREATED, $manager, 'user', $newId, $email);

        Response::json([
            'user' => Auth::publicUser(Database::first('SELECT * FROM users WHERE id = ?', [$newId])),
            'note' => 'They must change this password and enrol two-factor authentication on first sign-in.',
        ], 201);
    }

    /* ==================================================================
       Audit and security
       ================================================================== */

    public function audit(array $query): never
    {
        $this->gate();

        $limit   = (int) Validate::num($query['limit'] ?? 80, 'Limit', 1, 300, false, true);
        $offset  = (int) Validate::num($query['offset'] ?? 0, 'Offset', 0, 100000, false, true);
        $action  = Validate::str($query['action'] ?? null, 'Action', 1, 60, false);
        $actorId = isset($query['actorId']) && $query['actorId'] !== ''
            ? (int) Validate::num($query['actorId'], 'Actor', 1, PHP_INT_MAX, false, true)
            : null;

        Response::json(Audit::listEntries($limit, $offset, $action, $actorId));
    }

    public function security(): never
    {
        $this->gate();

        Response::json([
            'failedLogins24h' => (int) Database::value(
                'SELECT COUNT(*) FROM login_attempts
                  WHERE succeeded = 0 AND created_at > (NOW() - INTERVAL 24 HOUR)',
                [],
                0
            ),
            'lockedAccounts' => (int) Database::value(
                'SELECT COUNT(*) FROM users WHERE locked_until > NOW()',
                [],
                0
            ),
            'activeSessions' => (int) Database::value(
                'SELECT COUNT(*) FROM sessions WHERE revoked_at IS NULL AND expires_at > NOW()',
                [],
                0
            ),
            'managersWithoutTwoFactor' => (int) Database::value(
                "SELECT COUNT(*) FROM users WHERE role = 'manager' AND totp_enabled = 0",
                [],
                0
            ),
            'topTargetedAccounts' => array_map(
                static fn (array $r): array => [
                    'email'       => $r['email'],
                    'attempts'    => (int) $r['attempts'],
                    'lastAttempt' => $r['last_attempt'],
                ],
                Database::all(
                    "SELECT email, COUNT(*) AS attempts, MAX(created_at) AS last_attempt
                       FROM login_attempts
                      WHERE succeeded = 0 AND created_at > (NOW() - INTERVAL 24 HOUR)
                        AND email NOT LIKE '%:%'
                      GROUP BY email ORDER BY attempts DESC LIMIT 8"
                )
            ),
        ]);
    }
}
