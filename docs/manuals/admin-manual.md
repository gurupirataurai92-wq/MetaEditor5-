# SIMS AI — Administrator Manual

*For business owners and system administrators.*

## 1. Roles and permissions (RBAC)

Five roles are created automatically with your business. Assign each staff
member the least-privileged role that lets them do their job:

| Role | Can do | Cannot do |
|---|---|---|
| **owner** | Everything | — |
| **manager** | Products, stock, sales, customers, suppliers, expenses, rates, reports, analytics, employees | Manage users/shops |
| **cashier** | Make sales, view products/stock, add customers, sync | Void sales, see reports, change prices |
| **storekeeper** | Products, stock movements, suppliers, sync | Sales, finance, reports |
| **accountant** | Reports, expenses, rates, view sales, audit trail, analytics | Sell, change stock |

Create staff accounts via **POST /api/v1/users** (or the Users screen):
email, name, password and role. Permission checks are enforced on every API
endpoint *and* at the database layer (PostgreSQL row-level security), so one
tenant can never see another tenant's data.

## 2. Multi-shop

Each business starts with a "Main Shop". Add more via **POST /api/v1/shops**.
Staff can be attached to a shop; sales carry the shop id for per-shop
reporting.

## 3. Exchange rates

Record the ZWG→USD rate whenever it changes (**POST /api/v1/rates** or the
Rates screen; `source` may be `manual`, `rbz` or `interbank`). Sales capture
whichever rate applies at the moment of sale — historical reports are never
rewritten by later rate changes.

## 4. Tax (ZIMRA)

Standard-rated products have 15% VAT extracted from their VAT-inclusive
price; `zero` and `exempt` tax classes are supported per product. The VAT
rate is configuration (`SIMS_VAT_RATE`), not code, so statutory changes are
an environment update.

## 5. Audit trail

Every state change (sales, voids, price changes, user creation, rates,
expenses) is written to an append-only audit log with actor, action, entity
and data — **GET /api/v1/audit** (accountant/owner). Voids never delete:
they append reversing stock movements.

## 6. Offline sync operations

Mobile tills sync through **POST /api/v1/sync**. Operational notes:

- Retries are safe: operations carry client UUIDs and are deduplicated.
- If two offline tills sold the same last unit, both sales are accepted and
  flagged (`OVERSOLD`) in Alerts — investigate and adjust stock.
- The change feed is cursor-based; a till that has been offline for days
  simply catches up from its cursor.

## 7. Backup and restore

- **PostgreSQL:** schedule `pg_dump` (e.g. nightly) and store dumps
  off-site; restore with `pg_restore`.
- The Docker volume `pgdata` holds all data; snapshot it before upgrades.

## 8. Security checklist

- Set a strong `SIMS_JWT_SECRET` (32+ random bytes) — never the default.
- Serve only over HTTPS in production (terminate TLS at NGINX).
- Require 2FA for owner and accountant accounts.
- Review the audit trail and the Alerts panel weekly.
- Keep dependencies updated (`pip list --outdated`, `npm audit`).

## 9. Troubleshooting

| Symptom | Check |
|---|---|
| "No exchange rate available" on ZWG sale | Record a ZWG rate first (§3) |
| 403 on an endpoint | The user's role lacks that permission (§1) |
| Sale rejected: insufficient stock | Online POS enforces stock; receive stock or adjust |
| Sync results show `error` entries | The `detail` field names the cause per operation |
| Dashboard empty | Check the selected date range; seed demo data with `scripts/seed_demo.py` |
