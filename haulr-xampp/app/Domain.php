<?php
declare(strict_types=1);

namespace Haulr;

/**
 * The catalogue and the pricing model.
 *
 * The browser fetches this same data from GET api/meta, so the prices shown on
 * screen and the prices the server calculates can never drift apart.
 */
final class Domain
{
    public const VEHICLE_CLASSES = [
        ['id' => 'motorbike', 'name' => 'Motorbike',       'blurb' => 'Documents, food, small parcels',   'capacityKg' => 15,   'maxHelpers' => 0, 'baseFare' => 25,  'perKm' => 6.5,  'icon' => '🏍️'],
        ['id' => 'car',       'name' => 'Car',             'blurb' => 'Boxes, laptops, shopping bags',    'capacityKg' => 80,   'maxHelpers' => 1, 'baseFare' => 45,  'perKm' => 9,    'icon' => '🚗'],
        ['id' => 'panel_van', 'name' => 'Panel van',       'blurb' => 'Appliances, bulk boxes, single items', 'capacityKg' => 800, 'maxHelpers' => 2, 'baseFare' => 120, 'perKm' => 14, 'icon' => '🚐'],
        ['id' => 'pickup',    'name' => 'Pickup / bakkie', 'blurb' => 'Fridges, couches, garden waste',   'capacityKg' => 1000, 'maxHelpers' => 2, 'baseFare' => 150, 'perKm' => 16,   'icon' => '🛻'],
        ['id' => 'truck_4t',  'name' => '4-ton truck',     'blurb' => 'Flat or 1-bed apartment move',     'capacityKg' => 4000, 'maxHelpers' => 3, 'baseFare' => 450, 'perKm' => 24,   'icon' => '🚚'],
        ['id' => 'truck_8t',  'name' => '8-ton truck',     'blurb' => 'Full house move, office relocation', 'capacityKg' => 8000, 'maxHelpers' => 4, 'baseFare' => 850, 'perKm' => 34, 'icon' => '🚛'],
    ];

    public const CATEGORIES = [
        ['id' => 'parcel',            'name' => 'Parcel / documents',  'suggests' => 'motorbike'],
        ['id' => 'shopping',          'name' => 'Shopping & groceries','suggests' => 'car'],
        ['id' => 'appliance',         'name' => 'Single appliance',    'suggests' => 'panel_van'],
        ['id' => 'furniture',         'name' => 'Furniture item',      'suggests' => 'pickup'],
        ['id' => 'house_move',        'name' => 'House / flat move',   'suggests' => 'truck_4t'],
        ['id' => 'office_move',       'name' => 'Office relocation',   'suggests' => 'truck_8t'],
        ['id' => 'building_material', 'name' => 'Building materials',  'suggests' => 'pickup'],
        ['id' => 'other',             'name' => 'Something else',      'suggests' => 'panel_van'],
    ];

    public const PAYMENT_METHODS = [
        ['id' => 'cash',   'name' => 'Cash on delivery'],
        ['id' => 'card',   'name' => 'Card (on file)'],
        ['id' => 'eft',    'name' => 'Instant EFT / transfer'],
        ['id' => 'wallet', 'name' => 'Haulr wallet'],
    ];

    public const HELPER_FEE_PER_PERSON = 120;
    public const FLOOR_FEE = 45;

    public const STATUS_LABELS = [
        'requested'       => 'Waiting for offers',
        'accepted'        => 'Operator assigned',
        'en_route_pickup' => 'On the way to pickup',
        'at_pickup'       => 'Loading at pickup',
        'in_transit'      => 'In transit',
        'delivered'       => 'Delivered',
        'completed'       => 'Completed',
        'cancelled'       => 'Cancelled',
    ];

    /** Which status a driver may move a job to, from where. */
    public const OPERATOR_TRANSITIONS = [
        'accepted'        => ['en_route_pickup'],
        'en_route_pickup' => ['at_pickup'],
        'at_pickup'       => ['in_transit'],
        'in_transit'      => ['delivered'],
    ];

    public const ACTIVE_STATUSES = ['requested', 'accepted', 'en_route_pickup', 'at_pickup', 'in_transit'];
    public const TRACKABLE_STATUSES = ['accepted', 'en_route_pickup', 'at_pickup', 'in_transit'];

    /** Straight-line distance under-reads real driving; 1.35 is a common urban detour factor. */
    private const ROAD_FACTOR = 1.35;
    private const EARTH_RADIUS_KM = 6371;

    public static function vehicle(string $id): ?array
    {
        foreach (self::VEHICLE_CLASSES as $vehicle) {
            if ($vehicle['id'] === $id) {
                return $vehicle;
            }
        }
        return null;
    }

    public static function vehicleIds(): array
    {
        return array_column(self::VEHICLE_CLASSES, 'id');
    }

    public static function categoryIds(): array
    {
        return array_column(self::CATEGORIES, 'id');
    }

    public static function paymentIds(): array
    {
        return array_column(self::PAYMENT_METHODS, 'id');
    }

    /** Great-circle distance in kilometres. */
    public static function haversineKm(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);
        $a = sin($dLat / 2) ** 2
            + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;
        return 2 * self::EARTH_RADIUS_KM * asin(min(1.0, sqrt($a)));
    }

    public static function roadDistanceKm(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        return round(self::haversineKm($lat1, $lng1, $lat2, $lng2) * self::ROAD_FACTOR, 2);
    }

    /** Rough drive time for a distance, at a conservative urban average speed. */
    public static function etaMinutes(float $distanceKm, float $averageSpeedKph = 32): int
    {
        if ($distanceKm <= 0) {
            return 0;
        }
        return max(1, (int) round(($distanceKm / $averageSpeedKph) * 60));
    }

    /**
     * Suggested price band. The customer is free to offer anything — this is
     * guidance, the same way inDrive shows a recommended fare.
     */
    public static function priceGuide(
        string $vehicleClass,
        float $distanceKm,
        int $helpers = 0,
        int $pickupFloor = 0,
        int $dropoffFloor = 0,
        bool $pickupHasLift = false,
        bool $dropoffHasLift = false
    ): ?array {
        $vehicle = self::vehicle($vehicleClass);
        if ($vehicle === null) {
            return null;
        }

        $distance = max(0.0, $distanceKm);
        $helperCount = max(0, min($helpers, $vehicle['maxHelpers']));

        $stairFloors = ($pickupHasLift ? 0 : max(0, $pickupFloor))
            + ($dropoffHasLift ? 0 : max(0, $dropoffFloor));

        $baseFare      = (float) $vehicle['baseFare'];
        $distanceFare  = $vehicle['perKm'] * $distance;
        $helperFee     = $helperCount * self::HELPER_FEE_PER_PERSON;
        $stairFee      = $stairFloors * self::FLOOR_FEE;
        $recommended   = $baseFare + $distanceFare + $helperFee + $stairFee;

        return [
            'vehicleClass' => $vehicleClass,
            'distanceKm'   => round($distance, 2),
            'breakdown'    => [
                'baseFare'     => round($baseFare, 2),
                'distanceFare' => round($distanceFare, 2),
                'helperFee'    => round($helperFee, 2),
                'stairFee'     => round($stairFee, 2),
            ],
            // Drivers routinely bid ~15% either side depending on how busy
            // they are, so show the band rather than a single number.
            'min'         => (int) max($baseFare, round($recommended * 0.85)),
            'recommended' => (int) round($recommended),
            'max'         => (int) round($recommended * 1.2),
        ];
    }

    /** Short human-facing job reference, e.g. HLR-7QK4M2. */
    public static function makeReference(): string
    {
        $alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
        $out = '';
        for ($i = 0; $i < 6; $i++) {
            $out .= $alphabet[random_int(0, strlen($alphabet) - 1)];
        }
        return 'HLR-' . $out;
    }
}
