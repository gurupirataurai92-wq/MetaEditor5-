-- ============================================================
--  GOD MODE — Business Consultant OS
--  MySQL / MariaDB schema for XAMPP.
--
--  Import via phpMyAdmin (http://localhost/phpmyadmin):
--    1. Click "Import"
--    2. Choose this file
--    3. Go
--  ...or from the shell:
--    mysql -u root < schema.sql
-- ============================================================

CREATE DATABASE IF NOT EXISTS godmode_consultant
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE godmode_consultant;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS usage_log;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS businesses;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS inventory_moves;
DROP TABLE IF EXISTS inventory_items;
DROP TABLE IF EXISTS invoice_items;
DROP TABLE IF EXISTS invoices;
DROP TABLE IF EXISTS findings;
DROP TABLE IF EXISTS audits;
DROP TABLE IF EXISTS engagements;
DROP TABLE IF EXISTS journal;
DROP TABLE IF EXISTS accounts;
DROP TABLE IF EXISTS loans;
DROP TABLE IF EXISTS obligations;
DROP TABLE IF EXISTS employees;
DROP TABLE IF EXISTS risks;
DROP TABLE IF EXISTS ooda_log;
DROP TABLE IF EXISTS ooda;
DROP TABLE IF EXISTS clients;
DROP TABLE IF EXISTS settings;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------- Clients / CRM ----------
CREATE TABLE clients (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  name       VARCHAR(160) NOT NULL,
  industry   VARCHAR(120) DEFAULT '',
  contact    VARCHAR(160) DEFAULT '',
  notes      TEXT,
  swot_s     TEXT,
  swot_w     TEXT,
  swot_o     TEXT,
  swot_t     TEXT,
  created_at DATE
) ENGINE=InnoDB;

CREATE TABLE engagements (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  client_id  INT NOT NULL,
  service    VARCHAR(60) DEFAULT 'Consulting',
  fee        DECIMAL(14,2) DEFAULT 0,
  status     VARCHAR(20) DEFAULT 'active',       -- proposal | active | completed
  start_date DATE,
  FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------- Auditing ----------
CREATE TABLE audits (
  id        INT AUTO_INCREMENT PRIMARY KEY,
  client_id INT NOT NULL,
  scope     VARCHAR(200) NOT NULL,
  period    VARCHAR(60) NOT NULL,
  status    VARCHAR(20) DEFAULT 'planning',      -- planning | fieldwork | reporting | closed
  FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE findings (
  id             INT AUTO_INCREMENT PRIMARY KEY,
  audit_id       INT NOT NULL,
  title          VARCHAR(200) NOT NULL,
  severity       VARCHAR(12) DEFAULT 'medium',   -- low | medium | high | critical
  recommendation TEXT,
  status         VARCHAR(12) DEFAULT 'open',      -- open | resolved
  FOREIGN KEY (audit_id) REFERENCES audits(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------- Accounting ----------
CREATE TABLE accounts (
  id   INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  type VARCHAR(12) NOT NULL                       -- Asset | Liability | Equity | Income | Expense
) ENGINE=InnoDB;

CREATE TABLE journal (
  id             INT AUTO_INCREMENT PRIMARY KEY,
  entry_date     DATE NOT NULL,
  memo           VARCHAR(220) DEFAULT '',
  debit_account  INT NOT NULL,
  credit_account INT NOT NULL,
  amount         DECIMAL(14,2) NOT NULL,
  FOREIGN KEY (debit_account)  REFERENCES accounts(id),
  FOREIGN KEY (credit_account) REFERENCES accounts(id)
) ENGINE=InnoDB;

-- ---------- Invoicing ----------
CREATE TABLE invoices (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  number     VARCHAR(20) NOT NULL,
  client_id  INT NOT NULL,
  issue_date DATE NOT NULL,
  due_date   DATE NOT NULL,
  status     VARCHAR(12) DEFAULT 'draft',         -- draft | sent | paid
  paid_date  DATE NULL,
  FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE invoice_items (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  invoice_id  INT NOT NULL,
  description VARCHAR(200) NOT NULL,
  qty         DECIMAL(12,2) DEFAULT 1,
  price       DECIMAL(14,2) DEFAULT 0,
  FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------- Microfinance ----------
CREATE TABLE loans (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  borrower     VARCHAR(160) NOT NULL,
  principal    DECIMAL(14,2) NOT NULL,
  rate         DECIMAL(7,3) DEFAULT 0,            -- annual %
  months       INT DEFAULT 12,
  method       VARCHAR(12) DEFAULT 'declining',   -- declining | flat
  repaid       DECIMAL(14,2) DEFAULT 0,
  days_overdue INT DEFAULT 0,
  status       VARCHAR(12) DEFAULT 'active',       -- active | closed
  start_date   DATE
) ENGINE=InnoDB;

-- ---------- Tax & Compliance ----------
CREATE TABLE obligations (
  id        INT AUTO_INCREMENT PRIMARY KEY,
  name      VARCHAR(160) NOT NULL,
  authority VARCHAR(160) DEFAULT '',
  client_id INT NULL,
  due_date  DATE NOT NULL,
  frequency VARCHAR(20) DEFAULT 'one-off',
  status    VARCHAR(12) DEFAULT 'pending',         -- pending | filed
  FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- ---------- HR & Payroll ----------
CREATE TABLE employees (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  name       VARCHAR(160) NOT NULL,
  role       VARCHAR(120) DEFAULT '',
  gross      DECIMAL(14,2) DEFAULT 0,
  deduct_pct DECIMAL(6,2) DEFAULT 15
) ENGINE=InnoDB;

-- ---------- Risk Register ----------
CREATE TABLE risks (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  title      VARCHAR(200) NOT NULL,
  category   VARCHAR(30) DEFAULT 'Operational',
  owner      VARCHAR(120) DEFAULT '',
  likelihood INT DEFAULT 3,                        -- 1..5
  impact     INT DEFAULT 3,                        -- 1..5
  mitigation TEXT,
  status     VARCHAR(12) DEFAULT 'open'            -- open | mitigated
) ENGINE=InnoDB;

-- ---------- OODA decision loops ----------
CREATE TABLE ooda (
  id        INT AUTO_INCREMENT PRIMARY KEY,
  title     VARCHAR(200) NOT NULL,
  objective TEXT,
  status    VARCHAR(12) DEFAULT 'active',          -- active | done
  stage     INT DEFAULT 0,                         -- 0 Observe .. 3 Act
  cycles    INT DEFAULT 0,
  observe   TEXT,
  orient    TEXT,
  decide    TEXT,
  act       TEXT
) ENGINE=InnoDB;

CREATE TABLE ooda_log (
  id        INT AUTO_INCREMENT PRIMARY KEY,
  ooda_id   INT NOT NULL,
  cycle     INT,
  logged_at DATE,
  observe   TEXT,
  orient    TEXT,
  decide    TEXT,
  act       TEXT,
  FOREIGN KEY (ooda_id) REFERENCES ooda(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------- Inventory ----------
CREATE TABLE inventory_items (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  sku           VARCHAR(40) DEFAULT '',
  name          VARCHAR(160) NOT NULL,
  category      VARCHAR(80) DEFAULT '',
  unit          VARCHAR(20) DEFAULT 'unit',
  quantity      DECIMAL(14,2) DEFAULT 0,
  unit_cost     DECIMAL(14,2) DEFAULT 0,
  reorder_level DECIMAL(14,2) DEFAULT 0,
  updated_at    DATE
) ENGINE=InnoDB;

CREATE TABLE inventory_moves (
  id        INT AUTO_INCREMENT PRIMARY KEY,
  item_id   INT NOT NULL,
  move_type VARCHAR(10) NOT NULL,               -- in | out | set
  qty       DECIMAL(14,2) NOT NULL,
  note      VARCHAR(200) DEFAULT '',
  moved_at  DATE,
  FOREIGN KEY (item_id) REFERENCES inventory_items(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------- Payments (with authorization / sign-off) ----------
CREATE TABLE payments (
  id             INT AUTO_INCREMENT PRIMARY KEY,
  payee          VARCHAR(160) NOT NULL,
  purpose        VARCHAR(220) DEFAULT '',
  amount         DECIMAL(14,2) NOT NULL,
  method         VARCHAR(20) DEFAULT 'bank',     -- cash | bank | mobile | cheque
  client_id      INT NULL,
  debit_account  INT NULL,                        -- what is being paid for
  credit_account INT NULL,                        -- what it is paid from
  status         VARCHAR(12) DEFAULT 'pending',   -- pending | signed | rejected
  requested_at   DATE,
  signed_by      VARCHAR(120) DEFAULT '',         -- authorizing signatory
  signed_at      DATE NULL,
  journal_id     INT NULL,                        -- ledger entry created on sign-off
  FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- ---------- SaaS: tenants, users, usage ----------
CREATE TABLE businesses (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  name          VARCHAR(160) NOT NULL,
  contact_email VARCHAR(160) DEFAULT '',
  plan          VARCHAR(20) DEFAULT 'Trial',      -- Trial | Starter | Professional | Enterprise
  status        VARCHAR(12) DEFAULT 'active',      -- active | suspended
  trial_ends    DATE NULL,
  created_at    DATE,
  last_active   DATETIME NULL
) ENGINE=InnoDB;

CREATE TABLE users (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  business_id   INT NULL,                          -- NULL for the distributor
  name          VARCHAR(120) NOT NULL,
  email         VARCHAR(160) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  role          VARCHAR(16) NOT NULL DEFAULT 'business',  -- distributor | business
  created_at    DATE,
  last_seen     DATETIME NULL,
  FOREIGN KEY (business_id) REFERENCES businesses(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE usage_log (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  user_id     INT NULL,
  business_id INT NULL,
  action      VARCHAR(40) DEFAULT 'visit',
  page        VARCHAR(60) DEFAULT '',
  at          DATETIME
) ENGINE=InnoDB;

-- ---------- Settings ----------
CREATE TABLE settings (
  id       INT PRIMARY KEY DEFAULT 1,
  currency VARCHAR(4) DEFAULT 'USD'
) ENGINE=InnoDB;

-- ============================================================
--  Seed data
-- ============================================================
INSERT INTO settings (id, currency) VALUES (1, 'USD');

-- Default tenant + accounts.  CHANGE THESE PASSWORDS after first login.
INSERT INTO businesses (id, name, contact_email, plan, status, trial_ends, created_at)
  VALUES (1, 'Demo Consulting Co', 'owner@demo.co', 'Professional', 'active', NULL, '2026-01-01');

-- Passwords: distributor = "admin123", business owner = "business123"
INSERT INTO users (business_id, name, email, password_hash, role, created_at) VALUES
  (NULL, 'Platform Distributor', 'distributor@godmode.co',
   '$2y$12$LIyvQtrEXZrC.4FIFYh1Z.Je3kJ4SU2myZHij33s1q/Huj/RmVwca', 'distributor', '2026-01-01'),
  (1,    'Business Owner',        'owner@demo.co',
   '$2y$12$V5mDHPK4KAFuOdEli87q8Og1XI5iLYuqCXXDMcxS5dvgqK7H2JmoS', 'business', '2026-01-01');

INSERT INTO accounts (name, type) VALUES
  ('Cash & Bank',         'Asset'),
  ('Accounts Receivable', 'Asset'),
  ('Equipment',           'Asset'),
  ('Accounts Payable',    'Liability'),
  ('Loans Payable',       'Liability'),
  ('Owner''s Capital',    'Equity'),
  ('Consulting Fees',     'Income'),
  ('Interest Income',     'Income'),
  ('Rent Expense',        'Expense'),
  ('Salaries Expense',    'Expense'),
  ('Other Expenses',      'Expense');
