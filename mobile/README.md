# SIMS AI — Mobile (Flutter)

Offline-first Android/PWA client. **Status: working skeleton** — the
offline-first core (local SQLite replica, Lamport-clocked outbox, idempotent
sync against `/api/v1/sync`) is implemented; screens beyond the POS are
extension points.

## Design (matches dissertation §4.6)

- **Local first:** every sale commits to SQLite instantly, network or not.
- **Outbox:** each mutation is queued with a client UUID + Lamport clock.
- **Sync:** on connectivity, the outbox is pushed (server dedupes by op id —
  retries are safe) and server deltas are pulled by cursor and folded in.

## Run

```bash
flutter pub get
flutter run --dart-define=SIMS_API=http://<backend-host>:8000/api/v1
# PWA build:
flutter build web
```

`10.0.2.2` (the default API host) reaches the host machine from the Android
emulator.
