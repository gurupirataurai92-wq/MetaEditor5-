<?php
declare(strict_types=1);

namespace Haulr\Controllers;

use Haulr\{Auth, Database, Domain, Events, Response, Serialize, Validate};

final class TrackingController
{
    // A phone emits GPS several times a second. Broadcast every ping so the
    // map stays smooth, but only persist a breadcrumb once the vehicle has
    // actually moved — otherwise a two-hour job writes tens of thousands of rows.
    private const MIN_BREADCRUMB_METRES = 25;
    private const MIN_BREADCRUMB_SECONDS = 15;

    /** Where is this job heading right now? */
    private function nextWaypoint(array $trip): array
    {
        $beforePickup = in_array($trip['status'], ['accepted', 'en_route_pickup', 'at_pickup'], true);
        return $beforePickup
            ? ['label' => 'pickup',  'lat' => (float) $trip['pickup_lat'],  'lng' => (float) $trip['pickup_lng'],  'address' => $trip['pickup_address']]
            : ['label' => 'dropoff', 'lat' => (float) $trip['dropoff_lat'], 'lng' => (float) $trip['dropoff_lng'], 'address' => $trip['dropoff_address']];
    }

    /** POST api/trips/{id}/location — the driver's device pushes its GPS fix. */
    public function push(int $tripId, array $body): never
    {
        $user = Auth::requireRole('operator');
        $trip = TripController::loadTrip($tripId);

        if ((int) $trip['operator_id'] !== (int) $user['id']) {
            Response::error('This job is not yours.', 403);
        }
        if (!in_array($trip['status'], Domain::TRACKABLE_STATUSES, true)) {
            Response::error('Tracking is not active for this job.', 409);
        }

        $lat       = Validate::latitude($body['lat'] ?? null);
        $lng       = Validate::longitude($body['lng'] ?? null);
        $heading   = isset($body['heading'])   ? Validate::num($body['heading'], 'Heading', 0, 360) : null;
        $speedKph  = isset($body['speedKph'])  ? Validate::num($body['speedKph'], 'Speed', 0, 300) : null;
        $accuracyM = isset($body['accuracyM']) ? Validate::num($body['accuracyM'], 'Accuracy', 0, 10000) : null;

        $last = Database::first(
            'SELECT lat, lng, recorded_at FROM trip_locations WHERE trip_id = ? ORDER BY id DESC LIMIT 1',
            [$tripId]
        );

        $stored = true;
        if ($last !== null) {
            $movedMetres = Domain::haversineKm((float) $last['lat'], (float) $last['lng'], $lat, $lng) * 1000;
            $agedSeconds = time() - strtotime((string) $last['recorded_at']);
            $stored = $movedMetres >= self::MIN_BREADCRUMB_METRES
                || $agedSeconds >= self::MIN_BREADCRUMB_SECONDS;
        }

        if ($stored) {
            Database::run(
                'INSERT INTO trip_locations (trip_id, operator_id, lat, lng, heading, speed_kph, accuracy_m)
                 VALUES (?, ?, ?, ?, ?, ?, ?)',
                [$tripId, (int) $user['id'], $lat, $lng, $heading, $speedKph, $accuracyM]
            );
        }

        // Keep the driver's last known position fresh for dispatch and for the
        // customer-facing nearby-vehicles map.
        Database::run(
            'UPDATE operator_profiles
                SET last_lat = ?, last_lng = ?, last_heading = COALESCE(?, last_heading), last_seen_at = NOW()
              WHERE user_id = ?',
            [$lat, $lng, $heading, (int) $user['id']]
        );

        $waypoint    = $this->nextWaypoint($trip);
        $remainingKm = round(Domain::haversineKm($lat, $lng, $waypoint['lat'], $waypoint['lng']) * 1.35, 2);
        $eta         = Domain::etaMinutes(
            $remainingKm,
            ($speedKph !== null && $speedKph > 8) ? min((float) $speedKph, 80.0) : 32.0
        );

        $update = [
            'tripId'     => $tripId,
            'position'   => [
                'lat'        => $lat,
                'lng'        => $lng,
                'heading'    => $heading,
                'speedKph'   => $speedKph,
                'accuracyM'  => $accuracyM,
                'recordedAt' => date('Y-m-d H:i:s'),
            ],
            'headingTo'   => $waypoint['label'],
            'remainingKm' => $remainingKm,
            'etaMinutes'  => $eta,
        ];

        Events::toTrip($tripId, 'location_update', $update);
        Events::toUser((int) $trip['customer_id'], 'location_update', $update);

        Response::json([
            'ok'          => true,
            'stored'      => $stored,
            'remainingKm' => $remainingKm,
            'etaMinutes'  => $eta,
        ]);
    }

    /**
     * GET api/trips/{id}/track
     * Everything the tracking screen needs in one call: the job, the driver's
     * current fix, the breadcrumb trail so far, and a live ETA.
     */
    public function track(int $tripId): never
    {
        $user = Auth::requireAuth();
        $trip = TripController::loadTrip($tripId);

        if (!TripController::isParty($trip, $user)) {
            Response::error('This job is not yours.', 403);
        }

        $trail = array_map(
            [Serialize::class, 'location'],
            Database::all(
                'SELECT lat, lng, heading, speed_kph, accuracy_m, recorded_at
                   FROM trip_locations WHERE trip_id = ? ORDER BY id ASC LIMIT 2000',
                [$tripId]
            )
        );

        $current  = $trail === [] ? null : $trail[count($trail) - 1];
        $waypoint = $this->nextWaypoint($trip);

        $remainingKm = null;
        $eta = null;
        if ($current !== null && in_array($trip['status'], Domain::TRACKABLE_STATUSES, true)) {
            $remainingKm = round(
                Domain::haversineKm($current['lat'], $current['lng'], $waypoint['lat'], $waypoint['lng']) * 1.35,
                2
            );
            $eta = Domain::etaMinutes($remainingKm);
        }

        Response::json([
            'trip'        => Serialize::trip($trip, (int) $user['id']),
            'current'     => $current,
            'trail'       => $trail,
            'headingTo'   => $waypoint,
            'remainingKm' => $remainingKm,
            'etaMinutes'  => $eta,
            'events'      => array_map(
                [Serialize::class, 'event'],
                Database::all('SELECT * FROM trip_events WHERE trip_id = ? ORDER BY id ASC', [$tripId])
            ),
        ]);
    }
}
