-- SIMS AI — MySQL schema (XAMPP / phpMyAdmin).
-- Operators manage this database from phpMyAdmin at http://localhost/phpmyadmin.
-- You can run this file there (Import tab), or just open install.php once.

CREATE DATABASE IF NOT EXISTS sims_ai
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE sims_ai;

-- Branches / shops -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS branches (
  id        INT AUTO_INCREMENT PRIMARY KEY,
  name      VARCHAR(120) NOT NULL,
  location  VARCHAR(160) NOT NULL DEFAULT '',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Users / operators (owner, manager, till operator) --------------------------
-- password_hash holds a password_hash() digest ONLY. Passwords are never
-- stored or shown in plain text — they are confidential to each operator.
CREATE TABLE IF NOT EXISTS users (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  name          VARCHAR(120) NOT NULL,
  email         VARCHAR(160) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  role          ENUM('owner','manager','cashier') NOT NULL DEFAULT 'cashier',
  branch_id     INT NOT NULL DEFAULT 1,
  on_duty       TINYINT(1) NOT NULL DEFAULT 0,
  active        TINYINT(1) NOT NULL DEFAULT 1,
  created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_user_branch FOREIGN KEY (branch_id) REFERENCES branches(id)
) ENGINE=InnoDB;

-- Products -------------------------------------------------------------------
-- code is the barcode / product code and is REQUIRED and UNIQUE (managers must
-- supply it when adding a product; the POS can scan it).
CREATE TABLE IF NOT EXISTS products (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  code       VARCHAR(64) NOT NULL UNIQUE,
  name       VARCHAR(160) NOT NULL,
  price      DECIMAL(12,2) NOT NULL DEFAULT 0,   -- VAT-inclusive selling price
  cost       DECIMAL(12,2) NOT NULL DEFAULT 0,   -- purchase cost (for profit)
  stock      INT NOT NULL DEFAULT 0,
  active     TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Sales (one per checkout) ---------------------------------------------------
CREATE TABLE IF NOT EXISTS sales (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  branch_id  INT NOT NULL,
  user_id    INT NOT NULL,
  total      DECIMAL(12,2) NOT NULL DEFAULT 0,   -- VAT-inclusive total
  vat        DECIMAL(12,2) NOT NULL DEFAULT 0,
  method     VARCHAR(32) NOT NULL DEFAULT 'cash',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_sale_branch FOREIGN KEY (branch_id) REFERENCES branches(id),
  CONSTRAINT fk_sale_user   FOREIGN KEY (user_id)   REFERENCES users(id)
) ENGINE=InnoDB;

-- Sale line items (unit price & cost snapshotted at sale time) ----------------
CREATE TABLE IF NOT EXISTS sale_items (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  sale_id    INT NOT NULL,
  product_id INT NOT NULL,
  name       VARCHAR(160) NOT NULL,
  qty        INT NOT NULL,
  unit_price DECIMAL(12,2) NOT NULL,
  unit_cost  DECIMAL(12,2) NOT NULL DEFAULT 0,
  CONSTRAINT fk_item_sale    FOREIGN KEY (sale_id)    REFERENCES sales(id) ON DELETE CASCADE,
  CONSTRAINT fk_item_product FOREIGN KEY (product_id) REFERENCES products(id)
) ENGINE=InnoDB;

-- Expenses (owner finance) ---------------------------------------------------
CREATE TABLE IF NOT EXISTS expenses (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  branch_id  INT NOT NULL,
  label      VARCHAR(160) NOT NULL,
  amount     DECIMAL(12,2) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_expense_branch FOREIGN KEY (branch_id) REFERENCES branches(id)
) ENGINE=InnoDB;
