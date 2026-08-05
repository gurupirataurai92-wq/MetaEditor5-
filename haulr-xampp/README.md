# Haulr — delivery & moving marketplace (XAMPP edition)

A dynamic PHP + MySQL web application. Customers post what they need moved and
**name the price they want to pay**, drivers accept the job or counter with
their own price, and a manager oversees everything on a live map.

Anything from an envelope on a motorbike to a full house move on an 8-ton truck.

```
customer posts a job → driver accepts → live GPS tracking → delivered → both rate
                                    ↘ manager oversees, intervenes, audits ↙
```

**Stack:** PHP 8.1+ · MySQL/MariaDB · Apache — i.e. exactly what XAMPP gives
you. No Composer, no npm, no build step, no external PHP libraries.

---

## Install (about 5 minutes)

### 1. Copy the files into XAMPP

Put this whole folder into your XAMPP `htdocs` directory and name it `haulr`:

```
C:\xampp\htdocs\haulr\          (Windows)
/Applications/XAMPP/htdocs/haulr/   (macOS)
/opt/lampp/htdocs/haulr/            (Linux)
```

### 2. Start Apache and MySQL

Open the **XAMPP Control Panel** and press **Start** next to both **Apache**
and **MySQL**.

### 3. Create the database

1. Go to <http://localhost/phpmyadmin>
2. Click the **Import** tab at the top
3. **Choose File** → `htdocs/haulr/database/schema.sql`
4. Scroll down and click **Go**

That creates the `haulr` database and all eleven tables. You do not need to
create the database first — the file does it.

### 4. Load the demo data

Open <http://localhost/haulr/database/seed.php> in your browser.

It prints the demo accounts and, importantly, the **manager's two-factor
secret and recovery codes** — copy those somewhere before closing the page.

### 5. Open the site

<http://localhost/haulr/>

> **Different folder name?** Everything is relative — if you call the folder
> something else, the app finds itself. Only the URLs in this README change.

---

## Signing in — three different dashboards

The password for every demo account is `Haulr!Demo2026`.

| Role | Email | Lands on | What they do |
| --- | --- | --- | --- |
| **Customer** | `thandi@example.com` | `customer.html` | Posts delivery requests, names a price, tracks the vehicle |
| **Driver** | `nomsa@example.com` | `operator.html` | Sees nearby jobs, accepts them, streams GPS |
| **Manager** | `manager@example.com` | `manager.html` | Oversees every job, driver and customer |

The sign-in page has one-click buttons for all three. **The server decides
where each role lands** — the browser does not choose.

### The manager needs a second factor

Manager accounts can read every job and every customer's phone number, so they
require an authenticator code. Three ways in:

- **Authenticator app** — add the secret the seeder printed to Google
  Authenticator, Aegis, 1Password, etc.
- **Recovery code** — the seeder printed five; each works once.
- **Print a valid code** — open
  <http://localhost/haulr/database/totp_code.php?email=manager@example.com>
  (only works from the machine running the server).

### Seeing it properly

Open two browsers, or one normal window and one private window, so the two
sessions do not share cookies. Post a job as the customer in one, accept it as
the driver in the other, and watch the customer's screen update on its own.

---

## What each role can do

### Customer

Map-driven booking: drop pins or search an address, pick a vehicle class,
describe the load, set floors and lift availability, add helpers, and name your
price. A live breakdown shows base fare, distance, helpers and stairs, plus the
band drivers usually bid within.

Then: watch the vehicle move, chat with the driver, and rate them at the end.

### Driver

Go on duty and the jobs board shows everything nearby **that your vehicle can
actually carry**, sorted by distance to the pickup. Two ways to take work:

- **Accept the job as posted** — it is yours immediately at the customer's
  price, no waiting for them to choose.
- **Counter with your own price** — goes to the customer alongside other bids.

Then walk it forward: on the way → arrived → loaded → delivered, with live
location streaming to the customer the whole time.

### Manager

- **Live map** of every driver on duty, and which are on a job
- **Jobs** — filter by status, search by reference or address, open any job's
  full record including both parties' contact details
- **Interventions** — reassign a job to another driver (a breakdown, a
  no-show), cancel a job at any stage, flag one for attention
- **People** — verify drivers, suspend or reinstate accounts, force a
  sign-out, create other manager accounts
- **Audit log** — every privileged action and every look at personal data,
  including other managers'
- **Security** — failed sign-ins, locked accounts, live sessions, and which
  accounts are being targeted

---

## Security

This was built defensively. What is actually in place:

**Sessions**
- Passwords hashed with bcrypt (cost 12); nothing reversible is ever stored
- The session token lives in an **httpOnly cookie** — page scripts cannot read
  it, so an XSS bug cannot be escalated into a stolen session
- Only the **SHA-256 of the token** is stored, so reading the `sessions` table
  (a stolen backup, a leak) does not let anyone sign in
- Sessions are server-side rows, so revocation is **instant**: sign out
  everywhere, manager-forced logout and suspension all take effect immediately
- `SameSite=Strict`, `Secure` when you enable HTTPS, scoped to the app folder

**Sign-in**
- **Progressive lockout** — repeated failures double the wait, up to an hour
- **Rate limits** per IP and per account, shared across requests via MySQL
- **No account enumeration**: a wrong email and a wrong password take the same
  time and return the same message
- **Two-factor (TOTP)** — mandatory for managers, optional for everyone else,
  with single-use recovery codes stored only as hashes; a code cannot be
  replayed inside its own 30-second window

**Requests**
- **CSRF tokens** on every state-changing request, bound to the session
- **Prepared statements everywhere** — no SQL is built by string concatenation
- Strict server-side validation of every field; the client is never trusted
- Content-Security-Policy blocking all third-party scripts, plus
  `X-Frame-Options`, `nosniff`, `Referrer-Policy` and friends
- PHP errors are logged, never rendered — no paths, SQL or versions leak out
- `app/`, `config.php` and `*.sql` are unreachable over HTTP

**Privacy**
- **Phone numbers are exchanged only after a job is assigned.** A driver
  browsing the open board never sees a customer's number
- **The public landing map does not show real positions** — they are snapped
  to a ~1.1 km grid server-side, so a visitor sees the service is busy but
  cannot follow a driver
- The signed-in "vehicles near you" map uses opaque keys, no identities
- **Manager access is audited**, including every record they open

**Roles**
- Three roles: `customer`, `operator` (driver), `manager`
- **Managers cannot be created by signing up.** The registration endpoint
  refuses the role outright. The first one comes from
  `database/create_manager.php`; every one after that is created inside the
  console by an existing manager confirming their own password
- Every endpoint enforces its own role check — the client-side redirect is a
  convenience, not the boundary

### Before this is reachable by anyone else

1. Set a real `app_key` in `config.php` (`php -r "echo bin2hex(random_bytes(32));"`)
2. Give MySQL's `root` a password in phpMyAdmin and put it in `config.php`
3. Serve over HTTPS and set `'https_only' => true`
4. Delete `database/seed.php` and `database/totp_code.php`
5. Change every demo account's password, or delete them

The app refuses to start with the shipped placeholder key on any hostname
other than localhost, so step 1 is enforced rather than merely suggested.

---

## How it is put together

```
haulr/
├── index.html            landing page
├── auth.html             sign in / register / two-factor
├── customer.html         customer dashboard
├── operator.html         driver console
├── manager.html          manager console
├── request.html          booking flow
├── track.html            live tracking (serves customer and driver)
├── config.php            ← the one file you edit
├── .htaccess             Apache rules and security headers
│
├── api/
│   ├── index.php         front controller: routing, CSRF, error handling
│   └── .htaccess         rewrites api/... into index.php
│
├── app/                  (not reachable over HTTP)
│   ├── Config.php        configuration loader
│   ├── Database.php      PDO wrapper, prepared statements only
│   ├── Auth.php          sessions, password handling, role guards
│   ├── Security.php      cookies, CSRF, rate limiting, password policy
│   ├── Totp.php          RFC 6238 two-factor
│   ├── Audit.php         append-only audit trail
│   ├── Domain.php        vehicle catalogue, pricing, geo maths
│   ├── Validate.php      input validation
│   ├── Serialize.php     API shapes (contact-detail gating lives here)
│   ├── Events.php        the polling feed
│   ├── Response.php      JSON responses
│   └── Controllers/      one per area of the API
│
├── database/
│   ├── schema.sql        import this in phpMyAdmin
│   ├── seed.php          demo data
│   ├── create_manager.php  bootstrap a manager (terminal)
│   └── totp_code.php     print a valid 2FA code (local only)
│
├── css/ · js/            front end — plain HTML, CSS and JavaScript
└── vendor/leaflet/       Leaflet, bundled locally (no CDN)
```

### Managing the data

Everything lives in eleven InnoDB tables you can browse, edit, export and back
up in **phpMyAdmin** like any other MySQL database:

| Table | Holds |
| --- | --- |
| `users` | all three account types, separated by `role` |
| `operator_profiles` | the vehicle behind each driver account |
| `trips` | one row per delivery job |
| `offers` | drivers' bids |
| `trip_events` | the job timeline |
| `trip_locations` | GPS breadcrumb trail |
| `messages` | in-job chat |
| `sessions` | live sign-ins (token hashes only) |
| `login_attempts` | drives lockout and the security dashboard |
| `audit_log` | privileged actions, append-only |
| `event_queue` | pending live updates |

Day-to-day management is meant to happen in the **manager console**, which
enforces the rules and writes an audit entry. phpMyAdmin is the raw
back door for backups, bulk fixes and inspection — changes made there bypass
the application's checks and are not audited.

### Live updates without WebSockets

Apache and PHP have no persistent connection to push down — each request is a
separate short-lived process. So instead of a socket, the browser polls
`api/events?since=N` every 2–3 seconds and the server replays anything new
addressed to that user, ordered and authorisation-checked on read.

The trade-off is honest: updates arrive in a couple of seconds rather than
instantly. Everything else behaves identically, and polling backs off when the
tab is hidden or the server is unreachable so it will not hammer XAMPP.

If you later want true real-time, the queue table is already the right shape —
point a Ratchet/Swoole worker at it, or run this behind Node.

---

## Troubleshooting

**"The database is not set up yet"** — import `database/schema.sql` in
phpMyAdmin (step 3), then reload.

**"Cannot connect to MySQL"** — MySQL is not started in the XAMPP control
panel, or you set a root password without putting it in `config.php`.

**Blank page or 404 on every API call** — Apache's `mod_rewrite` is off. In
XAMPP it is normally on; check that `httpd.conf` has
`LoadModule rewrite_module modules/mod_rewrite.so` uncommented and that
`AllowOverride All` is set for `htdocs`.

**Port 80 already in use** — usually Skype or IIS on Windows. Either stop
them, or change Apache's port in XAMPP and use
`http://localhost:8080/haulr/`.

**Map is blank/grey** — the map tiles come from OpenStreetMap, so the machine
needs internet access. Everything else (pins, tracking, pricing) is computed
locally and still works offline.

**Location does not work** — browsers only allow geolocation on `localhost` or
HTTPS. `http://localhost/haulr/` is fine; `http://192.168.x.x/haulr/` is not.

---

## Not built

Deliberately out of scope, and worth knowing before this takes real money:

- **Payments** — the payment method is recorded, nothing is charged
- **Identity/licence verification** — `is_verified` is a flag a manager sets;
  there is no verification pipeline behind it
- **Email and SMS** — no password reset, no notifications
- **Proof-of-delivery photos**
- **Real routing** — distance is great-circle × 1.35, a standard urban detour
  factor, not a road network. A routing engine (OSRM, Valhalla, Google
  Directions) would give true distances and turn-by-turn navigation

---

Map data © OpenStreetMap contributors. Leaflet is BSD-2-Clause licensed.
