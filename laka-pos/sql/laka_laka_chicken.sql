-- =====================================================================
--  LAKA LAKA CHICKEN — Restaurant Management System
--  MySQL / MariaDB schema + seed data  (XAMPP · phpMyAdmin importable)
-- ---------------------------------------------------------------------
--  How to load:
--    1. Start Apache + MySQL in the XAMPP Control Panel.
--    2. Open http://localhost/phpmyadmin
--    3. Import  ->  choose this file  ->  Go
--    (or from CLI:  mysql -u root < sql/laka_laka_chicken.sql )
--
--  Default logins (username / password):
--    owner   / owner123      manager / manager123
--    cashier / cashier123     cook    / cook123
-- =====================================================================

CREATE DATABASE IF NOT EXISTS laka_laka_chicken
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE laka_laka_chicken;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS recipes;
DROP TABLE IF EXISTS stock_movements;
DROP TABLE IF EXISTS menu_items;
DROP TABLE IF EXISTS categories;
DROP TABLE IF EXISTS ingredients;
DROP TABLE IF EXISTS audit_log;
DROP TABLE IF EXISTS users;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
--  Identity & RBAC
-- ---------------------------------------------------------------------
CREATE TABLE users (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  full_name     VARCHAR(120)  NOT NULL,
  username      VARCHAR(60)   NOT NULL UNIQUE,
  password_hash VARCHAR(255)  NOT NULL,
  role          ENUM('owner','manager','cashier','cook') NOT NULL,
  is_active     TINYINT(1)    NOT NULL DEFAULT 1,
  created_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  Menu & Recipes
-- ---------------------------------------------------------------------
CREATE TABLE categories (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  name       VARCHAR(80) NOT NULL UNIQUE,
  sort_order INT NOT NULL DEFAULT 0
) ENGINE=InnoDB;

CREATE TABLE ingredients (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  name          VARCHAR(80)   NOT NULL UNIQUE,
  unit          VARCHAR(20)   NOT NULL DEFAULT 'unit',
  stock_qty     DECIMAL(18,3) NOT NULL DEFAULT 0,
  reorder_point DECIMAL(18,3) NOT NULL DEFAULT 0,
  unit_cost     DECIMAL(18,4) NOT NULL DEFAULT 0
) ENGINE=InnoDB;

CREATE TABLE menu_items (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  name         VARCHAR(120)  NOT NULL,
  category_id  INT           NOT NULL,
  price        DECIMAL(18,4) NOT NULL,
  cost         DECIMAL(18,4) NOT NULL DEFAULT 0,
  station      ENUM('fryer','grill','drinks','assembly') NOT NULL DEFAULT 'fryer',
  prep_minutes INT           NOT NULL DEFAULT 4,
  is_available TINYINT(1)    NOT NULL DEFAULT 1,
  CONSTRAINT fk_item_cat FOREIGN KEY (category_id) REFERENCES categories(id)
) ENGINE=InnoDB;

CREATE TABLE recipes (
  menu_item_id  INT NOT NULL,
  ingredient_id INT NOT NULL,
  qty           DECIMAL(18,3) NOT NULL,
  PRIMARY KEY (menu_item_id, ingredient_id),
  CONSTRAINT fk_recipe_item FOREIGN KEY (menu_item_id) REFERENCES menu_items(id) ON DELETE CASCADE,
  CONSTRAINT fk_recipe_ing  FOREIGN KEY (ingredient_id) REFERENCES ingredients(id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  Orders & POS  (multi-currency, transaction-time FX capture)
-- ---------------------------------------------------------------------
CREATE TABLE orders (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  channel       ENUM('counter','kiosk','drive_thru','online') NOT NULL DEFAULT 'counter',
  cashier_id    INT           NULL,
  subtotal      DECIMAL(18,4) NOT NULL DEFAULT 0,
  tax_amount    DECIMAL(18,4) NOT NULL DEFAULT 0,
  total         DECIMAL(18,4) NOT NULL DEFAULT 0,
  currency      CHAR(3)       NOT NULL DEFAULT 'USD',
  base_currency CHAR(3)       NOT NULL DEFAULT 'USD',
  exchange_rate DECIMAL(18,6) NOT NULL DEFAULT 1.000000,
  status        ENUM('placed','cooking','ready','served','void') NOT NULL DEFAULT 'placed',
  -- customer details (used by online / self-service orders)
  order_type     ENUM('pickup','delivery') NULL,
  customer_name  VARCHAR(120) NULL,
  customer_phone VARCHAR(40)  NULL,
  address        VARCHAR(255) NULL,
  notes          VARCHAR(255) NULL,
  payment_status ENUM('unpaid','paid') NOT NULL DEFAULT 'unpaid',
  created_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_order_cashier FOREIGN KEY (cashier_id) REFERENCES users(id)
) ENGINE=InnoDB;

CREATE TABLE order_items (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  order_id     INT NOT NULL,
  menu_item_id INT NOT NULL,
  item_name    VARCHAR(120)  NOT NULL,
  qty          INT           NOT NULL DEFAULT 1,
  unit_price   DECIMAL(18,4) NOT NULL,
  station      ENUM('fryer','grill','drinks','assembly') NOT NULL,
  status       ENUM('queued','cooking','ready') NOT NULL DEFAULT 'queued',
  CONSTRAINT fk_oi_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
  CONSTRAINT fk_oi_item  FOREIGN KEY (menu_item_id) REFERENCES menu_items(id)
) ENGINE=InnoDB;

CREATE TABLE payments (
  id        INT AUTO_INCREMENT PRIMARY KEY,
  order_id  INT NOT NULL,
  method    ENUM('cash','ecocash','onemoney','zipit','card') NOT NULL DEFAULT 'cash',
  amount    DECIMAL(18,4) NOT NULL,
  currency  CHAR(3) NOT NULL DEFAULT 'USD',
  paid_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_pay_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  Inventory movements & audit trail
-- ---------------------------------------------------------------------
CREATE TABLE stock_movements (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  ingredient_id INT NOT NULL,
  change_qty    DECIMAL(18,3) NOT NULL,        -- negative = consumed
  reason        VARCHAR(120)  NOT NULL,
  created_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_sm_ing FOREIGN KEY (ingredient_id) REFERENCES ingredients(id)
) ENGINE=InnoDB;

CREATE TABLE audit_log (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    INT NULL,
  action     VARCHAR(120) NOT NULL,
  details    VARCHAR(255) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- =====================================================================
--  SEED DATA
-- =====================================================================

-- Users (bcrypt hashes match password_verify in PHP)
INSERT INTO users (full_name, username, password_hash, role) VALUES
 ('Rumbi Owner',   'owner',   '$2y$12$9ifDPO7QQ67C/uaeKOH94efq8PEOdvZXjmNCJWDCeeYd0iyQe4Ww.', 'owner'),
 ('Tapiwa Manager','manager', '$2y$12$CtOnNO.smP.rzokCenGK5.XamYlmL5xZ/XtVK55RsAZb89IGE.F2S', 'manager'),
 ('Chipo Till',    'cashier', '$2y$12$Q2szMg5naWxMTxreVkRRN.VIcBNOvv/n6F1E.xcNnzFLeucGVJpme', 'cashier'),
 ('Farai Cook',    'cook',    '$2y$12$F6bdOJ/6eGhxIS6q5ZJ1sORmkp2KTEQBijmzyupLfFDM8InRP3aiS', 'cook');

-- Categories
INSERT INTO categories (id, name, sort_order) VALUES
 (1,'Buckets & Chicken',1),
 (2,'Burgers',2),
 (3,'Sides',3),
 (4,'Drinks',4),
 (5,'Combos',5);

-- Ingredients (stock, reorder point, unit cost)
INSERT INTO ingredients (id, name, unit, stock_qty, reorder_point, unit_cost) VALUES
 (1,'Chicken piece','pc',400,80,0.5500),
 (2,'Burger bun','pc',200,40,0.2000),
 (3,'Potato portion','portion',300,60,0.1000),
 (4,'Cooking oil','L',120,30,0.2500),
 (5,'Soft drink','pc',250,50,0.1500),
 (6,'Spice mix','portion',300,60,0.0800);

-- Menu items
INSERT INTO menu_items (id, name, category_id, price, cost, station, prep_minutes) VALUES
 (1,'Original Bucket (8pc)',1,18.9900,6.4000,'fryer',6),
 (2,'Hot Wings (6pc)',      1,5.9900,1.8000,'fryer',5),
 (3,'Laka Zinger Burger',   2,6.4900,2.1000,'grill',4),
 (4,'Laka Fries',           3,2.9900,0.7000,'fryer',3),
 (5,'Soft Drink',           4,1.9900,0.3500,'drinks',1),
 (6,'Laka Combo (Zinger+Fries+Drink)',5,9.9900,3.1500,'assembly',5);

-- Recipes (menu_item -> ingredient -> qty consumed)
INSERT INTO recipes (menu_item_id, ingredient_id, qty) VALUES
 (1,1,8),(1,4,2),(1,6,2),                       -- Bucket
 (2,1,3),(2,4,1),(2,6,2),                       -- Wings
 (3,1,1),(3,2,1),(3,6,1),                       -- Zinger
 (4,3,2),(4,4,1),                               -- Fries
 (5,5,1),                                       -- Drink
 (6,1,1),(6,2,1),(6,3,2),(6,4,1),(6,5,1),(6,6,1); -- Combo

-- A couple of sample orders so the dashboard isn't empty
INSERT INTO orders (id, channel, cashier_id, subtotal, tax_amount, total, currency, exchange_rate, status) VALUES
 (1,'counter',3,9.4800,1.4200,10.9000,'USD',1.000000,'served'),
 (2,'drive_thru',3,18.9900,2.8500,21.8400,'USD',1.000000,'served');

INSERT INTO order_items (order_id, menu_item_id, item_name, qty, unit_price, station, status) VALUES
 (1,3,'Laka Zinger Burger',1,6.4900,'grill','ready'),
 (1,4,'Laka Fries',1,2.9900,'fryer','ready'),
 (2,1,'Original Bucket (8pc)',1,18.9900,'fryer','ready');

INSERT INTO payments (order_id, method, amount, currency) VALUES
 (1,'ecocash',10.9000,'USD'),
 (2,'cash',21.8400,'USD');
