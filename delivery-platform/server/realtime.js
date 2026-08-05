'use strict';

const { WebSocketServer } = require('ws');
const { resolveToken } = require('./auth');
const { SESSION_COOKIE, parseCookies } = require('./security');
const { get } = require('./db');

// Channel naming:
//   trip:<id>   live feed for one job (location, status, chat, offers)
//   user:<id>   personal feed (new offer on my job, job assigned to me, ...)
//   dispatch    the open-jobs board every online operator watches
//   managers    oversight feed, managers only
const DISPATCH = 'dispatch';
const MANAGERS = 'managers';

/** clientId -> ws */
const clients = new Map();
/** channel -> Set<clientId> */
const channels = new Map();

let nextClientId = 1;

function subscribe(clientId, channel) {
  if (!channels.has(channel)) channels.set(channel, new Set());
  channels.get(channel).add(clientId);
  const ws = clients.get(clientId);
  if (ws) ws.channels.add(channel);
}

function unsubscribe(clientId, channel) {
  channels.get(channel)?.delete(clientId);
  if (channels.get(channel)?.size === 0) channels.delete(channel);
  clients.get(clientId)?.channels.delete(channel);
}

function dropClient(clientId) {
  const ws = clients.get(clientId);
  if (!ws) return;
  for (const channel of ws.channels) {
    channels.get(channel)?.delete(clientId);
    if (channels.get(channel)?.size === 0) channels.delete(channel);
  }
  clients.delete(clientId);
}

function send(ws, payload) {
  if (ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(payload));
  }
}

/** Push a payload to every socket listening on `channel`. */
function publish(channel, payload) {
  const members = channels.get(channel);
  if (!members) return 0;
  const frame = JSON.stringify(payload);
  let delivered = 0;
  for (const clientId of members) {
    const ws = clients.get(clientId);
    if (ws && ws.readyState === ws.OPEN) {
      ws.send(frame);
      delivered += 1;
    }
  }
  return delivered;
}

const toTrip = (tripId, payload) => publish(`trip:${tripId}`, payload);
const toUser = (userId, payload) => publish(`user:${userId}`, payload);
const toDispatch = (payload) => publish(DISPATCH, payload);
const toManagers = (payload) => publish(MANAGERS, payload);

/**
 * May `user` listen in on `tripId`?
 *  - the customer who posted it, always
 *  - the assigned operator, always
 *  - any operator while the job is still open for bidding (so they can watch
 *    offers arrive and see if they have been outbid)
 */
function canWatchTrip(user, tripId) {
  const trip = get('SELECT customer_id, operator_id, status FROM trips WHERE id = ?', tripId);
  if (!trip) return false;
  if (user.role === 'manager') return true;
  if (trip.customer_id === user.id) return true;
  if (trip.operator_id === user.id) return true;
  if (user.role === 'operator' && trip.status === 'requested') return true;
  return false;
}

/**
 * A WebSocket handshake is not covered by the same-origin policy, so a page on
 * any site can open a socket to us and the browser will attach our cookies.
 * Checking Origin against our own host is the defence — the equivalent of CSRF
 * protection for the socket.
 */
function originAllowed(req) {
  const origin = req.headers.origin;
  // Non-browser clients (scripts, tests) send no Origin at all; they are not
  // the threat here because nothing attaches a cookie on their behalf.
  if (!origin) return true;
  try {
    return new URL(origin).host === req.headers.host;
  } catch {
    return false;
  }
}

function attach(server) {
  const wss = new WebSocketServer({
    server,
    path: '/ws',
    // Cap frame size: a socket is authenticated, but an authenticated client
    // should still not be able to push the process into swap.
    maxPayload: 64 * 1024,
  });

  wss.on('connection', (ws, req) => {
    if (!originAllowed(req)) {
      ws.close(4003, 'origin not allowed');
      return;
    }

    // The session cookie is sent automatically on the handshake, so the token
    // never appears in a URL where it would land in access logs, proxy logs
    // and browser history.
    const cookies = parseCookies(req);
    const resolved = resolveToken(cookies[SESSION_COOKIE]);
    const user = resolved?.user;

    if (!user) {
      send(ws, { type: 'error', error: 'Invalid or expired session.' });
      ws.close(4001, 'unauthorised');
      return;
    }

    const clientId = nextClientId++;
    ws.clientId = clientId;
    ws.user = user;
    ws.channels = new Set();
    ws.isAlive = true;
    clients.set(clientId, ws);

    subscribe(clientId, `user:${user.id}`);
    if (user.role === 'operator') subscribe(clientId, DISPATCH);
    // Managers watch the dispatch board too, so the console reflects jobs
    // appearing and being taken without polling.
    if (user.role === 'manager') {
      subscribe(clientId, DISPATCH);
      subscribe(clientId, MANAGERS);
    }

    send(ws, {
      type: 'ready',
      userId: user.id,
      role: user.role,
      serverTime: new Date().toISOString(),
    });

    ws.on('pong', () => {
      ws.isAlive = true;
    });

    ws.on('message', (raw) => {
      let msg;
      try {
        msg = JSON.parse(raw.toString());
      } catch {
        return send(ws, { type: 'error', error: 'Malformed message.' });
      }

      switch (msg.type) {
        case 'subscribe': {
          const tripId = Number(msg.tripId);
          if (!Number.isInteger(tripId) || !canWatchTrip(user, tripId)) {
            return send(ws, { type: 'error', error: 'Cannot subscribe to that job.' });
          }
          subscribe(clientId, `trip:${tripId}`);
          return send(ws, { type: 'subscribed', tripId });
        }
        case 'unsubscribe': {
          const tripId = Number(msg.tripId);
          unsubscribe(clientId, `trip:${tripId}`);
          return send(ws, { type: 'unsubscribed', tripId });
        }
        case 'ping':
          return send(ws, { type: 'pong', serverTime: new Date().toISOString() });
        default:
          return send(ws, { type: 'error', error: `Unknown message type "${msg.type}".` });
      }
    });

    ws.on('close', () => dropClient(clientId));
    ws.on('error', () => dropClient(clientId));
  });

  // Reap sockets that stopped answering — mobile clients disappear without a
  // close frame all the time.
  const heartbeat = setInterval(() => {
    for (const ws of clients.values()) {
      if (!ws.isAlive) {
        ws.terminate();
        dropClient(ws.clientId);
        continue;
      }
      ws.isAlive = false;
      try {
        ws.ping();
      } catch {
        /* socket already gone; the next sweep drops it */
      }
    }
  }, 30_000);

  wss.on('close', () => clearInterval(heartbeat));

  return wss;
}

module.exports = { attach, publish, toTrip, toUser, toDispatch, toManagers, DISPATCH, MANAGERS };
