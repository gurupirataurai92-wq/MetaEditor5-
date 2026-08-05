-- ===========================================================================
--  Haulr — delivery & moving marketplace
--  MySQL / MariaDB schema for XAMPP
--
--  Import this in phpMyAdmin:
--    1. Start Apache and MySQL in the XAMPP control panel
--    2. Open http://localhost/phpmyadmin
--    3. Import  ->  Choose File  ->  database/schema.sql  ->  Go
--
--  It creates the `haulr` database and every table, so you do not need to
--  create the database first.
-- ===========================================================================

CREATE DATABASE IF NOT EXISTS `haulr`
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE `haulr`;

SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS `event_queue`;
DROP TABLE IF EXISTS `audit_log`;
DROP TABLE IF EXISTS `login_attempts`;
DROP TABLE IF EXISTS `sessions`;
DROP TABLE IF EXISTS `messages`;
DROP TABLE IF EXISTS `trip_locations`;
DROP TABLE IF EXISTS `trip_events`;
DROP TABLE IF EXISTS `offers`;
DROP TABLE IF EXISTS `trips`;
DROP TABLE IF EXISTS `operator_profiles`;
DROP TABLE IF EXISTS `users`;

SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------------
--  users — the three account types live in one table, separated by `role`
-- ---------------------------------------------------------------------------
CREATE TABLE `users` (
  `id`                   INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `role`                 ENUM('customer','operator','manager') NOT NULL,
  `full_name`            VARCHAR(120)  NOT NULL,
  `email`                VARCHAR(254)  NOT NULL,
  `phone`                VARCHAR(24)   NOT NULL,
  -- bcrypt hash from PHP password_hash(). Never a plaintext password.
  `password_hash`        VARCHAR(255)  NOT NULL,
  `rating_sum`           DECIMAL(10,2) NOT NULL DEFAULT 0,
  `rating_count`         INT UNSIGNED  NOT NULL DEFAULT 0,
  `is_suspended`         TINYINT(1)    NOT NULL DEFAULT 0,
  `suspended_reason`     VARCHAR(300)      NULL,

  -- Two-factor authentication (mandatory for managers)
  `totp_secret`          VARCHAR(64)       NULL,
  `totp_enabled`         TINYINT(1)    NOT NULL DEFAULT 0,
  `totp_last_counter`    BIGINT            NULL,
  `recovery_codes`       TEXT              NULL,

  `must_change_password` TINYINT(1)    NOT NULL DEFAULT 0,
  `password_changed_at`  DATETIME          NULL,
  `locked_until`         DATETIME          NULL,
  `created_at`           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_users_email` (`email`),
  KEY `idx_users_role` (`role`, `is_suspended`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
--  operator_profiles — the vehicle behind a driver account
-- ---------------------------------------------------------------------------
CREATE TABLE `operator_profiles` (
  `user_id`           INT UNSIGNED NOT NULL,
  `vehicle_class`     VARCHAR(32)  NOT NULL,
  `vehicle_make`      VARCHAR(60)      NULL,
  `vehicle_model`     VARCHAR(60)      NULL,
  `vehicle_plate`     VARCHAR(16)      NULL,
  `capacity_kg`       INT UNSIGNED NOT NULL DEFAULT 0,
  `helpers_available` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `has_tail_lift`     TINYINT(1)   NOT NULL DEFAULT 0,
  `licence_number`    VARCHAR(40)      NULL,
  `bio`               VARCHAR(400)     NULL,
  `is_verified`       TINYINT(1)   NOT NULL DEFAULT 0,
  `is_online`         TINYINT(1)   NOT NULL DEFAULT 0,
  `last_lat`          DECIMAL(10,7)    NULL,
  `last_lng`          DECIMAL(10,7)    NULL,
  `last_heading`      DECIMAL(6,2)     NULL,
  `last_seen_at`      DATETIME         NULL,
  `trips_completed`   INT UNSIGNED NOT NULL DEFAULT 0,

  PRIMARY KEY (`user_id`),
  KEY `idx_operators_online` (`is_online`, `vehicle_class`),
  CONSTRAINT `fk_profile_user` FOREIGN KEY (`user_id`)
    REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
--  trips — one delivery job
-- ---------------------------------------------------------------------------
CREATE TABLE `trips` (
  `id`                   INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `reference`            VARCHAR(16)  NOT NULL,
  `customer_id`          INT UNSIGNED NOT NULL,
  `operator_id`          INT UNSIGNED     NULL,
  `status` ENUM('requested','accepted','en_route_pickup','at_pickup',
                'in_transit','delivered','completed','cancelled')
                         NOT NULL DEFAULT 'requested',
  `category`             VARCHAR(32)  NOT NULL,
  `vehicle_class`        VARCHAR(32)  NOT NULL,

  `pickup_address`       VARCHAR(300) NOT NULL,
  `pickup_lat`           DECIMAL(10,7) NOT NULL,
  `pickup_lng`           DECIMAL(10,7) NOT NULL,
  `pickup_contact`       VARCHAR(120)     NULL,
  `pickup_floor`         TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `pickup_has_lift`      TINYINT(1)   NOT NULL DEFAULT 0,

  `dropoff_address`      VARCHAR(300) NOT NULL,
  `dropoff_lat`          DECIMAL(10,7) NOT NULL,
  `dropoff_lng`          DECIMAL(10,7) NOT NULL,
  `dropoff_contact`      VARCHAR(120)     NULL,
  `dropoff_floor`        TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `dropoff_has_lift`     TINYINT(1)   NOT NULL DEFAULT 0,

  `distance_km`          DECIMAL(8,2) NOT NULL DEFAULT 0,
  `item_description`     TEXT         NOT NULL,
  `weight_estimate_kg`   INT UNSIGNED NOT NULL DEFAULT 0,
  `helpers_required`     TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `scheduled_at`         DATETIME         NULL,

  `customer_offer_price` DECIMAL(10,2) NOT NULL,
  `agreed_price`         DECIMAL(10,2)    NULL,
  `payment_method`       VARCHAR(16)  NOT NULL DEFAULT 'cash',

  `customer_rating`      TINYINT UNSIGNED NULL,
  `operator_rating`      TINYINT UNSIGNED NULL,
  `customer_review`      VARCHAR(600)     NULL,

  `cancel_reason`        VARCHAR(300)     NULL,
  `cancelled_by`         VARCHAR(16)      NULL,

  -- Manager oversight
  `assigned_by`          VARCHAR(16)      NULL,
  `flagged_reason`       VARCHAR(300)     NULL,
  `flagged_at`           DATETIME         NULL,

  `created_at`           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `accepted_at`          DATETIME         NULL,
  `picked_up_at`         DATETIME         NULL,
  `delivered_at`         DATETIME         NULL,
  `closed_at`            DATETIME         NULL,

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_trips_reference` (`reference`),
  KEY `idx_trips_customer` (`customer_id`, `status`),
  KEY `idx_trips_operator` (`operator_id`, `status`),
  KEY `idx_trips_status`   (`status`, `created_at`),
  CONSTRAINT `fk_trip_customer` FOREIGN KEY (`customer_id`)
    REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_trip_operator` FOREIGN KEY (`operator_id`)
    REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
--  offers — a driver's bid on a job
-- ---------------------------------------------------------------------------
CREATE TABLE `offers` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `trip_id`     INT UNSIGNED NOT NULL,
  `operator_id` INT UNSIGNED NOT NULL,
  `price`       DECIMAL(10,2) NOT NULL,
  `eta_minutes` SMALLINT UNSIGNED NOT NULL,
  `message`     VARCHAR(300)     NULL,
  `status` ENUM('pending','accepted','rejected','withdrawn') NOT NULL DEFAULT 'pending',
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_offer_trip_operator` (`trip_id`, `operator_id`),
  KEY `idx_offers_operator` (`operator_id`, `status`),
  CONSTRAINT `fk_offer_trip` FOREIGN KEY (`trip_id`)
    REFERENCES `trips` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_offer_operator` FOREIGN KEY (`operator_id`)
    REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
--  trip_events — the job timeline
-- ---------------------------------------------------------------------------
CREATE TABLE `trip_events` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `trip_id`    INT UNSIGNED NOT NULL,
  `actor_id`   INT UNSIGNED     NULL,
  `type`       VARCHAR(48)  NOT NULL,
  `note`       VARCHAR(300)     NULL,
  `lat`        DECIMAL(10,7)    NULL,
  `lng`        DECIMAL(10,7)    NULL,
  `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

  PRIMARY KEY (`id`),
  KEY `idx_events_trip` (`trip_id`, `id`),
  CONSTRAINT `fk_event_trip` FOREIGN KEY (`trip_id`)
    REFERENCES `trips` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_event_actor` FOREIGN KEY (`actor_id`)
    REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
--  trip_locations — GPS breadcrumb trail
-- ---------------------------------------------------------------------------
CREATE TABLE `trip_locations` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `trip_id`     INT UNSIGNED NOT NULL,
  `operator_id` INT UNSIGNED NOT NULL,
  `lat`         DECIMAL(10,7) NOT NULL,
  `lng`         DECIMAL(10,7) NOT NULL,
  `heading`     DECIMAL(6,2)     NULL,
  `speed_kph`   DECIMAL(6,2)     NULL,
  `accuracy_m`  DECIMAL(8,2)     NULL,
  `recorded_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

  PRIMARY KEY (`id`),
  KEY `idx_locations_trip` (`trip_id`, `id`),
  CONSTRAINT `fk_location_trip` FOREIGN KEY (`trip_id`)
    REFERENCES `trips` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_location_operator` FOREIGN KEY (`operator_id`)
    REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
--  messages — in-job chat between customer and driver
-- ---------------------------------------------------------------------------
CREATE TABLE `messages` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `trip_id`    INT UNSIGNED NOT NULL,
  `sender_id`  INT UNSIGNED NOT NULL,
  `body`       VARCHAR(1000) NOT NULL,
  `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

  PRIMARY KEY (`id`),
  KEY `idx_messages_trip` (`trip_id`, `id`),
  CONSTRAINT `fk_message_trip` FOREIGN KEY (`trip_id`)
    REFERENCES `trips` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_message_sender` FOREIGN KEY (`sender_id`)
    REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
--  sessions — server-side sessions so a sign-in can be revoked instantly
--
--  Only the SHA-256 of the token is stored. Someone who reads this table
--  (a stolen backup, a SQL injection elsewhere) still cannot sign in as
--  anybody, because the value the browser holds cannot be derived from it.
-- ---------------------------------------------------------------------------
CREATE TABLE `sessions` (
  `id`           CHAR(36)     NOT NULL,
  `user_id`      INT UNSIGNED NOT NULL,
  `token_hash`   CHAR(64)     NOT NULL,
  `csrf_token`   VARCHAR(64)  NOT NULL,
  `ip`           VARCHAR(45)      NULL,
  `user_agent`   VARCHAR(300)     NULL,
  `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_seen_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expires_at`   DATETIME     NOT NULL,
  `revoked_at`   DATETIME         NULL,
  `revoked_by`   INT UNSIGNED     NULL,

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_sessions_token` (`token_hash`),
  KEY `idx_sessions_user` (`user_id`, `revoked_at`),
  CONSTRAINT `fk_session_user` FOREIGN KEY (`user_id`)
    REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
--  login_attempts — drives progressive lockout and the security dashboard
-- ---------------------------------------------------------------------------
CREATE TABLE `login_attempts` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `email`      VARCHAR(254)     NULL,
  `ip`         VARCHAR(45)      NULL,
  `succeeded`  TINYINT(1)   NOT NULL DEFAULT 0,
  `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

  PRIMARY KEY (`id`),
  KEY `idx_attempts_email` (`email`, `created_at`),
  KEY `idx_attempts_ip` (`ip`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
--  audit_log — append-only record of privileged actions
-- ---------------------------------------------------------------------------
CREATE TABLE `audit_log` (
  `id`           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `actor_id`     INT UNSIGNED     NULL,
  `actor_role`   VARCHAR(16)      NULL,
  `action`       VARCHAR(64)  NOT NULL,
  `subject_type` VARCHAR(32)      NULL,
  `subject_id`   VARCHAR(32)      NULL,
  `detail`       VARCHAR(500)     NULL,
  `ip`           VARCHAR(45)      NULL,
  `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

  PRIMARY KEY (`id`),
  KEY `idx_audit_created` (`created_at`),
  KEY `idx_audit_actor` (`actor_id`, `created_at`),
  CONSTRAINT `fk_audit_actor` FOREIGN KEY (`actor_id`)
    REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
--  event_queue — how live updates reach the browser
--
--  Apache + PHP has no persistent connection to push down, so the browser
--  polls `GET api/events?since=N` and the server replays anything newer.
--  Rows are addressed either to one user or to everyone watching one trip.
-- ---------------------------------------------------------------------------
CREATE TABLE `event_queue` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    INT UNSIGNED     NULL,  -- deliver to this user
  `trip_id`    INT UNSIGNED     NULL,  -- ...or to watchers of this trip
  `audience`   ENUM('user','trip','dispatch','managers') NOT NULL,
  `type`       VARCHAR(48)  NOT NULL,
  `payload`    MEDIUMTEXT   NOT NULL,  -- JSON
  `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

  PRIMARY KEY (`id`),
  KEY `idx_events_user` (`user_id`, `id`),
  KEY `idx_events_trip` (`trip_id`, `id`),
  KEY `idx_events_audience` (`audience`, `id`),
  KEY `idx_events_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
