-- =====================================================================
--  HiveBet — database schema + demo data
--  Import this file in phpMyAdmin (XAMPP):  http://localhost/phpmyadmin
--    1. Start Apache + MySQL in the XAMPP control panel
--    2. phpMyAdmin  ->  Import  ->  choose this file  ->  Go
--  It creates the `hivebet` database and everything the app needs.
--
--  Demo logins created below:
--    admin  / admin123   (full admin panel)
--    beeplayer / play123  (normal player, starts with demo credits)
--  PLAY-MONEY DEMO ONLY. No real gambling. 18+. See README.md.
-- =====================================================================

CREATE DATABASE IF NOT EXISTS hivebet
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE hivebet;

-- Clean re-import
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS bets;
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS events;
DROP TABLE IF EXISTS jackpots;
DROP TABLE IF EXISTS users;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
--  Users
-- ---------------------------------------------------------------------
CREATE TABLE users (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  username      VARCHAR(50)  NOT NULL UNIQUE,
  email         VARCHAR(120) NOT NULL UNIQUE,
  phone         VARCHAR(30)  DEFAULT NULL,
  password_hash VARCHAR(255) NOT NULL,
  balance       DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  role          ENUM('player','staff','owner') NOT NULL DEFAULT 'player',
  is_admin      TINYINT(1)   NOT NULL DEFAULT 0,   -- legacy flag: 1 for staff/owner
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  Wallet ledger — every credit movement is one row (audit trail)
-- ---------------------------------------------------------------------
CREATE TABLE transactions (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  user_id       INT NOT NULL,
  type          ENUM('deposit','withdraw','stake','payout','bonus') NOT NULL,
  method        VARCHAR(40)  DEFAULT NULL,   -- ecocash, card, agent, voucher, demo
  amount        DECIMAL(14,2) NOT NULL,      -- + credit to player, - debit
  balance_after DECIMAL(14,2) NOT NULL,
  status        ENUM('pending','completed','rejected') NOT NULL DEFAULT 'completed',
  reference     VARCHAR(60)  DEFAULT NULL,
  note          VARCHAR(255) DEFAULT NULL,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_tx_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  Bets — one row per placed bet across every game
-- ---------------------------------------------------------------------
CREATE TABLE bets (
  id               INT AUTO_INCREMENT PRIMARY KEY,
  user_id          INT NOT NULL,
  game             VARCHAR(30) NOT NULL,     -- sports, aviator, lucky, financial, jackpot
  event_id         INT DEFAULT NULL,
  selection        VARCHAR(160) NOT NULL,
  stake            DECIMAL(14,2) NOT NULL,
  odds             DECIMAL(8,2) NOT NULL,
  potential_payout DECIMAL(14,2) NOT NULL,
  status           ENUM('pending','won','lost','void','cashed_out') NOT NULL DEFAULT 'pending',
  result           VARCHAR(160) DEFAULT NULL,
  payout           DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  settled_at       DATETIME DEFAULT NULL,
  CONSTRAINT fk_bet_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  Sports / financial events with odds
-- ---------------------------------------------------------------------
CREATE TABLE events (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  category   VARCHAR(30)  NOT NULL,          -- football, basketball, financial
  league     VARCHAR(80)  DEFAULT NULL,
  home       VARCHAR(80)  NOT NULL,
  away       VARCHAR(80)  NOT NULL,
  odds_home  DECIMAL(6,2) NOT NULL,
  odds_draw  DECIMAL(6,2) DEFAULT NULL,
  odds_away  DECIMAL(6,2) NOT NULL,
  starts_at  DATETIME     NOT NULL,
  status     ENUM('open','locked','settled') NOT NULL DEFAULT 'open',
  result     ENUM('home','draw','away') DEFAULT NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  Jackpot pools
-- ---------------------------------------------------------------------
CREATE TABLE jackpots (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  title        VARCHAR(120) NOT NULL,
  pool         DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  ticket_price DECIMAL(10,2) NOT NULL DEFAULT 1.00,
  matches      INT NOT NULL DEFAULT 8,
  status       ENUM('open','closed') NOT NULL DEFAULT 'open',
  draw_at      DATETIME NOT NULL
) ENGINE=InnoDB;

-- =====================================================================
--  Demo data
-- =====================================================================

-- owner123 / staff123 / play123 (bcrypt). Change these before any real deployment.
INSERT INTO users (username, email, phone, password_hash, balance, role, is_admin) VALUES
('owner',     'owner@hivebet.local',  '+263770000000', '$2y$12$NNcaL7NMqRUwEAGvEaqEreKw0iCiMdPdcJ0I3o0DhUrkZBSPQkPX.', 0.00,    'owner',  1),
('staff',     'staff@hivebet.local',  '+263770000001', '$2y$12$NqqgS6M/m7YcqUR0CV2P.uraT.BClBYYWNuf85nOHnWboiQ8cv4jK', 0.00,    'staff',  1),
('beeplayer', 'player@hivebet.local', '+263771111111', '$2y$12$dd.yOTFBr4k/D8RI7YgE9ey7xl5aKlAwAHJcvz7cjV17J5IDm6q3G', 2500.00, 'player', 0);

INSERT INTO transactions (user_id, type, method, amount, balance_after, note) VALUES
(3, 'bonus', 'demo', 2500.00, 2500.00, 'Welcome demo credits');

INSERT INTO events (category, league, home, away, odds_home, odds_draw, odds_away, starts_at, status) VALUES
('football','English Premier League','Arsenal','Chelsea',            2.10, 3.30, 3.40, DATE_ADD(NOW(), INTERVAL 2 HOUR), 'open'),
('football','English Premier League','Man City','Liverpool',         1.95, 3.60, 3.80, DATE_ADD(NOW(), INTERVAL 5 HOUR), 'open'),
('football','Castle Lager PSL','Highlanders','Dynamos',              2.45, 3.10, 2.90, DATE_ADD(NOW(), INTERVAL 1 DAY),  'open'),
('football','Castle Lager PSL','FC Platinum','Chicken Inn',          1.80, 3.20, 4.50, DATE_ADD(NOW(), INTERVAL 1 DAY),  'open'),
('football','UEFA Champions League','Real Madrid','Bayern',          2.30, 3.50, 2.95, DATE_ADD(NOW(), INTERVAL 3 DAY),  'open'),
('basketball','NBA','Lakers','Celtics',                              1.90, NULL, 1.90, DATE_ADD(NOW(), INTERVAL 6 HOUR), 'open');

INSERT INTO jackpots (title, pool, ticket_price, matches, status, draw_at) VALUES
('Weekend Mega Jackpot', 12500.00, 1.00, 8, 'open', DATE_ADD(NOW(), INTERVAL 2 DAY));
