'use strict';

// Populates the database with a believable slice of activity so the site is
// explorable the moment it boots. Safe to re-run: it clears its own rows first.

const { db, run, get, all } = require('./db');
const { hashPassword } = require('./auth');
const { roadDistanceKm, priceGuide, makeReference } = require('./domain');

// Centred on Johannesburg — change these to move the demo to your own city.
const CITY = { lat: -26.2041, lng: 28.0473 };
const DEMO_PASSWORD = 'haulr1234';

function jitter(km) {
  // ~111 km per degree of latitude; longitude shrinks with the cosine of lat.
  const dLat = (Math.random() - 0.5) * 2 * (km / 111);
  const dLng = (Math.random() - 0.5) * 2 * (km / (111 * Math.cos((CITY.lat * Math.PI) / 180)));
  return { lat: CITY.lat + dLat, lng: CITY.lng + dLng };
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

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];

/** Two different entries from `arr` — a job whose ends match reads as a bug. */
function pickPair(arr) {
  const a = pick(arr);
  let b = pick(arr);
  while (b === a) b = pick(arr);
  return [a, b];
}

async function seed() {
  console.log('Seeding demo data…');

  // Wipe in FK-safe order.
  for (const table of ['trip_locations', 'trip_events', 'messages', 'offers', 'trips', 'operator_profiles', 'users']) {
    run(`DELETE FROM ${table}`);
  }
  run("DELETE FROM sqlite_sequence WHERE name IN ('users','trips','offers','trip_events','trip_locations','messages')");

  const passwordHash = await hashPassword(DEMO_PASSWORD);

  const makeUser = (role, fullName, email, phone, ratingSum = 0, ratingCount = 0) =>
    Number(
      run(
        `INSERT INTO users (role, full_name, email, phone, password_hash, rating_sum, rating_count)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        role,
        fullName,
        email,
        phone,
        passwordHash,
        ratingSum,
        ratingCount
      ).lastInsertRowid
    );

  // ---- Customers -----------------------------------------------------------
  const customers = [
    makeUser('customer', 'Thandi Mokoena', 'thandi@example.com', '+27 82 555 0111', 47, 10),
    makeUser('customer', 'Riaan de Villiers', 'riaan@example.com', '+27 83 555 0122', 18, 4),
    makeUser('customer', 'Aisha Patel', 'aisha@example.com', '+27 84 555 0133', 0, 0),
  ];

  // ---- Operators -----------------------------------------------------------
  const operatorSpecs = [
    ['Sipho Ndlovu', 'sipho@example.com', '+27 71 555 0201', 'motorbike', 'Honda', 'ACE 125', 'JHB 123 GP', 15, 0, 4.9, 128],
    ['Lerato Dlamini', 'lerato@example.com', '+27 72 555 0202', 'car', 'Toyota', 'Corolla', 'KL 44 MP GP', 80, 1, 4.7, 86],
    ['Johan Pretorius', 'johan@example.com', '+27 73 555 0203', 'panel_van', 'Hyundai', 'H100', 'BX 09 YT GP', 800, 2, 4.8, 240],
    ['Nomsa Khumalo', 'nomsa@example.com', '+27 74 555 0204', 'pickup', 'Ford', 'Ranger', 'CA 77 PL GP', 1000, 2, 4.6, 152],
    ['Ahmed Cassim', 'ahmed@example.com', '+27 76 555 0205', 'truck_4t', 'Isuzu', 'NQR 500', 'DR 12 KK GP', 4000, 3, 4.9, 310],
    ['Pieter Botha', 'pieter@example.com', '+27 78 555 0206', 'truck_8t', 'Mercedes', 'Atego 1518', 'MN 55 QQ GP', 8000, 4, 4.5, 198],
    ['Zanele Mahlangu', 'zanele@example.com', '+27 79 555 0207', 'pickup', 'Nissan', 'NP200', 'PT 31 ZR GP', 800, 1, 5.0, 64],
    ['David Okafor', 'david@example.com', '+27 81 555 0208', 'panel_van', 'VW', 'Crafter', 'SG 88 WW GP', 900, 2, 4.4, 41],
  ];

  const operators = operatorSpecs.map(
    ([name, email, phone, vClass, make, model, plate, capacity, helpers, rating, trips]) => {
      const id = makeUser('operator', name, email, phone, rating * trips, trips);
      const pos = jitter(9);
      run(
        `INSERT INTO operator_profiles
           (user_id, vehicle_class, vehicle_make, vehicle_model, vehicle_plate, capacity_kg,
            helpers_available, has_tail_lift, licence_number, bio, is_verified, is_online,
            last_lat, last_lng, last_heading, last_seen_at, trips_completed)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 1, ?, ?, ?, datetime('now'), ?)`,
        id,
        vClass,
        make,
        model,
        plate,
        capacity,
        helpers,
        capacity >= 4000 ? 1 : 0,
        `DL-${Math.floor(100000 + Math.random() * 899999)}`,
        `${trips}+ jobs done. Careful with fragile loads, blankets and straps always on board.`,
        pos.lat,
        pos.lng,
        Math.floor(Math.random() * 360),
        trips
      );
      return { id, vehicleClass: vClass, pos };
    }
  );

  // ---- Jobs ----------------------------------------------------------------
  function createTrip({ customerId, operatorId = null, status = 'requested', category, vehicleClass, helpers = 0, description, weight, priceFactor = 1 }) {
    const from = jitter(12);
    const to = jitter(12);
    const distanceKm = roadDistanceKm(from.lat, from.lng, to.lat, to.lng);
    const guide = priceGuide({ vehicleClass, distanceKm, helpers });
    const offerPrice = Math.round(guide.recommended * priceFactor);
    const [pickupPlace, dropoffPlace] = pickPair(PLACES);

    const id = Number(
      run(
        `INSERT INTO trips (
           reference, customer_id, operator_id, status, category, vehicle_class,
           pickup_address, pickup_lat, pickup_lng, pickup_contact, pickup_floor, pickup_has_lift,
           dropoff_address, dropoff_lat, dropoff_lng, dropoff_contact, dropoff_floor, dropoff_has_lift,
           distance_km, item_description, weight_estimate_kg, helpers_required,
           customer_offer_price, agreed_price, payment_method, accepted_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        makeReference(),
        customerId,
        operatorId,
        status,
        category,
        vehicleClass,
        pickupPlace, from.lat, from.lng, 'Gate code 4471', Math.floor(Math.random() * 4), Math.random() > 0.5 ? 1 : 0,
        dropoffPlace, to.lat, to.lng, 'Ring the buzzer', Math.floor(Math.random() * 4), Math.random() > 0.5 ? 1 : 0,
        distanceKm,
        description,
        weight,
        helpers,
        offerPrice,
        operatorId ? offerPrice : null,
        pick(['cash', 'card', 'eft']),
        operatorId ? new Date().toISOString() : null
      ).lastInsertRowid
    );

    run('INSERT INTO trip_events (trip_id, actor_id, type) VALUES (?, ?, ?)', id, customerId, 'created');
    return { id, from, to, offerPrice };
  }

  // Open jobs waiting for bids.
  const openJobs = [
    createTrip({ customerId: customers[0], category: 'furniture', vehicleClass: 'pickup', helpers: 2, description: 'Three-seater couch and a coffee table. Couch is heavy, needs two people.', weight: 140 }),
    createTrip({ customerId: customers[1], category: 'house_move', vehicleClass: 'truck_4t', helpers: 3, description: 'One-bedroom flat: bed, wardrobe, fridge, washing machine, ~15 boxes.', weight: 900 }),
    createTrip({ customerId: customers[2], category: 'appliance', vehicleClass: 'panel_van', helpers: 1, description: 'Double-door fridge, must stay upright the whole way.', weight: 110 }),
    createTrip({ customerId: customers[0], category: 'parcel', vehicleClass: 'motorbike', description: 'Signed contract envelope, urgent — recipient is waiting.', weight: 1 }),
    createTrip({ customerId: customers[1], category: 'building_material', vehicleClass: 'pickup', helpers: 1, description: '20 bags of cement and 3 lengths of steel.', weight: 700 }),
    createTrip({ customerId: customers[2], category: 'office_move', vehicleClass: 'truck_8t', helpers: 4, description: 'Small office: 12 desks, 14 chairs, server cabinet, filing units.', weight: 3200, priceFactor: 0.92 }),
  ];

  // Bids on the open jobs, from operators whose vehicle actually fits.
  const capacityOf = { motorbike: 15, car: 80, panel_van: 800, pickup: 1000, truck_4t: 4000, truck_8t: 8000 };
  for (const job of openJobs) {
    const trip = get('SELECT * FROM trips WHERE id = ?', job.id);
    const eligible = operators.filter((o) => capacityOf[o.vehicleClass] >= capacityOf[trip.vehicle_class]);
    for (const op of eligible.slice(0, 2 + Math.floor(Math.random() * 2))) {
      const swing = 0.88 + Math.random() * 0.3;
      run(
        'INSERT INTO offers (trip_id, operator_id, price, eta_minutes, message) VALUES (?, ?, ?, ?, ?)',
        job.id,
        op.id,
        Math.round(trip.customer_offer_price * swing),
        8 + Math.floor(Math.random() * 30),
        pick([
          'Can be there shortly, blankets and straps on board.',
          'I am close by, happy to do it at this price.',
          'Slightly higher — the stairs and the load size add time.',
          null,
        ])
      );
    }
  }

  // A job that is live right now, with a GPS trail already laid down.
  const liveOperator = operators.find((o) => o.vehicleClass === 'pickup');
  const live = createTrip({
    customerId: customers[0],
    operatorId: liveOperator.id,
    status: 'in_transit',
    category: 'furniture',
    vehicleClass: 'pickup',
    helpers: 1,
    description: 'Queen bed base, mattress and a bedside table.',
    weight: 95,
  });
  run("UPDATE trips SET picked_up_at = datetime('now','-18 minutes') WHERE id = ?", live.id);
  run(
    "INSERT INTO offers (trip_id, operator_id, price, eta_minutes, status) VALUES (?, ?, ?, ?, 'accepted')",
    live.id,
    liveOperator.id,
    live.offerPrice,
    12
  );
  for (const [type, note, minsAgo] of [
    ['status:en_route_pickup', null, 40],
    ['status:at_pickup', null, 28],
    ['status:in_transit', null, 18],
  ]) {
    run(
      `INSERT INTO trip_events (trip_id, actor_id, type, note, created_at)
       VALUES (?, ?, ?, ?, datetime('now', ?))`,
      live.id,
      liveOperator.id,
      type,
      note,
      `-${minsAgo} minutes`
    );
  }
  // Lay breadcrumbs from the pickup roughly two-thirds of the way to the drop-off.
  const STEPS = 24;
  for (let i = 0; i <= STEPS; i += 1) {
    const t = (i / STEPS) * 0.66;
    run(
      `INSERT INTO trip_locations (trip_id, operator_id, lat, lng, heading, speed_kph, accuracy_m, recorded_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now', ?))`,
      live.id,
      liveOperator.id,
      live.from.lat + (live.to.lat - live.from.lat) * t + (Math.random() - 0.5) * 0.0016,
      live.from.lng + (live.to.lng - live.from.lng) * t + (Math.random() - 0.5) * 0.0016,
      Math.floor(Math.random() * 360),
      Math.round(18 + Math.random() * 45),
      Math.round(4 + Math.random() * 12),
      `-${Math.round(18 - (i / STEPS) * 18)} minutes`
    );
  }
  run(
    "UPDATE operator_profiles SET last_lat = ?, last_lng = ?, last_seen_at = datetime('now') WHERE user_id = ?",
    live.from.lat + (live.to.lat - live.from.lat) * 0.66,
    live.from.lng + (live.to.lng - live.from.lng) * 0.66,
    liveOperator.id
  );
  run(
    'INSERT INTO messages (trip_id, sender_id, body) VALUES (?, ?, ?), (?, ?, ?)',
    live.id, liveOperator.id, 'Loaded and on the way. Should be about 15 minutes.',
    live.id, customers[0], 'Perfect, thank you. I will meet you at the gate.'
  );

  // Some finished history so ratings and earnings are not empty.
  for (let i = 0; i < 9; i += 1) {
    const op = pick(operators);
    const done = createTrip({
      customerId: pick(customers),
      operatorId: op.id,
      status: 'completed',
      category: pick(['parcel', 'furniture', 'appliance', 'shopping']),
      vehicleClass: op.vehicleClass,
      description: 'Completed job from the last few days.',
      weight: 40,
    });
    run(
      `UPDATE trips
          SET picked_up_at = datetime('now', ?), delivered_at = datetime('now', ?),
              closed_at = datetime('now', ?), operator_rating = ?, customer_rating = 5,
              created_at = datetime('now', ?)
        WHERE id = ?`,
      `-${i + 1} days`,
      `-${i + 1} days`,
      `-${i + 1} days`,
      4 + Math.round(Math.random()),
      `-${i + 1} days`,
      done.id
    );
  }

  const counts = {
    users: get('SELECT COUNT(*) n FROM users').n,
    trips: get('SELECT COUNT(*) n FROM trips').n,
    offers: get('SELECT COUNT(*) n FROM offers').n,
    breadcrumbs: get('SELECT COUNT(*) n FROM trip_locations').n,
  };

  console.log('Done.', counts);
  console.log('\nSign in with any of these — password is:', DEMO_PASSWORD);
  console.log('  Customers:');
  for (const row of all("SELECT email FROM users WHERE role='customer'")) console.log('   ', row.email);
  console.log('  Operators:');
  for (const row of all("SELECT email FROM users WHERE role='operator'")) console.log('   ', row.email);
  console.log(`\nLive job to watch: /track.html?trip=${live.id}`);
}

seed()
  .then(() => db.close())
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
