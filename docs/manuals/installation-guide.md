# SIMS AI — Installation Guide

## A. Development setup (5 minutes)

Prerequisites: Python 3.11+, Node 18+ (for the dashboard), git.

```bash
git clone <repository-url> sims-ai && cd sims-ai

# 1. Backend (SQLite — zero configuration)
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m pytest -q            # expect: all tests pass
.venv/bin/uvicorn app.main:app --reload  # API on :8000, docs at /docs

# 2. Demo data (new terminal, from the repo root)
python3 scripts/seed_demo.py             # prints demo login credentials

# 3. Web dashboard (new terminal)
cd web
npm install
npm run dev                              # http://localhost:5173 (proxies /api)
```

Sign in with the credentials the seed script printed.

## B. Production deployment (single VPS)

Prerequisites: a Linux server with Docker + Docker Compose, a domain name.

```bash
git clone <repository-url> sims-ai && cd sims-ai

# Build the dashboard once (served statically by NGINX)
cd web && npm install && npm run build && cd ..

cd infra
SIMS_JWT_SECRET=$(openssl rand -hex 32) \
POSTGRES_PASSWORD=$(openssl rand -hex 16) \
docker compose up -d
```

This starts PostgreSQL (with row-level-security policies applied on first
init), Redis, the API and NGINX on port 80. Put TLS in front (Caddy,
certbot, or your provider's load balancer) before real use.

### Environment variables

| Variable | Default | Notes |
|---|---|---|
| `SIMS_DATABASE_URL` | sqlite | Set to `postgresql+psycopg2://…` in prod |
| `SIMS_JWT_SECRET` | change-me | **Must** be a strong random value |
| `SIMS_VAT_RATE` | 0.15 | ZIMRA standard rate |
| `SIMS_BASE_CURRENCY` | USD | Reporting currency |
| `SIMS_CORS_ORIGINS` | * | Restrict to your dashboard origin in prod |

### Upgrades

```bash
git pull
cd web && npm run build && cd ../infra
docker compose build api && docker compose up -d
```

Snapshot the `pgdata` volume (or `pg_dump`) before upgrading.

## C. Android app

```bash
cd mobile
flutter pub get
flutter run --dart-define=SIMS_API=https://your-domain/api/v1
flutter build apk --release   # distributable APK
```

## D. Verifying an installation

1. `curl https://your-domain/health` → `{"status":"ok"}`
2. Register a business in the dashboard; make a sale; download the receipt.
3. Turn networking off on a mobile till, sell, reconnect — the sale appears
   on the dashboard after sync.
