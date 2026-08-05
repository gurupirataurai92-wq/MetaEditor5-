<?php
declare(strict_types=1);

namespace Haulr\Controllers;

use Haulr\{Auth, Database, Domain, Events, Response, Serialize, Validate};

final class OfferController
{
    /**
     * POST api/trips/{id}/accept
     *
     * The driver takes the job outright at the price the customer already
     * named. No second confirmation is asked of the customer, and that is
     * deliberate: posting a job at a stated price *is* the offer, so a driver
     * agreeing to it forms the deal there and then. A counter at a different
     * price still goes through bidding, because that changes the terms.
     */
    public function accept(int $tripId): never
    {
        $user = Auth::requireRole('operator');
        $trip = TripController::loadTrip($tripId);

        if ($trip['status'] !== 'requested') {
            Response::error('This job has already been taken.', 409);
        }
        if ((int) $trip['customer_id'] === (int) $user['id']) {
            Response::error('You cannot take your own job.');
        }

        $profile = $this->requireProfile((int) $user['id']);
        $this->assertCanCarry($trip, $profile);

        $etaMinutes = $this->etaFrom($profile, $trip);

        $claimed = Database::transaction(static function () use ($tripId, $user, $trip, $etaMinutes): bool {
            // Guarded UPDATE — the race between two drivers tapping accept at
            // the same instant is settled by the database, not by who asked first.
            $changed = Database::affected(
                "UPDATE trips
                    SET status = 'accepted', operator_id = ?, agreed_price = customer_offer_price,
                        assigned_by = 'operator', accepted_at = NOW()
                  WHERE id = ? AND status = 'requested' AND operator_id IS NULL",
                [(int) $user['id'], $tripId]
            );
            if ($changed !== 1) {
                return false;
            }

            // Record the acceptance as an offer so the paper trail matches the
            // negotiated path exactly.
            Database::run(
                "INSERT INTO offers (trip_id, operator_id, price, eta_minutes, message, status)
                 VALUES (?, ?, ?, ?, ?, 'accepted')
                 ON DUPLICATE KEY UPDATE
                   price = VALUES(price), eta_minutes = VALUES(eta_minutes),
                   status = 'accepted', created_at = NOW()",
                [$tripId, (int) $user['id'], (float) $trip['customer_offer_price'], $etaMinutes, 'Accepted at your asking price']
            );
            Database::run(
                "UPDATE offers SET status = 'rejected'
                  WHERE trip_id = ? AND operator_id <> ? AND status = 'pending'",
                [$tripId, (int) $user['id']]
            );
            return true;
        });

        if (!$claimed) {
            Response::error('Another operator just took this job.', 409);
        }

        TripController::logEvent($tripId, (int) $user['id'], 'operator_accepted', (string) $trip['customer_offer_price']);
        TripController::broadcast($tripId, 'accepted');

        foreach (Database::all("SELECT operator_id FROM offers WHERE trip_id = ? AND status = 'rejected'", [$tripId]) as $lost) {
            Events::toUser((int) $lost['operator_id'], 'offer_rejected', ['tripId' => $tripId]);
        }
        Events::toDispatch('job_closed', ['tripId' => $tripId]);

        Response::json([
            'trip' => Serialize::trip(Database::first('SELECT * FROM trips WHERE id = ?', [$tripId]), (int) $user['id']),
        ]);
    }

    /**
     * POST api/trips/{id}/offers
     * A counter-offer: the driver names their own price and the customer picks.
     */
    public function create(int $tripId, array $body): never
    {
        $user = Auth::requireRole('operator');
        $trip = TripController::loadTrip($tripId);

        if ($trip['status'] !== 'requested') {
            Response::error('This job is no longer open for offers.', 409);
        }
        if ((int) $trip['customer_id'] === (int) $user['id']) {
            Response::error('You cannot bid on your own job.');
        }

        $profile = $this->requireProfile((int) $user['id']);
        $this->assertCanCarry($trip, $profile);

        $price   = (float) Validate::num($body['price'] ?? null, 'Your price', 1, 1000000);
        $message = Validate::str($body['message'] ?? null, 'Message', 1, 300, false);
        $eta     = Validate::num($body['etaMinutes'] ?? null, 'ETA', 1, 1440, false, true);
        $eta     = $eta === null ? $this->etaFrom($profile, $trip) : (int) $eta;

        $existing = Database::first(
            'SELECT * FROM offers WHERE trip_id = ? AND operator_id = ?',
            [$tripId, (int) $user['id']]
        );

        if ($existing !== null && $existing['status'] === 'accepted') {
            Response::error('Your offer was already accepted.', 409);
        }

        if ($existing !== null) {
            // Let a driver revise their bid while the job is still open.
            Database::run(
                "UPDATE offers SET price = ?, eta_minutes = ?, message = ?, status = 'pending', created_at = NOW()
                  WHERE id = ?",
                [$price, $eta, $message, (int) $existing['id']]
            );
            $offerId = (int) $existing['id'];
        } else {
            $offerId = Database::insert(
                'INSERT INTO offers (trip_id, operator_id, price, eta_minutes, message) VALUES (?, ?, ?, ?, ?)',
                [$tripId, (int) $user['id'], $price, $eta, $message]
            );
        }

        $offer = Serialize::offer(Database::first('SELECT * FROM offers WHERE id = ?', [$offerId]));
        TripController::logEvent(
            $tripId,
            (int) $user['id'],
            $existing !== null ? 'offer_updated' : 'offer_made',
            (string) $price
        );

        Events::toTrip($tripId, 'offer_new', ['tripId' => $tripId, 'offer' => $offer]);
        Events::toUser((int) $trip['customer_id'], 'offer_new', ['tripId' => $tripId, 'offer' => $offer]);

        Response::json(['offer' => $offer], $existing !== null ? 200 : 201);
    }

    /** GET api/trips/{id}/offers — customers see every bid, drivers only their own. */
    public function index(int $tripId): never
    {
        $user = Auth::requireAuth();
        $trip = TripController::loadTrip($tripId);

        $isCustomer = (int) $trip['customer_id'] === (int) $user['id'];
        if (!$isCustomer && !in_array($user['role'], ['operator', 'manager'], true)) {
            Response::error('This job is not yours.', 403);
        }

        $rows = ($isCustomer || $user['role'] === 'manager')
            ? Database::all(
                "SELECT * FROM offers WHERE trip_id = ? AND status IN ('pending','accepted')
                  ORDER BY price ASC, eta_minutes ASC",
                [$tripId]
            )
            : Database::all(
                'SELECT * FROM offers WHERE trip_id = ? AND operator_id = ?',
                [$tripId, (int) $user['id']]
            );

        Response::json(['offers' => array_map([Serialize::class, 'offer'], $rows)]);
    }

    /**
     * POST api/offers/{id}/accept
     * The customer picks a counter-offer. One transaction, so two drivers can
     * never both "win" the same job.
     */
    public function acceptOffer(int $offerId): never
    {
        $user  = Auth::requireRole('customer');
        $offer = Database::first('SELECT * FROM offers WHERE id = ?', [$offerId]);
        if ($offer === null) {
            Response::error('Offer not found.', 404);
        }

        $trip = Database::first('SELECT * FROM trips WHERE id = ?', [(int) $offer['trip_id']]);
        if ($trip === null) {
            Response::error('Job not found.', 404);
        }
        if ((int) $trip['customer_id'] !== (int) $user['id']) {
            Response::error('This job is not yours.', 403);
        }
        if ($trip['status'] !== 'requested') {
            Response::error('This job already has an operator.', 409);
        }
        if ($offer['status'] !== 'pending') {
            Response::error('That offer is no longer available.', 409);
        }

        $assigned = Database::transaction(static function () use ($offer, $trip): bool {
            $changed = Database::affected(
                "UPDATE trips
                    SET status = 'accepted', operator_id = ?, agreed_price = ?,
                        assigned_by = 'customer', accepted_at = NOW()
                  WHERE id = ? AND status = 'requested' AND operator_id IS NULL",
                [(int) $offer['operator_id'], (float) $offer['price'], (int) $trip['id']]
            );
            if ($changed !== 1) {
                return false;
            }

            Database::run("UPDATE offers SET status = 'accepted' WHERE id = ?", [(int) $offer['id']]);
            Database::run(
                "UPDATE offers SET status = 'rejected'
                  WHERE trip_id = ? AND id <> ? AND status = 'pending'",
                [(int) $trip['id'], (int) $offer['id']]
            );
            return true;
        });

        if (!$assigned) {
            Response::error('This job was just assigned to someone else.', 409);
        }

        $tripId = (int) $trip['id'];
        TripController::logEvent($tripId, (int) $user['id'], 'offer_accepted', (string) $offer['price']);
        TripController::broadcast($tripId, 'accepted');

        Events::toUser((int) $offer['operator_id'], 'offer_accepted', [
            'tripId'  => $tripId,
            'offerId' => (int) $offer['id'],
            'price'   => (float) $offer['price'],
        ]);
        foreach (Database::all("SELECT operator_id FROM offers WHERE trip_id = ? AND status = 'rejected'", [$tripId]) as $lost) {
            Events::toUser((int) $lost['operator_id'], 'offer_rejected', ['tripId' => $tripId]);
        }
        Events::toDispatch('job_closed', ['tripId' => $tripId]);

        Response::json([
            'trip' => Serialize::trip(Database::first('SELECT * FROM trips WHERE id = ?', [$tripId]), (int) $user['id']),
        ]);
    }

    /** DELETE api/offers/{id} — a driver pulls their bid. */
    public function withdraw(int $offerId): never
    {
        $user  = Auth::requireRole('operator');
        $offer = Database::first('SELECT * FROM offers WHERE id = ?', [$offerId]);

        if ($offer === null || (int) $offer['operator_id'] !== (int) $user['id']) {
            Response::error('Offer not found.', 404);
        }
        if ($offer['status'] !== 'pending') {
            Response::error('Only a pending offer can be withdrawn.', 409);
        }

        Database::run("UPDATE offers SET status = 'withdrawn' WHERE id = ?", [$offerId]);
        TripController::logEvent((int) $offer['trip_id'], (int) $user['id'], 'offer_withdrawn');

        $tripId = (int) $offer['trip_id'];
        Events::toTrip($tripId, 'offer_withdrawn', ['tripId' => $tripId, 'offerId' => $offerId]);
        $trip = Database::first('SELECT customer_id FROM trips WHERE id = ?', [$tripId]);
        if ($trip !== null) {
            Events::toUser((int) $trip['customer_id'], 'offer_withdrawn', ['tripId' => $tripId, 'offerId' => $offerId]);
        }

        Response::json(['ok' => true]);
    }

    /* ==================================================================
       Internals
       ================================================================== */

    private function requireProfile(int $userId): array
    {
        $profile = Database::first('SELECT * FROM operator_profiles WHERE user_id = ?', [$userId]);
        if ($profile === null) {
            Response::error('Add your vehicle details before taking jobs.');
        }
        return $profile;
    }

    /**
     * A driver may take a job needing their vehicle class or anything smaller
     * — a 4-ton truck can do a parcel run, a motorbike cannot move a couch.
     */
    private function assertCanCarry(array $trip, array $profile): void
    {
        $required = Domain::vehicle((string) $trip['vehicle_class']);
        $mine     = Domain::vehicle((string) $profile['vehicle_class']);

        if ($mine === null || $mine['capacityKg'] < $required['capacityKg']) {
            Response::error(
                'This job needs a ' . mb_strtolower($required['name']) . ' or bigger. Your '
                . ($mine !== null ? mb_strtolower($mine['name']) : 'vehicle') . ' is too small.'
            );
        }
        if ((int) $trip['helpers_required'] > $mine['maxHelpers']) {
            Response::error(
                'This job needs ' . (int) $trip['helpers_required']
                . ' helper(s); your vehicle class cannot bring that many.'
            );
        }
    }

    private function etaFrom(array $profile, array $trip): int
    {
        if ($profile['last_lat'] === null || $profile['last_lng'] === null) {
            return 20;
        }
        return Domain::etaMinutes(
            Domain::haversineKm(
                (float) $profile['last_lat'],
                (float) $profile['last_lng'],
                (float) $trip['pickup_lat'],
                (float) $trip['pickup_lng']
            ) * 1.35
        );
    }
}
