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

5. **Open the app:** <http://localhost/godmode-php/>

If the database isn't running or hasn't been imported yet, the app shows a
clear message telling you exactly what to do — it won't white-screen.

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

## Security note

This is a single-user back-office tool intended to run on localhost via XAMPP.
All queries use PDO prepared statements. Before exposing it on a network, add
authentication and put it behind HTTPS.
