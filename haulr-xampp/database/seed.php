<?php
declare(strict_types=1);

/**
 * Fills the database with a believable slice of activity so the site is
 * explorable the moment it boots.
 *
 * Run it from the browser once  ->  http://localhost/haulr/database/seed.php
 * or from a terminal            ->  php database/seed.php
 *
 * Safe to re-run: it clears its own rows first.
 */

namespace Haulr;

spl_autoload_register(static function (string $class): void {
    $prefix = 'Haulr\\';
    if (!str_starts_with($class, $prefix)) {
        return;
    }
    $file = dirname(__DIR__) . '/app/' . str_replace('\\', '/', substr($class, strlen($prefix))) . '.php';
    if (is_file($file)) {
        require_once $file;
    }
});

$isCli = PHP_SAPI === 'cli';
if (!$isCli) {
    header('Content-Type: text/plain; charset=utf-8');
    // Seeding wipes the database, so it is refused over the web once the
    // site is reachable from anywhere but this machine.
    $local = in_array($_SERVER['REMOTE_ADDR'] ?? '', ['127.0.0.1', '::1'], true);
    if (!$local) {
        http_response_code(403);
        exit("Seeding is only allowed from the machine running the server.\n");
    }
}

$out = static function (string $line = ''): void {
    echo $line . "\n";
    if (function_exists('flush')) {
        flush();
    }
};

// Centred on Johannesburg — change these to move the demo to your own city.
const CITY_LAT = -26.2041;
const CITY_LNG = 28.0473;
const DEMO_PASSWORD = 'Haulr!Demo2026';

/** A random point within roughly $km of the city centre. */
function jitter(float $km): array
{
    $dLat = (mt_rand() / mt_getrandmax() - 0.5) * 2 * ($km / 111);
    $dLng = (mt_rand() / mt_getrandmax() - 0.5) * 2 * ($km / (111 * cos(deg2rad(CITY_LAT))));
    return ['lat' => CITY_LAT + $dLat, 'lng' => CITY_LNG + $dLng];
}

const PLACES = [
    'Sandton City, Sandton',
    '14 Grayston Drive, Morningside',
    'Rosebank Mall, Rosebank',
    '88 Jan Smuts Ave, Parktown North',
    'Maboneng Precinct, Johannesburg CBD',
    'Eastgate Shopping Centre, Bedfordview',
    '21 Katherine Street, Sandown',
    'Melville, 7th Street',
    'Fourways Mall, Fourways',
    'Randburg, Republic Road',
    'Soweto, Vilakazi Street',
    'Midrand, Allandale Road',
];

function pick(array $items): mixed
{
    return $items[array_rand($items)];
}

/** Two different entries — a job whose ends match reads as a bug. */
function pickPair(array $items): array
{
    $a = pick($items);
    do {
        $b = pick($items);
    } while ($b === $a);
    return [$a, $b];
}

try {
    if (!Database::isInstalled()) {
        $out('The tables do not exist yet.');
        $out('Import database/schema.sql in phpMyAdmin first, then run this again.');
        exit(1);
    }

    $out('Seeding demo data…');

    $pdo = Database::pdo();
    $pdo->exec('SET FOREIGN_KEY_CHECKS = 0');
    foreach (['event_queue', 'audit_log', 'login_attempts', 'sessions', 'messages',
              'trip_locations', 'trip_events', 'offers', 'trips',
              'operator_profiles', 'users'] as $table) {
        $pdo->exec("TRUNCATE TABLE `$table`");
    }
    $pdo->exec('SET FOREIGN_KEY_CHECKS = 1');

    $passwordHash = Auth::hashPassword(DEMO_PASSWORD);

    $makeUser = static function (string $role, string $name, string $email, string $phone, float $ratingSum = 0, int $ratingCount = 0) use ($passwordHash): int {
        return Database::insert(
            'INSERT INTO users (role, full_name, email, phone, password_hash, rating_sum, rating_count, password_changed_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, NOW())',
            [$role, $name, $email, $phone, $passwordHash, $ratingSum, $ratingCount]
        );
    };

    // ---- Customers -------------------------------------------------------
    $customers = [
        $makeUser('customer', 'Thandi Mokoena',   'thandi@example.com', '+27 82 555 0111', 47, 10),
        $makeUser('customer', 'Riaan de Villiers','riaan@example.com',  '+27 83 555 0122', 18, 4),
        $makeUser('customer', 'Aisha Patel',      'aisha@example.com',  '+27 84 555 0133', 0, 0),
    ];

    // ---- Manager ---------------------------------------------------------
    // Managers are never created by self-service registration. This seeds the
    // first one; in a real deployment that is database/create_manager.php, and
    // every manager after it is created from inside the console.
    $managerSecret  = Totp::generateSecret();
    $recoveryCodes  = Totp::generateRecoveryCodes(5);
    $managerId      = $makeUser('manager', 'Grace Molefe', 'manager@example.com', '+27 82 555 0100');
    Database::run(
        'UPDATE users SET totp_secret = ?, totp_enabled = 1, recovery_codes = ? WHERE id = ?',
        [$managerSecret, json_encode(array_map([Totp::class, 'hashRecoveryCode'], $recoveryCodes)), $managerId]
    );

    // ---- Drivers ---------------------------------------------------------
    $operatorSpecs = [
        ['Sipho Ndlovu',    'sipho@example.com',  '+27 71 555 0201', 'motorbike', 'Honda',    'ACE 125',    'JHB 123 GP',  15,   0, 4.9, 128],
        ['Lerato Dlamini',  'lerato@example.com', '+27 72 555 0202', 'car',       'Toyota',   'Corolla',    'KL 44 MP GP', 80,   1, 4.7, 86],
        ['Johan Pretorius', 'johan@example.com',  '+27 73 555 0203', 'panel_van', 'Hyundai',  'H100',       'BX 09 YT GP', 800,  2, 4.8, 240],
        ['Nomsa Khumalo',   'nomsa@example.com',  '+27 74 555 0204', 'pickup',    'Ford',     'Ranger',     'CA 77 PL GP', 1000, 2, 4.6, 152],
        ['Ahmed Cassim',    'ahmed@example.com',  '+27 76 555 0205', 'truck_4t',  'Isuzu',    'NQR 500',    'DR 12 KK GP', 4000, 3, 4.9, 310],
        ['Pieter Botha',    'pieter@example.com', '+27 78 555 0206', 'truck_8t',  'Mercedes', 'Atego 1518', 'MN 55 QQ GP', 8000, 4, 4.5, 198],
        ['Zanele Mahlangu', 'zanele@example.com', '+27 79 555 0207', 'pickup',    'Nissan',   'NP200',      'PT 31 ZR GP', 800,  1, 5.0, 64],
        ['David Okafor',    'david@example.com',  '+27 81 555 0208', 'panel_van', 'VW',       'Crafter',    'SG 88 WW GP', 900,  2, 4.4, 41],
    ];

    $operators = [];
    foreach ($operatorSpecs as [$name, $email, $phone, $class, $make, $model, $plate, $capacity, $helpers, $rating, $trips]) {
        $id = $makeUser('operator', $name, $email, $phone, $rating * $trips, $trips);
        $pos = jitter(9);
        Database::run(
            'INSERT INTO operator_profiles
               (user_id, vehicle_class, vehicle_make, vehicle_model, vehicle_plate, capacity_kg,
                helpers_available, has_tail_lift, licence_number, bio, is_verified, is_online,
                last_lat, last_lng, last_heading, last_seen_at, trips_completed)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 1, ?, ?, ?, NOW(), ?)',
            [
                $id, $class, $make, $model, $plate, $capacity, $helpers,
                $capacity >= 4000 ? 1 : 0,
                'DL-' . random_int(100000, 999999),
                "$trips+ jobs done. Careful with fragile loads, blankets and straps always on board.",
                $pos['lat'], $pos['lng'], random_int(0, 359), $trips,
            ]
        );
        $operators[] = ['id' => $id, 'class' => $class, 'pos' => $pos];
    }

    // ---- Jobs ------------------------------------------------------------
    $createTrip = static function (array $o): array {
        $from = jitter(12);
        $to   = jitter(12);
        $distanceKm = Domain::roadDistanceKm($from['lat'], $from['lng'], $to['lat'], $to['lng']);
        $guide = Domain::priceGuide($o['vehicleClass'], $distanceKm, $o['helpers'] ?? 0);
        $price = (int) round($guide['recommended'] * ($o['priceFactor'] ?? 1));
        [$pickupPlace, $dropoffPlace] = pickPair(PLACES);

        $id = Database::insert(
            'INSERT INTO trips (
                reference, customer_id, operator_id, status, category, vehicle_class,
                pickup_address, pickup_lat, pickup_lng, pickup_contact, pickup_floor, pickup_has_lift,
                dropoff_address, dropoff_lat, dropoff_lng, dropoff_contact, dropoff_floor, dropoff_has_lift,
                distance_km, item_description, weight_estimate_kg, helpers_required,
                customer_offer_price, agreed_price, payment_method, accepted_at
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
                Domain::makeReference(), $o['customerId'], $o['operatorId'] ?? null,
                $o['status'] ?? 'requested', $o['category'], $o['vehicleClass'],
                $pickupPlace,  $from['lat'], $from['lng'], 'Gate code 4471',  random_int(0, 3), random_int(0, 1),
                $dropoffPlace, $to['lat'],   $to['lng'],   'Ring the buzzer', random_int(0, 3), random_int(0, 1),
                $distanceKm, $o['description'], $o['weight'] ?? 0, $o['helpers'] ?? 0,
                $price, isset($o['operatorId']) ? $price : null,
                pick(['cash', 'card', 'eft']),
                isset($o['operatorId']) ? date('Y-m-d H:i:s') : null,
            ]
        );

        Database::run(
            'INSERT INTO trip_events (trip_id, actor_id, type) VALUES (?, ?, ?)',
            [$id, $o['customerId'], 'created']
        );
        return ['id' => $id, 'from' => $from, 'to' => $to, 'price' => $price];
    };

    $openJobs = [
        $createTrip(['customerId' => $customers[0], 'category' => 'furniture',         'vehicleClass' => 'pickup',    'helpers' => 2, 'description' => 'Three-seater couch and a coffee table. Couch is heavy, needs two people.', 'weight' => 140]),
        $createTrip(['customerId' => $customers[1], 'category' => 'house_move',        'vehicleClass' => 'truck_4t',  'helpers' => 3, 'description' => 'One-bedroom flat: bed, wardrobe, fridge, washing machine, ~15 boxes.', 'weight' => 900]),
        $createTrip(['customerId' => $customers[2], 'category' => 'appliance',         'vehicleClass' => 'panel_van', 'helpers' => 1, 'description' => 'Double-door fridge, must stay upright the whole way.', 'weight' => 110]),
        $createTrip(['customerId' => $customers[0], 'category' => 'parcel',            'vehicleClass' => 'motorbike', 'description' => 'Signed contract envelope, urgent — recipient is waiting.', 'weight' => 1]),
        $createTrip(['customerId' => $customers[1], 'category' => 'building_material', 'vehicleClass' => 'pickup',    'helpers' => 1, 'description' => '20 bags of cement and 3 lengths of steel.', 'weight' => 700]),
        $createTrip(['customerId' => $customers[2], 'category' => 'office_move',       'vehicleClass' => 'truck_8t',  'helpers' => 4, 'description' => 'Small office: 12 desks, 14 chairs, server cabinet, filing units.', 'weight' => 3200, 'priceFactor' => 0.92]),
    ];

    // Bids on the open jobs, from drivers whose vehicle actually fits.
    $capacityOf = [];
    foreach (Domain::VEHICLE_CLASSES as $v) {
        $capacityOf[$v['id']] = $v['capacityKg'];
    }

    foreach ($openJobs as $job) {
        $trip = Database::first('SELECT * FROM trips WHERE id = ?', [$job['id']]);
        $eligible = array_values(array_filter(
            $operators,
            static fn (array $op): bool => $capacityOf[$op['class']] >= $capacityOf[$trip['vehicle_class']]
        ));
        foreach (array_slice($eligible, 0, random_int(2, 3)) as $op) {
            $swing = 0.88 + (mt_rand() / mt_getrandmax()) * 0.3;
            Database::run(
                'INSERT INTO offers (trip_id, operator_id, price, eta_minutes, message) VALUES (?, ?, ?, ?, ?)',
                [
                    $job['id'], $op['id'],
                    round(((float) $trip['customer_offer_price']) * $swing, 2),
                    random_int(8, 38),
                    pick([
                        'Can be there shortly, blankets and straps on board.',
                        'I am close by, happy to do it at this price.',
                        'Slightly higher — the stairs and the load size add time.',
                        null,
                    ]),
                ]
            );
        }
    }

    // A job that is live right now, with a GPS trail already laid down.
    $liveOperator = null;
    foreach ($operators as $op) {
        if ($op['class'] === 'pickup') {
            $liveOperator = $op;
            break;
        }
    }

    $live = $createTrip([
        'customerId'  => $customers[0],
        'operatorId'  => $liveOperator['id'],
        'status'      => 'in_transit',
        'category'    => 'furniture',
        'vehicleClass' => 'pickup',
        'helpers'     => 1,
        'description' => 'Queen bed base, mattress and a bedside table.',
        'weight'      => 95,
    ]);

    Database::run("UPDATE trips SET picked_up_at = (NOW() - INTERVAL 18 MINUTE) WHERE id = ?", [$live['id']]);
    Database::run(
        "INSERT INTO offers (trip_id, operator_id, price, eta_minutes, status) VALUES (?, ?, ?, ?, 'accepted')",
        [$live['id'], $liveOperator['id'], $live['price'], 12]
    );
    foreach ([['status:en_route_pickup', 40], ['status:at_pickup', 28], ['status:in_transit', 18]] as [$type, $minsAgo]) {
        Database::run(
            'INSERT INTO trip_events (trip_id, actor_id, type, created_at)
             VALUES (?, ?, ?, (NOW() - INTERVAL ? MINUTE))',
            [$live['id'], $liveOperator['id'], $type, $minsAgo]
        );
    }

    // Breadcrumbs from the pickup roughly two-thirds of the way to the drop-off.
    $steps = 24;
    for ($i = 0; $i <= $steps; $i++) {
        $t = ($i / $steps) * 0.66;
        Database::run(
            'INSERT INTO trip_locations (trip_id, operator_id, lat, lng, heading, speed_kph, accuracy_m, recorded_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, (NOW() - INTERVAL ? MINUTE))',
            [
                $live['id'], $liveOperator['id'],
                $live['from']['lat'] + ($live['to']['lat'] - $live['from']['lat']) * $t + (mt_rand() / mt_getrandmax() - 0.5) * 0.0016,
                $live['from']['lng'] + ($live['to']['lng'] - $live['from']['lng']) * $t + (mt_rand() / mt_getrandmax() - 0.5) * 0.0016,
                random_int(0, 359), random_int(18, 63), random_int(4, 16),
                (int) round(18 - ($i / $steps) * 18),
            ]
        );
    }
    Database::run(
        'UPDATE operator_profiles SET last_lat = ?, last_lng = ?, last_seen_at = NOW() WHERE user_id = ?',
        [
            $live['from']['lat'] + ($live['to']['lat'] - $live['from']['lat']) * 0.66,
            $live['from']['lng'] + ($live['to']['lng'] - $live['from']['lng']) * 0.66,
            $liveOperator['id'],
        ]
    );
    Database::run(
        'INSERT INTO messages (trip_id, sender_id, body) VALUES (?, ?, ?), (?, ?, ?)',
        [
            $live['id'], $liveOperator['id'], 'Loaded and on the way. Should be about 15 minutes.',
            $live['id'], $customers[0],       'Perfect, thank you. I will meet you at the gate.',
        ]
    );

    // Finished history so ratings and earnings are not empty.
    for ($i = 0; $i < 9; $i++) {
        $op = pick($operators);
        $done = $createTrip([
            'customerId'   => pick($customers),
            'operatorId'   => $op['id'],
            'status'       => 'completed',
            'category'     => pick(['parcel', 'furniture', 'appliance', 'shopping']),
            'vehicleClass' => $op['class'],
            'description'  => 'Completed job from the last few days.',
            'weight'       => 40,
        ]);
        Database::run(
            'UPDATE trips
                SET picked_up_at = (NOW() - INTERVAL ? DAY),
                    delivered_at = (NOW() - INTERVAL ? DAY),
                    closed_at    = (NOW() - INTERVAL ? DAY),
                    created_at   = (NOW() - INTERVAL ? DAY),
                    operator_rating = ?, customer_rating = 5
              WHERE id = ?',
            [$i + 1, $i + 1, $i + 1, $i + 1, random_int(4, 5), $done['id']]
        );
    }

    $counts = [
        'users'       => (int) Database::value('SELECT COUNT(*) FROM users', [], 0),
        'trips'       => (int) Database::value('SELECT COUNT(*) FROM trips', [], 0),
        'offers'      => (int) Database::value('SELECT COUNT(*) FROM offers', [], 0),
        'breadcrumbs' => (int) Database::value('SELECT COUNT(*) FROM trip_locations', [], 0),
    ];

    $out('Done. ' . json_encode($counts));
    $out('');
    $out('Sign in with any of these — the password for all of them is: ' . DEMO_PASSWORD);
    $out('');
    $out('  Customers (post jobs):');
    foreach (Database::all("SELECT email FROM users WHERE role='customer'") as $row) {
        $out('    ' . $row['email']);
    }
    $out('  Drivers (accept jobs):');
    foreach (Database::all("SELECT email FROM users WHERE role='operator'") as $row) {
        $out('    ' . $row['email']);
    }
    $out('');
    $out('  Manager (oversees everything): manager@example.com');
    $out('  Manager accounts need a second factor. Either:');
    $out('    a) add this secret to an authenticator app: ' . $managerSecret);
    $out('    b) sign in with one of these single-use recovery codes:');
    foreach ($recoveryCodes as $code) {
        $out('         ' . $code);
    }
    $out('    c) run:  php database/totp_code.php manager@example.com');
    $out('');
    $out('Live job to watch: track.html?trip=' . $live['id']);
} catch (\Throwable $e) {
    $out('Seeding failed: ' . $e->getMessage());
    exit(1);
}
