'use strict';

// Single source of truth for the catalogue and the pricing model. The browser
// fetches this same data from GET /api/meta so the two never drift apart.

const VEHICLE_CLASSES = [
  {
    id: 'motorbike',
    name: 'Motorbike',
    blurb: 'Documents, food, small parcels',
    capacityKg: 15,
    maxHelpers: 0,
    baseFare: 25,
    perKm: 6.5,
    icon: '🏍️',
  },
  {
    id: 'car',
    name: 'Car',
    blurb: 'Boxes, laptops, shopping bags',
    capacityKg: 80,
    maxHelpers: 1,
    baseFare: 45,
    perKm: 9,
    icon: '🚗',
  },
  {
    id: 'panel_van',
    name: 'Panel van',
    blurb: 'Appliances, bulk boxes, single items',
    capacityKg: 800,
    maxHelpers: 2,
    baseFare: 120,
    perKm: 14,
    icon: '🚐',
  },
  {
    id: 'pickup',
    name: 'Pickup / bakkie',
    blurb: 'Fridges, couches, garden waste',
    capacityKg: 1000,
    maxHelpers: 2,
    baseFare: 150,
    perKm: 16,
    icon: '🛻',
  },
  {
    id: 'truck_4t',
    name: '4-ton truck',
    blurb: 'Flat or 1-bed apartment move',
    capacityKg: 4000,
    maxHelpers: 3,
    baseFare: 450,
    perKm: 24,
    icon: '🚚',
  },
  {
    id: 'truck_8t',
    name: '8-ton truck',
    blurb: 'Full house move, office relocation',
    capacityKg: 8000,
    maxHelpers: 4,
    baseFare: 850,
    perKm: 34,
    icon: '🚛',
  },
];

const CATEGORIES = [
  { id: 'parcel', name: 'Parcel / documents', suggests: 'motorbike' },
  { id: 'shopping', name: 'Shopping & groceries', suggests: 'car' },
  { id: 'appliance', name: 'Single appliance', suggests: 'panel_van' },
  { id: 'furniture', name: 'Furniture item', suggests: 'pickup' },
  { id: 'house_move', name: 'House / flat move', suggests: 'truck_4t' },
  { id: 'office_move', name: 'Office relocation', suggests: 'truck_8t' },
  { id: 'building_material', name: 'Building materials', suggests: 'pickup' },
  { id: 'other', name: 'Something else', suggests: 'panel_van' },
];

const PAYMENT_METHODS = [
  { id: 'cash', name: 'Cash on delivery' },
  { id: 'card', name: 'Card (on file)' },
  { id: 'eft', name: 'Instant EFT / transfer' },
  { id: 'wallet', name: 'Haulr wallet' },
];

const HELPER_FEE_PER_PERSON = 120; // flat, per helper, per job
const FLOOR_FEE = 45; // per floor above ground when there is no lift

// Ordered lifecycle. `index` powers "can this actor move the trip forward?".
const TRIP_STATUSES = [
  'requested', // customer posted it, waiting for offers
  'accepted', // customer picked an operator
  'en_route_pickup', // operator driving to collection point
  'at_pickup', // operator arrived, loading
  'in_transit', // goods loaded, driving to destination
  'delivered', // goods handed over, awaiting rating
  'completed', // rated and closed
  'cancelled',
];

const STATUS_LABELS = {
  requested: 'Waiting for offers',
  accepted: 'Operator assigned',
  en_route_pickup: 'On the way to pickup',
  at_pickup: 'Loading at pickup',
  in_transit: 'In transit',
  delivered: 'Delivered',
  completed: 'Completed',
  cancelled: 'Cancelled',
};

// Which status an operator may move a trip to, from where.
const OPERATOR_TRANSITIONS = {
  accepted: ['en_route_pickup'],
  en_route_pickup: ['at_pickup'],
  at_pickup: ['in_transit'],
  in_transit: ['delivered'],
};

const ACTIVE_STATUSES = [
  'requested',
  'accepted',
  'en_route_pickup',
  'at_pickup',
  'in_transit',
];

// Statuses in which the operator's GPS feed should be running.
const TRACKABLE_STATUSES = [
  'accepted',
  'en_route_pickup',
  'at_pickup',
  'in_transit',
];

const vehicleById = new Map(VEHICLE_CLASSES.map((v) => [v.id, v]));
const categoryById = new Map(CATEGORIES.map((c) => [c.id, c]));

const EARTH_RADIUS_KM = 6371;
const toRad = (deg) => (deg * Math.PI) / 180;

/** Great-circle distance between two coordinates, in kilometres. */
function haversineKm(lat1, lng1, lat2, lng2) {
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.min(1, Math.sqrt(a)));
}

/**
 * Straight-line distance under-reads real driving distance. 1.35 is a common
 * urban detour factor and keeps price suggestions honest without a routing API.
 */
const ROAD_FACTOR = 1.35;

function roadDistanceKm(lat1, lng1, lat2, lng2) {
  return round2(haversineKm(lat1, lng1, lat2, lng2) * ROAD_FACTOR);
}

function round2(n) {
  return Math.round(n * 100) / 100;
}

/**
 * Suggested price band for a job. The customer is free to offer anything —
 * this is guidance, exactly like inDrive's recommended fare.
 */
function priceGuide({
  vehicleClass,
  distanceKm,
  helpers = 0,
  pickupFloor = 0,
  dropoffFloor = 0,
  pickupHasLift = false,
  dropoffHasLift = false,
}) {
  const vehicle = vehicleById.get(vehicleClass);
  if (!vehicle) return null;

  const distance = Math.max(0, Number(distanceKm) || 0);
  const helperCount = clamp(Number(helpers) || 0, 0, vehicle.maxHelpers);

  const stairFloors =
    (pickupHasLift ? 0 : Math.max(0, Number(pickupFloor) || 0)) +
    (dropoffHasLift ? 0 : Math.max(0, Number(dropoffFloor) || 0));

  const base = vehicle.baseFare + vehicle.perKm * distance;
  const extras = helperCount * HELPER_FEE_PER_PERSON + stairFloors * FLOOR_FEE;
  const recommended = base + extras;

  return {
    vehicleClass,
    distanceKm: round2(distance),
    breakdown: {
      baseFare: round2(vehicle.baseFare),
      distanceFare: round2(vehicle.perKm * distance),
      helperFee: round2(helperCount * HELPER_FEE_PER_PERSON),
      stairFee: round2(stairFloors * FLOOR_FEE),
    },
    // Operators routinely bid ~15% either side of the guide depending on how
    // busy they are, so show the band rather than a single number.
    min: Math.max(vehicle.baseFare, Math.round(recommended * 0.85)),
    recommended: Math.round(recommended),
    max: Math.round(recommended * 1.2),
  };
}

function clamp(n, lo, hi) {
  return Math.min(hi, Math.max(lo, n));
}

/** Rough drive time for a distance, using a conservative urban average speed. */
function etaMinutes(distanceKm, averageSpeedKph = 32) {
  if (!distanceKm || distanceKm <= 0) return 0;
  return Math.max(1, Math.round((distanceKm / averageSpeedKph) * 60));
}

/** Short human-facing job reference, e.g. `HLR-7QK4M2`. */
function makeReference() {
  const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  let out = '';
  for (let i = 0; i < 6; i += 1) {
    out += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return `HLR-${out}`;
}

module.exports = {
  VEHICLE_CLASSES,
  CATEGORIES,
  PAYMENT_METHODS,
  TRIP_STATUSES,
  STATUS_LABELS,
  OPERATOR_TRANSITIONS,
  ACTIVE_STATUSES,
  TRACKABLE_STATUSES,
  HELPER_FEE_PER_PERSON,
  FLOOR_FEE,
  vehicleById,
  categoryById,
  haversineKm,
  roadDistanceKm,
  priceGuide,
  etaMinutes,
  makeReference,
  round2,
  clamp,
};
