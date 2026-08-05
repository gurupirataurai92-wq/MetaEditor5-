<?php
declare(strict_types=1);

namespace Haulr;

/**
 * API response shapes.
 *
 * The contact-detail gating lives here, in one place, so no controller can
 * accidentally leak a phone number by forgetting a rule.
 */
final class Serialize
{
    public static function ratingOf(mixed $sum, mixed $count): ?float
    {
        $count = (int) $count;
        return $count > 0 ? round(((float) $sum) / $count, 2) : null;
    }

    /** The party summary embedded in a job — enough to render a card, no more. */
    public static function party(?int $userId): ?array
    {
        if ($userId === null) {
            return null;
        }

        $row = Database::first(
            'SELECT u.id, u.full_name, u.phone, u.rating_sum, u.rating_count,
                    p.vehicle_class, p.vehicle_make, p.vehicle_model, p.vehicle_plate,
                    p.is_verified, p.trips_completed
               FROM users u
               LEFT JOIN operator_profiles p ON p.user_id = u.id
              WHERE u.id = ?',
            [$userId]
        );
        if ($row === null) {
            return null;
        }

        return [
            'id'             => (int) $row['id'],
            'fullName'       => (string) $row['full_name'],
            'phone'          => $row['phone'],
            'rating'         => self::ratingOf($row['rating_sum'], $row['rating_count']),
            'ratingCount'    => (int) $row['rating_count'],
            'tripsCompleted' => (int) ($row['trips_completed'] ?? 0),
            'verified'       => (bool) ($row['is_verified'] ?? false),
            'vehicle'        => $row['vehicle_class'] === null ? null : [
                'class' => $row['vehicle_class'],
                'make'  => $row['vehicle_make'],
                'model' => $row['vehicle_model'],
                'plate' => $row['vehicle_plate'],
            ],
        ];
    }

    /**
     * Shape a job for the API.
     *
     * `$viewerId` controls contact-detail exposure: phone numbers only become
     * visible to the two parties once a job is actually assigned, so a driver
     * browsing the open board cannot harvest customer numbers.
     */
    public static function trip(?array $row, ?int $viewerId = null, bool $includeParties = true): ?array
    {
        if ($row === null) {
            return null;
        }

        $customerId = (int) $row['customer_id'];
        $operatorId = $row['operator_id'] === null ? null : (int) $row['operator_id'];

        $isParty  = $viewerId !== null && ($viewerId === $customerId || $viewerId === $operatorId);
        $assigned = $operatorId !== null;
        $shareContacts = $isParty && $assigned;

        $out = [
            'id'          => (int) $row['id'],
            'reference'   => (string) $row['reference'],
            'status'      => (string) $row['status'],
            'statusLabel' => Domain::STATUS_LABELS[$row['status']] ?? (string) $row['status'],
            'trackable'   => in_array($row['status'], Domain::TRACKABLE_STATUSES, true),
            'category'      => (string) $row['category'],
            'vehicleClass'  => (string) $row['vehicle_class'],

            'pickup' => [
                'address' => (string) $row['pickup_address'],
                'lat'     => (float) $row['pickup_lat'],
                'lng'     => (float) $row['pickup_lng'],
                'floor'   => (int) $row['pickup_floor'],
                'hasLift' => (bool) $row['pickup_has_lift'],
                'contact' => $shareContacts ? $row['pickup_contact'] : null,
            ],
            'dropoff' => [
                'address' => (string) $row['dropoff_address'],
                'lat'     => (float) $row['dropoff_lat'],
                'lng'     => (float) $row['dropoff_lng'],
                'floor'   => (int) $row['dropoff_floor'],
                'hasLift' => (bool) $row['dropoff_has_lift'],
                'contact' => $shareContacts ? $row['dropoff_contact'] : null,
            ],

            'distanceKm'         => (float) $row['distance_km'],
            'itemDescription'    => (string) $row['item_description'],
            'weightEstimateKg'   => (int) $row['weight_estimate_kg'],
            'helpersRequired'    => (int) $row['helpers_required'],
            'scheduledAt'        => $row['scheduled_at'],

            'customerOfferPrice' => (float) $row['customer_offer_price'],
            'agreedPrice'        => $row['agreed_price'] === null ? null : (float) $row['agreed_price'],
            'paymentMethod'      => (string) $row['payment_method'],

            'customerRating' => $row['customer_rating'] === null ? null : (int) $row['customer_rating'],
            'operatorRating' => $row['operator_rating'] === null ? null : (int) $row['operator_rating'],
            'customerReview' => $row['customer_review'],

            'cancelReason' => $row['cancel_reason'],
            'cancelledBy'  => $row['cancelled_by'],

            'createdAt'   => $row['created_at'],
            'acceptedAt'  => $row['accepted_at'],
            'pickedUpAt'  => $row['picked_up_at'],
            'deliveredAt' => $row['delivered_at'],
            'closedAt'    => $row['closed_at'],

            'customerId' => $customerId,
            'operatorId' => $operatorId,
        ];

        if ($includeParties) {
            $out['customer'] = self::party($customerId);
            $out['operator'] = self::party($operatorId);
            if ($out['customer'] !== null && !$shareContacts) {
                $out['customer']['phone'] = null;
            }
            if ($out['operator'] !== null && !$shareContacts) {
                $out['operator']['phone'] = null;
            }
        }

        if (array_key_exists('offer_count', $row)) {
            $out['offerCount'] = (int) $row['offer_count'];
        }
        if (array_key_exists('best_offer', $row)) {
            $out['bestOffer'] = $row['best_offer'] === null ? null : (float) $row['best_offer'];
        }

        return $out;
    }

    public static function offer(?array $row): ?array
    {
        if ($row === null) {
            return null;
        }
        return [
            'id'          => (int) $row['id'],
            'tripId'      => (int) $row['trip_id'],
            'operatorId'  => (int) $row['operator_id'],
            'price'       => (float) $row['price'],
            'etaMinutes'  => (int) $row['eta_minutes'],
            'message'     => $row['message'],
            'status'      => (string) $row['status'],
            'createdAt'   => $row['created_at'],
            'operator'    => self::party((int) $row['operator_id']),
        ];
    }

    public static function event(array $row): array
    {
        return [
            'id'        => (int) $row['id'],
            'tripId'    => (int) $row['trip_id'],
            'type'      => (string) $row['type'],
            'note'      => $row['note'],
            'lat'       => $row['lat'] === null ? null : (float) $row['lat'],
            'lng'       => $row['lng'] === null ? null : (float) $row['lng'],
            'createdAt' => $row['created_at'],
        ];
    }

    public static function location(array $row): array
    {
        return [
            'lat'        => (float) $row['lat'],
            'lng'        => (float) $row['lng'],
            'heading'    => $row['heading'] === null ? null : (float) $row['heading'],
            'speedKph'   => $row['speed_kph'] === null ? null : (float) $row['speed_kph'],
            'accuracyM'  => $row['accuracy_m'] === null ? null : (float) $row['accuracy_m'],
            'recordedAt' => $row['recorded_at'],
        ];
    }

    public static function message(array $row): array
    {
        return [
            'id'         => (int) $row['id'],
            'tripId'     => (int) $row['trip_id'],
            'senderId'   => (int) $row['sender_id'],
            'senderName' => $row['sender_name'] ?? null,
            'body'       => (string) $row['body'],
            'createdAt'  => $row['created_at'],
        ];
    }

    public static function operatorProfile(int $userId): ?array
    {
        $row = Database::first('SELECT * FROM operator_profiles WHERE user_id = ?', [$userId]);
        if ($row === null) {
            return null;
        }
        return [
            'vehicleClass'     => $row['vehicle_class'],
            'vehicleMake'      => $row['vehicle_make'],
            'vehicleModel'     => $row['vehicle_model'],
            'vehiclePlate'     => $row['vehicle_plate'],
            'capacityKg'       => (int) $row['capacity_kg'],
            'helpersAvailable' => (int) $row['helpers_available'],
            'hasTailLift'      => (bool) $row['has_tail_lift'],
            'licenceNumber'    => $row['licence_number'],
            'bio'              => $row['bio'],
            'isVerified'       => (bool) $row['is_verified'],
            'isOnline'         => (bool) $row['is_online'],
            'lastSeenAt'       => $row['last_seen_at'],
            'tripsCompleted'   => (int) $row['trips_completed'],
            'lastPosition'     => $row['last_lat'] === null ? null : [
                'lat'     => (float) $row['last_lat'],
                'lng'     => (float) $row['last_lng'],
                'heading' => $row['last_heading'] === null ? null : (float) $row['last_heading'],
            ],
        ];
    }
}
