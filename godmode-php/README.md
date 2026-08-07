# GOD MODE — Business Consultant OS (PHP + MySQL / XAMPP)

A full, multi-page business-consultant management system built on the classic
**XAMPP** stack: **Apache + MySQL/MariaDB + PHP**. Every page is server-rendered
PHP and every record lives in a MySQL database — nothing is faked in the browser.

## Requirements

- [XAMPP](https://www.apachefriends.org/) (PHP 8.0+ and MySQL/MariaDB)

## Setup (5 minutes)

1. **Copy the app into XAMPP.** Put the `godmode-php` folder inside your XAMPP
   `htdocs` directory, e.g. `C:\xampp\htdocs\godmode-php`
   (macOS: `/Applications/XAMPP/htdocs/godmode-php`).

2. **Start Apache and MySQL** from the XAMPP Control Panel.

3. **Create the database.** Open phpMyAdmin at
   <http://localhost/phpmyadmin> → **Import** → choose
   `godmode-php/sql/schema.sql` → **Go**.
   This creates the `godmode_consultant` database, all tables, and seed data
   (chart of accounts + default currency).

   *Prefer the shell?* `mysql -u root < godmode-php/sql/schema.sql`

4. **Check the credentials.** The defaults in `config/db.php` match a stock
   XAMPP install (host `127.0.0.1`, user `root`, empty password). Edit them
   only if your MySQL is different.

5. **Open the app:** <http://localhost/godmode-php/> (you'll be sent to the
   login page).

If the database isn't running or hasn't been imported yet, the app shows a
clear message telling you exactly what to do — it won't white-screen.

## Logging in — one form, two dashboards

Everyone signs in on the **same login page**; the role on the account decides
where you land.

| Role | Demo login | Lands on |
|---|---|---|
| **Software distributor** | `distributor@godmode.co` / `admin123` | Distributor Console — every subscriber, their plan/status, and live "who's using the system" activity |
| **Business** | `owner@demo.co` / `business123` | The full business consultant app |

> **Change these passwords after first login** (they're seeded for the demo).
> Passwords are stored as bcrypt hashes; every page is behind a session guard.

- **Distributor** can provision a new business — it creates the tenant *and*
  its owner login in one step — plus suspend/reactivate, change plans, and see
  recent per-user activity.
- **Business** users get the consultant app, the AI Advisor, and the Zimbabwe
  law library.

## AI Advisor (decision support)

A slide-out **✦ Advisor** panel (button above the Ctrl+K hint) reads your live
data and gives prioritized, actionable suggestions — overdue filings, ageing
receivables, portfolio-at-risk, low stock, payments awaiting sign-off, severe
risks — plus Zimbabwe-specific payroll/tax reminders and a per-page tip. It's a
transparent rules engine over your own numbers (no data leaves the machine),
and it's structured so a real LLM can be plugged in later.

## Zimbabwe law library

`legal.php` is a structured compliance reference (ZIMRA taxes & QPDs, VAT, PAYE,
NSSA, ZIMDEF, Labour Act, COBE company law, IMTT, data protection) with the
governing statute and authority for each. The Advisor draws on it. Rates and
thresholds change often, so each entry carries a **"verify with the authority"**
note — treat it as guidance, not legal advice.

## Pages (all functional, all backed by SQL)

| Page | File | What it does |
|---|---|---|
| Dashboard | `index.php` | KPIs across every module + a live cash-flow chart drawn from the journal |
| OODA Engine | `ooda.php` | Observe→Orient→Decide→Act decision loops; completed cycles archive to `ooda_log` |
| Consulting / CRM | `consulting.php` | Clients, engagements (pipeline), SWOT per client |
| Auditing | `auditing.php` | Audit engagements (planning→closed) and a findings register |
| Accounting | `accounting.php` | Double-entry journal → live income statement, balance sheet, trial balance |
| Invoicing | `invoicing.php` + `invoice.php` | Invoices with line items; marking **paid** auto-posts a journal entry; printable |
| Payments | `payments.php` | Every payment is requested, then **signed for** by a named signatory before it posts to the ledger; signed payments are locked as an audit trail |
| Inventory | `inventory.php` | Stock register with automatic reorder / out-of-stock alerts, stock-in/out with a full movement log, and live stock valuation |
| Microfinance | `microfinance.php` | Loan book, amortization schedules, repayments, PAR>30 monitoring |
| Tax & Compliance | `tax.php` | Filing calendar with overdue / due-soon flags |
| HR & Payroll | `hr.php` | Headcount and gross→net payroll |
| Risk Register | `risk.php` | Likelihood × impact scoring |
| Financial Analysis | `analysis.php` | Ratios, break-even, NPV, DCF valuation, EBITDA multiples |
| Client 360° | `client.php` | Health score (0–100 / A–E) combining findings, receivables, compliance, risk |
| Distributor Console | `distributor.php` | (distributor role) subscribers, plans, suspend/reactivate, provisioning, and live usage |
| Zimbabwe Law | `legal.php` | Compliance reference feeding the AI Advisor |
| Login / Logout | `login.php` / `logout.php` | One login form for both roles; session-based auth |

## Power features

- **Ctrl + K command palette** — search every client, invoice, loan, finding,
  risk, deadline and OODA loop, or jump to any page (index built server-side).
- **Currency switch** — 16 currencies, applied everywhere instantly.
- **Print to PDF** — invoices and 360° reports print as clean documents.

## Structure

```
godmode-php/
  config/db.php          PDO connection (edit credentials here)
  includes/              functions.php (logic), header.php, footer.php
  sql/schema.sql         import this in phpMyAdmin
  assets/                styles.css, app.js
  *.php                  one file per page
```

## Security & scope notes

- Login is session-based with bcrypt password hashing, and every page is behind
  a role guard. All queries use PDO prepared statements.
- **Shared workspace, for now:** the distributor registry (businesses, users,
  usage) is fully multi-tenant, but the *operational* data (clients, ledger,
  invoices, etc.) is a single shared workspace rather than being partitioned per
  business. Full per-tenant data isolation (a `business_id` on every record) is
  the recommended next step before onboarding real, separate clients.
- Change the seeded passwords, and put the app behind HTTPS before exposing it
  beyond localhost.
