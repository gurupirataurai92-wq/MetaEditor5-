'use strict';

const { get } = require('./db');
const { STATUS_LABELS, TRACKABLE_STATUSES } = require('./domain');

function ratingOf(sum, count) {
  return count > 0 ? Number((sum / count).toFixed(2)) : null;
}

/** The party summary embedded in a trip — enough to render a card, no more. */
function partySummary(userId) {
  if (!userId) return null;
  const row = get(
    `SELECT u.id, u.full_name, u.phone, u.rating_sum, u.rating_count,
            p.vehicle_class, p.vehicle_make, p.vehicle_model, p.vehicle_plate,
            p.is_verified, p.trips_completed
       FROM users u
       LEFT JOIN operator_profiles p ON p.user_id = u.id
      WHERE u.id = ?`,
    userId
  );
  if (!row) return null;
  return {
    id: row.id,
    fullName: row.full_name,
    phone: row.phone,
    rating: ratingOf(row.rating_sum, row.rating_count),
    ratingCount: row.rating_count,
    tripsCompleted: row.trips_completed ?? 0,
    verified: Boolean(row.is_verified),
    vehicle: row.vehicle_class
      ? {
          class: row.vehicle_class,
          make: row.vehicle_make,
          model: row.vehicle_model,
          plate: row.vehicle_plate,
        }
      : null,
  };
}

/**
 * Shape a trip row for the API.
 *
 * `viewerId` controls contact-detail exposure: phone numbers only become
 * visible to the two parties once a job has actually been assigned, so
 * operators browsing the open board cannot harvest customer numbers.
 */
function trip(row, { viewerId = null, includeParties = true } = {}) {
  if (!row) return null;

  const isParty = viewerId != null && (viewerId === row.customer_id || viewerId === row.operator_id);
  const assigned = Boolean(row.operator_id);
  const shareContacts = isParty && assigned;

  const out = {
    id: row.id,
    reference: row.reference,
    status: row.status,
    statusLabel: STATUS_LABELS[row.status] || row.status,
    trackable: TRACKABLE_STATUSES.includes(row.status),
    category: row.category,
    vehicleClass: row.vehicle_class,

    pickup: {
      address: row.pickup_address,
      lat: row.pickup_lat,
      lng: row.pickup_lng,
      floor: row.pickup_floor,
      hasLift: Boolean(row.pickup_has_lift),
      contact: shareContacts ? row.pickup_contact : null,
    },
    dropoff: {
      address: row.dropoff_address,
      lat: row.dropoff_lat,
      lng: row.dropoff_lng,
      floor: row.dropoff_floor,
      hasLift: Boolean(row.dropoff_has_lift),
      contact: shareContacts ? row.dropoff_contact : null,
    },

    distanceKm: row.distance_km,
    itemDescription: row.item_description,
    weightEstimateKg: row.weight_estimate_kg,
    helpersRequired: row.helpers_required,
    scheduledAt: row.scheduled_at,

    customerOfferPrice: row.customer_offer_price,
    agreedPrice: row.agreed_price,
    paymentMethod: row.payment_method,

    customerRating: row.customer_rating,
    operatorRating: row.operator_rating,
    customerReview: row.customer_review,

    cancelReason: row.cancel_reason,
    cancelledBy: row.cancelled_by,

    createdAt: row.created_at,
    acceptedAt: row.accepted_at,
    pickedUpAt: row.picked_up_at,
    deliveredAt: row.delivered_at,
    closedAt: row.closed_at,

    customerId: row.customer_id,
    operatorId: row.operator_id,
  };

  if (includeParties) {
    out.customer = partySummary(row.customer_id);
    out.operator = partySummary(row.operator_id);
    if (out.customer && !shareContacts) out.customer.phone = null;
    if (out.operator && !shareContacts) out.operator.phone = null;
  }

  if (row.offer_count !== undefined) out.offerCount = row.offer_count;
  if (row.best_offer !== undefined) out.bestOffer = row.best_offer;

  return out;
}

function offer(row) {
  if (!row) return null;
  return {
    id: row.id,
    tripId: row.trip_id,
    operatorId: row.operator_id,
    price: row.price,
    etaMinutes: row.eta_minutes,
    message: row.message,
    status: row.status,
    createdAt: row.created_at,
    operator: partySummary(row.operator_id),
  };
}

function event(row) {
  return {
    id: row.id,
    tripId: row.trip_id,
    type: row.type,
    note: row.note,
    lat: row.lat,
    lng: row.lng,
    createdAt: row.created_at,
  };
}

function location(row) {
  return {
    lat: row.lat,
    lng: row.lng,
    heading: row.heading,
    speedKph: row.speed_kph,
    accuracyM: row.accuracy_m,
    recordedAt: row.recorded_at,
  };
}

function message(row) {
  return {
    id: row.id,
    tripId: row.trip_id,
    senderId: row.sender_id,
    senderName: row.sender_name ?? null,
    body: row.body,
    createdAt: row.created_at,
  };
}

module.exports = { trip, offer, event, location, message, partySummary, ratingOf };
