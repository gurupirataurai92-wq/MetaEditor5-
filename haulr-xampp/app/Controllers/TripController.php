<?php
declare(strict_types=1);

namespace Haulr\Controllers;

use Haulr\{Auth, Database, Domain, Events, Response, Serialize, Validate};

final class TripController
{
    /* ==================================================================
       Shared helpers
       ================================================================== */

    public static function loadTrip(int $id): array
    {
        $trip = Database::first('SELECT * FROM trips WHERE id = ?', [$id]);
        if ($trip === null) {
            Response::error('Job not found.', 404);
        }
        return $trip;
    }

    public static function isParty(array $trip, array $user): bool
    {
        $id = (int) $user['id'];
        return (int) $trip['customer_id'] === $id
            || ($trip['operator_id'] !== null && (int) $trip['operator_id'] === $id)
            || $user['role'] === 'manager';
    }

    public static function logEvent(int $tripId, ?int $actorId, string $type, ?string $note = null, ?float $lat = null, ?float $lng = null): void
    {
        Database::run(
            'INSERT INTO trip_events (trip_id, actor_id, type, note, lat, lng) VALUES (?, ?, ?, ?, ?, ?)',
            [$tripId, $actorId, $type, $note, $lat, $lng]
        );
    }

    /** Re-read a job and push it to everyone watching, plus both parties. */
    public static function broadcast(int $tripId, string $reason = ''): void
    {
        $row = Database::first('SELECT * FROM trips WHERE id = ?', [$tripId]);
        if ($row === null) {
            return;
        }
        // Serialised from the customer's viewpoint: both parties are entitled
        // to the same contact details once a job is assigned.
        $payload = [
            'tripId' => $tripId,
            'trip'   => Serialize::trip($row, (int) $row['customer_id']),
            'reason' => $reason,
        ];

        Events::toTrip($tripId, 'trip_update', $payload);
        Events::toUser((int) $row['customer_id'], 'trip_update', $payload);
        if ($row['operator_id'] !== null) {
            Events::toUser((int) $row['operator_id'], 'trip_update', $payload);
        }
    }

    /* ==================================================================
       Quote
       ================================================================== */

    /** POST api/quote — price guidance as the pins move on the booking map. */
    public function quote(array $body): never
    {
        Auth::requireAuth();

        $vehicleClass = Validate::oneOf($body['vehicleClass'] ?? null, 'Vehicle type', Domain::vehicleIds());
        $pickupLat    = Validate::latitude($body['pickupLat'] ?? null, 'Pickup latitude');
        $pickupLng    = Validate::longitude($body['pickupLng'] ?? null, 'Pickup longitude');
        $dropoffLat   = Validate::latitude($body['dropoffLat'] ?? null, 'Drop-off latitude');
        $dropoffLng   = Validate::longitude($body['dropoffLng'] ?? null, 'Drop-off longitude');

        $distanceKm = Domain::roadDistanceKm($pickupLat, $pickupLng, $dropoffLat, $dropoffLng);

        $guide = Domain::priceGuide(
            $vehicleClass,
            $distanceKm,
            (int) (Validate::num($body['helpersRequired'] ?? 0, 'Helpers', 0, 6, false, true) ?? 0),
            (int) (Validate::num($body['pickupFloor'] ?? 0, 'Pickup floor', 0, 60, false, true) ?? 0),
            (int) (Validate::num($body['dropoffFloor'] ?? 0, 'Drop-off floor', 0, 60, false, true) ?? 0),
            Validate::bool($body['pickupHasLift'] ?? false),
            Validate::bool($body['dropoffHasLift'] ?? false)
        );

        Response::json(array_merge($guide, ['driveMinutes' => Domain::etaMinutes($distanceKm)]));
    }

    /* ==================================================================
       Create
       ================================================================== */

    /** POST api/trips — the customer posts a job at the price they will pay. */
    public function create(array $body): never
    {
        $user = Auth::requireRole('customer');

        $category     = Validate::oneOf($body['category'] ?? null, 'Category', Domain::categoryIds());
        $vehicleClass = Validate::oneOf($body['vehicleClass'] ?? null, 'Vehicle type', Domain::vehicleIds());
        $spec         = Domain::vehicle($vehicleClass);

        $pickup = [
            'address' => Validate::str($body['pickupAddress'] ?? null, 'Pickup address', 4, 300),
            'lat'     => Validate::latitude($body['pickupLat'] ?? null, 'Pickup latitude'),
            'lng'     => Validate::longitude($body['pickupLng'] ?? null, 'Pickup longitude'),
            'contact' => Validate::str($body['pickupContact'] ?? null, 'Pickup contact', 1, 120, false),
            'floor'   => (int) (Validate::num($body['pickupFloor'] ?? 0, 'Pickup floor', 0, 60, false, true) ?? 0),
            'lift'    => Validate::bool($body['pickupHasLift'] ?? false),
        ];
        $dropoff = [
            'address' => Validate::str($body['dropoffAddress'] ?? null, 'Drop-off address', 4, 300),
            'lat'     => Validate::latitude($body['dropoffLat'] ?? null, 'Drop-off latitude'),
            'lng'     => Validate::longitude($body['dropoffLng'] ?? null, 'Drop-off longitude'),
            'contact' => Validate::str($body['dropoffContact'] ?? null, 'Drop-off contact', 1, 120, false),
            'floor'   => (int) (Validate::num($body['dropoffFloor'] ?? 0, 'Drop-off floor', 0, 60, false, true) ?? 0),
            'lift'    => Validate::bool($body['dropoffHasLift'] ?? false),
        ];

        $description = Validate::str($body['itemDescription'] ?? null, 'What are we moving', 4, 1000);
        $weight      = (int) (Validate::num($body['weightEstimateKg'] ?? 0, 'Estimated weight', 0, 40000, false, true) ?? 0);
        $helpers     = (int) (Validate::num($body['helpersRequired'] ?? 0, 'Helpers', 0, 6, false, true) ?? 0);
        $offerPrice  = (float) Validate::num($body['offerPrice'] ?? null, 'Your offer', 1, 1000000);
        $payment     = Validate::oneOf($body['paymentMethod'] ?? 'cash', 'Payment method', Domain::paymentIds());

        if ($helpers > $spec['maxHelpers']) {
            Response::error(
                'A ' . mb_strtolower($spec['name']) . " can bring at most {$spec['maxHelpers']} helper(s). Pick a bigger vehicle."
            );
        }
        if ($weight > $spec['capacityKg']) {
            Response::error(
                'A ' . mb_strtolower($spec['name']) . " carries up to {$spec['capacityKg']} kg. Pick a bigger vehicle."
            );
        }

        $scheduledAt = Validate::datetime($body['scheduledAt'] ?? null, 'Scheduled time');
        if ($scheduledAt !== null && strtotime($scheduledAt) < time() - 60) {
            Response::error('Scheduled time cannot be in the past.');
        }

        $openJobs = (int) Database::value(
            "SELECT COUNT(*) FROM trips
              WHERE customer_id = ? AND status IN ('requested','accepted','en_route_pickup','at_pickup','in_transit')",
            [(int) $user['id']],
            0
        );
        if ($openJobs >= 10) {
            Response::error('You already have 10 jobs in flight. Finish or cancel one first.', 429);
        }

        $distanceKm = Domain::roadDistanceKm($pickup['lat'], $pickup['lng'], $dropoff['lat'], $dropoff['lng']);

        // References are random, so retry on the (very unlikely) collision.
        $tripId = null;
        for ($attempt = 0; $attempt < 5 && $tripId === null; $attempt++) {
            try {
                $tripId = Database::insert(
                    'INSERT INTO trips (
                        reference, customer_id, category, vehicle_class,
                        pickup_address, pickup_lat, pickup_lng, pickup_contact, pickup_floor, pickup_has_lift,
                        dropoff_address, dropoff_lat, dropoff_lng, dropoff_contact, dropoff_floor, dropoff_has_lift,
                        distance_km, item_description, weight_estimate_kg, helpers_required, scheduled_at,
                        customer_offer_price, payment_method
                     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                    [
                        Domain::makeReference(), (int) $user['id'], $category, $vehicleClass,
                        $pickup['address'], $pickup['lat'], $pickup['lng'], $pickup['contact'], $pickup['floor'], $pickup['lift'] ? 1 : 0,
                        $dropoff['address'], $dropoff['lat'], $dropoff['lng'], $dropoff['contact'], $dropoff['floor'], $dropoff['lift'] ? 1 : 0,
                        $distanceKm, $description, $weight, $helpers, $scheduledAt,
                        $offerPrice, $payment,
                    ]
                );
            } catch (\PDOException $e) {
                if ($attempt === 4 || !str_contains($e->getMessage(), 'uq_trips_reference')) {
                    throw $e;
                }
            }
        }

        self::logEvent($tripId, (int) $user['id'], 'created', null, $pickup['lat'], $pickup['lng']);

        $row = Database::first('SELECT * FROM trips WHERE id = ?', [$tripId]);

        // Put it on the open board every on-duty driver is watching.
        Events::toDispatch('job_posted', ['trip' => Serialize::trip($row, null)]);

        Response::json(['trip' => Serialize::trip($row, (int) $user['id'])], 201);
    }

    /* ==================================================================
       Read
       ================================================================== */

    /** GET api/trips?scope=active|history|all */
    public function index(array $query): never
    {
        $user  = Auth::requireAuth();
        $scope = Validate::oneOf($query['scope'] ?? 'all', 'Scope', ['active', 'history', 'all']);
        $limit = (int) Validate::num($query['limit'] ?? 50, 'Limit', 1, 200, false, true);

        $column = $user['role'] === 'operator' ? 'operator_id' : 'customer_id';
        $placeholders = implode(',', array_fill(0, count(Domain::ACTIVE_STATUSES), '?'));

        $sql = "SELECT t.*,
                       (SELECT COUNT(*) FROM offers o WHERE o.trip_id = t.id AND o.status = 'pending') AS offer_count,
                       (SELECT MIN(o.price) FROM offers o WHERE o.trip_id = t.id AND o.status = 'pending') AS best_offer
                  FROM trips t
                 WHERE t.$column = ?";
        $params = [(int) $user['id']];

        if ($scope === 'active') {
            $sql .= " AND t.status IN ($placeholders)";
            $params = array_merge($params, Domain::ACTIVE_STATUSES);
        } elseif ($scope === 'history') {
            $sql .= " AND t.status NOT IN ($placeholders)";
            $params = array_merge($params, Domain::ACTIVE_STATUSES);
        }

        $sql .= " ORDER BY t.created_at DESC, t.id DESC LIMIT $limit";

        $rows = Database::all($sql, $params);
        Response::json([
            'trips' => array_map(
                static fn (array $r): array => Serialize::trip($r, (int) $user['id']),
                $rows
            ),
        ]);
    }

    /** GET api/trips/{id} */
    public function show(int $id): never
    {
        $user = Auth::requireAuth();
        $trip = self::loadTrip($id);

        // Drivers may read a job while it is still open for bidding; contact
        // details stay hidden until it is assigned.
        $openToBidders = $user['role'] === 'operator' && $trip['status'] === 'requested';
        if (!self::isParty($trip, $user) && !$openToBidders) {
            Response::error('This job is not yours.', 403);
        }

        $payload = Serialize::trip($trip, (int) $user['id']);
        $payload['offerCount'] = (int) Database::value(
            "SELECT COUNT(*) FROM offers WHERE trip_id = ? AND status = 'pending'",
            [$id],
            0
        );

        if ($user['role'] === 'operator') {
            $payload['myOffer'] = Serialize::offer(
                Database::first('SELECT * FROM offers WHERE trip_id = ? AND operator_id = ?', [$id, (int) $user['id']])
            );
        }

        Response::json(['trip' => $payload]);
    }

    /* ==================================================================
       Status flow
       ================================================================== */

    /** POST api/trips/{id}/status — the driver walks the job forward. */
    public function updateStatus(int $id, array $body): never
    {
        $user = Auth::requireRole('operator');
        $trip = self::loadTrip($id);

        if ((int) $trip['operator_id'] !== (int) $user['id']) {
            Response::error('This job is not yours.', 403);
        }

        $target  = Validate::str($body['status'] ?? null, 'Status', 1, 32);
        $allowed = Domain::OPERATOR_TRANSITIONS[$trip['status']] ?? [];

        if (!in_array($target, $allowed, true)) {
            Response::error(
                "Cannot move a job from \"{$trip['status']}\" to \"$target\".",
                409,
                ['allowed' => $allowed]
            );
        }

        $lat = isset($body['lat']) ? Validate::latitude($body['lat']) : null;
        $lng = isset($body['lng']) ? Validate::longitude($body['lng']) : null;

        $stampColumn = match ($target) {
            'in_transit' => 'picked_up_at',
            'delivered'  => 'delivered_at',
            default      => null,
        };

        $sql = 'UPDATE trips SET status = ?' . ($stampColumn ? ", $stampColumn = NOW()" : '') . ' WHERE id = ?';
        Database::run($sql, [$target, $id]);

        self::logEvent($id, (int) $user['id'], "status:$target", null, $lat, $lng);
        self::broadcast($id, 'status');

        Response::json([
            'trip' => Serialize::trip(Database::first('SELECT * FROM trips WHERE id = ?', [$id]), (int) $user['id']),
        ]);
    }

    /* ==================================================================
       Cancel / release
       ================================================================== */

    /** POST api/trips/{id}/cancel — the customer stops a job. */
    public function cancel(int $id, array $body): never
    {
        $user = Auth::requireAuth();
        $trip = self::loadTrip($id);

        if (!self::isParty($trip, $user)) {
            Response::error('This job is not yours.', 403);
        }
        if ((int) $trip['customer_id'] !== (int) $user['id'] && $user['role'] !== 'manager') {
            Response::error('Drivers release a job instead of cancelling it.', 403);
        }

        $cancellable = ['requested', 'accepted', 'en_route_pickup', 'at_pickup'];
        if (!in_array($trip['status'], $cancellable, true)) {
            Response::error(
                $trip['status'] === 'in_transit'
                    ? 'The load is already on the vehicle. Contact support to stop this job.'
                    : "A {$trip['status']} job cannot be cancelled.",
                409
            );
        }

        $reason = Validate::str($body['reason'] ?? null, 'Reason', 3, 300, false);

        Database::transaction(static function () use ($id, $reason, $user): void {
            Database::run(
                "UPDATE trips SET status = 'cancelled', cancel_reason = ?, cancelled_by = ?, closed_at = NOW()
                  WHERE id = ?",
                [$reason, (string) $user['role'], $id]
            );
            Database::run("UPDATE offers SET status = 'rejected' WHERE trip_id = ? AND status = 'pending'", [$id]);
        });

        self::logEvent($id, (int) $user['id'], 'cancelled', $reason);
        self::broadcast($id, 'cancelled');
        Events::toDispatch('job_closed', ['tripId' => $id]);

        Response::json(['ok' => true]);
    }

    /** POST api/trips/{id}/release — the driver drops a job back on the board. */
    public function release(int $id, array $body): never
    {
        $user = Auth::requireRole('operator');
        $trip = self::loadTrip($id);

        if ((int) $trip['operator_id'] !== (int) $user['id']) {
            Response::error('This job is not yours.', 403);
        }
        if (!in_array($trip['status'], ['accepted', 'en_route_pickup', 'at_pickup'], true)) {
            Response::error('This job can no longer be released.', 409);
        }

        $reason = Validate::str($body['reason'] ?? null, 'Reason', 3, 300, false);

        Database::transaction(static function () use ($id, $user): void {
            Database::run(
                "UPDATE trips
                    SET status = 'requested', operator_id = NULL, agreed_price = NULL, accepted_at = NULL
                  WHERE id = ?",
                [$id]
            );
            Database::run(
                "UPDATE offers SET status = 'withdrawn' WHERE trip_id = ? AND operator_id = ?",
                [$id, (int) $user['id']]
            );
        });

        self::logEvent($id, (int) $user['id'], 'released', $reason);
        self::broadcast($id, 'released');

        $row = Database::first('SELECT * FROM trips WHERE id = ?', [$id]);
        Events::toDispatch('job_posted', ['trip' => Serialize::trip($row, null)]);

        Response::json(['ok' => true]);
    }

    /* ==================================================================
       Rating
       ================================================================== */

    /** POST api/trips/{id}/rate — both sides rate each other. */
    public function rate(int $id, array $body): never
    {
        $user = Auth::requireAuth();
        $trip = self::loadTrip($id);

        if (!self::isParty($trip, $user)) {
            Response::error('This job is not yours.', 403);
        }
        if (!in_array($trip['status'], ['delivered', 'completed'], true)) {
            Response::error('You can only rate a job once it has been delivered.', 409);
        }

        $stars  = (int) Validate::num($body['rating'] ?? null, 'Rating', 1, 5, true, true);
        $review = Validate::str($body['review'] ?? null, 'Review', 1, 600, false);

        $isCustomer   = (int) $trip['customer_id'] === (int) $user['id'];
        $column       = $isCustomer ? 'operator_rating' : 'customer_rating';
        $ratedUserId  = $isCustomer ? $trip['operator_id'] : $trip['customer_id'];

        if ($trip[$column] !== null) {
            Response::error('You have already rated this job.', 409);
        }
        if ($ratedUserId === null) {
            Response::error('There is nobody to rate on this job.', 409);
        }

        Database::transaction(static function () use ($id, $column, $stars, $review, $isCustomer, $ratedUserId, $trip): void {
            if ($isCustomer) {
                Database::run(
                    "UPDATE trips SET $column = ?, customer_review = ? WHERE id = ?",
                    [$stars, $review, $id]
                );
            } else {
                Database::run("UPDATE trips SET $column = ? WHERE id = ?", [$stars, $id]);
            }

            Database::run(
                'UPDATE users SET rating_sum = rating_sum + ?, rating_count = rating_count + 1 WHERE id = ?',
                [$stars, (int) $ratedUserId]
            );

            if ($isCustomer) {
                Database::run("UPDATE trips SET status = 'completed', closed_at = NOW() WHERE id = ?", [$id]);
                Database::run(
                    'UPDATE operator_profiles SET trips_completed = trips_completed + 1 WHERE user_id = ?',
                    [(int) $trip['operator_id']]
                );
            }
        });

        self::logEvent($id, (int) $user['id'], 'rated', $stars . '★');
        self::broadcast($id, 'rated');

        Response::json(['ok' => true]);
    }

    /* ==================================================================
       Timeline and chat
       ================================================================== */

    public function events(int $id): never
    {
        $user = Auth::requireAuth();
        $trip = self::loadTrip($id);
        if (!self::isParty($trip, $user)) {
            Response::error('This job is not yours.', 403);
        }

        $rows = Database::all('SELECT * FROM trip_events WHERE trip_id = ? ORDER BY id ASC', [$id]);
        Response::json(['events' => array_map([Serialize::class, 'event'], $rows)]);
    }

    public function messages(int $id): never
    {
        $user = Auth::requireAuth();
        $trip = self::loadTrip($id);
        if (!self::isParty($trip, $user)) {
            Response::error('This job is not yours.', 403);
        }

        $rows = Database::all(
            'SELECT m.*, u.full_name AS sender_name
               FROM messages m JOIN users u ON u.id = m.sender_id
              WHERE m.trip_id = ? ORDER BY m.id ASC LIMIT 300',
            [$id]
        );
        Response::json(['messages' => array_map([Serialize::class, 'message'], $rows)]);
    }

    public function sendMessage(int $id, array $body): never
    {
        $user = Auth::requireAuth();
        $trip = self::loadTrip($id);

        if (!self::isParty($trip, $user)) {
            Response::error('This job is not yours.', 403);
        }
        if ($trip['operator_id'] === null) {
            Response::error('Chat opens once a driver is assigned.', 409);
        }

        $text = Validate::str($body['body'] ?? null, 'Message', 1, 1000);

        $messageId = Database::insert(
            'INSERT INTO messages (trip_id, sender_id, body) VALUES (?, ?, ?)',
            [$id, (int) $user['id'], $text]
        );

        $row = Database::first(
            'SELECT m.*, u.full_name AS sender_name
               FROM messages m JOIN users u ON u.id = m.sender_id
              WHERE m.id = ?',
            [$messageId]
        );
        $message = Serialize::message($row);

        Events::toTrip($id, 'message', ['tripId' => $id, 'message' => $message]);
        $otherId = (int) $user['id'] === (int) $trip['customer_id']
            ? (int) $trip['operator_id']
            : (int) $trip['customer_id'];
        Events::toUser($otherId, 'message', ['tripId' => $id, 'message' => $message]);

        Response::json(['message' => $message], 201);
    }
}
