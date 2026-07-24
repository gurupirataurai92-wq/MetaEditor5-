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
| `admin.php` | Settle events, add fixtures, view house GGR |

Shared code: `config/db.php` (PDO connection), `includes/functions.php`
(auth, wallet ledger, bet engine), `includes/header.php` + `footer.php`
(layout), `assets/css/style.css` + `assets/js/main.js` (the honey-gold theme).

Database: `sql/hivebet.sql` (schema + demo data).

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
   - Admin: **admin** / **admin123**
   - Player: **beeplayer** / **play123** (starts with demo credits)

Or click **Join the Hive** to register — new accounts get 1,000 free demo credits.

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
