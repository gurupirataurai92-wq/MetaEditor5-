# 🐝 HiveBet — XAMPP betting platform (demo)

A multi-page betting platform built with **plain PHP + MySQL** so it runs on
**XAMPP** and opens/edits cleanly in **VS Code**. Play-money only (virtual
"Hive Credits") — designed to demonstrate the product, not to run real gambling.

> **Legal:** Real-money betting needs a gaming licence (in Zimbabwe: the Lotteries
> and Gaming Board) plus KYC/AML and responsible-gambling controls. Strictly 18+.
> See `../docs/BETTING_PLATFORM_BRAINSTORM.md` for the full business plan.

---

## What's inside

| Page | What it does |
|------|--------------|
| `index.php` | Landing page — hero, live stats, game tiles |
| `register.php` / `login.php` / `logout.php` | Accounts (bcrypt passwords, CSRF, sessions) |
| `lobby.php` | Player dashboard: balance, open bets, quick links |
| `sports.php` | Football/basketball betting with 1X2 odds |
| `aviator.php` | Aviator-style crash game (provably-fair, animated) |
| `lucky.php` | Lucky Numbers — pick 6 of 49, tiered payouts |
| `financial.php` | **Gold Market** UP/DOWN bets (the MT5 differentiator) |
| `jackpot.php` | Pool jackpot — predict the slate, share the pool |
| `wallet.php` | Deposit/withdraw: EcoCash, card, agent, voucher, PayPal, demo |
| `history.php` | Full bet history + win/loss/net stats |
| `leaderboard.php` | Players ranked by net winnings |
| `staff.php` | **Employee dashboard** — players, activity, settle fixtures |
| `admin.php` | **Owner console** — revenue (GGR), staff accounts, odds sync |

Shared code: `config/db.php` (PDO connection), `includes/functions.php`
(auth, wallet ledger, bet engine), `includes/header.php` + `footer.php`
(layout), `assets/css/style.css` + `assets/js/main.js` (the honey-gold theme).

Database: `sql/hivebet.sql` (schema + demo data).

### Live Aviator (real-time cash-out)
`aviator.php` runs a **server-authoritative** round: the crash point is committed
before take-off (the page shows the SHA-256 of the round seed) and only the server
decides the outcome. The browser (`assets/js/aviator.js`) animates the climbing
multiplier and polls `api/aviator_status.php`; **Cash Out** posts to
`api/aviator_cashout.php`, which awards `stake × current multiplier` if you beat
the crash. After the round the seed is revealed so you can verify it — provably
fair. Endpoints live in `api/` and settle through the same wallet ledger.

### Odds-feed integration stub
`includes/odds_feed.php` is where a real sports-data provider (Sportradar,
BetConstruct, The Odds API…) plugs in. `odds_feed_fetch()` returns a normalised
slate (the demo jitters the odds so the line visibly moves); `odds_feed_sync()`
upserts it into `events`. Run it two ways:
- **Admin panel:** the *Sync odds feed* button on `admin.php`.
- **Cron:** `php bin/sync_odds.php` (the file header has cron / Task Scheduler
  examples). A real key would come from `getenv('ODDS_API_KEY')`.

### Mobile navigation
On phones (≤820px) the top links collapse into a ☰ button that opens a full
drawer (`#mobileMenu` in `includes/header.php`, toggled in `assets/js/main.js`).

---

## Run it on XAMPP (5 steps)

1. **Install XAMPP** and open the **XAMPP Control Panel**. Start **Apache** and **MySQL**.
2. **Copy the `hivebet` folder** into your XAMPP web root:
   - Windows: `C:\xampp\htdocs\hivebet`
   - macOS: `/Applications/XAMPP/htdocs/hivebet`
   - Linux: `/opt/lampp/htdocs/hivebet`
3. **Import the database:** open <http://localhost/phpmyadmin> → **Import** →
   choose `hivebet/sql/hivebet.sql` → **Go**. This creates the `hivebet` database.
4. **Open the app:** <http://localhost/hivebet/>
5. **Log in** with a demo account:
   - Owner: **owner** / **owner123** (Owner console + everything)
   - Staff: **staff** / **staff123** (Staff dashboard)
   - Player: **beeplayer** / **play123** (starts with demo credits)

Or click **Join the Hive** to register — new accounts get 1,000 free demo credits.

### Roles &amp; access
Each account has a `role` — **player**, **staff** or **owner**:
- **Players** play games, deposit/withdraw and see their own history.
- **Staff (employees)** additionally get `staff.php`: player list + search, live
  activity, and fixture settlement — but not revenue or account controls.
- **Owners** get `admin.php` too: house revenue (GGR), odds-feed sync, and full
  team management (create staff/owner accounts, change roles, remove accounts).
The very first account you register becomes the **owner**; owners create the rest.
Usernames and emails are unique — duplicate registration is rejected.

### Install as a mobile app (PWA)
HiveBet ships a web-app manifest (`manifest.webmanifest`) + service worker
(`sw.js`), so it installs on phones and desktops as a standalone app:
- **Android / desktop Chrome:** an **📲 Install app** button appears, or use the
  browser's "Install" / "Add to Home Screen".
- **iPhone (Safari):** Share → **Add to Home Screen**.
It then opens full-screen with its own 🐝 icon, no app store required. (For the
Play/App stores later, wrap this PWA with Capacitor or TWA. The SVG app icon is
at `assets/icon.svg`; add 192px &amp; 512px PNGs for best Android results.)

### Instant demo (no XAMPP needed)
`demo/index.html` is a **self-contained** version of the whole platform — same
games, unique account signup, and player/staff/owner dashboards — running entirely
in the browser (it uses the browser's storage as its database). Double-click it, or
open the hosted version, to try everything without installing XAMPP. The XAMPP app
above is the real product with the MySQL backend and hashed passwords.

### Editing in VS Code
Open the `hivebet` folder in VS Code (`code hivebet`). Recommended extensions:
*PHP Intelephense* and *SQLTools*. Edit any `.php`/`.css`/`.js` file and just
refresh the browser — XAMPP serves your changes live.

### If the DB config differs
Default XAMPP MySQL is user `root` with an empty password. If yours differs,
edit `config/db.php` (`$DB_USER`, `$DB_PASS`).

---

## How the money works (play money)

Every balance change goes through one function — `wallet_move()` in
`includes/functions.php` — which locks the row, updates the balance, and writes
a `transactions` ledger row. Bets go through `place_bet()` (debits stake, opens
the bet) and `settle_bet()` (marks won/lost/void and pays winnings). This
wallet-first, single-ledger design is what a real deployment would keep — you'd
swap "demo credits" for a licensed payment gateway without touching the games.

## Turning this into a real platform
See the roadmap and compliance checklist in
`../docs/BETTING_PLATFORM_BRAINSTORM.md`. Short version: get the licence, plug in
a real odds feed (Sportradar/BetConstruct), licensed game providers (Aviator,
virtuals, casino), and Paynow/Flutterwave/DPO for EcoCash + cards, then keep this
wallet ledger as the core.
