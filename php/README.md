# SIMS AI — XAMPP Edition (PHP + MySQL)

A **dynamic** business-management website that runs on **XAMPP** (Apache +
MySQL + PHP). The database is real MySQL, managed by operators through
**phpMyAdmin**. One login screen decides which dashboard you see:

- **Owner** → Dashboard (finance overview, per-branch performance, branches, staff)
- **Manager** → Staff & Duty (add/remove operators, on/off duty, inventory & prices)
- **Till Operator** → Point of Sale (serve customers, scan barcodes, print receipts)

> **Security:** staff passwords are stored only as `password_hash()` hashes and
> are **never displayed anywhere in the system**. They are confidential to each
> operator. (The one exception is the demo credentials on the one-time
> `install.php` setup page.)

---

## 1. Install XAMPP

Download and install XAMPP (PHP 8+) from apachefriends.org. Open the **XAMPP
Control Panel** and press **Start** on **Apache** and **MySQL**.

## 2. Copy the app into htdocs

Unzip this folder into your XAMPP web root so you have:

```
C:\xampp\htdocs\sims-ai\      (Windows)
/opt/lampp/htdocs/sims-ai/    (Linux)
/Applications/XAMPP/htdocs/sims-ai/   (macOS)
```

(The folder name `sims-ai` becomes the URL path.)

## 3. Run the one-time setup

In your browser open:

```
http://localhost/sims-ai/install.php
```

This creates the `sims_ai` database and all tables, seeds demo branches,
products and two weeks of sales, and creates the three operator accounts. It
then prints the sign-in credentials.

> Prefer to do it by hand? In **phpMyAdmin** (`http://localhost/phpmyadmin`)
> use the **Import** tab to run `sql/schema.sql`, then still open `install.php`
> once to create the hashed operator accounts and demo data.

## 4. Sign in

```
http://localhost/sims-ai/
```

| Role          | Email                   | Password      | Lands on       |
|---------------|-------------------------|---------------|----------------|
| Owner         | owner@simsai.co.zw      | owner1234     | Dashboard      |
| Manager       | manager@simsai.co.zw    | manager1234   | Staff & Duty   |
| Till Operator | till@simsai.co.zw       | till1234      | Point of Sale  |

---

## Operators manage the SQL

The MySQL database `sims_ai` is administered from **phpMyAdmin**
(`http://localhost/phpmyadmin`) — browse/edit/back up every table
(users, branches, products, sales, sale_items, expenses). Change the DB
connection in `config/config.php` if your MySQL user/password differ from the
XAMPP defaults (`root` / empty password).

## Use it as an app (tablets / PC / phone)

It ships a web manifest and a service worker, so Chrome/Edge show an **Install**
icon in the address bar — install it and it runs full-screen like a native app.
It is fully responsive for tablets, PCs and monitors. On a phone use the
browser's *Add to Home screen*.

> Installable PWAs need HTTPS in production (localhost is exempt for testing).
> To install over a network, serve XAMPP behind HTTPS.

## Barcodes

- **POS:** type or scan a code in the scan box (USB scanners "type" the code, so
  they work out of the box), or tap **📷 Scan** to use the device camera
  (browsers with the native `BarcodeDetector`).
- **Adding a product:** a **product code is required** — scan it with the camera
  or type it. Codes are unique.

## File map

```
config/       config.php (DB + settings), db.php (PDO connection)
includes/     auth.php (login + RBAC), functions.php (helpers), layout_*.php
sql/          schema.sql (database + tables)
assets/       style.css, app.js
install.php   one-time setup (creates DB, seeds data, hashes passwords)
index.php     entry — routes to the right dashboard
login.php  logout.php
dashboard.php pos.php  receipt.php  inventory.php  staff.php  branches.php
manifest.php  sw.js    (installable-app support)
```
