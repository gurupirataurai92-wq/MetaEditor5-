# Lymond Services — dynamic website (PHP + MySQL, for XAMPP)

A database-driven website for a business that imports Japanese vehicles (sourced through exporters
and auction houses, BE FORWARD among them) and sells spare parts of every size, from clips and
filters to complete engines.

Everything the public sees comes out of a MySQL database. Operators sign in and manage it through
a browser — stock, prices, photographs, company details and customer enquiries. No files are
edited to change the site.

Plain PHP 8 and MySQL. No Composer, no frameworks, nothing to build or install beyond XAMPP.

---

## Setting it up on XAMPP

1. **Install XAMPP** (Windows, macOS or Linux) from <https://www.apachefriends.org>.

2. **Copy this folder into `htdocs`**, renamed to `lymond`, so you end up with
   `C:\xampp\htdocs\lymond\index.php` (or `/opt/lampp/htdocs/lymond/` on Linux,
   `/Applications/XAMPP/htdocs/lymond/` on macOS).

3. **Start Apache and MySQL** in the XAMPP control panel. Both must show green.

4. **Create the database.** Open <http://localhost/phpmyadmin>, click the **Import** tab, choose
   `sql/lymond_schema.sql` from this folder, and press **Go**. It creates the database, the tables
   and a starter catalogue of 18 vehicles and 36 parts, so you can see the site working before you
   put your own stock in.

5. **Open the site** at <http://localhost/lymond/>
   and the operator area at <http://localhost/lymond/admin/>.

### First sign-in

| User name  | Password        | Can do                                              |
| ---------- | --------------- | --------------------------------------------------- |
| `admin`    | `Lymond#2026`   | Everything, including adding and removing operators |
| `operator` | `Operator#2026` | Stock, photographs and enquiries                    |

**Change both passwords immediately** — My account → Change your password. These defaults are
printed in a file that ships with the site, so anybody who has the files knows them.

### If something does not work

- **"Cannot reach the database"** — MySQL is not running in XAMPP, or the import in step 4 was not
  done. The page tells you which.
- **You set a MySQL root password** — put it in `includes/config.php` under `DB_PASS`.
- **Photographs will not upload** — the web server needs to be able to write to `assets/uploads`.
  On Linux or macOS: `chmod 775 assets/uploads`. On Windows this normally works already.
- **Uploads bigger than 2 MB fail** — that is PHP's own limit, not this site's. In XAMPP, edit
  `php.ini` and raise `upload_max_filesize` and `post_max_size` to `10M`, then restart Apache.

---

## What operators can do

Sign in at `/admin/`.

| Screen              | What it is for |
| ------------------- | -------------- |
| **Dashboard**       | Counts, the newest enquiries, and a log of who changed what |
| **Vehicles**        | Add, edit, delete. Publish or hide without deleting. Filter by "missing photographs" |
| **Spare parts**     | The same, plus category, part size (small → large) and grade |
| **Enquiries**       | Everything sent through the contact form; mark new / in progress / closed |
| **Company details** | Phone, WhatsApp, emails, address, hours — applied across every page instantly |
| **Operators**       | Administrators only: add staff, set roles, reset passwords, turn accounts off |
| **My account**      | Your own name, email and password |

Two roles. **operator** manages stock, photographs and enquiries. **admin** does that plus the
Operators screen. Every change is written to an activity log with the operator's name and time.

### Photographs

Up to 10 per item, uploaded through the browser. Each one is resized to 1600 px and re-encoded as
JPEG on the server, so a photo straight off a phone is fine and the site stays fast. The first
photo is the cover shown on cards; use the **Cover** button to promote another. Items with no
photograph fall back to a line drawing, and the dashboard tells you how many are waiting.

---

## How it is put together

```
lymond/
├── index.php  vehicles.php  vehicle.php        public pages, rendered from the database
│   parts.php  part.php  about.php  contact.php
├── admin/                                      the operator area
│   ├── login.php  logout.php  index.php
│   ├── vehicles.php  vehicle-edit.php
│   ├── parts.php  part-edit.php
│   ├── enquiries.php  operators.php
│   ├── settings.php  account.php
│   └── _header.php  _footer.php
├── includes/
│   ├── config.php      database details and limits — the file you may need to edit
│   ├── bootstrap.php   loaded first by every page
│   ├── db.php          PDO connection; every query is a prepared statement
│   ├── auth.php        sign-in, roles, lockout, activity log
│   ├── photos.php      upload checking, resizing, storage
│   ├── helpers.php     escaping, formatting, settings, CSRF
│   ├── cards.php       shared card markup
│   └── header.php  footer.php
├── assets/
│   ├── css/styles.css  css/admin.css
│   ├── js/site.js      js/admin.js
│   ├── img/            fallback illustrations
│   └── uploads/        photographs added by operators
└── sql/lymond_schema.sql   the database: import this once
```

### Database

| Table             | Holds |
| ----------------- | ----- |
| `operators`       | Staff accounts: name, role, password hash, last sign-in |
| `vehicles`        | Stock, with a unique reference (V-001…) generated on save |
| `parts`           | Spare parts, with a category and part size |
| `part_categories` | The eight groups used by the catalogue filters |
| `photos`          | One row per picture, tied to a vehicle or a part |
| `enquiries`       | Contact-form messages and their status |
| `settings`        | Company details shown across the site |
| `activity_log`    | Who did what, and when |
| `login_attempts`  | Used to slow down password guessing |

InnoDB with foreign keys throughout. Deleting an operator keeps the stock they entered.

---

## Security notes

This is a real sign-in, not a decoration — the checks happen on the server, where a visitor cannot
reach them.

- **Passwords** are stored only as hashes (`password_hash`, bcrypt) and re-hashed automatically if
  PHP's default gets stronger. Nobody can read a password back, including an administrator.
- **SQL injection** — every query uses prepared statements with bound parameters. Where a column
  name has to vary (sorting), the value is picked from a fixed list in the code, never from the URL.
- **Cross-site scripting** — everything printed goes through `e()`, which escapes HTML.
- **CSRF** — every form that changes something carries a one-time token that is checked server-side.
- **Sign-in** — five failed attempts from one address locks that user name for 15 minutes. Sessions
  are HTTP-only, `SameSite=Lax`, regenerated on sign-in, and dropped after 45 minutes idle.
- **Uploads** — checked as genuine images, size-limited, re-encoded through GD (which discards
  anything hidden in the file), given a generated name, and stored in a folder whose `.htaccess`
  forbids executing anything.
- **Roles** — checked on the server on every request, not just hidden in the menu.

Before putting this on a public server rather than your own machine: change both default passwords,
set `SHOW_ERRORS` to `false` in `includes/config.php`, give MySQL a real password and a
non-root user with rights to this one database, and put the site behind HTTPS.

---

## Still placeholder content

The starter data is illustrative and needs replacing with your own:

- The stock list, prices and part numbers.
- Phone number, address and the `*.example` email addresses (Company details screen).
- The four figures on the home page — "2,400+ vehicles delivered", "12 years in the trade" and so
  on. They are claims to a customer; put real numbers in on the Company details screen, or clear
  the boxes to hide them.
- The invented customer testimonials that were on the old static home page have been dropped
  rather than carried over. Add real ones when you have them.
- The line drawings in `assets/img/`, replaced naturally as you upload real photographs.

Every page footer states that the company is independent and not an agent of BE FORWARD or any
other exporter. Keep that accurate — reword it only if a formal agreement actually exists.
