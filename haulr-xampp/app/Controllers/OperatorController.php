<?php
declare(strict_types=1);

namespace Haulr\Controllers;

use Haulr\{Auth, Config, Database, Domain, Response, Serialize, Validate};

final class OperatorController
{
    private function staleMinutes(): int
    {
        return (int) Config::get('operator_stale_minutes', 10);
    }

    /* ==================================================================
       Duty and profile
       ================================================================== */

    /** POST api/operator/status — go on or off duty. */
    public function setDuty(array $body): never
    {
        $user = Auth::requireRole('operator');

        $isOnline = Validate::bool($body['isOnline'] ?? false);
        $lat      = isset($body['lat']) ? Validate::latitude($body['lat']) : null;
        $lng      = isset($body['lng']) ? Validate::longitude($body['lng']) : null;
        $heading  = isset($body['heading']) ? Validate::num($body['heading'], 'Heading', 0, 360) : null;

        if ($isOnline && ($lat === null || $lng === null)) {
            Response::error('Share your location before going online — jobs are matched by distance.');
        }

        Database::run(
            'UPDATE operator_profiles
                SET is_online = ?,
                    last_lat = COALESCE(?, last_lat),
                    last_lng = COALESCE(?, last_lng),
                    last_heading = COALESCE(?, last_heading),
                    last_seen_at = NOW()
              WHERE user_id = ?',
            [$isOnline ? 1 : 0, $lat, $lng, $heading, (int) $user['id']]
        );

        Response::json(['operatorProfile' => Serialize::operatorProfile((int) $user['id'])]);
    }

    /** PATCH api/operator/profile */
    public function updateProfile(array $body): never
    {
        $user = Auth::requireRole('operator');

        $vehicleClass = isset($body['vehicleClass']) && $body['vehicleClass'] !== ''
            ? Validate::oneOf($body['vehicleClass'], 'Vehicle type', Domain::vehicleIds())
            : null;

        Database::run(
            'UPDATE operator_profiles
                SET vehicle_class     = COALESCE(?, vehicle_class),
                    vehicle_make      = COALESCE(?, vehicle_make),
                    vehicle_model     = COALESCE(?, vehicle_model),
                    vehicle_plate     = COALESCE(?, vehicle_plate),
                    capacity_kg       = COALESCE(?, capacity_kg),
                    helpers_available = COALESCE(?, helpers_available),
                    has_tail_lift     = COALESCE(?, has_tail_lift),
                    bio               = COALESCE(?, bio)
              WHERE user_id = ?',
            [
                $vehicleClass,
                Validate::str($body['vehicleMake'] ?? null, 'Vehicle make', 1, 60, false),
                Validate::str($body['vehicleModel'] ?? null, 'Vehicle model', 1, 60, false),
                Validate::str($body['vehiclePlate'] ?? null, 'Number plate', 2, 16, false),
                Validate::num($body['capacityKg'] ?? null, 'Capacity', 1, 40000, false, true),
                Validate::num($body['helpersAvailable'] ?? null, 'Helpers', 0, 6, false, true),
                isset($body['hasTailLift']) ? (Validate::bool($body['hasTailLift']) ? 1 : 0) : null,
                Validate::str($body['bio'] ?? null, 'About you', 1, 400, false),
                (int) $user['id'],
            ]
        );

        Response::json(['operatorProfile' => Serialize::operatorProfile((int) $user['id'])]);
    }

    /* ==================================================================
       Jobs board
       ================================================================== */

    /**
     * GET api/operator/board
     * Everything still up for grabs that this driver's vehicle can handle,
     * nearest first.
     */
    public function board(array $query): never
    {
        $user = Auth::requireRole('operator');

        $profile = Database::first('SELECT * FROM operator_profiles WHERE user_id = ?', [(int) $user['id']]);
        if ($profile === null) {
            Response::error('Your operator profile is incomplete.');
        }

        $lat = isset($query['lat']) && $query['lat'] !== ''
            ? Validate::latitude($query['lat'])
            : ($profile['last_lat'] === null ? null : (float) $profile['last_lat']);
        $lng = isset($query['lng']) && $query['lng'] !== ''
            ? Validate::longitude($query['lng'])
            : ($profile['last_lng'] === null ? null : (float) $profile['last_lng']);

        $radiusKm = (float) Validate::num(
            $query['radiusKm'] ?? Config::get('dispatch_radius_km', 25),
            'Radius',
            1,
            500,
            false
        );

        $mine = Domain::vehicle((string) $profile['vehicle_class']);
        if ($mine === null) {
            Response::json(['jobs' => []]);
        }

        $eligible = array_values(array_map(
            static fn (array $v): string => $v['id'],
            array_filter(
                Domain::VEHICLE_CLASSES,
                static fn (array $v): bool => $v['capacityKg'] <= $mine['capacityKg']
            )
        ));
        $placeholders = implode(',', array_fill(0, count($eligible), '?'));

        $rows = Database::all(
            "SELECT t.*,
                    (SELECT COUNT(*) FROM offers o WHERE o.trip_id = t.id AND o.status = 'pending') AS offer_count,
                    (SELECT MIN(o.price) FROM offers o WHERE o.trip_id = t.id AND o.status = 'pending') AS best_offer,
                    (SELECT o.id FROM offers o WHERE o.trip_id = t.id AND o.operator_id = ?) AS my_offer_id,
                    (SELECT o.price FROM offers o WHERE o.trip_id = t.id AND o.operator_id = ?) AS my_offer_price
               FROM trips t
              WHERE t.status = 'requested'
                AND t.customer_id <> ?
                AND t.vehicle_class IN ($placeholders)
                AND t.helpers_required <= ?
              ORDER BY t.created_at DESC
              LIMIT 100",
            array_merge(
                [(int) $user['id'], (int) $user['id'], (int) $user['id']],
                $eligible,
                [$mine['maxHelpers']]
            )
        );

        $jobs = [];
        foreach ($rows as $row) {
            $job = Serialize::trip($row, null);
            $job['myOfferId']    = $row['my_offer_id'] === null ? null : (int) $row['my_offer_id'];
            $job['myOfferPrice'] = $row['my_offer_price'] === null ? null : (float) $row['my_offer_price'];
            $job['guide'] = Domain::priceGuide(
                (string) $row['vehicle_class'],
                (float) $row['distance_km'],
                (int) $row['helpers_required'],
                (int) $row['pickup_floor'],
                (int) $row['dropoff_floor'],
                (bool) $row['pickup_has_lift'],
                (bool) $row['dropoff_has_lift']
            );

            if ($lat !== null && $lng !== null) {
                $toPickup = round(
                    Domain::haversineKm($lat, $lng, (float) $row['pickup_lat'], (float) $row['pickup_lng']) * 1.35,
                    2
                );
                if ($toPickup > $radiusKm) {
                    continue;
                }
                $job['distanceToPickupKm'] = $toPickup;
                $job['minutesToPickup']    = Domain::etaMinutes($toPickup);
            }

            $jobs[] = $job;
        }

        usort($jobs, static fn (array $a, array $b): int =>
            ($a['distanceToPickupKm'] ?? 1e9) <=> ($b['distanceToPickupKm'] ?? 1e9));

        Response::json([
            'jobs'     => $jobs,
            'radiusKm' => $radiusKm,
            'origin'   => $lat === null ? null : ['lat' => $lat, 'lng' => $lng],
        ]);
    }

    /** GET api/operator/stats */
    public function stats(): never
    {
        $user = Auth::requireRole('operator');
        $id = (int) $user['id'];

        $allTime = Database::first(
            "SELECT COUNT(*) AS jobs, COALESCE(SUM(agreed_price), 0) AS earnings
               FROM trips WHERE operator_id = ? AND status = 'completed'",
            [$id]
        );
        $week = Database::first(
            "SELECT COUNT(*) AS jobs, COALESCE(SUM(agreed_price), 0) AS earnings
               FROM trips WHERE operator_id = ? AND status = 'completed'
                 AND closed_at >= (NOW() - INTERVAL 7 DAY)",
            [$id]
        );
        $active = (int) Database::value(
            "SELECT COUNT(*) FROM trips
              WHERE operator_id = ? AND status IN ('accepted','en_route_pickup','at_pickup','in_transit')",
            [$id],
            0
        );
        $pendingOffers = (int) Database::value(
            "SELECT COUNT(*) FROM offers WHERE operator_id = ? AND status = 'pending'",
            [$id],
            0
        );
        $me = Database::first('SELECT rating_sum, rating_count FROM users WHERE id = ?', [$id]);

        Response::json([
            'allTime'       => ['jobs' => (int) $allTime['jobs'], 'earnings' => (float) $allTime['earnings']],
            'last7Days'     => ['jobs' => (int) $week['jobs'], 'earnings' => (float) $week['earnings']],
            'activeJobs'    => $active,
            'pendingOffers' => $pendingOffers,
            'rating'        => Serialize::ratingOf($me['rating_sum'], $me['rating_count']),
            'ratingCount'   => (int) $me['rating_count'],
        ]);
    }

    /* ==================================================================
       Nearby vehicles
       ================================================================== */

    /**
     * GET api/operators/nearby
     * Anonymised live vehicle positions for the customer's booking map. No
     * identities are exposed — just an opaque key so markers can animate.
     */
    public function nearby(array $query): never
    {
        Auth::requireAuth();

        $lat      = Validate::latitude($query['lat'] ?? null);
        $lng      = Validate::longitude($query['lng'] ?? null);
        $radiusKm = (float) Validate::num($query['radiusKm'] ?? 15, 'Radius', 1, 200, false);

        $vehicleClass = isset($query['vehicleClass']) && $query['vehicleClass'] !== ''
            ? Validate::oneOf($query['vehicleClass'], 'Vehicle type', Domain::vehicleIds())
            : null;

        $sql = 'SELECT user_id, vehicle_class, last_lat, last_lng, last_heading
                  FROM operator_profiles
                 WHERE is_online = 1 AND last_lat IS NOT NULL
                   AND last_seen_at >= (NOW() - INTERVAL ? MINUTE)';
        $params = [$this->staleMinutes()];

        if ($vehicleClass !== null) {
            $sql .= ' AND vehicle_class = ?';
            $params[] = $vehicleClass;
        }
        $sql .= ' LIMIT 500';

        $vehicles = [];
        foreach (Database::all($sql, $params) as $row) {
            $distance = round(Domain::haversineKm($lat, $lng, (float) $row['last_lat'], (float) $row['last_lng']), 2);
            if ($distance > $radiusKm) {
                continue;
            }
            $vehicles[] = [
                // Opaque per-vehicle key: the map can follow a marker between
                // polls without learning which driver it is.
                'key'          => 'v' . $row['user_id'],
                'vehicleClass' => $row['vehicle_class'],
                'lat'          => (float) $row['last_lat'],
                'lng'          => (float) $row['last_lng'],
                'heading'      => $row['last_heading'] === null ? null : (float) $row['last_heading'],
                '_distance'    => $distance,
            ];
        }

        usort($vehicles, static fn (array $a, array $b): int => $a['_distance'] <=> $b['_distance']);
        $vehicles = array_slice($vehicles, 0, 60);

        $nearest = $vehicles[0]['_distance'] ?? null;
        foreach ($vehicles as &$vehicle) {
            unset($vehicle['_distance']);
        }
        unset($vehicle);

        Response::json([
            'vehicles'       => $vehicles,
            'count'          => count($vehicles),
            'nearestKm'      => $nearest,
            'nearestMinutes' => $nearest === null ? null : Domain::etaMinutes($nearest * 1.35),
        ]);
    }

    /**
     * GET api/public/activity
     *
     * The marketing map. Positions are snapped to a ~1.1 km grid and
     * de-duplicated before they leave the server, so a signed-out visitor can
     * see the service is busy without being able to follow any one driver.
     */
    public function publicActivity(): never
    {
        $rows = Database::all(
            'SELECT vehicle_class, last_lat, last_lng
               FROM operator_profiles
              WHERE is_online = 1 AND last_lat IS NOT NULL
                AND last_seen_at >= (NOW() - INTERVAL ? MINUTE)
              LIMIT 500',
            [$this->staleMinutes()]
        );

        $grid = 0.01; // ≈1.1 km
        $cells = [];
        $sumLat = 0.0;
        $sumLng = 0.0;

        foreach ($rows as $row) {
            $lat = round(((float) $row['last_lat']) / $grid) * $grid;
            $lng = round(((float) $row['last_lng']) / $grid) * $grid;
            $key = number_format($lat, 2, '.', '') . ',' . number_format($lng, 2, '.', '');

            $cells[$key] ??= ['key' => $key, 'lat' => $lat, 'lng' => $lng, 'vehicleClass' => $row['vehicle_class'], 'count' => 0];
            $cells[$key]['count']++;

            $sumLat += (float) $row['last_lat'];
            $sumLng += (float) $row['last_lng'];
        }

        $count = count($rows);
        Response::json([
            'online' => $count,
            'centre' => $count > 0 ? ['lat' => $sumLat / $count, 'lng' => $sumLng / $count] : null,
            'cells'  => array_slice(array_values($cells), 0, 80),
        ]);
    }
}
